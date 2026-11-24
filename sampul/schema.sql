-- Cetak Rapor SD: skema database untuk Supabase.
-- Jalankan sekali di Supabase > SQL Editor > New query > Run.
-- Aman dijalankan ulang: tidak menghapus data yang sudah ada.

-- 1. Identitas sekolah (selalu satu baris, id = 1)
create table if not exists public.rapor_sekolah (
  id           int primary key default 1 check (id = 1),
  nama         text not null default '',
  npsn         text not null default '',
  alamat       text not null default '',
  kodepos      text not null default '',
  desa         text not null default '',
  kecamatan    text not null default '',
  kabupaten    text not null default '',
  provinsi     text not null default '',
  website      text not null default '',
  email        text not null default '',
  kepsek       text not null default '',
  nip          text not null default '',
  kota         text not null default 'Semarang',
  tanggal      text not null default '',
  kemen1       text not null default 'KEMENTERIAN PENDIDIKAN DAN KEBUDAYAAN',
  kemen2       text not null default 'REPUBLIK INDONESIA',
  font         text not null default 'helvetica',
  logo_twh     jsonb,
  logo_sekolah jsonb,
  updated_at   timestamptz not null default now()
);

-- 2. Data peserta didik
create table if not exists public.rapor_siswa (
  id            uuid primary key default gen_random_uuid(),
  nama          text not null,
  nis           text not null default '',
  nisn          text not null default '',
  tempat_lahir  text not null default '',
  tanggal_lahir text not null default '',
  jk            text not null default '',
  agama         text not null default '',
  pendidikan    text not null default '',
  alamat        text not null default '',
  ayah          text not null default '',
  ibu           text not null default '',
  kerja_ayah    text not null default '',
  kerja_ibu     text not null default '',
  ortu_jalan    text not null default '',
  ortu_kel      text not null default '',
  ortu_kec      text not null default '',
  ortu_kab      text not null default '',
  ortu_prov     text not null default '',
  wali_nama     text not null default '',
  wali_kerja    text not null default '',
  wali_alamat   text not null default '',
  mut_tanggal   text not null default '',
  mut_kelas     text not null default '',
  mut_alasan    text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists rapor_siswa_nama_idx on public.rapor_siswa (nama);

-- 3. Baris awal identitas sekolah
insert into public.rapor_sekolah (id, nama)
values (1, 'SD Tunas Harum Bangsa')
on conflict (id) do nothing;

-- 4. Keamanan: hanya akun yang sudah login (staf) yang boleh mengakses data.
alter table public.rapor_sekolah enable row level security;
alter table public.rapor_siswa   enable row level security;

drop policy if exists "staf baca sekolah"   on public.rapor_sekolah;
drop policy if exists "staf tambah sekolah" on public.rapor_sekolah;
drop policy if exists "staf ubah sekolah"   on public.rapor_sekolah;
drop policy if exists "staf baca siswa"     on public.rapor_siswa;
drop policy if exists "staf tambah siswa"   on public.rapor_siswa;
drop policy if exists "staf ubah siswa"     on public.rapor_siswa;
drop policy if exists "staf hapus siswa"    on public.rapor_siswa;

create policy "staf baca sekolah"   on public.rapor_sekolah for select to authenticated using (true);
create policy "staf tambah sekolah" on public.rapor_sekolah for insert to authenticated with check (true);
create policy "staf ubah sekolah"   on public.rapor_sekolah for update to authenticated using (true) with check (true);

create policy "staf baca siswa"     on public.rapor_siswa for select to authenticated using (true);
create policy "staf tambah siswa"   on public.rapor_siswa for insert to authenticated with check (true);
create policy "staf ubah siswa"     on public.rapor_siswa for update to authenticated using (true) with check (true);
create policy "staf hapus siswa"    on public.rapor_siswa for delete to authenticated using (true);

-- Pengunjung tanpa login (role anon) tidak mendapat policy apa pun,
-- sehingga tidak bisa membaca satu baris pun.

-- 5. Izin tabel untuk Data API.
-- Sejak 2026 Supabase tidak lagi memberi izin otomatis untuk tabel baru di schema public,
-- jadi izin harus diberikan sendiri. Tanpa bagian ini aplikasi gagal memuat data
-- ("permission denied for table ..."), walaupun tabel dan policy di atas sudah ada.
-- Hanya akun yang login (authenticated) yang diberi izin; pengunjung (anon) dicabut.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.rapor_sekolah to authenticated;
grant select, insert, update, delete on public.rapor_siswa   to authenticated;
revoke all on public.rapor_sekolah from anon;
revoke all on public.rapor_siswa   from anon;
