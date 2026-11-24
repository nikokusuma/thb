# Penjaga Kode: Panduan Guru

Game belajar koding untuk kelas 1–6 dengan cerita **Petualangan Nusantara**. Siswa masuk dengan username + PIN 4 angka, progresnya tersimpan per akun, dan ending ceritanya berbeda sesuai bintang yang dikumpulkan.

## Isi paket

| File | Fungsi |
|---|---|
| `index.html` | Seluruh game. Boleh diganti kapan saja saat ada misi baru. |
| `config.js` | Alamat dan kunci Supabase. Tidak ikut berubah saat `index.html` diganti. |
| `supabase_setup.sql` | Menyiapkan penyimpanan akun dan progres di Supabase. |
| `PANDUAN.md` | Panduan ini. |

## 1. Coba dulu tanpa internet (mode demo)

Buka `index.html` langsung di browser (tanpa `config.js`, atau dengan `config.js` yang masih kosong), game berjalan dalam **mode demo**:

- Akun dan progres hanya tersimpan di browser itu (tidak online).
- Kode guru demo: `guru`.
- Tambahkan `?semua` di akhir alamat (contoh: `index.html?semua`) untuk membuka semua misi dan dunia. Berguna untuk menguji; jangan dibagikan ke siswa.

## 2. Menyambungkan ke Supabase (agar bisa dimainkan online)

1. Buka project Supabase. Boleh memakai project yang sudah dipakai untuk bank soal: semua tabel dan fungsi game memakai awalan `kg_`, jadi tidak bentrok.
2. Buka `supabase_setup.sql` di editor teks. **Ganti `GANTI-KODE-INI`** dengan kode guru milikmu (minimal 8 karakter, jangan dibagikan ke siswa).
3. Di Supabase, buka **SQL Editor → New query**, tempel seluruh isi file, lalu **Run**. Aman diulang; data siswa tidak terhapus.
4. Buka **Project Settings → API**. Salin **Project URL** dan **anon public key**.
5. Buka `config.js` dengan editor teks, lalu isi:
   ```js
   window.KG_CONFIG = {
     SUPABASE_URL: 'https://xxxx.supabase.co',
     SUPABASE_ANON_KEY: 'sb_publishable_...'   // atau kunci anon lama yang berawalan eyJ
   };
   ```
6. Simpan. Game kini otomatis memakai Supabase.

Catatan keamanan:
- Kunci **anon public** memang dirancang terlihat publik. Tabel dikunci, dan browser hanya boleh memanggil fungsi `kg_...`.
- **Jangan pernah** menaruh kunci `secret` atau `service_role` di `config.js`.
- PIN disimpan dalam bentuk acak (bcrypt), bukan teks biasa. PIN salah 5 kali mengunci akun 5 menit. Kode guru salah 10 kali mengunci halaman guru 10 menit.
- Minta siswa memakai **nama panggilan**, bukan nama lengkap atau data pribadi.

## 3. Mengunggah ke GitHub Pages

1. Di repo GitHub-mu, buat folder baru (misalnya `penjaga-kode`) dan unggah `index.html` serta `config.js` ke dalamnya.
2. Pastikan **Settings → Pages** sudah aktif (sumber: branch utama).
3. Alamat game: `https://<username-github>.github.io/<nama-repo>/penjaga-kode/`
4. Bagikan alamat itu ke siswa. Cukup sekali daftar; berikutnya masuk dengan username + PIN dari perangkat apa pun.

Setelah mengubah berkas di GitHub, tunggu 1–2 menit lalu muat ulang halaman.

## 4. Menggunakan halaman guru

Di halaman masuk, tekan **Masuk sebagai guru** lalu isi kode guru. Di sana kamu bisa:

- melihat daftar siswa, jumlah misi selesai, total bintang, dan tanggal terakhir main;
- **Reset PIN** siswa yang lupa (sekaligus membuka kunci akunnya);
- **Ubah kelas** siswa. Dunia yang terbuka mengikuti kelas siswa, misalnya siswa kelas 3 bisa bermain Dunia 1–3;
- **Unduh CSV** untuk rekap (bisa dibuka di Excel/Google Sheets).

Perintah SQL yang berguna (jalankan di SQL Editor):

```sql
-- ganti kode guru
update public.kg_pengaturan
   set nilai = extensions.crypt('KODE-BARU-KAMU', extensions.gen_salt('bf'))
 where kunci = 'kode_guru';

-- tutup pendaftaran setelah semua siswa terdaftar (ganti 'buka' untuk membukanya lagi)
update public.kg_pengaturan set nilai = 'tutup' where kunci = 'pendaftaran';

-- hapus satu siswa beserta progresnya
delete from public.kg_siswa where username = 'nama.pengguna';
```

## 5. Cara kerja cerita dan ending

- Ada 6 dunia, satu per kelas. Misi terbuka berurutan; bab baru memunculkan cerita pendek.
- Cara koding naik bertahap: kelas rendah memakai **puzzle dan blok**, lalu bertahap ke **kode teks** berbahasa Indonesia (`maju`, `ulangi 3 kali { ... }`, `jika depan_kosong { ... }`, `fungsi ...`).
- Jenis misi: antar Kodi di peta, urutkan langkah, lengkapi pola, pilihan, cari kesalahan, dan tebak hasil kode.
- Bintang: 3 bintang bila kodenya sama singkat dengan jawaban terbaik. Memakai petunjuk membatasi hasil maksimal 2 bintang.
- Tiap dunia punya 3 ending (emas, perak, perunggu) menurut bintang di dunia itu.
- **Ending akhir** muncul setelah Dunia 6 selesai, dihitung dari seluruh bintang: Garuda Emas (≥ 85%), Penjaga Kristal (≥ 60%), Penjelajah Pemberani (≥ 35%), Sahabat Kodi (di bawahnya). Siswa boleh mengulang misi untuk menambah bintang, dan ending-nya ikut berubah.

## 6. Status misi dan menambah misi

Saat ini tersedia **25 misi per kelas (total 150)** sebagai contoh lengkap semua jenis misi. Mesin game sudah siap untuk 100 misi per kelas (600 total). Tinggal menambah misinya per tahap, misalnya 25 misi per kelas per tahap, dengan jumlah bab per dunia ikut membesar. Minta tahap berikutnya kapan saja, lalu `index.html` baru diunggah menimpa yang lama (`config.js` tidak perlu diubah). Akun dan progres siswa tetap aman karena tersimpan di Supabase.

## 7. Bila ada masalah

- **"Server menolak permintaan"**: SQL setup belum dijalankan, atau URL/anon key salah salin.
- **Siswa lupa PIN**: Reset PIN di halaman guru.
- **Username sudah dipakai**: minta siswa menambah angka di belakang usernamenya.
- **Progres tidak tersimpan saat sinyal buruk**: game menyimpannya sementara di perangkat dan mengirim ulang otomatis saat tersambung lagi.
- Font bulat (Fredoka) dimuat dari Google Fonts. Tanpa internet, game memakai font bawaan perangkat dan tetap berfungsi.
