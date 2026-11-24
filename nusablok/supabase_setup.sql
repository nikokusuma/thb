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
  misi       text not null check (misi ~ '^(ipa|ips|mat|ing|man)-[1-6]-([1-5]|g[0-9]{1,9})$'),
  bintang    smallint not null check (bintang between 1 and 3),
  diperbarui timestamptz not null default now(),
  primary key (username, misi)
);

-- Instalasi lama: lebarkan aturan kode misi agar misi buatan guru (…-g12) boleh disimpan.
do $$
declare c text;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.nb_progres'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) like '%misi%'
  loop
    execute format('alter table public.nb_progres drop constraint %I', c);
  end loop;
  alter table public.nb_progres add constraint nb_progres_misi_check
    check (misi ~ '^(ipa|ips|mat|ing|man)-[1-6]-([1-5]|g[0-9]{1,9})$');
end $$;

-- Misi tambahan yang ditulis guru. Tiap (mapel, level) punya 10 slot (0-9) = 10 NPC emas di pulau misi guru.
create table if not exists public.nb_misi_guru (
  id         bigint generated always as identity primary key,
  mapel      text     not null check (mapel in ('ipa','ips','mat','ing','man')),
  level      smallint not null check (level between 1 and 6),
  slot       smallint not null check (slot between 0 and 9),
  judul      text     not null check (char_length(judul) between 1 and 40),
  cerita     text     not null default '' check (char_length(cerita) <= 300),
  penjaga    text     not null default '' check (char_length(penjaga) <= 24),
  aktif      boolean  not null default true,
  soal       jsonb    not null check (jsonb_typeof(soal) = 'array' and jsonb_array_length(soal) between 3 and 8),
  dibuat     timestamptz not null default now(),
  diperbarui timestamptz not null default now(),
  unique (mapel, level, slot)
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
alter table public.nb_misi_guru  enable row level security;
revoke all on table public.nb_siswa, public.nb_progres, public.nb_pengaturan, public.nb_misi_guru from anon, authenticated;

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
  if p_misi is null or p_misi !~ '^(ipa|ips|mat|ing|man)-[1-6]-([1-5]|g[0-9]{1,9})$' then
    return jsonb_build_object('ok', false, 'pesan', 'Kode misi tidak dikenal.');
  end if;
  if p_bintang is null or p_bintang not between 1 and 3 then
    return jsonb_build_object('ok', false, 'pesan', 'Jumlah bintang tidak valid.');
  end if;
  if split_part(p_misi, '-', 2)::int > (v ->> 'kelas')::int then
    return jsonb_build_object('ok', false, 'pesan', 'Misi ini belum untuk levelmu.');
  end if;
  -- Misi buatan guru: harus masih ada, aktif, dan cocok dengan mapel + level pada kodenya.
  if split_part(p_misi, '-', 3) like 'g%' then
    if not exists (select 1 from public.nb_misi_guru g
                    where g.id = substr(split_part(p_misi, '-', 3), 2)::bigint
                      and g.aktif
                      and g.mapel = split_part(p_misi, '-', 1)
                      and g.level = split_part(p_misi, '-', 2)::int) then
      return jsonb_build_object('ok', false, 'pesan', 'Misi ini sudah tidak tersedia.');
    end if;
  end if;

  insert into public.nb_progres (username, misi, bintang)
  values (v ->> 'username', p_misi, p_bintang)
  on conflict (username, misi) do update
    set bintang = greatest(public.nb_progres.bintang, excluded.bintang), diperbarui = now();

  update public.nb_siswa set terakhir = now() where username = v ->> 'username';
  return jsonb_build_object('ok', true);
end;
$$;

-- Naik ke level berikutnya: syaratnya sedikitnya 20 dari 25 misi BAWAAN di level sekarang sudah selesai
-- (misi tambahan dari guru tidak dihitung, supaya syarat naik level tidak berubah-ubah).
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
   where username = v ->> 'username'
     and misi ~ '^(ipa|ips|mat|ing|man)-[1-6]-[1-5]$'
     and split_part(misi, '-', 2)::int = v_lv;
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
           'tambahan', coalesce(p.tambahan, 0),
           'ipa', coalesce(p.ipa, 0), 'ips', coalesce(p.ips, 0), 'mat', coalesce(p.mat, 0),
           'ing', coalesce(p.ing, 0), 'man', coalesce(p.man, 0),
           'terakhir', to_char(s.terakhir at time zone 'Asia/Jakarta', 'YYYY-MM-DD"T"HH24:MI:SS"+07:00"'))
         order by s.kelas, s.nama), '[]'::jsonb)
    into v_res
    from public.nb_siswa s
    left join (select username, sum(bintang)::int as bintang,
                      -- "selesai" dan hitungan per mapel hanya misi bawaan; misi guru dihitung terpisah ("tambahan")
                      count(*) filter (where misi ~ '-[1-5]$')::int as selesai,
                      count(*) filter (where misi !~ '-[1-5]$')::int as tambahan,
                      count(*) filter (where misi like 'ipa-%' and misi ~ '-[1-5]$')::int as ipa,
                      count(*) filter (where misi like 'ips-%' and misi ~ '-[1-5]$')::int as ips,
                      count(*) filter (where misi like 'mat-%' and misi ~ '-[1-5]$')::int as mat,
                      count(*) filter (where misi like 'ing-%' and misi ~ '-[1-5]$')::int as ing,
                      count(*) filter (where misi like 'man-%' and misi ~ '-[1-5]$')::int as man
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

-- ---------- Misi tambahan dari guru ----------
-- Pemeriksa soal (tidak bisa dipanggil dari browser). Mengembalikan {ok, soal} yang sudah dirapikan,
-- atau {ok:false, pesan}. Aturan: 3-8 soal; tiap soal punya pertanyaan (t), jawaban benar (b)
-- dan 2-3 jawaban salah (s); semua pilihan dalam satu soal harus berbeda.
create or replace function public.nb_norm_soal(p jsonb)
returns jsonb
language plpgsql immutable set search_path = public
as $$
declare
  el jsonb; x jsonb; i int := 0; n int;
  t text; b text; w text;
  seen text[]; sarr jsonb; arr jsonb := '[]'::jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'array' then
    return jsonb_build_object('ok', false, 'pesan', 'Daftar soal tidak valid.');
  end if;
  n := jsonb_array_length(p);
  if n < 3 or n > 8 then
    return jsonb_build_object('ok', false, 'pesan', 'Satu misi harus punya 3 sampai 8 soal.');
  end if;

  for el in select value from jsonb_array_elements(p) loop
    i := i + 1;
    if jsonb_typeof(el) <> 'object'
       or jsonb_typeof(el -> 't') is distinct from 'string'
       or jsonb_typeof(el -> 'b') is distinct from 'string'
       or jsonb_typeof(el -> 's') is distinct from 'array' then
      return jsonb_build_object('ok', false, 'pesan', format('Soal ke-%s: isinya tidak lengkap.', i));
    end if;
    t := btrim(el ->> 't');
    b := btrim(el ->> 'b');
    if char_length(t) not between 1 and 200 then
      return jsonb_build_object('ok', false, 'pesan', format('Soal ke-%s: pertanyaan harus 1 sampai 200 karakter.', i));
    end if;
    if char_length(b) not between 1 and 80 then
      return jsonb_build_object('ok', false, 'pesan', format('Soal ke-%s: jawaban benar harus 1 sampai 80 karakter.', i));
    end if;
    seen := array[lower(b)];
    sarr := '[]'::jsonb;
    for x in select value from jsonb_array_elements(el -> 's') loop
      if jsonb_typeof(x) <> 'string' then
        return jsonb_build_object('ok', false, 'pesan', format('Soal ke-%s: jawaban salah tidak valid.', i));
      end if;
      w := btrim(x #>> '{}');
      if char_length(w) not between 1 and 80 then
        return jsonb_build_object('ok', false, 'pesan', format('Soal ke-%s: tiap jawaban salah harus 1 sampai 80 karakter.', i));
      end if;
      if lower(w) = any(seen) then
        return jsonb_build_object('ok', false, 'pesan', format('Soal ke-%s: pilihan jawaban tidak boleh kembar.', i));
      end if;
      seen := seen || lower(w);
      sarr := sarr || to_jsonb(w);
    end loop;
    if jsonb_array_length(sarr) not between 2 and 3 then
      return jsonb_build_object('ok', false, 'pesan', format('Soal ke-%s: butuh 2 sampai 3 jawaban salah.', i));
    end if;
    arr := arr || jsonb_build_array(jsonb_build_object('t', t, 'b', b, 's', sarr));
  end loop;

  return jsonb_build_object('ok', true, 'soal', arr);
end;
$$;

-- Inti penyimpanan misi (dipanggil fungsi guru setelah kode guru terbukti benar).
create or replace function public.nb_misi_simpan_inti(p_id bigint, p_misi jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_mapel text; v_level int; v_judul text; v_cerita text; v_penjaga text; v_aktif boolean;
  v_norm jsonb; v_slot int; v_id bigint; o public.nb_misi_guru%rowtype;
begin
  if p_misi is null or jsonb_typeof(p_misi) <> 'object' then
    return jsonb_build_object('ok', false, 'pesan', 'Data misi tidak valid.');
  end if;

  v_mapel := lower(coalesce(p_misi ->> 'mapel', ''));
  if v_mapel not in ('ipa','ips','mat','ing','man') then
    return jsonb_build_object('ok', false, 'pesan', 'Pilih mata pelajaran.');
  end if;
  if coalesce(p_misi ->> 'level', '') !~ '^[1-6]$' then
    return jsonb_build_object('ok', false, 'pesan', 'Pilih level kelas 1 sampai 6.');
  end if;
  v_level := (p_misi ->> 'level')::int;

  v_judul   := btrim(coalesce(p_misi ->> 'judul', ''));
  v_cerita  := btrim(coalesce(p_misi ->> 'cerita', ''));
  v_penjaga := btrim(coalesce(p_misi ->> 'penjaga', ''));
  v_aktif   := coalesce(p_misi ->> 'aktif', 'true') <> 'false';

  if char_length(v_judul) not between 1 and 40 then
    return jsonb_build_object('ok', false, 'pesan', 'Judul misi harus 1 sampai 40 karakter.');
  end if;
  if char_length(v_cerita) > 300 then
    return jsonb_build_object('ok', false, 'pesan', 'Cerita pembuka maksimal 300 karakter.');
  end if;
  if char_length(v_penjaga) > 24 then
    return jsonb_build_object('ok', false, 'pesan', 'Nama penjaga maksimal 24 karakter.');
  end if;

  v_norm := public.nb_norm_soal(p_misi -> 'soal');
  if not (v_norm ->> 'ok')::boolean then return v_norm; end if;

  -- Satu penyimpan pada satu waktu supaya pembagian slot tidak bentrok.
  perform pg_advisory_xact_lock(7311001);

  if p_id is null then
    select g into v_slot from generate_series(0, 9) g
     where not exists (select 1 from public.nb_misi_guru m
                        where m.mapel = v_mapel and m.level = v_level and m.slot = g)
     order by g limit 1;
    if v_slot is null then
      return jsonb_build_object('ok', false,
        'pesan', 'Slot misi guru untuk pelajaran dan kelas ini sudah penuh (maksimal 10). Hapus satu misi dulu.');
    end if;
    insert into public.nb_misi_guru (mapel, level, slot, judul, cerita, penjaga, aktif, soal)
    values (v_mapel, v_level, v_slot, v_judul, v_cerita, v_penjaga, v_aktif, v_norm -> 'soal')
    returning id into v_id;
    return jsonb_build_object('ok', true, 'id', v_id, 'slot', v_slot);
  end if;

  select * into o from public.nb_misi_guru where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'pesan', 'Misi tidak ditemukan (mungkin sudah dihapus).');
  end if;

  if o.mapel = v_mapel and o.level = v_level then
    v_slot := o.slot;
  else
    select g into v_slot from generate_series(0, 9) g
     where not exists (select 1 from public.nb_misi_guru m
                        where m.mapel = v_mapel and m.level = v_level and m.slot = g)
     order by g limit 1;
    if v_slot is null then
      return jsonb_build_object('ok', false,
        'pesan', 'Slot misi guru untuk pelajaran dan kelas tujuan sudah penuh (maksimal 10).');
    end if;
    -- Kode misi memuat mapel + level, jadi progres lama tidak berlaku lagi di tempat baru.
    delete from public.nb_progres where split_part(misi, '-', 3) = 'g' || p_id::text;
  end if;

  update public.nb_misi_guru
     set mapel = v_mapel, level = v_level, slot = v_slot, judul = v_judul, cerita = v_cerita,
         penjaga = v_penjaga, aktif = v_aktif, soal = v_norm -> 'soal', diperbarui = now()
   where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id, 'slot', v_slot);
end;
$$;

create or replace function public.nb_misi_hapus_inti(p_id bigint)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare n int;
begin
  delete from public.nb_misi_guru where id = p_id;
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('ok', false, 'pesan', 'Misi tidak ditemukan (mungkin sudah dihapus).');
  end if;
  delete from public.nb_progres where split_part(misi, '-', 3) = 'g' || p_id::text;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.nb_misi_daftar_guru_inti()
returns jsonb
language sql stable security definer set search_path = public, extensions
as $$
  select jsonb_build_object('ok', true, 'misi', coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'mapel', m.mapel, 'level', m.level, 'slot', m.slot, 'judul', m.judul,
           'cerita', m.cerita, 'penjaga', m.penjaga, 'aktif', m.aktif, 'soal', m.soal,
           'selesai', (select count(*) from public.nb_progres p
                        where p.misi = m.mapel || '-' || m.level || '-g' || m.id))
         order by m.mapel, m.level, m.slot), '[]'::jsonb))
    from public.nb_misi_guru m;
$$;

-- Dipakai SISWA: misi guru yang aktif untuk satu level.
create or replace function public.nb_misi_daftar(p_level integer)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
begin
  if p_level is null or p_level not between 1 and 6 then
    return jsonb_build_object('ok', false, 'pesan', 'Level tidak valid.');
  end if;
  return jsonb_build_object('ok', true, 'misi', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', m.id, 'mapel', m.mapel, 'level', m.level, 'slot', m.slot, 'judul', m.judul,
             'cerita', m.cerita, 'penjaga', m.penjaga, 'soal', m.soal) order by m.mapel, m.slot)
      from public.nb_misi_guru m where m.level = p_level and m.aktif), '[]'::jsonb));
end;
$$;

-- Dipakai GURU (semuanya memeriksa kode guru yang sama dengan Penjaga Kode).
create or replace function public.nb_guru_misi_daftar(p_kode text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare v_err text := public.kg_cek_guru(p_kode);
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;
  return public.nb_misi_daftar_guru_inti();
end;
$$;

create or replace function public.nb_guru_misi_simpan(p_kode text, p_id bigint, p_misi jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare v_err text := public.kg_cek_guru(p_kode);
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;
  return public.nb_misi_simpan_inti(p_id, p_misi);
end;
$$;

create or replace function public.nb_guru_misi_hapus(p_kode text, p_id bigint)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare v_err text := public.kg_cek_guru(p_kode);
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;
  return public.nb_misi_hapus_inti(p_id);
end;
$$;

-- ---------- Izin: hanya fungsi game yang boleh dipanggil dari browser ----------
revoke all on function public.nb_norm_soal(jsonb)                from public, anon, authenticated;
revoke all on function public.nb_misi_simpan_inti(bigint, jsonb) from public, anon, authenticated;
revoke all on function public.nb_misi_hapus_inti(bigint)         from public, anon, authenticated;
revoke all on function public.nb_misi_daftar_guru_inti()         from public, anon, authenticated;

revoke all on function public.nb_daftar(text, text, text, integer, integer) from public;
revoke all on function public.nb_masuk(text, text)                          from public;
revoke all on function public.nb_tempatkan(text, text, integer)             from public;
revoke all on function public.nb_simpan(text, text, text, integer)          from public;
revoke all on function public.nb_naik(text, text)                           from public;
revoke all on function public.nb_guru_rekap(text)                           from public;
revoke all on function public.nb_guru_set_level(text, text, integer)        from public;
revoke all on function public.nb_guru_reset_pin(text, text, text)           from public;
revoke all on function public.nb_misi_daftar(integer)                       from public;
revoke all on function public.nb_guru_misi_daftar(text)                     from public;
revoke all on function public.nb_guru_misi_simpan(text, bigint, jsonb)      from public;
revoke all on function public.nb_guru_misi_hapus(text, bigint)              from public;

grant execute on function public.nb_daftar(text, text, text, integer, integer) to anon, authenticated;
grant execute on function public.nb_masuk(text, text)                          to anon, authenticated;
grant execute on function public.nb_tempatkan(text, text, integer)             to anon, authenticated;
grant execute on function public.nb_simpan(text, text, text, integer)          to anon, authenticated;
grant execute on function public.nb_naik(text, text)                           to anon, authenticated;
grant execute on function public.nb_guru_rekap(text)                           to anon, authenticated;
grant execute on function public.nb_guru_set_level(text, text, integer)        to anon, authenticated;
grant execute on function public.nb_guru_reset_pin(text, text, text)           to anon, authenticated;
grant execute on function public.nb_misi_daftar(integer)                       to anon, authenticated;
grant execute on function public.nb_guru_misi_daftar(text)                     to anon, authenticated;
grant execute on function public.nb_guru_misi_simpan(text, bigint, jsonb)      to anon, authenticated;
grant execute on function public.nb_guru_misi_hapus(text, bigint)              to anon, authenticated;

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
