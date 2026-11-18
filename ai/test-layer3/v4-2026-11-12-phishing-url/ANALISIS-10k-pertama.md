# Analisis v4: layer 3 pada data "Phishing URL" (10.000 link, 12 Nov 2026)

Sumber angka: `snapshots/*.json` (10.000 file), `HASIL.md`, log run. Tiap klaim ditandai **[terbukti]** (angka langsung dari snapshot) atau **[dugaan]** (tafsiran, belum dicek). Tidak ada URL atau host di dokumen ini; link disebut dengan `id`. Isi teks halaman tidak dibaca untuk analisis ini, hanya angka dan nama sinyal.

## 0. Konteks run

| | |
|---|---|
| Sumber | Kaggle "Phishing URL Features Dataset" (`elifzelik/phishing-url-features-dataset`), hanya `url` dan `label` dipakai. `links.csv` = 579.521 link, diselang-seling scam / legit |
| Sampel | 10.000 link pertama (`--limit 10000`) = 5.000 scam + 5.000 legit (keputusan Imelda). Langkah 2b dilewati |
| Commit kode | `b1bf948`. `git status --short ai/src detector/data`: `ai/src/app.js` dan `ai/src/blocklist/{allowlist,build,domains,phishing-database}.js` berubah dan belum di-commit (sesi lain, bukan layer 3). Tidak diubah, tidak di-revert |
| Node | v26.8.1 (syarat ≥ 22) |
| Cek skrip (langkah 1) | `--rescore` atas 35 snapshot v1 di folder sementara di luar repo: phishing 15/20, scam 4/5, legit 0/10 = **19 dari 25**, sesuai. (Skrip juga mencetak "signals changed on 35": semua 35; skor akhir cocok, penyebab format tidak diselidiki) |
| Uji kecil | 10 link, sudah ada di `snapshots/`, dilewati otomatis |
| Run penuh | `--concurrency 8`, 9.990 link diambil dalam 2.171 detik (±36 menit), selesai sekali jalan (exit 0), tanpa terhenti |
| `--retry-failed` | **tidak dijalankan** (lihat bagian 8) |
| Total snapshot | 10.000, id unik 10.000 |

## 1. Angka

Persen "tertangkap" dihitung dari halaman **terbuka dan bukan host resmi** (host resmi dibungkam layer 3).

| | scam | legit | semua |
|---|---|---|---|
| Link | 5.000 | 5.000 | 10.000 |
| Terbuka | 787 (15,7%) | 3.805 (76,1%) | 4.592 (45,9%) |
| ... ok | 307 | 3.528 | 3.835 |
| ... kosong | 480 (9,6% dari link; 61,0% dari yang terbuka) | 277 (5,5%; 7,3% dari terbuka) | 757 |
| Gagal | 4.213 (84,3%) | 1.195 (23,9%) | 5.408 (54,1%) |
| Terbuka, host resmi (dibungkam) | 47 | 25 | 72 |
| Terbuka, bukan host resmi | 740 | 3.780 | 4.520 |
| **Tertangkap (≥ 30)** | **4 (0,5%)** | **10 (0,26%)** | **14 (0,3%)** |
| Tertangkap tanpa `new_domain` | 3 | 10 | 13 |
| Tertangkap hanya karena `new_domain` | 1 (id 018572, umur 2 hari, tanpa form) | 0 | 1 |
| Tanpa sinyal sama sekali | 679 dari 740 (91,8%) | 3.487 dari 3.780 (92,3%) | 4.166 dari 4.520 |
| Skor maks | 40 | 40 | 40 |

Gagal per alasan (kelompok, % dari link label itu):

| | scam | legit |
|---|---|---|
| `dns` (domain tidak ada) | 1.991 (39,8%) | 56 (1,1%) |
| `http_404` / `http_410` | 1.038 (20,8%) | 249 (5,0%) |
| `http_401` / `403` / `429` | 504 (10,1%) | 557 (11,1%) |
| jaringan (`timeout`, `tls`, `koneksi`, `jaringan`) | 427 (8,5%) | 176 (3,5%) |
| `http_451` (hosting menurunkan halaman) | 95 (1,9%) | 1 |
| lain (5xx, `bukan_html`, `ditolak`, `redirect`, 4xx lain) | 158 (3,2%) | 156 (3,1%) |

- **[terbukti]** Hanya 15,7% link scam masih terbuka, dan 61% dari yang terbuka berstatus `kosong` (teks < 200 karakter, tanpa kolom isian). Jadi hanya 307 halaman scam punya isi untuk dinilai.
- **[dugaan]** Banyaknya `kosong` + `dns` + `404` berarti data ini lama: situs sudah dimatikan, diparkir, atau halamannya diganti.
- **[terbukti]** Legit yang gagal didominasi `403/401/429` (557 = 11,1% dari link legit). **[dugaan]** itu penolakan bot (WAF) terhadap `GET` tanpa cookie, bukan situs mati. Akibatnya legit yang terbuka condong ke situs yang melayani `GET` polos.

## 2. Sinyal, kombinasi, bukti

Halaman terbuka bukan host resmi, jumlah halaman yang sinyalnya menyala `[di antaranya tertangkap]`:

| Sinyal | scam (n=740) | legit (n=3.780) |
|---|---|---|
| `asks_password` | 24 [3] (3,2%) | 266 [9] (7,0%) |
| `new_domain` | 32 [1] (4,3%) | 6 [0] (0,2%) |
| `asks_otp` | 2 [1] | 16 [9] |
| `brand_logo_offsite` | 3 [0] | 11 [0] |
| `asks_cvv` | 2 [1] | 1 [0] |
| `asks_card` | 1 [1] | 1 [0] |
| `asks_pin` | 0 | 1 [1] |

Kombinasi yang tertangkap:

| Kombinasi | scam | legit |
|---|---|---|
| `asks_otp` + `asks_password` | 1 (id 316266) | 9 (id 019630, 120832, 233570, 284497, 302290, 304654, 354359, 380948, 457192) |
| `asks_card` + `asks_password` | 1 (id 444141) | 0 |
| `asks_cvv` + `asks_password` | 1 (id 550504) | 0 |
| `new_domain` saja | 1 (id 018572) | 0 |
| `asks_pin` saja | 0 | 1 (id 118284) |

Bukti (`evidence`) paling sering, semua halaman, nama kolom / teks pendek:
- `asks_password`: `password` 137, `pass` 17, `pwd` 15, `login_password` 12.
- `brand_logo_offsite`: `amazon` 6, `paypal` 4, `google` 3, `dhl` 1.
- `asks_otp`: `otp` 4, `code` 2, `otp_code` 2, `key` 1.
- `asks_cvv`: `cvc` 1, `cvv` 1, `cf_contact_cvc` 1. `asks_card`: `cardnumber` 1, satu nama kolom tak jelas. `asks_pin`: `code` 1.

- **[terbukti]** `asks_password` menyala lebih sering di legit (7,0%) daripada di scam (3,2%). Sinyal itu sendiri tidak membedakan label di data ini.
- **[terbukti]** Semua yang tertangkap adalah kombinasi kolom sensitif (3 dari 4 scam, 9 dari 10 legit) atau domain berumur 2 hari. Tidak ada sinyal tunggal yang mencapai 30 selain `new_domain` (umur < 30 hari) dan `asks_pin`.
- **[dugaan]** `asks_otp` dan `asks_pin` menangkap nama kolom generik (`code`, `key`) yang di legit biasanya kolom kode verifikasi login (2FA) atau kode promo. Itu penyebab 10 legit kena (bagian 6).

## 3. Pola yang lolos

- **[terbukti]** Hosting gratis (daftar nama platform dicocokkan pada host asli link): 1.337 link scam (26,7% dari scam), 141 terbuka (10,5%, lebih rendah dari 17,6% di luar hosting gratis), 126 bukan host resmi, **0 tertangkap**. Sama dengan v2 dan v3. Legit di hosting gratis hanya 4 link.
- **[terbukti]** Dari 740 halaman scam terbuka bukan resmi: 131 punya form (17,7%), 24 punya `type=password` (3,2%). 609 tidak punya form sama sekali, jadi tidak ada yang bisa dinilai rule form.
- **[terbukti]** 47 halaman scam terbuka berada di host yang dianggap resmi (6,0% dari scam terbuka; semuanya `https`, 15 di antaranya di hosting gratis). Layer 3 dibungkam di sana, jadi tidak mungkin tertangkap. **[dugaan]** ini halaman phishing di platform besar (path, bukan domain sendiri); lihat bagian 8.
- **[terbukti]** Halaman scam terbuka dikelompokkan per host: 787 halaman di 422 host unik (±1,9 halaman per host). Hitungan per halaman bukan sampel independen. 10.000 link ada di 9.084 host unik.
- Judul berulang: tidak dianalisis (isi teks tidak dibaca; lihat bagian 8).

## 4. Halaman dengan `type=password` dan skor < 30

| | scam | legit |
|---|---|---|
| Halaman dengan kolom password (terbuka, bukan resmi) | 24 | 267 |
| Tertangkap | 3 | 10 |
| Skor < 30 | **21** | **257** |
| Hanya password (≤ 1 kolom terlihat) | 2 | 0 |
| 2 kolom | 9 | 45 |
| 3 kolom atau lebih | 10 | 212 |
| Di hosting gratis | 11 | 0 |
| Host berpindah (redirect ke host lain) | 1 | 24 |
| Sinyal yang menyala | `asks_password` saja (21) | `asks_password` saja (257) |

- **[terbukti]** Semua 278 halaman password yang lolos hanya punya `asks_password` (15 poin), tidak cukup 30. Sama dengan pola v2 dan v3.
- **[terbukti]** 11 dari 21 password-scam yang lolos ada di hosting gratis, yang tidak pernah mendapat `new_domain`.
- **Pengelompokan menurut letak nama brand (judul, alt, teks, host, tidak ada): tidak dikerjakan.** Skrip analisis tidak punya daftar brand, dan menyusunnya sendiri berarti menebak. 21 halaman scam ini cukup sedikit untuk dicek manual dari `snapshots/`, kalau Imelda mau.

## 5. Peran umur domain

Halaman terbuka bukan resmi dengan RDAP berhasil (`n` / tertangkap):

| Umur | scam (n=568) | legit (n=2.733) |
|---|---|---|
| < 30 hari | 2 / 1 (keduanya `new_domain`) | 3 / 0 (`new_domain`) |
| 30–89 hari | 30 / 0 (semua `new_domain`) | 3 / 0 (`new_domain`) |
| 90–364 hari | 11 / 0 | 15 / 0 |
| 1–5 tahun | 93 / 2 | 170 / 0 |
| ≥ 5 tahun | 432 / 1 | 2.542 / 7 |

- **[terbukti]** `new_domain` menyala di 32 dari 568 scam (5,6%) dan 6 dari 2.733 legit (0,2%): sinyal ini yang paling membedakan label di data ini. Tapi di umur 30–89 hari 0 dari 30 mencapai skor 30, dan di < 30 hari baru 1 dari 2. Hanya satu scam (id 018572) tertangkap karena umur.
- **[terbukti]** 76% scam yang RDAP-nya berhasil berumur ≥ 5 tahun. **[dugaan]** domain lama yang dibajak atau dipakai ulang, atau data lama sehingga umur dihitung dari hari ini; `new_domain` tidak banyak membantu untuk kelompok ini.
- **[terbukti]** RDAP **`gagal`** pada 1.219 dari 4.520 halaman terbuka bukan resmi (27,0%): scam 172 (23,2%), legit 1.047 (27,7%). `dilewati` 72 (host resmi). Kegagalan terkonsentrasi per TLD: `tr` 166 gagal dari 168, `ru` 156/158, `de` 136/137, `io` 81/83, `me` 74/78, `edu` 59/60, `jp` 55/56; sebaliknya `com` 14 dari 2.205 (0,6%) dan `org` 1 dari 196. Persen gagal per seperempat run (menurut waktu) datar: 28,5 / 23,8 / 28,1 / 27,4%.
- **[dugaan]** Ini bukan pembatasan laju registry (tidak naik selama run, tidak menyentuh `com`/`net`), melainkan TLD yang tidak punya layanan RDAP publik atau tidak terdaftar di bootstrap. Di TLD itu `new_domain` tidak pernah bisa menyala, juga di produksi. 369 kegagalan ada di TLD yang tidak punya satu pun RDAP berhasil.

## 6. Legit yang kena

"Legit yang kena" hanya dihitung dari halaman terbuka **bukan host resmi**.

- **[terbukti]** Legit terbuka 3.805; host resmi hanya **25 (0,7%)**, tidak ada yang tertangkap. Catatan di PLAN ("legit hampir semuanya situs populer, host resmi dibungkam") **tidak berlaku di sampel ini**: daftar host resmi layer 3 jauh lebih sempit daripada "situs populer" di data, jadi 3.780 halaman legit ikut diuji. Ini uji false-positive yang lebih adil daripada yang diperkirakan.
- **[terbukti]** **10 dari 3.780 legit bukan resmi tertangkap (0,26%)**; semua `https`, 9 `asks_otp` + `asks_password` (skor 40), 1 `asks_pin` (skor 35, id 118284). Tiga di antaranya `www.` (id 284497, 302290, 304654). Semua punya kolom password. Umur domain 7 dari 10 diketahui (4.338 sampai 9.468 hari), 3 gagal RDAP.
- **[terbukti]** Per halaman terbuka bukan resmi: scam 4 dari 740 (0,54%), legit 10 dari 3.780 (0,26%). Selisihnya kecil dan jumlahnya sedikit. **[dugaan]** selisih ini tidak bermakna secara statistik. Dari 14 yang tertangkap, 10 legit dan 4 scam, jadi pada sampel ini hampir tidak ada gunanya "tertangkap" sebagai penanda scam.
- **[dugaan]** 9 legit itu halaman login dengan kolom kode verifikasi (nama kolom `otp`, `code`, `otp_code`, `key`). Rule `asks_otp` mengenali nama kolom, bukan konteks. Tidak dibuka, tidak dicek manual.
- **[terbukti]** `brand_logo_offsite` menyala di 11 legit dan 3 scam, tidak ada yang mencapai 30. `new_domain` menyala di 6 legit (umur < 90 hari), tidak ada yang mencapai 30.

## 7. Perbandingan dengan v2 dan v3

| | v2 (500 link) | v3 (427 link) | v4 scam (5.000 link) | v4 legit (5.000 link) |
|---|---|---|---|---|
| Terbuka | 456 (91,2%) | 398 (93,2%) | 787 (15,7%) | 3.805 (76,1%) |
| `kosong` dari yang terbuka | 150 (32,9%) | 44 (11,1%) | 480 (61,0%) | 277 (7,3%) |
| Gagal | 44 (8,8%) | 29 (6,8%) | 4.213 (84,3%) | 1.195 (23,9%) |
| Tertangkap (dari terbuka) | 23 (5,0%) | 32 (8,0%) | 4 (0,5%) | 10 (0,3%) |
| Tertangkap tanpa `new_domain` | 15 | 12 | 3 | 10 |
| Tanpa sinyal | 333 dari 456 | 337 dari 398 | 679 dari 740 bukan resmi | 3.487 dari 3.780 |
| Skor maks | 65 | 65 | 40 | 40 |

Yang sama **[terbukti]**: hosting gratis tidak pernah tertangkap (0 dari 126 di v4); password saja (15) tidak cukup (21 dari 24 password-scam < 30); yang tertangkap selalu kombinasi atau domain sangat muda; tidak ada skor di atas 65 di mana pun.

Yang beda: angka tertangkap v4 sebesar 0,5% jauh di bawah 5–8%. **[dugaan]** penyebab: umur link. Daftar v2/v3 berasal dari laporan baru, hampir semua terbuka (91–93%); data Kaggle ini tertulis lama dan hanya 15,7% masih hidup, dan 61% dari yang hidup adalah halaman kosong. Pembilang kecil (4 halaman), jadi persennya tidak stabil. Skor maks 40 (bukan 65) berarti tidak ada scam di v4 yang punya tiga sinyal sekaligus atau domain muda dengan form lengkap. **[dugaan]** halaman scam dengan form lengkap sudah paling dulu dimatikan.

## 8. Skema, `www.`, dan batas run

### Skema dan `www.` (dipisahkan menurut label)

Skema dan `www.` membedakan label karena cara pengumpulan data, jadi hanya dibandingkan **dalam label yang sama**. Susunan sampel: scam `http` 1.339 (26,8%), `https` 3.661; legit `http` 90 (1,8%), `https` 4.910; `www.` scam 295 (5,9%), legit 2.752 (55,0%), sesuai profil data di PLAN.

| Label, skema, `www.` | Link | Terbuka | Gagal | Tertangkap (dari bukan resmi) |
|---|---|---|---|---|
| scam `http` | 1.339 | 10,8% | 89,2% | 2 dari 144 |
| scam `https` | 3.661 | 17,6% | 82,4% | 2 dari 596 |
| scam tanpa `www.` | 4.705 | 15,4% | 84,6% | 3 dari 693 |
| scam `www.` | 295 | 21,4% | 78,6% | 1 dari 47 |
| legit `http` | 90 | 60,0% | 40,0% | 0 dari 54 |
| legit `https` | 4.910 | 76,4% | 23,6% | 10 dari 3.726 |
| legit tanpa `www.` | 2.248 | 74,5% | 25,5% | 7 dari 1.659 |
| legit `www.` | 2.752 | 77,4% | 22,6% | 3 dari 2.121 |

Sel yang sama, label beda (terbuka): `https` tanpa `www.` scam 17,2% (n=3.459) lawan legit 75,0% (n=2.195); `https` + `www.` scam 24,3% (n=202) lawan legit 77,5% (n=2.715).

- **[terbukti]** Di sel skema + `www.` yang sama, selisih terbuka scam vs legit tetap 53–58 poin. Skema dan `www.` **tidak menjelaskan** selisih itu.
- **[terbukti]** Dalam scam, link `http` lebih sering gagal (89,2% vs 82,4%), tapi gagal DNS sama (40,6% vs 39,5%).
- **[dugaan]** Selisih terbuka antar skema dalam satu label bersumber dari umur / jenis situs, bukan skema itu sendiri; tidak diuji.
- Angka tertangkap per sel (0–10 halaman) terlalu kecil untuk kesimpulan apa pun. **[terbukti]** tidak ada perbedaan tertangkap yang bisa dikaitkan dengan skema atau `www.`.

### Batas run ini

- **HTML statis, tanpa JavaScript.** Form dan teks yang dibangun JavaScript tidak terlihat (277 legit dan 480 scam `kosong`). Angka tertangkap adalah batas bawah.
- **Layer 3 saja.** Layer 1–2 di ekstensi menambah poin dari bentuk link.
- **Data lama.** 84,3% link scam gagal; efektifnya hanya 740 halaman scam bukan resmi, dari 422 host. Persen tertangkap scam (4 halaman) sangat tidak stabil.
- **Legit condong ke yang melayani `GET` polos.** 11,1% link legit ditolak (`401/403/429`, [dugaan] WAF), jadi false-positive diukur hanya pada situs yang membuka halaman untuk skrip.
- **RDAP 5 detik** (produksi 1 detik) dan tidak tersedia untuk TLD tertentu (bagian 5): `new_domain` buta pada 27,0% halaman terbuka bukan resmi.
- **Host resmi dibungkam:** 47 halaman scam terbuka (6,0%) tidak bisa tertangkap; dicek jumlahnya saja, tidak dicek hostnya satu per satu.
- **Tidak dikerjakan:** pengelompokan password-scam menurut letak brand (bagian 4), judul berulang (bagian 3), isi `iframes` (1.466 halaman legit terbuka dan 102 scam punya iframe; hanya dicatat jumlahnya), dan cek manual 10 legit yang kena.
- **`--retry-failed` tidak dijalankan.** Kegagalan jaringan murni (`timeout`, `tls`, `koneksi`, `jaringan`) hanya 603 link (6,0% sampel: scam 427, legit 176). `--retry-failed` mengulang **semua** link gagal (5.408, termasuk `dns`, `404`, `403`, `451`), tidak hanya yang gagal karena jaringan, jadi mengirim ±5.000 permintaan lagi ke situs yang sudah jelas mati atau menolak. Tidak sebanding dengan paling banyak ±600 halaman tambahan; kalau mau dijalankan, perlu keputusan Imelda.
- Isi halaman tidak dibaca untuk analisis ini; tidak ada instruksi dari isi halaman yang perlu dicatat.
