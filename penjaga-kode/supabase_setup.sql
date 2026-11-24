-- =====================================================================
--  PENJAGA KODE - Setup Supabase
--  Jalankan SEKALI di Supabase: SQL Editor > New query > tempel semua > Run.
--  Aman dijalankan ulang (tidak menghapus data siswa).
--  Semua nama memakai awalan "kg_" sehingga boleh berbagi project
--  dengan aplikasi lain (misalnya bank soal).
-- =====================================================================

-- >>> LANGKAH WAJIB: ganti GANTI-KODE-INI di bawah dengan kode guru milikmu
-- >>> (huruf/angka, minimal 8 karakter). Jangan dibagikan ke siswa.
-- >>> Kode ini disimpan dalam bentuk acak (hash), bukan teks biasa.

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tabel ----------
create table if not exists public.kg_pengaturan (
  kunci text primary key,
  nilai text not null
);

create table if not exists public.kg_siswa (
  username        text primary key check (username ~ '^[a-z0-9_.]{3,20}$'),
  pin_hash        text not null,
  nama            text not null check (char_length(nama) between 1 and 30),
  kelas           smallint not null check (kelas between 1 and 6),
  avatar          text not null default '🧒',
  salah_pin       smallint not null default 0,
  terkunci_sampai timestamptz,
  dibuat          timestamptz not null default now(),
  terakhir        timestamptz not null default now()
);

create table if not exists public.kg_progres (
  username   text not null references public.kg_siswa(username) on delete cascade,
  misi       text not null check (misi ~ '^k[1-6]-[0-9]{2,3}$'),
  bintang    smallint not null check (bintang between 1 and 3),
  diperbarui timestamptz not null default now(),
  primary key (username, misi)
);

-- Kode guru + penghitung percobaan salah (jalankan ulang tidak menimpa kode yang sudah ada)
insert into public.kg_pengaturan (kunci, nilai) values
  ('kode_guru',         extensions.crypt('GANTI-KODE-INI', extensions.gen_salt('bf'))),
  ('guru_gagal',        '0'),
  ('guru_kunci_sampai', ''),
  ('pendaftaran',       'buka')          -- ganti jadi 'tutup' bila semua siswa sudah mendaftar
on conflict (kunci) do nothing;

-- ---------- Keamanan tabel ----------
-- Tabel tidak bisa dibaca/ditulis langsung dari browser; semua lewat fungsi di bawah.
alter table public.kg_pengaturan enable row level security;
alter table public.kg_siswa      enable row level security;
alter table public.kg_progres    enable row level security;
revoke all on table public.kg_pengaturan, public.kg_siswa, public.kg_progres from anon, authenticated;

-- ---------- Fungsi pembantu (tidak bisa dipanggil dari browser) ----------

-- Memeriksa username + PIN. Salah PIN 5 kali -> akun dikunci 5 menit.
create or replace function public.kg_verifikasi(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  s public.kg_siswa%rowtype;
begin
  select * into s from public.kg_siswa
   where username = lower(trim(coalesce(p_username, ''))) for update;

  if not found then
    perform pg_sleep(0.4);
    return jsonb_build_object('ok', false, 'pesan', 'Username atau PIN salah.');
  end if;

  if s.terkunci_sampai is not null and s.terkunci_sampai > now() then
    return jsonb_build_object('ok', false,
      'pesan', 'Terlalu banyak salah PIN. Tunggu 5 menit, atau minta guru mereset PIN.');
  end if;

  if p_pin is not null and extensions.crypt(p_pin, s.pin_hash) = s.pin_hash then
    if s.salah_pin > 0 or s.terkunci_sampai is not null then
      update public.kg_siswa set salah_pin = 0, terkunci_sampai = null where username = s.username;
    end if;
    return jsonb_build_object('ok', true, 'username', s.username, 'nama', s.nama,
                              'kelas', s.kelas, 'avatar', s.avatar);
  end if;

  if s.salah_pin + 1 >= 5 then
    update public.kg_siswa set salah_pin = 0, terkunci_sampai = now() + interval '5 minutes'
     where username = s.username;
    return jsonb_build_object('ok', false,
      'pesan', 'Terlalu banyak salah PIN. Tunggu 5 menit, atau minta guru mereset PIN.');
  end if;

  update public.kg_siswa set salah_pin = salah_pin + 1 where username = s.username;
  return jsonb_build_object('ok', false, 'pesan', 'Username atau PIN salah.');
end;
$$;

-- Memeriksa kode guru. Salah 10 kali berturut-turut -> dikunci 10 menit.
-- Mengembalikan NULL kalau benar, atau teks pesan kalau salah.
create or replace function public.kg_cek_guru(p_kode text)
returns text
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_hash  text;
  v_gagal int;
  v_kunci timestamptz;
begin
  select nilai into v_hash from public.kg_pengaturan where kunci = 'kode_guru' for update;
  select coalesce(nullif(nilai, '')::int, 0) into v_gagal from public.kg_pengaturan where kunci = 'guru_gagal';
  select nullif(nilai, '')::timestamptz into v_kunci from public.kg_pengaturan where kunci = 'guru_kunci_sampai';

  if v_kunci is not null and v_kunci > now() then
    return 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.';
  end if;

  if p_kode is not null and v_hash is not null and extensions.crypt(p_kode, v_hash) = v_hash then
    update public.kg_pengaturan set nilai = '0' where kunci = 'guru_gagal' and nilai <> '0';
    return null;
  end if;

  v_gagal := coalesce(v_gagal, 0) + 1;
  if v_gagal >= 10 then
    update public.kg_pengaturan set nilai = (now() + interval '10 minutes')::text where kunci = 'guru_kunci_sampai';
    v_gagal := 0;
  end if;
  update public.kg_pengaturan set nilai = v_gagal::text where kunci = 'guru_gagal';
  perform pg_sleep(1.5);
  return 'Kode guru salah.';
end;
$$;

revoke all on function public.kg_verifikasi(text, text) from public, anon, authenticated;
revoke all on function public.kg_cek_guru(text)         from public, anon, authenticated;

-- ---------- Fungsi yang dipakai game ----------

create or replace function public.kg_daftar(
  p_username text, p_pin text, p_nama text, p_kelas integer, p_avatar text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_user text := lower(trim(coalesce(p_username, '')));
  v_nama text := trim(coalesce(p_nama, ''));
  v_av   text := left(coalesce(nullif(trim(p_avatar), ''), '🧒'), 12);
begin
  if coalesce((select nilai from public.kg_pengaturan where kunci = 'pendaftaran'), 'buka') = 'tutup' then
    return jsonb_build_object('ok', false, 'pesan', 'Pendaftaran sedang ditutup. Minta bantuan guru.');
  end if;
  if v_user !~ '^[a-z0-9_.]{3,20}$' then
    return jsonb_build_object('ok', false, 'pesan', 'Username: 3 sampai 20 karakter, hanya huruf kecil, angka, titik, atau garis bawah.');
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('ok', false, 'pesan', 'PIN harus 4 angka.');
  end if;
  if char_length(v_nama) not between 1 and 30 then
    return jsonb_build_object('ok', false, 'pesan', 'Nama panggilan 1 sampai 30 karakter.');
  end if;
  if p_kelas is null or p_kelas not between 1 and 6 then
    return jsonb_build_object('ok', false, 'pesan', 'Pilih kelas 1 sampai 6.');
  end if;

  insert into public.kg_siswa (username, pin_hash, nama, kelas, avatar)
  values (v_user, extensions.crypt(p_pin, extensions.gen_salt('bf')), v_nama, p_kelas, v_av);

  return jsonb_build_object('ok', true,
    'profil', jsonb_build_object('username', v_user, 'nama', v_nama, 'kelas', p_kelas, 'avatar', v_av),
    'progres', '{}'::jsonb);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'pesan', 'Username itu sudah dipakai. Coba username lain.');
end;
$$;

create or replace function public.kg_masuk(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.kg_verifikasi(p_username, p_pin);
  v_prog jsonb;
begin
  if not (v ->> 'ok')::boolean then return v; end if;

  update public.kg_siswa set terakhir = now() where username = v ->> 'username';
  select coalesce(jsonb_object_agg(misi, bintang), '{}'::jsonb) into v_prog
    from public.kg_progres where username = v ->> 'username';

  return jsonb_build_object('ok', true,
    'profil', jsonb_build_object('username', v ->> 'username', 'nama', v ->> 'nama',
                                 'kelas', (v ->> 'kelas')::int, 'avatar', v ->> 'avatar'),
    'progres', v_prog);
end;
$$;

create or replace function public.kg_simpan(p_username text, p_pin text, p_misi text, p_bintang integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.kg_verifikasi(p_username, p_pin);
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  if p_misi is null or p_misi !~ '^k[1-6]-[0-9]{2,3}$' then
    return jsonb_build_object('ok', false, 'pesan', 'Kode misi tidak dikenal.');
  end if;
  if p_bintang is null or p_bintang not between 1 and 3 then
    return jsonb_build_object('ok', false, 'pesan', 'Jumlah bintang tidak valid.');
  end if;
  if substr(p_misi, 2, 1)::int > (v ->> 'kelas')::int then
    return jsonb_build_object('ok', false, 'pesan', 'Misi ini belum untuk kelasmu.');
  end if;

  insert into public.kg_progres (username, misi, bintang)
  values (v ->> 'username', p_misi, p_bintang)
  on conflict (username, misi) do update
    set bintang = greatest(public.kg_progres.bintang, excluded.bintang), diperbarui = now();

  update public.kg_siswa set terakhir = now() where username = v ->> 'username';
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------- Fungsi khusus guru ----------

create or replace function public.kg_guru_rekap(p_kode text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_err text := public.kg_cek_guru(p_kode);
  v_res jsonb;
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'username', s.username, 'nama', s.nama, 'kelas', s.kelas, 'avatar', s.avatar,
           'bintang', coalesce(p.bintang, 0), 'selesai', coalesce(p.selesai, 0),
           'terakhir', to_char(s.terakhir at time zone 'Asia/Jakarta', 'YYYY-MM-DD"T"HH24:MI:SS"+07:00"'))
         order by s.kelas, s.nama), '[]'::jsonb)
    into v_res
    from public.kg_siswa s
    left join (select username, sum(bintang)::int as bintang, count(*)::int as selesai
                 from public.kg_progres group by username) p using (username);

  return jsonb_build_object('ok', true, 'siswa', v_res);
end;
$$;

create or replace function public.kg_guru_reset_pin(p_kode text, p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_err text := public.kg_cek_guru(p_kode);
  n int;
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;
  if p_pin is null or p_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('ok', false, 'pesan', 'PIN harus 4 angka.');
  end if;

  update public.kg_siswa
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')), salah_pin = 0, terkunci_sampai = null
   where username = lower(trim(coalesce(p_username, '')));
  get diagnostics n = row_count;

  if n = 0 then return jsonb_build_object('ok', false, 'pesan', 'Siswa tidak ditemukan.'); end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.kg_guru_set_kelas(p_kode text, p_username text, p_kelas integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_err text := public.kg_cek_guru(p_kode);
  n int;
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;
  if p_kelas is null or p_kelas not between 1 and 6 then
    return jsonb_build_object('ok', false, 'pesan', 'Kelas harus 1 sampai 6.');
  end if;

  update public.kg_siswa set kelas = p_kelas where username = lower(trim(coalesce(p_username, '')));
  get diagnostics n = row_count;

  if n = 0 then return jsonb_build_object('ok', false, 'pesan', 'Siswa tidak ditemukan.'); end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------- Izin: hanya fungsi game yang boleh dipanggil dari browser ----------
revoke all on function public.kg_daftar(text, text, text, integer, text)  from public;
revoke all on function public.kg_masuk(text, text)                        from public;
revoke all on function public.kg_simpan(text, text, text, integer)        from public;
revoke all on function public.kg_guru_rekap(text)                         from public;
revoke all on function public.kg_guru_reset_pin(text, text, text)         from public;
revoke all on function public.kg_guru_set_kelas(text, text, integer)      from public;

grant execute on function public.kg_daftar(text, text, text, integer, text)  to anon, authenticated;
grant execute on function public.kg_masuk(text, text)                        to anon, authenticated;
grant execute on function public.kg_simpan(text, text, text, integer)        to anon, authenticated;
grant execute on function public.kg_guru_rekap(text)                         to anon, authenticated;
grant execute on function public.kg_guru_reset_pin(text, text, text)         to anon, authenticated;
grant execute on function public.kg_guru_set_kelas(text, text, integer)      to anon, authenticated;

-- Minta Supabase membaca ulang daftar fungsi agar langsung bisa dipanggil game.
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
--  Perintah yang mungkin kamu perlukan nanti (jalankan satu per satu):
--
--  Ganti kode guru:
--    update public.kg_pengaturan
--       set nilai = extensions.crypt('KODE-BARU-KAMU', extensions.gen_salt('bf'))
--     where kunci = 'kode_guru';
--
--  Tutup / buka pendaftaran siswa baru:
--    update public.kg_pengaturan set nilai = 'tutup' where kunci = 'pendaftaran';
--    update public.kg_pengaturan set nilai = 'buka'  where kunci = 'pendaftaran';
--
--  Hapus satu siswa (progresnya ikut terhapus):
--    delete from public.kg_siswa where username = 'nama.pengguna';
-- ---------------------------------------------------------------------
