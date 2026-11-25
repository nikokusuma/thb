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
  skin            smallint not null default 0 check (skin between 0 and 23),
  salah_pin       smallint not null default 0,
  terkunci_sampai timestamptz,
  dibuat          timestamptz not null default now(),
  terakhir        timestamptz not null default now()
);

create table if not exists public.nb_progres (
  username   text not null references public.nb_siswa(username) on delete cascade,
  misi       text not null check (misi ~ '^(ipa|ips|mat|ing|man)-[1-6]-([1-5]|g[0-9]{1,9}|k[1-9])$'),
  bintang    smallint not null check (bintang between 1 and 3),
  diperbarui timestamptz not null default now(),
  primary key (username, misi)
);

-- Instalasi lama: lebarkan aturan kode misi agar misi buatan guru (…-g12) dan misi Kumpulkan Barang (…-k1) boleh disimpan.
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
    check (misi ~ '^(ipa|ips|mat|ing|man)-[1-6]-([1-5]|g[0-9]{1,9}|k[1-9])$');
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

-- Instalasi lama: karakter perempuan (skin 12-23) dan kostum.
alter table public.nb_siswa drop constraint if exists nb_siswa_skin_check;
alter table public.nb_siswa add constraint nb_siswa_skin_check check (skin between 0 and 23);
alter table public.nb_siswa add column if not exists kostum smallint not null default 0;
alter table public.nb_siswa drop constraint if exists nb_siswa_kostum_check;
alter table public.nb_siswa add constraint nb_siswa_kostum_check check (kostum between 0 and 15);

-- Koleksi pemain: {"i":{ikan},"h":{harta},"b":{bahan buruan},"m":{masakan dibuat},"u":{bahan terpakai}}. Semua angka hanya bisa naik.
create table if not exists public.nb_koleksi (
  username   text primary key references public.nb_siswa(username) on delete cascade,
  data       jsonb not null default '{}'::jsonb
             check (jsonb_typeof(data) = 'object' and char_length(data::text) <= 4000),
  diperbarui timestamptz not null default now()
);

-- Prestasi (achievement) yang sudah diraih tiap pemain.
-- Instalasi lama: koleksi kini memuat grup i, h, b (bahan buruan), m (masakan), u (bahan terpakai).
alter table public.nb_koleksi drop constraint if exists nb_koleksi_data_check;
alter table public.nb_koleksi add constraint nb_koleksi_data_check check (jsonb_typeof(data) = 'object' and char_length(data::text) <= 4000);

create table if not exists public.nb_prestasi (
  username text not null references public.nb_siswa(username) on delete cascade,
  kode     text not null check (kode ~ '^[a-z0-9_]{3,24}$'),
  waktu    timestamptz not null default now(),
  primary key (username, kode)
);

-- Item langka yang berhasil didapat tiap pemain (per mapel).
create table if not exists public.nb_langka (
  username text not null references public.nb_siswa(username) on delete cascade,
  mapel    text not null check (mapel in ('ipa','ips','mat','ing','man')),
  jumlah   integer not null default 1 check (jumlah >= 1),
  pertama  timestamptz not null default now(),
  terakhir timestamptz not null default now(),
  primary key (username, mapel)
);

-- Pengumuman untuk SEMUA pemain ("Budi mendapatkan Kristal Kehidupan!"). Hanya 200 terakhir yang disimpan.
create table if not exists public.nb_umum (
  id     bigint generated always as identity primary key,
  jenis  text not null check (jenis in ('langka','legenda')),
  mapel  text not null default '' check (mapel in ('','ipa','ips','mat','ing','man')),
  nama   text not null check (char_length(nama) between 1 and 30),
  level  smallint not null check (level between 1 and 6),
  dibuat timestamptz not null default now()
);

-- ---------- Keamanan tabel ----------
-- Tabel tidak bisa dibaca/ditulis langsung dari browser; semua lewat fungsi di bawah.
alter table public.nb_siswa      enable row level security;
alter table public.nb_progres    enable row level security;
alter table public.nb_pengaturan enable row level security;
alter table public.nb_misi_guru  enable row level security;
alter table public.nb_koleksi    enable row level security;
alter table public.nb_prestasi   enable row level security;
alter table public.nb_langka     enable row level security;
alter table public.nb_umum       enable row level security;
revoke all on table public.nb_siswa, public.nb_progres, public.nb_pengaturan, public.nb_misi_guru,
                    public.nb_koleksi, public.nb_prestasi, public.nb_langka, public.nb_umum from anon, authenticated;

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
                              'kelas_sekolah', s.kelas_sekolah, 'ditempatkan', s.ditempatkan, 'skin', s.skin, 'kostum', s.kostum);
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
  if p_skin is null or p_skin not between 0 and 23 then p_skin := 0; end if;

  insert into public.nb_siswa (username, pin_hash, nama, kelas, kelas_sekolah, skin)
  values (v_user, extensions.crypt(p_pin, extensions.gen_salt('bf')), v_nama,
          p_kelas_sekolah, p_kelas_sekolah, p_skin);

  return jsonb_build_object('ok', true,
    'profil', jsonb_build_object('username', v_user, 'nama', v_nama, 'kelas', p_kelas_sekolah,
                                 'kelas_sekolah', p_kelas_sekolah, 'ditempatkan', false, 'skin', p_skin, 'kostum', 0),
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
                                 'ditempatkan', (v ->> 'ditempatkan')::boolean, 'skin', (v ->> 'skin')::int,
                                 'kostum', coalesce((v ->> 'kostum')::int, 0)),
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
  if p_misi is null or p_misi !~ '^(ipa|ips|mat|ing|man)-[1-6]-([1-5]|g[0-9]{1,9}|k[1-9])$' then
    return jsonb_build_object('ok', false, 'pesan', 'Kode misi tidak dikenal.');
  end if;
  if p_bintang is null or p_bintang not between 1 and 3 then
    return jsonb_build_object('ok', false, 'pesan', 'Jumlah bintang tidak valid.');
  end if;
  if split_part(p_misi, '-', 2)::int > (v ->> 'kelas')::int then
    return jsonb_build_object('ok', false, 'pesan', 'Misi ini belum untuk levelmu.');
  end if;
  -- (Misi Kumpulkan Barang berkode …-k1 hanya bonus; tidak dihitung untuk naik level.)
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
  return jsonb_build_object('ok', true, 'waktu', public.nb_waktu_bonus(v ->> 'username', p_misi));
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

-- ---------- Koleksi, prestasi, item langka, pengumuman ----------
-- Mengambil koleksi + jumlah item langka + daftar prestasi milik pemain.
create or replace function public.nb_koleksi_ambil(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_u text;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  v_u := v ->> 'username';
  return jsonb_build_object('ok', true,
    'data', coalesce((select k.data from public.nb_koleksi k where k.username = v_u), '{}'::jsonb),
    'langka', coalesce((select jsonb_object_agg(l.mapel, l.jumlah) from public.nb_langka l where l.username = v_u), '{}'::jsonb),
    'prestasi', coalesce((select jsonb_agg(p.kode order by p.waktu) from public.nb_prestasi p where p.username = v_u), '[]'::jsonb));
end;
$$;

-- Menyimpan koleksi. Angka tiap jenis hanya boleh naik (diambil yang terbesar dari data lama dan baru).
create or replace function public.nb_koleksi_simpan(p_username text, p_pin text, p_data jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_u text;
  v_lama jsonb;
  v_g text;
  v_in jsonb;
  v_old jsonb;
  v_gab jsonb;
  v_hasil jsonb := '{}'::jsonb;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  v_u := v ->> 'username';
  if p_data is null or jsonb_typeof(p_data) <> 'object' or char_length(p_data::text) > 4000 then
    return jsonb_build_object('ok', false, 'pesan', 'Data koleksi tidak valid.');
  end if;
  select k.data into v_lama from public.nb_koleksi k where k.username = v_u;
  v_lama := coalesce(v_lama, '{}'::jsonb);

  foreach v_g in array array['i', 'h', 'b', 'm', 'u'] loop
    v_in := coalesce(p_data -> v_g, '{}'::jsonb);
    if jsonb_typeof(v_in) <> 'object' then
      return jsonb_build_object('ok', false, 'pesan', 'Data koleksi tidak valid.');
    end if;
    if (select count(*) from jsonb_object_keys(v_in)) > 30
       or exists (select 1 from jsonb_each(v_in) e
                   where e.key !~ '^[a-z0-9_]{1,16}$'
                      or jsonb_typeof(e.value) <> 'number'
                      or e.value::text !~ '^[0-9]{1,5}$') then
      return jsonb_build_object('ok', false, 'pesan', 'Data koleksi tidak valid.');
    end if;
    v_old := coalesce(v_lama -> v_g, '{}'::jsonb);
    select coalesce(jsonb_object_agg(x.k, x.mx), '{}'::jsonb) into v_gab
      from (select t.k, max(t.n) as mx
              from (select e.key as k, (e.value::text)::bigint as n from jsonb_each(v_in) e
                    union all
                    select e.key, (e.value::text)::bigint from jsonb_each(v_old) e) t
             group by t.k) x;
    v_hasil := v_hasil || jsonb_build_object(v_g, v_gab);
  end loop;

  if char_length(v_hasil::text) > 4000 then
    return jsonb_build_object('ok', false, 'pesan', 'Koleksi terlalu besar.');
  end if;
  insert into public.nb_koleksi (username, data) values (v_u, v_hasil)
  on conflict (username) do update set data = excluded.data, diperbarui = now();
  return jsonb_build_object('ok', true, 'data', v_hasil);
end;
$$;

-- Mencatat prestasi biasa (dihitung di game). Prestasi item langka tidak bisa dicatat lewat sini.
create or replace function public.nb_prestasi_catat(p_username text, p_pin text, p_kode text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_u text;
  v_baru boolean := false;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  v_u := v ->> 'username';
  if p_kode is null or p_kode !~ '^[a-z0-9_]{3,24}$' or p_kode ~ '^(langka_|legenda)' then
    return jsonb_build_object('ok', false, 'pesan', 'Kode prestasi tidak valid.');
  end if;
  if (select count(*) from public.nb_prestasi p where p.username = v_u) < 60 then
    insert into public.nb_prestasi (username, kode) values (v_u, p_kode) on conflict do nothing;
    v_baru := found;
  end if;
  return jsonb_build_object('ok', true, 'baru', v_baru);
end;
$$;

-- Pemain menyelesaikan Tantangan Legendaris: item langka masuk, pengumuman dikirim ke semua pemain.
-- Item langka: satu pemain saja yang bisa mengambil tiap kemunculan (win = nomor jendela waktu).
create table if not exists public.nb_langka_win (
  win      bigint primary key,
  username text not null,
  mapel    text not null,
  level    smallint not null,
  waktu    timestamptz not null default now()
);
alter table public.nb_langka_win enable row level security;
revoke all on public.nb_langka_win from anon, authenticated, public;
drop function if exists public.nb_langka_dapat(text, text, text);
create or replace function public.nb_langka_dapat(p_username text, p_pin text, p_mapel text, p_win bigint default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_u text;
  v_terakhir timestamptz;
  v_jumlah int;
  v_baru jsonb := '[]'::jsonb;
  v_legenda boolean := false;
  v_kode text;
  v_maks bigint;
  v_oleh text;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  v_u := v ->> 'username';
  if p_mapel is null or p_mapel not in ('ipa', 'ips', 'mat', 'ing', 'man') then
    return jsonb_build_object('ok', false, 'pesan', 'Item tidak dikenal.');
  end if;
  if p_win is null or p_win < 0 then
    return jsonb_build_object('ok', false, 'pesan', 'Muat ulang game dulu (versi lama), lalu coba lagi.');
  end if;
  select max(l.terakhir) into v_terakhir from public.nb_langka l where l.username = v_u;
  if v_terakhir is not null and v_terakhir > now() - interval '60 seconds' then
    return jsonb_build_object('ok', false, 'pesan', 'Tunggu sebentar sebelum tantangan berikutnya.');
  end if;

  -- Satu item langka hanya bisa diambil SATU pemain: siapa yang menyimpan duluan menang.
  insert into public.nb_langka_win (win, username, mapel, level) values (p_win, v_u, p_mapel, (v ->> 'kelas')::int)
  on conflict (win) do nothing;
  if not found then
    select w.username into v_oleh from public.nb_langka_win w where w.win = p_win;
    return jsonb_build_object('ok', false, 'diambil', true,
      'pesan', coalesce((select nama from public.nb_siswa where username = v_oleh), 'Pemain lain') || ' sudah mengambil item ini lebih dulu!');
  end if;

  insert into public.nb_langka (username, mapel) values (v_u, p_mapel)
  on conflict (username, mapel) do update set jumlah = public.nb_langka.jumlah + 1, terakhir = now()
  returning jumlah into v_jumlah;

  v_kode := 'langka_' || p_mapel;
  insert into public.nb_prestasi (username, kode) values (v_u, v_kode) on conflict do nothing;
  if found then v_baru := v_baru || to_jsonb(v_kode); end if;

  insert into public.nb_umum (jenis, mapel, nama, level)
  values ('langka', p_mapel, v ->> 'nama', (v ->> 'kelas')::int);

  if (select count(*) from public.nb_langka l where l.username = v_u) >= 5 then
    insert into public.nb_prestasi (username, kode) values (v_u, 'legenda') on conflict do nothing;
    if found then
      v_legenda := true;
      v_baru := v_baru || to_jsonb('legenda'::text);
      insert into public.nb_umum (jenis, mapel, nama, level)
      values ('legenda', '', v ->> 'nama', (v ->> 'kelas')::int);
    end if;
  end if;

  select max(u.id) into v_maks from public.nb_umum u;
  delete from public.nb_umum u where u.id <= v_maks - 200;
  update public.nb_siswa set terakhir = now() where username = v_u;
  return jsonb_build_object('ok', true, 'jumlah', v_jumlah, 'legenda', v_legenda, 'prestasi', v_baru);
end;
$$;

-- Dibaca SEMUA pemain tiap ~20 detik: pengumuman baru ("... mendapatkan item langka!").
--   p_sejak = -1 -> hanya minta penanda terakhir (tanpa berita) saat pertama masuk
--   p_sejak =  0 -> 20 berita terakhir (untuk tab Berita)
--   p_sejak >  0 -> berita yang lebih baru dari id itu (maksimal 15)
create or replace function public.nb_umum_baru(p_sejak bigint)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_maks bigint;
  v_rows jsonb;
  v_akhir bigint;
begin
  select coalesce(max(u.id), 0) into v_maks from public.nb_umum u;
  if p_sejak is null or p_sejak < 0 then
    return jsonb_build_object('ok', true, 'terakhir', v_maks, 'berita', '[]'::jsonb);
  end if;
  if p_sejak = 0 then
    select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'jenis', t.jenis, 'mapel', t.mapel, 'nama', t.nama,
             'level', t.level, 'waktu', (extract(epoch from t.dibuat) * 1000)::bigint) order by t.id), '[]'::jsonb)
      into v_rows
      from (select * from public.nb_umum u order by u.id desc limit 20) t;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'jenis', t.jenis, 'mapel', t.mapel, 'nama', t.nama,
             'level', t.level, 'waktu', (extract(epoch from t.dibuat) * 1000)::bigint) order by t.id), '[]'::jsonb)
      into v_rows
      from (select * from public.nb_umum u where u.id > p_sejak order by u.id asc limit 15) t;
  end if;
  select coalesce(max((r ->> 'id')::bigint), v_maks) into v_akhir from jsonb_array_elements(v_rows) r;
  return jsonb_build_object('ok', true, 'terakhir', v_akhir, 'berita', v_rows);
end;
$$;


-- ======================================================================
--  BATAS WAKTU BERMAIN HARIAN
--  Jatah dasar 30 menit per hari. Tiap misi selesai (sekali per misi per hari) menambah 15 menit,
--  bonus maksimal 30 menit per hari. Sisa waktu terbawa ke hari berikutnya, saldo maksimal 60 menit
--  (= terakumulasi paling banyak 2 hari). Hari diganti pukul 00.00 WIB. Semua dihitung di server.
-- ======================================================================
create table if not exists public.nb_waktu (
  username text primary key references public.nb_siswa(username) on delete cascade,
  hari     date    not null,                                   -- tanggal (WIB) terakhir dihitung
  saldo    integer not null default 1800 check (saldo between 0 and 10800),  -- detik waktu tersisa
  bonus    integer not null default 0 check (bonus between 0 and 1800),      -- detik bonus misi yang didapat hari ini
  dipakai  integer not null default 0,                         -- detik terpakai hari ini (info)
  terakhir timestamptz                                         -- detak terakhir sesi ini (null = sesi baru)
);
create table if not exists public.nb_waktu_misi (
  username text not null references public.nb_siswa(username) on delete cascade,
  hari     date not null,
  misi     text not null,
  primary key (username, hari, misi)
);
alter table public.nb_waktu      enable row level security;
alter table public.nb_waktu_misi enable row level security;
revoke all on table public.nb_waktu, public.nb_waktu_misi from anon, authenticated;
insert into public.nb_pengaturan (kunci, nilai) values ('batas_waktu', 'hidup') on conflict (kunci) do nothing;

-- Menghitung ulang baris waktu (ganti hari). Bukan untuk browser.
create or replace function public.nb_waktu_gulung(p_u text)
returns public.nb_waktu
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_hari date := (now() at time zone 'Asia/Jakarta')::date;
  w public.nb_waktu;
begin
  insert into public.nb_waktu (username, hari) values (p_u, v_hari) on conflict (username) do nothing;
  select * into w from public.nb_waktu where username = p_u for update;
  if w.hari < v_hari then
    update public.nb_waktu
       set saldo = case when saldo >= 3600 then saldo else least(3600, saldo + 1800 * (v_hari - hari)) end,
           bonus = 0, dipakai = 0, terakhir = null, hari = v_hari
     where username = p_u returning * into w;
    delete from public.nb_waktu_misi where username = p_u and hari < v_hari;
  end if;
  return w;
end;
$$;

create or replace function public.nb_waktu_json(w public.nb_waktu, p_tambah integer default 0)
returns jsonb
language sql stable set search_path = public
as $$
  select jsonb_build_object('aktif', coalesce((select nilai from public.nb_pengaturan where kunci = 'batas_waktu'), 'hidup') <> 'mati',
                            'saldo', w.saldo, 'bonus', w.bonus, 'tambah', p_tambah,
                            'sisa_bonus', 1800 - w.bonus, 'hari', w.hari);
$$;

-- Bonus waktu karena menyelesaikan misi (dipanggil nb_simpan). Sekali per misi per hari.
create or replace function public.nb_waktu_bonus(p_u text, p_misi text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  w public.nb_waktu := public.nb_waktu_gulung(p_u);
  v_tambah integer := 0; v_baru integer; v_n integer;
begin
  v_tambah := least(900, 1800 - w.bonus, greatest(0, 3600 - w.saldo));
  if v_tambah > 0 then
    insert into public.nb_waktu_misi (username, hari, misi) values (p_u, w.hari, p_misi) on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n = 1 then
      update public.nb_waktu set saldo = saldo + v_tambah, bonus = bonus + v_tambah where username = p_u returning * into w;
    else v_tambah := 0; end if;
  end if;
  return public.nb_waktu_json(w, v_tambah);
end;
$$;

-- Dipanggil saat masuk game: membaca sisa waktu hari ini.
create or replace function public.nb_waktu_ambil(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  w public.nb_waktu;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  w := public.nb_waktu_gulung(v ->> 'username');
  update public.nb_waktu set terakhir = null where username = w.username returning * into w;
  return jsonb_build_object('ok', true) || public.nb_waktu_json(w);
end;
$$;

-- Detak tiap ±20 detik saat siswa bermain. Server memotong waktu sebesar selang sejak detak terakhir
-- (maksimal 60 detik; bila terputus lebih dari 90 detik, selang itu tidak dihitung).
create or replace function public.nb_waktu_pakai(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  w public.nb_waktu; v_dt numeric; v_pakai integer := 0;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  w := public.nb_waktu_gulung(v ->> 'username');
  if w.terakhir is not null then
    v_dt := extract(epoch from (now() - w.terakhir));
    if v_dt <= 90 then v_pakai := least(60, greatest(0, round(v_dt)))::int; end if;
  end if;
  update public.nb_waktu set saldo = greatest(0, saldo - v_pakai), dipakai = dipakai + v_pakai, terakhir = now()
   where username = w.username returning * into w;
  return jsonb_build_object('ok', true) || public.nb_waktu_json(w);
end;
$$;

-- Guru menambah waktu bermain seorang siswa (5-120 menit; saldo maksimal 180 menit).
create or replace function public.nb_guru_waktu(p_kode text, p_username text, p_menit integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_err text := public.kg_cek_guru(p_kode);
  w public.nb_waktu; v_u text := lower(coalesce(p_username, ''));
begin
  if v_err is not null then return jsonb_build_object('ok', false, 'pesan', v_err); end if;
  if p_menit is null or p_menit not between 5 and 120 then
    return jsonb_build_object('ok', false, 'pesan', 'Tambahan waktu 5 sampai 120 menit.');
  end if;
  if not exists (select 1 from public.nb_siswa where username = v_u) then
    return jsonb_build_object('ok', false, 'pesan', 'Siswa tidak ditemukan.');
  end if;
  w := public.nb_waktu_gulung(v_u);
  update public.nb_waktu set saldo = least(10800, saldo + p_menit * 60) where username = v_u returning * into w;
  return jsonb_build_object('ok', true) || public.nb_waktu_json(w);
end;
$$;

-- Memilih kostum (hanya tampilan; kostum mana yang terbuka dihitung di game).
create or replace function public.nb_kostum_set(p_username text, p_pin text, p_kostum integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare v jsonb := public.nb_verifikasi(p_username, p_pin);
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  if p_kostum is null or p_kostum not between 0 and 15 then
    return jsonb_build_object('ok', false, 'pesan', 'Kostum tidak dikenal.');
  end if;
  update public.nb_siswa set kostum = p_kostum where username = v ->> 'username';
  return jsonb_build_object('ok', true, 'kostum', p_kostum);
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

revoke all on function public.nb_koleksi_ambil(text, text)            from public;
revoke all on function public.nb_koleksi_simpan(text, text, jsonb)    from public;
revoke all on function public.nb_prestasi_catat(text, text, text)    from public;
revoke all on function public.nb_langka_dapat(text, text, text, bigint) from public;
revoke all on function public.nb_umum_baru(bigint)                    from public;
revoke all on function public.nb_waktu_gulung(text)                   from public, anon, authenticated;
revoke all on function public.nb_waktu_json(public.nb_waktu, integer)  from public, anon, authenticated;
revoke all on function public.nb_waktu_bonus(text, text)              from public, anon, authenticated;
revoke all on function public.nb_waktu_ambil(text, text)              from public;
revoke all on function public.nb_waktu_pakai(text, text)              from public;
revoke all on function public.nb_guru_waktu(text, text, integer)      from public;
revoke all on function public.nb_kostum_set(text, text, integer)      from public;

grant execute on function public.nb_koleksi_ambil(text, text)         to anon, authenticated;
grant execute on function public.nb_koleksi_simpan(text, text, jsonb) to anon, authenticated;
grant execute on function public.nb_prestasi_catat(text, text, text)  to anon, authenticated;
grant execute on function public.nb_langka_dapat(text, text, text, bigint) to anon, authenticated;
grant execute on function public.nb_umum_baru(bigint)                 to anon, authenticated;
grant execute on function public.nb_waktu_ambil(text, text)           to anon, authenticated;
grant execute on function public.nb_waktu_pakai(text, text)           to anon, authenticated;
grant execute on function public.nb_guru_waktu(text, text, integer)   to anon, authenticated;
grant execute on function public.nb_kostum_set(text, text, integer)   to anon, authenticated;

-- =====================================================================
--  ITEM LANGKA: status (siapa yang sudah mengambil)
-- =====================================================================
create or replace function public.nb_langka_status(p_win bigint)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('diambil', true, 'oleh', coalesce(s.nama, 'Pemain lain'), 'mapel', w.mapel)
       from public.nb_langka_win w left join public.nb_siswa s on s.username = w.username where w.win = p_win),
    jsonb_build_object('diambil', false));
$$;

-- =====================================================================
--  MISI HARIAN (2 per hari; isi misi ditentukan game dari tanggal WIB)
-- =====================================================================
create table if not exists public.nb_harian (
  username text not null references public.nb_siswa(username) on delete cascade,
  hari     date not null,
  nomor    smallint not null check (nomor in (1, 2)),
  primary key (username, hari, nomor)
);
alter table public.nb_harian enable row level security;
revoke all on public.nb_harian from anon, authenticated, public;

create or replace function public.nb_harian_ambil(p_username text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_hari date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  return jsonb_build_object('ok', true, 'hari', v_hari,
    'selesai', coalesce((select jsonb_agg(h.nomor order by h.nomor) from public.nb_harian h where h.username = v ->> 'username' and h.hari = v_hari), '[]'::jsonb),
    'total', (select count(*) from public.nb_harian h where h.username = v ->> 'username'));
end;
$$;

-- Misi harian selesai: +10 menit waktu bermain (sekali per misi per hari, saldo tetap maksimal 60 menit)
create or replace function public.nb_harian_selesai(p_username text, p_pin text, p_nomor integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_u text; v_hari date := (now() at time zone 'Asia/Jakarta')::date;
  w public.nb_waktu; v_tambah integer := 0; v_n integer;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  v_u := v ->> 'username';
  if p_nomor is null or p_nomor not in (1, 2) then return jsonb_build_object('ok', false, 'pesan', 'Misi harian tidak dikenal.'); end if;
  insert into public.nb_harian (username, hari, nomor) values (v_u, v_hari, p_nomor) on conflict do nothing;
  get diagnostics v_n = row_count;
  w := public.nb_waktu_gulung(v_u);
  if v_n = 1 then
    v_tambah := least(600, greatest(0, 3600 - w.saldo));
    if v_tambah > 0 then update public.nb_waktu set saldo = saldo + v_tambah where username = v_u returning * into w; end if;
  end if;
  return jsonb_build_object('ok', true, 'baru', v_n = 1,
    'selesai', coalesce((select jsonb_agg(h.nomor order by h.nomor) from public.nb_harian h where h.username = v_u and h.hari = v_hari), '[]'::jsonb),
    'total', (select count(*) from public.nb_harian h where h.username = v_u),
    'waktu', public.nb_waktu_json(w, v_tambah));
end;
$$;

-- =====================================================================
--  RUANG CADANGAN (bertemu pemain lewat server bila WebSocket real time gagal, mis. di APK)
-- =====================================================================
create table if not exists public.nb_hadir (
  id       text primary key,
  username text not null,
  level    smallint not null,
  nama     text not null,
  skin     smallint not null default 0,
  kos      smallint not null default 0,
  x real not null default 0, y real not null default 0, z real not null default 0,
  r real not null default 0, vx real not null default 0, vz real not null default 0,
  e smallint not null default 0,
  et bigint not null default 0,
  t  timestamptz not null default now()
);
create index if not exists nb_hadir_lv on public.nb_hadir (level, t desc);
alter table public.nb_hadir enable row level security;
revoke all on public.nb_hadir from anon, authenticated, public;

create or replace function public.nb_ruang(p_username text, p_pin text, p_id text, p_s jsonb, p_keluar boolean default false)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v jsonb := public.nb_verifikasi(p_username, p_pin);
  v_u text; v_lv smallint;
begin
  if not (v ->> 'ok')::boolean then return v; end if;
  v_u := v ->> 'username'; v_lv := (v ->> 'kelas')::smallint;
  if p_id is null or char_length(p_id) > 40 or left(p_id, char_length(v_u) + 1) <> v_u || '.' then
    return jsonb_build_object('ok', false, 'pesan', 'ID ruang tidak valid.');
  end if;
  if p_keluar then delete from public.nb_hadir where id = p_id and username = v_u; return jsonb_build_object('ok', true); end if;
  insert into public.nb_hadir (id, username, level, nama, skin, kos, x, y, z, r, vx, vz, e, et, t)
  values (p_id, v_u, v_lv, v ->> 'nama', (v ->> 'skin')::smallint,
          greatest(0, least(15, coalesce((p_s ->> 'k')::int, 0))),
          coalesce((p_s ->> 'x')::real, 0), coalesce((p_s ->> 'y')::real, 0), coalesce((p_s ->> 'z')::real, 0),
          coalesce((p_s ->> 'r')::real, 0), coalesce((p_s ->> 'vx')::real, 0), coalesce((p_s ->> 'vz')::real, 0),
          greatest(0, least(20, coalesce((p_s ->> 'e')::int, 0))), coalesce((p_s ->> 'et')::bigint, 0), now())
  on conflict (id) do update set level = excluded.level, nama = excluded.nama, skin = excluded.skin, kos = excluded.kos,
    x = excluded.x, y = excluded.y, z = excluded.z, r = excluded.r, vx = excluded.vx, vz = excluded.vz,
    e = case when excluded.et > public.nb_hadir.et then excluded.e else public.nb_hadir.e end,
    et = greatest(excluded.et, public.nb_hadir.et), t = now()
  where public.nb_hadir.username = v_u;
  if random() < 0.03 then delete from public.nb_hadir where t < now() - interval '2 minutes'; end if;
  return jsonb_build_object('ok', true, 'o', coalesce((
    select jsonb_agg(jsonb_build_object('i', h.id, 'n', h.nama, 's', h.skin, 'k', h.kos, 'x', h.x, 'y', h.y, 'z', h.z, 'r', h.r,
                                        'vx', h.vx, 'vz', h.vz, 'e', h.e, 'et', h.et))
      from (select * from public.nb_hadir where level = v_lv and id <> p_id and t > now() - interval '9 seconds' order by t desc limit 14) h), '[]'::jsonb));
end;
$$;

revoke all on function public.nb_langka_status(bigint)                       from public;
revoke all on function public.nb_harian_ambil(text, text)                    from public;
revoke all on function public.nb_harian_selesai(text, text, integer)         from public;
revoke all on function public.nb_ruang(text, text, text, jsonb, boolean)     from public;
grant execute on function public.nb_langka_status(bigint)                    to anon, authenticated;
grant execute on function public.nb_harian_ambil(text, text)                 to anon, authenticated;
grant execute on function public.nb_harian_selesai(text, text, integer)      to anon, authenticated;
grant execute on function public.nb_ruang(text, text, text, jsonb, boolean)  to anon, authenticated;

-- Minta Supabase membaca ulang daftar fungsi agar langsung bisa dipanggil game.
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
--  Perintah yang mungkin kamu perlukan nanti (jalankan satu per satu):
--
--  Tutup / buka pendaftaran siswa baru:
--    update public.nb_pengaturan set nilai = 'tutup' where kunci = 'pendaftaran';
--    update public.nb_pengaturan set nilai = 'buka'  where kunci = 'pendaftaran';
--
--  Matikan / hidupkan batas waktu bermain harian untuk semua siswa:
--    update public.nb_pengaturan set nilai = 'mati'  where kunci = 'batas_waktu';
--    update public.nb_pengaturan set nilai = 'hidup' where kunci = 'batas_waktu';
--
--  Hapus satu siswa (progresnya ikut terhapus):
--    delete from public.nb_siswa where username = 'nama.pengguna';
-- ---------------------------------------------------------------------
