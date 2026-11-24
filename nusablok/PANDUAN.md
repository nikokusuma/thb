# NusaBlok · Panduan Guru

NusaBlok adalah game petualangan 3D bergaya balok (tanpa merek Minecraft) untuk siswa SD kelas 1–6.
Siswa berjalan di pulau NusaBlok, menemui penjaga di lima wilayah, dan menjawab soal pelajaran untuk mendapat bintang.

| Wilayah | Pelajaran |
|---|---|
| 🔬 Desa Sains | IPA |
| 🏛️ Kota Nusantara | IPS |
| 🔢 Menara Angka | Matematika |
| ⚓ Harbor English | Bahasa Inggris |
| 🏮 Kuil Hanzi | Bahasa Mandarin |

## Alamat game

`https://nikokusuma.github.io/thb/nusablok/`

Bisa dibuka di komputer, Chromebook, tablet, dan HP (siswa memakai sentuhan layar atau keyboard).

## Cara siswa mulai

1. Buka alamat game, pilih **Daftar Baru**.
2. Isi username (huruf kecil/angka), nama panggilan, kelas di sekolah, pilih karakter, dan buat PIN 4 angka.
3. Game memberi **tes penempatan** singkat (5–15 soal dari 5 pelajaran, tergantung jawabannya) untuk mencari level yang cocok. Tes ini sama sekali bukan ujian dan tidak ada nilai yang tampil.
4. Siswa masuk ke dunia game. Hari berikutnya cukup memilih **Masuk** dengan username dan PIN.

## Level dan misi

- Ada **6 level (kelas 1–6)**. Setiap level punya **25 misi berbeda**: 5 misi untuk setiap pelajaran. Total **150 misi**, tidak ada soal yang sama antar level.
- Soal Matematika dibuat acak setiap kali, jadi jawabannya tidak bisa dihafal.
- Setiap misi berisi 3 soal. Benar 3 soal = ⭐⭐⭐, benar 2 soal = ⭐⭐, selain itu belum berhasil dan boleh diulang. Bintang tidak pernah turun.
- Setelah **20 dari 25 misi** di satu level selesai, tombol **Naik ke Kelas berikutnya** muncul di menu 📋 Misi.
- Siswa hanya bisa melihat dan mengerjakan misi di levelnya sekarang.

## Mengubah level siswa (oleh guru)

1. Di layar masuk, klik **👩‍🏫 Untuk Guru**.
2. Masukkan **kode guru** (sama dengan kode guru Penjaga Kode).
3. Di tabel, ubah menu **Level** pada baris siswa. Perubahan langsung tersimpan dan berlaku saat siswa masuk lagi.

Panel ini juga menampilkan kelas sekolah, jumlah bintang, jumlah misi selesai per pelajaran, dan tanggal terakhir bermain.
Tombol **PIN** mengatur ulang PIN siswa yang lupa. Tombol **CSV** mengunduh rekap untuk Excel.

## Bertemu teman di level yang sama (real time)

- Siswa yang berada di **level yang sama** muncul di dunia yang sama dan bisa saling melihat berjalan.
- Satu ruang maksimal **10 pemain**. Bila penuh, siswa berikutnya otomatis masuk ruang lain di level yang sama. Ini menjaga game tetap lancar dan memenuhi batas paket gratis Supabase.
- Tidak ada kolom obrolan bebas. Siswa hanya bisa menyapa lewat tombol 💬 dengan 6 kalimat ramah yang sudah disediakan, jadi aman untuk anak.
- Pergerakan pemain tidak disimpan di database; data hanya lewat sambungan real time dan hilang saat siswa keluar.

Batas Supabase paket gratis: 200 sambungan bersamaan dan 100 pesan per detik untuk seluruh project. Untuk satu atau dua kelas bermain bersamaan ini cukup. Bila seluruh sekolah ingin bermain serentak, pertimbangkan paket Pro.

## Pemasangan

Game sudah terpasang di project Supabase "thb app" (tabel berawalan `nb_`, tidak mengganggu aplikasi lain).
Untuk memasang di project lain:

1. Jalankan setup Penjaga Kode lebih dulu (game ini memakai kode gurunya).
2. Di Supabase: **SQL Editor → New query**, tempel isi `supabase_setup.sql`, lalu **Run**.
3. Isi `config.js` dengan URL project dan kunci *publishable* (kunci ini aman dilihat orang; jangan pernah menaruh kunci *secret*).
4. Unggah `index.html` dan `config.js` ke folder `nusablok/` di GitHub Pages.

Mengosongkan nilai di `config.js` membuat game berjalan dalam **mode coba**: data hanya di perangkat itu, ada tiga pemain tiruan 🤖, dan kode guru adalah `guru1234`.

Menutup pendaftaran siswa baru (jalankan di SQL Editor):
`update public.nb_pengaturan set nilai = 'tutup' where kunci = 'pendaftaran';`
(ganti `'tutup'` dengan `'buka'` untuk membukanya lagi).

## Bila ada masalah

| Gejala | Yang dicek |
|---|---|
| Tulisan **📡 Tidak tersambung · main sendiri** | Internet sekolah memblokir sambungan real time, atau Realtime di Supabase belum mengizinkan kanal publik. Cek **Project Settings → Realtime → Allow public access**. Game tetap bisa dimainkan sendirian dan progres tetap tersimpan. |
| Siswa lupa PIN | Panel Guru → tombol **PIN**. |
| Siswa merasa soal terlalu mudah/sulit | Panel Guru → ubah **Level**. |
| Layar hitam atau dunia tidak muncul | Perangkat/peramban terlalu lama. Coba Chrome versi terbaru. |
| Progres belum tersimpan karena internet putus | Game mengantre dan mengirim ulang otomatis saat siswa masuk lagi dengan internet menyala. |
