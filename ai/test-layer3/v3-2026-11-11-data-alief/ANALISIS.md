# Analisis layer 3: data Alief (v3, 11 Nov 2026)

Pemilik: Imelda (`ai/`). Dijalankan mengikuti [`../v2-2026-11-11/PLAN.md`](../v2-2026-11-11/PLAN.md), langkah 0–6. `ai/src/` tidak diubah. Host ditulis dengan `[.]`; tidak ada URL atau domain scam di dokumen ini, hanya nama platform hosting gratis.

Cara baca: **[terbukti]** = angka langsung dari `snapshots/` atau dari kode yang dibaca. **[dugaan]** = penjelasan yang masuk akal tetapi belum dibuktikan.

## 0. Konteks run

| | |
|---|---|
| Sumber | `data-alief-links.txt` (v3 data Alief), 427 baris, satu link per baris, tanpa skema, tanpa duplikat |
| Link terpotong `…` | 0 |
| Kode layer 3 | commit `b1bf948`; `git status` untuk `ai/src` dan `detector/data` bersih |
| Cek skrip tanpa jaringan | v1 dinilai ulang: phishing 15/20, scam 4/5, legit 0/10 = 19/25, sama dengan v1 |
| Uji kecil | `--limit 10`: 3 terbuka, 7 gagal (5 `dns`, 1 `http_451`, 1 `http_403`) |
| Run penuh | satu kali, 98 detik, 8 paralel (417 link; 10 sisanya dari uji kecil). Tidak diulang |
| Label | semua `scam` (tidak ada label legit di data ini) |

## 1. Angka

| | jumlah |
|---|---|
| Link | 427 |
| Terbuka | 398 (93,2%): 354 `ok`, 44 `kosong` |
| Gagal | 29: 12 `dns`, 5 `http_451`, 3 `http_403`, 3 `http_404`, 3 `timeout`, 2 `tls`, 1 `http_523` |
| Tertangkap (skor ≥ 30) | **32** = 8,0% dari yang terbuka (28 dari `ok`, 4 dari `kosong`) |
| Tertangkap **tanpa** `new_domain` | **12** (skor tanpa umur ≥ 30) |
| Tertangkap **hanya** karena `new_domain` | **20** (62,5% dari yang tertangkap) |
| Tanpa sinyal sama sekali | 337 dari 398 (84,7%); 303 dari `ok`, 34 dari `kosong` |
| Skor | median 0, maks 65; sebaran 0 → 337, 1–29 → 29, 30–49 → 26, 50–79 → 6, ≥ 80 → 0 |
| Host resmi (dibungkam rule) | 1 |

**[terbukti]** Semua angka di atas. Angka tangkapan adalah **batas bawah** (lihat bagian 7).

## 2. Sinyal dan kombinasi

| sinyal | halaman | bobot | bukti paling sering (`evidence`) |
|---|---|---|---|
| `new_domain` | 29 | 10 (5), 20 (6), 30 (18) | tidak ada bukti teks |
| `asks_password` | 21 | 15 | nama kolom: `password` 6, `pword` 5, `pw` 3, `pass` 2 |
| `brand_logo_offsite` | 20 | 12 / 25 | alt gambar: Facebook 4, Instagram 3, Agoda 2, BCA 1, BNI 1, DANA 1, Google 1, Microsoft 1 |
| `asks_otp` | 9 | 25 | `otp` 7, `inputOtpAsli` 1, `code1` 1 |
| `asks_pin` | 2 | 35 | `inputPinAsli` 1, `pin1` 1 |
| `urgent_language` | 1 | 15 | "KLAIM SEKARANG" |

Kombinasi (halaman terbuka):

| kombinasi | halaman | tertangkap |
|---|---|---|
| (tanpa sinyal) | 337 | 0 |
| `new_domain` saja | 21 | 15 |
| `brand_logo_offsite` saja | 11 | 0 |
| `asks_password` saja | 9 | 0 |
| `asks_password` + `brand_logo_offsite` | 3 | 3 |
| `asks_password` + `new_domain` | 3 | 3 |
| `asks_otp` + `asks_password` | 2 | 2 |
| `asks_otp` + `new_domain` | 2 | 2 |
| `asks_otp` saja | 2 | 0 |
| `asks_password` + `brand_logo_offsite` + `new_domain` | 2 | 2 |
| lain-lain (satuan: PIN, PIN + brand, OTP + brand, OTP + password + brand, OTP + password + urgent, brand + `new_domain`) | 6 | 5 |

**[terbukti]** Yang tertangkap hampir selalu `new_domain`, atau kombinasi PIN / OTP / password dengan brand atau password. `brand_logo_offsite`, `asks_password`, atau `asks_otp` sendirian tidak pernah mencapai 30 (maks 25).

## 3. Pola yang lolos

### 3a. Per domain induk

| induk | terbuka | tertangkap | punya `type=password` |
|---|---|---|---|
| `blogspot[.]com` | **300** (75% dari yang terbuka) | **3** | 8 |
| `vercel[.]app` | 19 | 4 | 6 |
| `netlify[.]app` | 12 | 0 | 0 |
| `weebly[.]com` | 4 | 0 | 0 |
| `firebaseapp[.]com` | 3 | 0 | 0 |
| `pages[.]dev`, `my[.]id`, `web[.]app`, `webflow[.]io`, `sites[.]google[.]com` | 7 | 1 | 0 |
| induk lain (43 induk berbeda; induk terbesar 8 halaman, berikutnya 3 dan 2) | 53 | 24 | 7 |

- **[terbukti]** Tertangkap 24 dari 53 di induk lain, tetapi hanya 3 dari 300 di `blogspot[.]com`. Satu platform menentukan angka total.
- **[terbukti]** `blogspot[.]com`: 287 `ok`, 13 `kosong`; 286 dari 300 tanpa sinyal; 129 punya form; 6 kena `brand_logo_offsite`.
- Beda dengan v2: 24 halaman pindah host, tetapi 24 host akhir berbeda (tidak ada klaster), 1 berakhir kosong.

### 3b. Bentuk form (halaman terbuka)

- **[terbukti]** Halaman `ok`: 183 punya form, 171 tanpa form. Tidak ada form tanpa kolom.
- **[terbukti]** 21 halaman punya `type=password`: 12 tertangkap, 9 tidak (bagian 4).
- **[terbukti, temuan utama]** **50 halaman, semuanya `blogspot[.]com`, punya kolom bernama `password` dan `username` dengan `type="text"`** (bukan `type=password`). Semuanya skor **0**, tanpa sinyal. Penyebabnya terbaca di kode: `ai/src/layer3/forms.js:79` hanya memberi `asks_password` kalau `type === "password"`; nama kolom dan placeholder tidak dipakai untuk password (berbeda dengan OTP dan PIN yang dicocokkan dari nama). Placeholder paling sering di form ini: "verifikasi disini....." (23 halaman). 34 dari 50 berjudul bernuansa promo / bantuan (Telkomsel, MKIOS, Pertamina, DANA, BPJS).
- **[dugaan]** Kolom itu bisa saja disamarkan jadi bintang lewat CSS atau JavaScript, sehingga pengguna melihat kolom password sungguhan. Skrip tidak menjalankan JavaScript dan tidak membaca CSS, jadi ini belum dibuktikan. Ekstensi membaca DOM sungguhan; `type` di sana kemungkinan sama dengan di sini, kecuali skrip halaman mengubahnya.
- **[terbukti]** Form hanya-`text` secara umum: 119 halaman, 106 di `blogspot[.]com`, hanya 4 tertangkap. Nama kolom: `q` 56 (kotak cari blog), `username` 50, `password` 50. Jadi 56 form itu cuma pencarian blog, bukan sinyal yang terlewat.
- **[terbukti]** Halaman dengan kolom bernuansa telepon: 20, tertangkap 14, tanpa sinyal 2.

### 3c. Judul berulang (halaman terbuka)

| judul (dipotong) | halaman | catatan |
|---|---|---|
| TELKOMSEL | 27 persis (45 yang memuat kata itu, 44 di `blogspot[.]com`) | 0 tertangkap |
| PESTA ISI ULANG … (M-KIOS 2017/2018) | 36 | semua `blogspot[.]com`; 1 punya form; 0 tertangkap, 0 sinyal |
| MKIOS / PT.M-KIOS | 38 / 37 yang memuat kata itu | 0 tertangkap, 0 sinyal |
| PERTAMINA | 22 (10 persis) | 21 punya form; 0 tertangkap, 0 sinyal |
| DANA BANTUAN BPJS | 11 | tanpa form; 0 tertangkap |
| Facebook / Instagram | 19 / 10 | 0 / 1 tertangkap; 7 halaman FB/IG kena `brand_logo_offsite` |

**[terbukti]** Dari 175 halaman berjudul Telkomsel / MKIOS / Pertamina / BPJS / DANA (pencocokan substring pada judul), 83 punya form, 7 punya sinyal OTP / PIN / password, **2 tertangkap**. Judul berulang di yang tertangkap hanya dua: "PENDAFTARAN VIA TELEGRAM" 2 dan "Bot Verification" 2.

**[dugaan]** Ini kampanye templat (promo isi ulang / bantuan) yang diduplikasi di banyak subdomain `blogspot[.]com`; kesamaan judul dan bentuk form mendukung itu, tetapi pemiliknya tidak diperiksa.

### 3d. Halaman `kosong` (44)

- **[terbukti]** 13 `blogspot[.]com`, 5 `vercel[.]app`, 26 lain. 4 di antaranya tetap tertangkap (umur domain). 43 dari 44 memuat tag `<script>` (median 3); 1 punya iframe; 1 berakhir `kosong` setelah pindah host.
- **[dugaan]** Halamannya dibangun JavaScript sehingga form dan teks tidak terlihat skrip. `kosong` **tidak membuktikan** layer 3 gagal.

## 4. Halaman `type=password` dengan skor < 30

9 halaman. **[terbukti]** Semuanya skor 15 dengan sinyal `asks_password` saja. Kolom: `password+text` 7, `email+password` 2. Induk: `blogspot[.]com` 5, `vercel[.]app` 3, lain 1.

Letak nama brand (pencocokan substring pada daftar brand di `detector/data/brands.json` + beberapa tambahan seperti facebook, instagram, outlook, google, microsoft, netflix, agoda):

| letak | halaman |
|---|---|
| judul + teks | 1 |
| judul + teks + host | 2 |
| judul + alt + teks + host | 1 |
| hanya di teks | 5 |
| tidak ada sama sekali | 0 |

**[terbukti]** 4 dari 9 punya nama brand di judul tetapi `brand_logo_offsite` diam. Alasan rule: lihat bagian "Terbuka" di PLAN.md (rule judul butuh kata aksi, alt Meta / Google / Apple / Microsoft dikecualikan); alasan itu dicatat dari PLAN.md, tidak diuji ulang di run ini.
**[dugaan]** Pencocokan substring bisa menghitung kata umum sebagai brand (misalnya "apple", "dana" di teks biasa), jadi "hanya di teks" 5 halaman belum tentu klon brand. Tidak dicek satu per satu. Varian rule dari bagian "Terbuka" **tidak diterapkan dan tidak disimulasikan** di run ini.

## 5. Peran umur domain

| umur (RDAP berhasil) | halaman | tertangkap | tertangkap hanya karena umur | `new_domain` menyala |
|---|---|---|---|---|
| < 30 hari | 24 | 19 | 18 | 24 |
| 30–89 hari | 5 | 3 | 2 | 5 |
| 90–364 hari | 5 | 0 | 0 | 0 |
| 1–3 tahun | 12 | 2 | 0 | 0 |
| ≥ 3 tahun | 348 | 8 | 0 | 0 |

- **[terbukti]** RDAP: 394 berhasil, 3 gagal, 1 dilewati (host resmi). 344 dari 394 yang berhasil adalah subdomain hosting gratis; umur yang terbaca adalah umur domain induk, jadi `new_domain` tidak mungkin menyala di sana.
- **[terbukti]** `new_domain` menyala di 29 halaman; 20 tertangkap hanya karenanya. Domain < 30 hari: 19 dari 24 tertangkap. Domain ≥ 1 tahun: 10 dari 360.
- **[terbukti]** RDAP 5 detik (produksi 1 detik): angka `new_domain` di sini lebih tinggi daripada yang akan terlihat di produksi.
- **[dugaan]** Di domain milik sendiri (bukan hosting gratis), layer 3 sebagian besar bergantung pada umur domain. Kalau penyerang memakai domain lama atau subdomain gratis, hampir tidak ada yang menangkap tanpa kombinasi OTP / PIN / brand.

## 6. Ringkasan temuan

1. **[terbukti]** 8,0% tertangkap; 62,5% dari yang tertangkap hanya karena umur domain.
2. **[terbukti]** 75% halaman terbuka ada di `blogspot[.]com`, dan di sana 3 dari 300 tertangkap.
3. **[terbukti]** Celah paling konkret: 50 halaman memakai kolom `username` / `password` bertipe `text`, skor 0 (`forms.js:79`). Ini satu-satunya temuan di run ini yang menunjuk rule tertentu. Apakah di layar pengguna terlihat sebagai kolom password: belum dibuktikan.
4. **[terbukti]** 9 halaman `type=password` skor 15; 4 punya brand di judul.
5. **[terbukti]** 0 halaman dengan teks yang menyuruh skrip melakukan sesuatu (pencarian pola instruksi sederhana, hanya hitungan).
6. Tidak ada temuan yang diterapkan ke `ai/src/`. Perubahan rule apa pun = keputusan Imelda, plus tes dan laporan precision/recall (`ai/CLAUDE.md`).

## 7. Batas

- **HTML statis, tanpa JavaScript.** Form dan teks yang dibangun JavaScript tidak terlihat; 44 halaman `kosong`. Angka tangkapan adalah batas bawah, bukan angka ekstensi.
- **Layer 3 saja.** Layer 2 di ekstensi menambah poin dari bentuk link; total sungguhan lebih tinggi.
- **Hanya label scam.** Tidak ada halaman legit di data ini, jadi tidak ada angka salah-kena (false positive). Jangan menyimpulkan precision dari sini.
- **RDAP 5 detik** (produksi 1 detik).
- **Hosting gratis** memakai umur domain induk.
- **29 link gagal** tidak dinilai (12 `dns`, 5 `http_451` = sudah diturunkan hosting). Satu kali ambil; situs scam cepat mati, hasil ulang tidak akan sama.
- Redirect lewat JavaScript tidak diikuti; situs yang butuh cookie gagal.
- Pencocokan brand di bagian 4 dan pencocokan judul di bagian 3c adalah heuristik substring, bukan rule layer 3.
