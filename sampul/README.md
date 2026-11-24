# Cetak Rapor SD

Aplikasi web untuk mencetak **cover rapor, identitas sekolah, identitas peserta didik (dengan tempat foto 3x4 dan tanda tangan kepala sekolah), dan tabel keterangan pindah sekolah** dalam ukuran A4.

- Tampilan: satu halaman statis (`index.html`), dihosting gratis di **GitHub Pages**.
- Database online: **Supabase** (identitas sekolah, logo, dan data siswa).
- Login: akun staf yang dibuat di Supabase. Tanpa login, data tidak bisa dibaca.
- Data siswa diisi lewat **template Excel** (tombol *Unduh template* di aplikasi).

## Isi folder

| Berkas | Fungsi |
| --- | --- |
| `index.html` | Seluruh aplikasi |
| `config.js` | Alamat dan kunci Supabase (Anda isi sendiri) |
| `schema.sql` | Membuat tabel dan aturan keamanan di Supabase |
| `Template-Data-Siswa-Rapor.xlsx` | Salinan template Excel (di aplikasi juga ada) |

## Langkah pemasangan

### 1. Siapkan Supabase

1. Masuk ke supabase.com, buat proyek baru (atau pakai proyek yang sudah ada; nama tabel diawali `rapor_` sehingga tidak bentrok dengan tabel lain).
2. Buka **SQL Editor**, pilih **New query**, tempel seluruh isi `schema.sql`, lalu klik **Run**. Aman dijalankan ulang.
3. Buka **Authentication > Users > Add user**. Isi email dan kata sandi, lalu centang **Auto Confirm User**. Buat satu akun untuk setiap staf yang akan memakai aplikasi.
4. Matikan pendaftaran mandiri: **Authentication > Sign In / Providers** (atau *Settings*), matikan **Allow new users to sign up**. Ini penting karena aplikasi memuat data anak; hanya akun yang Anda buat yang boleh masuk.
5. Buka **Project Settings > API** (atau *Data API*). Salin **Project URL** dan kunci **anon / publishable**.

### 2. Isi `config.js`

Ganti dua nilai di `config.js` dengan Project URL dan kunci tadi. Kunci anon memang dirancang untuk dipakai di browser; keamanan data dijaga oleh aturan RLS di `schema.sql`. Jangan memakai kunci `service_role` atau `secret`.

### 3. Unggah ke GitHub

1. Buat repository baru di GitHub (misalnya `rapor-sd`).
2. Klik **Add file > Upload files**, seret semua berkas di folder ini, lalu **Commit changes**.
3. Buka **Settings > Pages**. Pada *Build and deployment*, pilih **Deploy from a branch**, branch `main`, folder `/ (root)`, lalu **Save**.
4. Tunggu satu sampai dua menit. Alamat aplikasi muncul di halaman yang sama, biasanya `https://NAMA-AKUN.github.io/rapor-sd/`.

Jika ingin menaruhnya di repository yang sudah dipakai aplikasi lain, letakkan semua berkas ini di dalam sebuah subfolder (misalnya `rapor/`) supaya `index.html` aplikasi lain tidak tertimpa. Alamatnya menjadi `.../rapor/`.

### 4. Pakai

1. Buka alamat aplikasi, masuk dengan akun staf.
2. Tab **Sekolah**: isi identitas sekolah, nama kepala sekolah, dan unggah dua logo (Tut Wuri Handayani dan logo sekolah). Perubahan tersimpan otomatis.
3. Tab **Data Siswa**: unduh template Excel, isi, lalu unggah. Pilihan *Ganti semua data* menghapus siswa lama; pilihan *Tambahkan ke daftar* menambah di bawahnya.
4. Tab **Cetak**: pilih dokumen dan siswa, periksa pratinjau, klik **Buat PDF**. Cetak PDF di kertas A4 dengan skala 100%.

## Jika aplikasi tidak bisa dipakai

Di layar masuk (dan di kotak merah bila data gagal dimuat) ada tombol **Tes koneksi database**. Tombol ini memeriksa satu per satu dan menulis hasilnya di layar:

| Hasil tes | Artinya | Perbaikan |
| --- | --- | --- |
| Supabase tidak bisa dijangkau | `SUPABASE_URL` salah ketik, atau proyek sedang dijeda | Periksa `config.js`; aktifkan proyek di dashboard Supabase |
| Kunci ditolak | `SUPABASE_ANON_KEY` salah atau terpotong | Salin ulang kunci anon/publishable (bukan `secret`) |
| Tabel ... belum ada | `schema.sql` belum dijalankan | Jalankan seluruh isi `schema.sql` di SQL Editor. Jika muncul peringatan tentang `drop policy`, pilih **Run this query** |
| Layanan login aktif, tabel ada, tetapi tidak bisa masuk | Akun belum dibuat atau belum dikonfirmasi | Authentication > Users > Add user, centang **Auto Confirm User** |

Setelah mengubah `config.js` di GitHub, tunggu satu sampai dua menit lalu muat ulang dengan **Ctrl+Shift+R** (di ponsel: tutup tab lalu buka lagi), karena GitHub Pages dan browser menyimpan salinan lama.

## Catatan

- **Keamanan data.** Tabel hanya bisa diakses akun yang sudah login. Pengunjung tanpa akun tidak mendapat data apa pun, walaupun alamat situs diketahui. Semua akun staf bisa melihat dan mengubah semua data.
- **Lupa kata sandi.** Atur ulang lewat Supabase: Authentication > Users.
- **Proyek gratis Supabase** dapat dijeda otomatis bila lama tidak dipakai. Jika aplikasi gagal tersambung, buka dashboard Supabase dan aktifkan kembali proyeknya.
- **Cadangan.** Tombol *Unduh data (Excel)* di tab Data Siswa menyimpan seluruh data siswa ke file Excel yang bisa diunggah ulang.
- **Mengubah teks cover.** Teks "KEMENTERIAN ..." dan jenis huruf dapat diubah di tab Sekolah.
- **Pustaka dari internet.** Aplikasi memuat supabase-js, jsPDF, dan SheetJS dari CDN (jsDelivr dan cdnjs), jadi perlu koneksi internet.
