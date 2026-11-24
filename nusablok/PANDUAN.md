# NusaBlok · Panduan Guru

NusaBlok adalah game petualangan 3D bergaya balok (tanpa merek Minecraft) untuk siswa SD kelas 1–6.
Siswa berjalan di pulau NusaBlok, menemui penjaga di lima wilayah, dan menjawab soal pelajaran untuk mendapat bintang.
Di luar pulau utama ada **lima pulau kecil "Misi Guru"** (satu per pelajaran) tempat misi buatan guru berada. Pulau-pulau itu dihubungkan jembatan kayu dari tiap wilayah.

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

## Menambah misi sendiri (oleh guru)

Selain 150 misi bawaan, guru bisa membuat misi tambahan yang berisi soal buatan sendiri.

1. Di layar masuk, klik **👩‍🏫 Untuk Guru**, masukkan kode guru, lalu buka tab **⭐ Misi Guru**.
2. Pilih pelajaran dan kelas, lalu ketuk **＋ Misi Baru**.
3. Isi **judul misi**, **nama penjaga** (boleh kosong, kalau kosong tertulis "Bapak/Ibu Guru"), dan **cerita pembuka** (boleh kosong).
4. Tulis **3 sampai 8 soal**. Tiap soal: satu pertanyaan, **satu jawaban benar**, dan **2 atau 3 jawaban salah** yang masuk akal. Pilihan dalam satu soal tidak boleh kembar.
5. Ketuk **💾 Simpan Misi**. Siswa di kelas itu melihatnya saat masuk game berikutnya.

Yang perlu diketahui:

- Misi muncul sebagai penjaga **bertopi emas** di pulau Misi Guru untuk pelajaran itu (mis. IPA di *Kebun Percobaan*, Matematika di *Taman Angka*). Siswa kelas 3 hanya melihat misi yang ditulis untuk kelas 3.
- Tiap pelajaran dan kelas punya **10 tempat** (jadi maksimal 10 misi guru per pelajaran per kelas, total 300). Tempat yang kosong terpakai lagi setelah misi dihapus.
- Siswa mengerjakan **3 soal** setiap kali main. Bila kamu menulis lebih dari 3 soal, 3 yang keluar diacak, jadi soalnya bervariasi. Aturan bintangnya sama dengan misi bawaan.
- Misi guru adalah **bonus**: tidak dihitung pada "20 dari 25 misi" untuk naik level. Bintangnya tetap ikut dihitung di total ⭐ siswa.
- **Tempel banyak soal sekaligus:** ketuk **📋 Tempel banyak soal**, lalu tulis satu soal per baris, dipisah tanda `|`:
  `Berapa hasil 3 x 4? | 12 | 7 | 10 | 14`
  (pertanyaan | jawaban benar | salah 1 | salah 2 | salah 3 yang boleh dikosongkan). Salinan dari kolom Excel atau Google Sheets (dipisah Tab) juga bisa.
- **Sembunyikan sementara:** hilangkan centang *Tampilkan ke siswa*. Misi tidak muncul bagi siswa, tetapi tidak terhapus.
- **Menghapus misi** (🗑️) juga menghapus bintang siswa dari misi itu. Mengubah pelajaran atau kelas misi berarti memindahkannya dan juga menghapus bintang lamanya.
- Panel Guru → tab **Siswa** menampilkan jumlah misi guru yang selesai di kolom Misi (mis. `18 +2 guru`), dan jumlahnya ada di unduhan CSV.
- Soal dan kunci jawabannya dikirim ke peramban siswa agar game bisa berjalan, jadi siswa yang mahir teknis bisa membacanya lewat alat pengembang peramban. Sama seperti misi bawaan, jadi jangan dipakai untuk ujian yang bernilai.

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
2. Di Supabase: **SQL Editor → New query**, tempel isi `supabase_setup.sql`, lalu **Run**. Berkas ini aman dijalankan ulang, dan **wajib dijalankan ulang bila game diperbarui** (versi ini menambah fitur misi guru).
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
| Tab **Misi Guru** berkata "belum bisa dimuat" | `supabase_setup.sql` versi terbaru belum dijalankan di Supabase. Jalankan (aman diulang), lalu muat ulang. |
| Misi guru baru tidak terlihat siswa | Siswa harus masuk ulang (atau muat ulang halaman). Periksa juga kelas misi sama dengan level siswa dan misi tidak disembunyikan. |
| Siswa lupa PIN | Panel Guru → tombol **PIN**. |
| Siswa merasa soal terlalu mudah/sulit | Panel Guru → ubah **Level**. |
| Layar hitam atau dunia tidak muncul | Perangkat/peramban terlalu lama. Coba Chrome versi terbaru. |
| Progres belum tersimpan karena internet putus | Game mengantre dan mengirim ulang otomatis saat siswa masuk lagi dengan internet menyala. |
