# Sampel legit tambahan (uji salah-tangkap layer 3)

Ambil 28 Oktober 2026. Tujuan: ukur false positive L3 pada halaman sah (PPDB/SPMB, SSO kampus, layanan pemerintah, bank/fintech, login HP, toko). Hanya halaman pertama, tidak submit, tidak mengisi data.

## Metode

- 44 URL dicoba: `curl` dulu (cek status), lalu **Chrome headless** (`--dump-dom`, UA iPhone Safari 17, JS dijalankan, 9 dtk virtual time). Beda dari eval scam awal yang memakai `curl` saja, supaya form buatan JS (SPA) ikut terbaca seperti di extension.
- DOM di-parse dengan parser yang sama (`html.parser`), lalu `analyzeSnapshot` dari kode saat ini (termasuk keyword token bank dan kata aksi title `otp`/`pin`). `localSignals` kosong, tanpa RDAP (semua domain sah tua).
- HTML tidak disimpan di repo.

## Hasil

| status | n |
|---|---:|
| URL dicoba | 44 |
| tidak terbuka (DNS mati, SSL rusak, timeout) | 14 |
| render kosong (timeout Chrome) | 2 (M32 kitabisa, M36 zenius) |
| host resmi/populer, L3 diam (`isOfficialHost`) | 3 (M39 GitHub, M40 Netflix, M44 Shopee) |
| **dianalisis penuh** | **25** |

- **0 dari 25** mencapai 30. Skor tertinggi **15**.
- `asks_password` 15: M09 (`sso.ui.ac.id`, username + password).
- `brand_logo_offsite` 12 (quiet): M38 (Glints, tanpa form).
- Sisanya 0: PPDB/SPMB (M02, M06, M07, M08), kampus (M12), pemerintah (M17, M19, M21, M22), bank/fintech (M23–M31), login HP (M33, M35, M37), toko (M41, M42).
- 13 dari 25 punya field di halaman pertama, tapi hampir semuanya pencarian, nama, email, HP, atau isian simulasi. Tidak ada field OTP, PIN, KTP/NIK, atau kartu.

## Yang tidak bisa disimpulkan

**Halaman pertama situs sah hampir tidak pernah memuat OTP/PIN/NIK.** Login, OTP, dan form NIK ada di balik klik (modal, halaman berikutnya), dan itu tidak diuji karena aturan "jangan submit". Jadi:

1. Sampel ini membuktikan situs sah tidak salah-tangkap **di halaman pertama**, bukan bahwa rule OTP aman di halaman OTP/2FA sah.
2. Risiko FP keyword `kode pendaftaran` tetap belum terukur. Halaman tempat kata itu muncul (cek status PPDB) tidak terjangkau tanpa melewati langkah login.
3. Sebaliknya, kit scam menaruh OTP/PIN langsung di landing. Itu sendiri pembeda: OTP/PIN di halaman pertama yang diakses dari tautan = mencurigakan.

Host PPDB pemda tetap sulit dibuka: jatengprov, jogjakota, surabaya DNS mati; bantenprov SSL rusak.

## Catatan teknis

- M23, M29, M30, M32, M37, M38, M41 dijawab 403 ke `curl` (pelindung bot) tapi terbuka di Chrome headless. Hasilnya dipakai.
- M02 `spmb.jatimprov.go.id` redirect ke `spmbjatim.net` (domain di luar `go.id`).
- Skrip pembuat snapshot ada di folder kerja sesi, bukan di repo.
