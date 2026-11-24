-- =====================================================================
--  NUSABLOK - Setup Supabase
--  Jalankan SEKALI di Supabase: SQL Editor > New query > tempel semua > Run.
--  Aman dijalankan ulang (tidak menghapus data siswa).
--  Semua nama memakai awalan "nb_" sehingga boleh berbagi project dengan
--  aplikasi lain (Penjaga Kode, bank soal, rapor).
--
--  KODE GURU: game ini memakai kode guru yang SAMA dengan Penjaga Kode
--  (fungsi kg_cek_guru). Jalankan setup Penjaga Kode terlebih dahulu bila
--  project ini belum memilikinya.
--
--  Pertemuan antar pemain (real time) memakai Supabase Realtime dan tidak
--  menyimpan apa pun di tabel, jadi tidak perlu pengaturan tambahan.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tabel ----------
create table if not exists public.nb_siswa (
  username        text primary key check (username ~ '^[a-z0-9_.]{3,20}$'),
  pin_hash        text not null,
  nama            text not null check (char_length(nama) between 1 and 30),
  kelas           smallint not null check (kelas between 1 and 6),        -- level bermain sekarang
  kelas_sekolah   smallint not null check (kelas_sekolah between 1 and 6), -- kelas di sekolah (titik awal tes)
  ditempatkan     boolean not null default false,                          -- sudah mengerjakan tes penempatan?
  skin            smallint not null default 0 check (skin between 0 and 11),
  salah_pin       smallint not null default 0,
  terkunci_sampai timestamptz,
  dibuat          timestamptz not null default now(),
  terakhir        timestamptz not null default now()
);

create table if not exists public.nb_progres (
  username   text not null references public.nb_siswa(username) on delete cascade,
  misi       text not null check (misi ~ '^(ipa|ips|mat|ing|man)-[1-6]-[1-5]$'),
  bintang    smallint not null check (bintang between 1 and 3),
  diperbarui timestamptz not null default now(),
  primary key (username, misi)
);

create table if not exists public.nb_pengaturan (
  kunci text primary key,
  nilai text not null
);
insert into public.nb_pengaturan (kunci, nilai) values ('pendaftaran', 'buka')
on conflict (kunci) do nothing;

-- ---------- Keamanan tabel ----------
-- Tabel tidak bisa dibaca/ditulis langsung dari browser; semua lewat fungsi di bawah.
alter table public.nb_siswa      enable row level security;
alter table public.nb_progres    enable row level security;
alter table public.nb_pengaturan enable row level security;
revoke all on table public.nb_siswa, public.nb_progres, public.nb_pengaturan from anon, authenticated;

-- ---------- Fungsi pembantu (tidak bisa dipanggil dari browser) ----------
-- Memeriksa username + PIN. Salah PIN 5 kali -> akun dikunci 5 menit.
create or replace function public.nb_verifikasi(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  s public.nb_siswa%rowtype;
begin
  select * into s from public.nb_siswa
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
      update public.nb_siswa set salah_pin = 0, terkunci_sampai = null where username = s.username;
    end if;
    return jsonb_build_object('ok', true, 'username', s.username, 'nama', s.nama, 'kelas', s.kelas,
                              'kelas_sekolah', s.kelas_sekolah, 'ditempatkan', s.ditempatkan, 'skin', s.skin);
  end if;

  if s.salah_pin + 1 >= 5 then
    update public.nb_siswa set salah_pin = 0, terkunci_sampai = now() + interval '5 minutes'
     where username = s.username;
    return jsonb_build_object('ok', false,
      'pesan', 'Terlalu banyak salah PIN. Tunggu 5 menit, atau minta guru mereset PIN.');
  end if;

  update public.nb_siswa set salah_pin = salah_pin + 1 where username = s.username;
  return jsonb_build_object('ok', false, 'pesan', 'Username atau PIN salah.');
end;
$$;

revoke all on function public.nb_verifikasi(text, text) from public, anon, authenticated;

-- ---------- Fungsi yang dipakai game ----------
create or replace function public.nb_daftar(
  p_username text, p_pin text, p_nama text, p_skin integer, p_kelas_sekolah integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_user text := lower(trim(coalesce(p_username, '')));
  v_nama text := trim(coalesce(p_nama, ''));
begin
  if coalesce((select nilai from public.nb_pengaturan where kunci = 'pendaftaran'), 'buka') = 'tutup' then
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
  if p_kelas_sekolah is null or p_kelas_sekolah not between 1 and 6 then
    return jsonb_build_object('ok', false, 'pesan', 'Pilih kelas 1 sampai 6.');
  end if;
  if p_skin is null or p_skin not between 0 and 11 then p_skin := 0; end if;

  insert into public.nb_siswa (username, pin_hash, nama, kelas, kelas_sekolah, skin)
  values (v_user, extensions.crypt(p_pin, extensions.gen_salt('bf')), v_nama,
          p_kelas_sekolah, p_kelas_sekolah, p_skin);

  return jsonb_build_object('ok', true,
    'profil', jsonb_build_object('username', v_user, 'nama', v_nama, 'kelas', p_kelas_sekolah,
                                 'kelas_sekolah', p_kelas_sekolah, 'ditempatkan', false, 'skin', p_skin),
    'progres', '{}'::jsonb);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'pesan', 'Username itu sudah dipakai. Coba username lain.');
end;
$$;

create or replace function public.nb_masuk(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_prog jsonb;
begin
  if not (v ->> 'ok')::boolean then return v; end if;

  update public.nb_siswa set terakhir = now() where username = v ->> 'username';
  select coalesce(jsonb_object_agg(misi, bintang), '{}'::jsonb) into v_prog
    from public.nb_progres where username = v ->> 'username';

  return jsonb_build_object('ok', true,
    'profil', jsonb_build_object('username', v ->> 'username', 'nama', v ->> 'nama',
                                 'kelas', (v ->> 'kelas')::int, 'kelas_sekolah', (v ->> 'kelas_sekolah')::int,
                                 'ditempatkan', (v ->> 'ditempatkan')::boolean, 'skin', (v ->> 'skin')::int),
    'progres', v_prog);
end;
$$;

-- Menyimpan hasil tes penempatan (hanya sekali; setelah itu level diubah guru atau lewat naik level).
create or replace function public.nb_tempatkan(p_username text, p_pin text, p_level integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  if p_level is null or p_level not between 1 and 6 then
    return jsonb_build_object('ok', false, 'pesan', 'Level tidak valid.');
  end if;
  if (v ->> 'ditempatkan')::boolean then
    return jsonb_build_object('ok', true, 'kelas', (v ->> 'kelas')::int, 'sudah', true);
  end if;
  update public.nb_siswa set kelas = p_level, ditempatkan = true, terakhir = now()
   where username = v ->> 'username';
  return jsonb_build_object('ok', true, 'kelas', p_level);
end;
$$;

-- Menyimpan bintang sebuah misi (bintang tidak pernah turun).
create or replace function public.nb_simpan(p_username text, p_pin text, p_misi text, p_bintang integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  if p_misi is null or p_misi !~ '^(ipa|ips|mat|ing|man)-[1-6]-[1-5]$' then
    return jsonb_build_object('ok', false, 'pesan', 'Kode misi tidak dikenal.');
  end if;
  if p_bintang is null or p_bintang not between 1 and 3 then
    return jsonb_build_object('ok', false, 'pesan', 'Jumlah bintang tidak valid.');
  end if;
  if split_part(p_misi, '-', 2)::int > (v ->> 'kelas')::int then
    return jsonb_build_object('ok', false, 'pesan', 'Misi ini belum untuk levelmu.');
  end if;

  insert into public.nb_progres (username, misi, bintang)
  values (v ->> 'username', p_misi, p_bintang)
  on conflict (username, misi) do update
    set bintang = greatest(public.nb_progres.bintang, excluded.bintang), diperbarui = now();

  update public.nb_siswa set terakhir = now() where username = v ->> 'username';
  return jsonb_build_object('ok', true);
end;
$$;

-- Naik ke level berikutnya: syaratnya sedikitnya 20 dari 25 misi di level sekarang sudah selesai.
create or replace function public.nb_naik(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_lv int; v_selesai int;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  v_lv := (v ->> 'kelas')::int;
  if v_lv >= 6 then return jsonb_build_object('ok', false, 'pesan', 'Kamu sudah di level tertinggi!'); end if;
  select count(*) into v_selesai from public.nb_progres
   where username = v ->> 'username' and split_part(misi, '-', 2)::int = v_lv;
  if v_selesai < 20 then
    return jsonb_build_object('ok', false, 'pesan', 'Selesaikan minimal 20 misi di levelmu dulu.');
  end if;
  update public.nb_siswa set kelas = v_lv + 1 where username = v ->> 'username';
  return jsonb_build_object('ok', true, 'kelas', v_lv + 1);
end;
$$;

-- ---------- Fungsi khusus guru ----------
create or replace function public.nb_guru_rekap(p_kode text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_err text := public.kg_cek_guru(p_kode);
  v_res jsonb;
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'username', s.username, 'nama', s.nama, 'kelas', s.kelas, 'kelas_sekolah', s.kelas_sekolah,
           'ditempatkan', s.ditempatkan, 'skin', s.skin,
           'bintang', coalesce(p.bintang, 0), 'selesai', coalesce(p.selesai, 0),
           'ipa', coalesce(p.ipa, 0), 'ips', coalesce(p.ips, 0), 'mat', coalesce(p.mat, 0),
           'ing', coalesce(p.ing, 0), 'man', coalesce(p.man, 0),
           'terakhir', to_char(s.terakhir at time zone 'Asia/Jakarta', 'YYYY-MM-DD"T"HH24:MI:SS"+07:00"'))
         order by s.kelas, s.nama), '[]'::jsonb)
    into v_res
    from public.nb_siswa s
    left join (select username, sum(bintang)::int as bintang, count(*)::int as selesai,
                      count(*) filter (where misi like 'ipa-%')::int as ipa,
                      count(*) filter (where misi like 'ips-%')::int as ips,
                      count(*) filter (where misi like 'mat-%')::int as mat,
                      count(*) filter (where misi like 'ing-%')::int as ing,
                      count(*) filter (where misi like 'man-%')::int as man
                 from public.nb_progres group by username) p using (username);

  return jsonb_build_object('ok', true, 'siswa', v_res);
end;
$$;

create or replace function public.nb_guru_set_level(p_kode text, p_username text, p_level integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_err text := public.kg_cek_guru(p_kode);
  n int;
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;
  if p_level is null or p_level not between 1 and 6 then
    return jsonb_build_object('ok', false, 'pesan', 'Level harus 1 sampai 6.');
  end if;

  update public.nb_siswa set kelas = p_level, ditempatkan = true
   where username = lower(trim(coalesce(p_username, '')));
  get diagnostics n = row_count;

  if n = 0 then return jsonb_build_object('ok', false, 'pesan', 'Siswa tidak ditemukan.'); end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.nb_guru_reset_pin(p_kode text, p_username text, p_pin text)
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

  update public.nb_siswa
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')), salah_pin = 0, terkunci_sampai = null
   where username = lower(trim(coalesce(p_username, '')));
  get diagnostics n = row_count;

  if n = 0 then return jsonb_build_object('ok', false, 'pesan', 'Siswa tidak ditemukan.'); end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------- Izin: hanya fungsi game yang boleh dipanggil dari browser ----------
revoke all on function public.nb_daftar(text, text, text, integer, integer) from public;
revoke all on function public.nb_masuk(text, text)                          from public;
revoke all on function public.nb_tempatkan(text, text, integer)             from public;
revoke all on function public.nb_simpan(text, text, text, integer)          from public;
revoke all on function public.nb_naik(text, text)                           from public;
revoke all on function public.nb_guru_rekap(text)                           from public;
revoke all on function public.nb_guru_set_level(text, text, integer)        from public;
revoke all on function public.nb_guru_reset_pin(text, text, text)           from public;

grant execute on function public.nb_daftar(text, text, text, integer, integer) to anon, authenticated;
grant execute on function public.nb_masuk(text, text)                          to anon, authenticated;
grant execute on function public.nb_tempatkan(text, text, integer)             to anon, authenticated;
grant execute on function public.nb_simpan(text, text, text, integer)          to anon, authenticated;
grant execute on function public.nb_naik(text, text)                           to anon, authenticated;
grant execute on function public.nb_guru_rekap(text)                           to anon, authenticated;
grant execute on function public.nb_guru_set_level(text, text, integer)        to anon, authenticated;
grant execute on function public.nb_guru_reset_pin(text, text, text)           to anon, authenticated;

-- Minta Supabase membaca ulang daftar fungsi agar langsung bisa dipanggil game.
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
--  Perintah yang mungkin kamu perlukan nanti (jalankan satu per satu):
--
--  Tutup / buka pendaftaran siswa baru:
--    update public.nb_pengaturan set nilai = 'tutup' where kunci = 'pendaftaran';
--    update public.nb_pengaturan set nilai = 'buka'  where kunci = 'pendaftaran';
--
--  Hapus satu siswa (progresnya ikut terhapus):
--    delete from public.nb_siswa where username = 'nama.pengguna';
-- ---------------------------------------------------------------------
