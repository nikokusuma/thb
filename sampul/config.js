// Isi dua nilai ini dengan data dari proyek Supabase Anda.
// Lokasi: Supabase > Project Settings > API (atau "Data API").
//
// SUPABASE_URL      : alamat proyek, contoh https://abcdefghijkl.supabase.co
// SUPABASE_ANON_KEY : kunci "anon public" atau "publishable".
//
// Kunci ini memang dibuat untuk dipakai di browser. Data tetap aman karena
// tabel dilindungi aturan RLS di schema.sql: hanya akun yang sudah login yang
// bisa membaca atau mengubah data. JANGAN pernah menaruh kunci "service_role"
// atau "secret" di berkas ini.

window.RAPOR_CONFIG = {
  SUPABASE_URL: "GANTI-DENGAN-PROJECT-URL",
  SUPABASE_ANON_KEY: "GANTI-DENGAN-ANON-KEY"
};
