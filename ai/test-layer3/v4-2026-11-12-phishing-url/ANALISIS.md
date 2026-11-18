# Analisis v4: layer 3 pada data "Phishing URL" (579.519 link dicek hidup, 111.215 dinilai L3, 13 Nov 2026)

Sumber angka: `.probe/summary.json` (cek hidup, semua link), `snapshots/*.json` (layer 3), `stats.mjs` (hitungan, mencetak angka saja), `HASIL.md`. Tiap klaim ditandai **[terbukti]** (angka langsung dari data) atau **[dugaan]** (tafsiran, belum dicek). Tidak ada URL atau host di dokumen ini. Isi teks halaman tidak dibaca untuk analisis ini, hanya angka, nama sinyal, dan nama kolom isian yang pendek.

Versi sebelumnya (10.000 link pertama, 12 Nov) disimpan di [`ANALISIS-10k-pertama.md`](ANALISIS-10k-pertama.md). Dokumen ini menggantikannya: angkanya dihitung ulang dari seluruh data.

## 0. Konteks run

| | |
|---|---|
| Sumber | Kaggle "Phishing URL Features Dataset" (`elifzelik/phishing-url-features-dataset`), hanya `url` dan `label`. `links.csv` = 579.521 link (240.838 scam, 338.683 legit); 579.519 dipakai setelah 2 baris dibuang skrip (duplikat / bukan http(s)) |
| Keputusan Imelda | Cek **semua** link apakah hidup; layer 3 hanya pada yang hidup. Sisa layer 3 hanya untuk **scam**; legit dihentikan di 61.958 dari 264.135 link hidup ("legit sudah cukup") |
| Commit kode | `b1bf948`. `git status --short ai/src detector/data`: `ai/src/app.js` dan `ai/src/blocklist/{allowlist,build,domains,phishing-database}.js` berubah, belum di-commit (sesi lain, bukan layer 3). Tidak diubah |
| Node | v26.8.1 (syarat ≥ 22) |
| Cek skrip (langkah 1) | `--rescore` atas 35 snapshot v1: 19 dari 25 (phishing 15/20, scam 4/5, legit 0/10), sesuai. Dijalankan di sesi 12 Nov; tidak diulang di sesi ini |
| Cek hidup (`probe.mjs`) | DNS 222.979 host (±7 menit), lalu satu `GET` header-saja per link yang hostnya ada (470.824 link, 5.114 detik, concurrency 150, maks 4 per host). Redirect tidak diikuti, badan tidak dibaca |
| Layer 3 (`run.mjs`) | Beberapa sesi: 10.000 link pertama (12 Nov, concurrency 8), lalu link hidup dengan concurrency 16 → 32 → 16 → 48. Terakhir, scam saja: 31.852 link dalam 883 detik (concurrency 48) |
| Perubahan skrip | `run.mjs` v4 mendapat penjaga `teks_ekstrem` (bagian 8). `probe.mjs` dan `stats.mjs` baru |
| `--retry-failed` | **tidak dijalankan** (bagian 8) |

## 1. Angka

### 1.1 Cek hidup (semua link)

| | scam | legit |
|---|---|---|
| Link | 240.836 | 338.683 |
| DNS mati (`nxdomain`) | 91.055 (37,8%) | 12.135 (3,6%) |
| DNS tidak jelas (timeout/SERVFAIL, dicoba 2 kali) | 4.406 (1,8%) | 1.099 (0,3%) |
| `http` 404 / 410 | 41.213 (17,1%) | 12.138 (3,6%) |
| `http` 401 / 403 / 429 | 26.853 (11,1%) | 31.697 (9,4%) |
| `http` 451 (hosting menurunkan) | 2.981 (1,2%) | 48 |
| `http` 5xx / 4xx lain | 3.005 (1,2%) | 4.412 (1,3%) |
| Gagal jaringan (`timeout`, `tls`, `koneksi`, `jaringan`, `ditolak`) | 20.379 (8,5%) | 11.801 (3,5%) |
| `host_skipped` (host dengan 50 probe tanpa satu pun 2xx/3xx) | 1.297 (0,5%) | 2 |
| 2xx bukan HTML | 359 | 1.187 |
| **Hidup untuk L3** (3xx, atau 2xx HTML) | **49.257 (20,5%)** | **264.135 (78,0%)** |
| ... 2xx HTML | 24.415 (10,1%) | 207.151 (61,2%) |
| ... 3xx | 24.842 (10,3%) | 56.984 (16,8%) |

- **[terbukti]** Hanya 20,5% link scam yang hidup menurut definisi ini, lawan 78,0% legit. 37,8% link scam domainnya sudah tidak ada.
- **[dugaan]** Data lama: link scam yang hidup sebagian adalah halaman yang sudah diganti isinya atau hanya mengalihkan.
- **[terbukti]** 3xx dihitung hidup; di layer 3 hasilnya sering gagal di ujung redirect (bagian 1.3).

### 1.2 Layer 3, pada link hidup

Persen "tertangkap" dihitung dari halaman **terbuka dan bukan host resmi** (host resmi dibungkam layer 3). Legit hanya **sampel**: 61.958 dari 264.135 link hidup (23,5%).

| | scam | legit (sampel) |
|---|---|---|
| Link hidup dinilai | 49.257 (semua) | 61.958 |
| Terbuka | 31.700 (64,4%) | 58.852 (95,0%) |
| ... ok | 13.241 | 55.155 |
| ... kosong (teks < 200 karakter dan tanpa kolom) | 18.459 (58,2% dari terbuka) | 3.697 (6,3%) |
| Gagal | 17.557 (35,6%) | 3.106 (5,0%) |
| Terbuka, host resmi (dibungkam) | 2.308 (7,3% dari terbuka) | 401 (0,7%) |
| Terbuka, bukan host resmi | 29.392 | 58.451 |
| **Tertangkap (≥ 30)** | **116 (0,39%)** | **277 (0,47%)** |
| Tertangkap tanpa `new_domain` | 75 | 253 |
| Tertangkap hanya karena `new_domain` | 41 | 24 |
| Tanpa sinyal sama sekali | 26.429 (89,9%) | 53.698 (91,9%) |
| Skor maks | 75 | 75 |

Corong scam, dari semua link: 240.836 → DNS ada 145.375 → hidup 49.257 (20,5%) → terbuka 31.700 (13,2%) → ok 13.241 (5,5%) → bukan resmi 29.392 → tertangkap **116 (0,05% dari semua link scam)**.

### 1.3 Gagal di layer 3, per alasan (link hidup)

| | scam (49.257) | legit sampel (61.958) |
|---|---|---|
| `http_4xx` | 12.482 (25,3%) | 1.443 (2,3%) |
| `dns` | 1.722 | 63 |
| `tls` | 1.042 | 58 |
| `bukan_html` | 727 | 52 |
| `timeout` | 557 | 736 |
| `redirect` (lebih dari 3 lompatan / tanpa tujuan) | 471 | 455 |
| `http_5xx` | 228 | 66 |
| `teks_ekstrem` (tidak diparse, bagian 8) | 142 | 130 |
| lain (`ditolak`, `koneksi`, `jaringan`, `http_3xx`) | 186 | 103 |

- **[terbukti]** Dari 12.482 scam hidup yang di L3 berakhir `http_4xx`, **96,3%** (12.025) adalah 3xx saat dicek hidup: 7.577 mengalihkan ke host yang sama, 4.448 ke host lain. Hanya 457 yang 2xx langsung lalu 4xx di L3. Jadi sebagian besar "hidup" scam itu redirect ke halaman yang sudah mati.
- **[terbukti]** Gagal jaringan murni (`timeout`, `tls`, `koneksi`, `jaringan`) di scam hidup hanya 1.643 (3,3%).
- **[terbukti]** 58,2% scam yang terbuka berstatus `kosong`, lawan 6,3% legit. Hanya 13.241 halaman scam punya isi (teks atau kolom) untuk dinilai penuh.

## 2. Sinyal, kombinasi, bukti

Halaman terbuka bukan resmi, jumlah halaman yang sinyalnya menyala `[di antaranya tertangkap]`:

| Sinyal | scam (n=29.392) | legit (n=58.451) |
|---|---|---|
| `asks_password` | 1.516 [57] (5,2%) | 4.271 [233] (7,3%) |
| `new_domain` | 1.163 [41] (4,0%) | 116 [27] (0,2%) |
| `brand_logo_offsite` | 239 [32] (0,8%) | 174 [7] (0,3%) |
| `asks_otp` | 53 [27] | 343 [194] (0,6%) |
| `asks_pin` | 13 [13] | 48 [48] |
| `asks_card` | 24 [14] | 24 [14] |
| `asks_cvv` | 25 [1] | 7 [0] |
| `urgent_language` | 0 | 20 [1] |
| `asks_ktp` | 0 | 5 [2] |

Kombinasi yang tertangkap:

| Kombinasi | scam (116) | legit (277) |
|---|---|---|
| `new_domain` saja | 40 | 12 |
| `asks_password` + `brand_logo_offsite` | **26** | 5 |
| `asks_otp` + `asks_password` | 16 | **184** |
| `asks_card` + `asks_password` | 10 | 6 |
| `asks_pin` saja | 8 | 25 |
| `asks_otp` + `brand_logo_offsite` | 6 | 0 |
| `asks_password` + `asks_pin` | 3 | 16 |
| `asks_card` + `asks_otp` | 3 | 0 |
| `asks_password` + `new_domain` | 0 | 12 |
| `asks_otp` + `asks_password` + `new_domain` | 0 | 3 |
| lain (digabung) | 4 | 14 |

Bukti (`evidence`) paling sering, nama kolom atau kata pendek (bukti berisi titik, garis miring atau `@` tidak dicetak):
- `asks_password`: scam `password` 608, `pass` 168, `pwd` 47; legit `password` 1.863, `pass` 279, `pwd` 210.
- `brand_logo_offsite`: scam `google` 143, `netflix` 55, `microsoft` 10, `instagram` 9, `facebook` 7; legit `amazon` 75, `paypal` 61, `dhl` 15, `netflix` 10, `bsi` 6.
- `asks_otp`: scam `password` 12, `otp` 6, `user_otp` 6, `verificationcodex` 5; legit `otp` 41, `otp_code` 32, **`website` 20**, `code` 12, `verificationcode` 9.
- `asks_pin`: scam `pincode` 3, `pin` 1; legit `pincode` 5, `code` 5, `pin` 5, **`locality` 4**, `pin_code` 3, `last-digits` 3.
- `asks_card`: scam `zawaq` 9, `card-number` 1; legit `card_number` 7, `cardnumber` 4. `asks_cvv`: scam `cf_contact_cvc` 21; legit `cvc` 3, `cf_contact_cvc` 3. `urgent_language` (legit): `within 24 hours` 12.

- **[terbukti]** `asks_password` menyala lebih sering di legit (7,3%) daripada di scam (5,2%). Sinyal itu sendiri tidak membedakan label.
- **[terbukti]** Dua kombinasi lebih sering di scam daripada legit: `asks_password` + `brand_logo_offsite` (26 scam = 0,09% halaman lawan 5 legit = 0,01%, ±10×) dan `new_domain` saja (40 = 0,14% lawan 12 = 0,02%, ±7×). Di v2/v3/v4-10k pola pertama tidak pernah tertangkap; sampel besar baru memperlihatkannya.
- **[terbukti]** Semua yang tertangkap adalah kombinasi atau sinyal tunggal dengan bobot ≥ 30 (`new_domain` untuk umur < 30 hari, `asks_pin`). `asks_otp` ikut di 194 dari 277 legit yang tertangkap (70%).
- **[dugaan]** Bukti `asks_otp` dan `asks_pin` berisi nama kolom umum (`website`, `locality`, `code`, `last-digits`) yang bukan OTP atau PIN. Penyebab diduga pencocokan nama kolom yang longgar. Belum dicek di rule-nya; **tidak diubah** (`src/` tidak disentuh).
- **[dugaan]** `asks_otp` + `asks_password` di legit (184) umumnya halaman login dengan kolom kode verifikasi (2FA) atau nama kolom yang cocok oleh kebetulan. Tidak dibuka, tidak dicek manual.

## 3. Pola yang lolos

- **Hosting gratis** (daftar nama platform yang lebih lebar dari analisis sebelumnya, ada di `stats.mjs`; dicocokkan pada host asli link): 18.078 link scam hidup (36,7%), 8.361 terbuka, 7.451 bukan resmi, **32 tertangkap (0,43%)**, sama dengan laju keseluruhan (0,39%). **[terbukti]** Di legit hanya 37 halaman bukan resmi di hosting gratis, 0 tertangkap. **Beda dengan v2/v3/v4-10k**, yang mencatat 0 tertangkap di hosting gratis: sampel jauh lebih besar dan daftar lebih lebar. `new_domain` tetap tidak bisa menyala di sana ([dugaan], umur domain induk; lihat PLAN).
- **[terbukti]** Dari 29.392 halaman scam terbuka bukan resmi: 5,2% punya kolom password. Mayoritas tidak punya sinyal sama sekali (89,9%).
- **[terbukti]** 2.308 halaman scam terbuka di host yang dianggap resmi (7,3% dari terbuka) dibungkam layer 3, jadi tidak mungkin tertangkap. **[dugaan]** halaman phishing di platform besar (path, bukan domain sendiri).
- **[terbukti]** Tidak diselidiki: pengelompokan per host. Hitungan per halaman bukan sampel independen (di 10k pertama, ±1,9 halaman per host untuk scam terbuka).
- Judul berulang: tidak dianalisis (isi teks tidak dibaca).

## 4. Halaman dengan kolom password dan skor < 30

| | scam | legit (sampel) |
|---|---|---|
| Halaman dengan kolom password (terbuka, bukan resmi) | 1.520 | 4.301 |
| Tertangkap | 58 | 239 |
| Skor < 30 | **1.462** | **4.062** |
| Hanya `asks_password` yang menyala | 1.458 | 4.032 |
| 1 kolom terlihat | 42 | 6 |
| 2 kolom | 467 | 398 |
| 3 kolom atau lebih | 953 | 3.658 |
| Di hosting gratis | 778 (53%) | 4 |

- **[terbukti]** 99,7% halaman password yang lolos hanya punya `asks_password` (15 poin), tidak cukup 30. Sama dengan v2, v3, v4-10k.
- **[terbukti]** Lebih dari separuh password-scam yang lolos ada di hosting gratis (778 dari 1.462).
- **Pengelompokan menurut letak nama brand (judul, alt, teks, host, tidak ada): tidak dikerjakan.** Skrip tidak punya daftar brand, dan menyusunnya sendiri berarti menebak. Dengan 1.462 halaman scam, ini kini layak jadi pekerjaan terpisah.

## 5. Peran umur domain

Halaman terbuka bukan resmi dengan RDAP berhasil (`n` / tertangkap):

| Umur | scam (n=24.585) | legit sampel (n=40.651) |
|---|---|---|
| < 30 hari | 98 / 40 | 57 / 24 |
| 30–89 hari | 1.065 / 1 | 57 / 3 |
| 90–364 hari | 432 / 0 | 147 / 0 |
| 1–5 tahun | 3.070 / 16 | 2.421 / 12 |
| ≥ 5 tahun | 19.920 / 31 | 37.969 / 174 |

- **[terbukti]** `new_domain` menyala di 1.163 scam (4,7% dari yang RDAP-nya berhasil) dan 116 legit (0,29%): sinyal yang paling membedakan label. Tapi hanya umur < 30 hari mencapai skor 30 sendirian (40 dari 98); di 30–89 hari baru 1 dari 1.065 tertangkap.
- **[terbukti]** 81,0% scam yang RDAP-nya berhasil berumur ≥ 5 tahun. **[dugaan]** domain lama yang dibajak atau dipakai ulang, data lama (umur dihitung dari hari ini), dan umur domain induk platform besar. `new_domain` tidak membantu untuk kelompok ini.

### RDAP `gagal`

- **[terbukti]** RDAP `gagal` di 22.607 dari 87.843 halaman terbuka bukan resmi (25,7%): scam 4.807 (16,4%), legit 17.800 (30,5%).
- **[terbukti]** Kegagalan terkonsentrasi per TLD: `ru` 2.509 dari 2.509, `tr` 2.394/2.394, `io` 2.101/2.101, `de` 2.092/2.092, `jp` 1.315/1.315, `me` 995/995, `edu` 853/853, `uk` 241/952; sebaliknya `com` 735 dari 44.382 (1,7%), `org` 21/3.296, `net` 50/2.383. **20.371 dari 22.607 kegagalan (90,1%) ada di TLD yang tidak punya satu pun RDAP berhasil.**
- **[terbukti]** Persen gagal per 30 menit berkisar 27–35% selama run, tanpa kenaikan yang teratur; ujung run (hanya scam, campuran TLD berbeda) 13,1%.
- **[dugaan]** Ini bukan pembatasan laju registry, melainkan TLD yang tidak punya layanan RDAP publik atau tidak ada di bootstrap. Di TLD itu `new_domain` tidak pernah bisa menyala, juga di produksi. Jendela concurrency 32 dengan thread pool 4 mungkin menaikkan gagal sedikit (31–35%), tapi tidak terpisahkan dari campuran TLD.

## 6. Legit yang kena

"Legit yang kena" hanya dihitung dari halaman terbuka **bukan host resmi**, pada **sampel** legit (58.451 halaman).

- **[terbukti]** **277 dari 58.451 (0,47%)** tertangkap; 253 tanpa `new_domain`. Interval 95% kira-kira 0,42–0,53%. Host resmi hanya 401 (0,7%) dari legit terbuka, tidak ada yang tertangkap. Catatan di PLAN ("legit hampir semuanya situs populer, host resmi dibungkam") tidak berlaku di sampel ini: daftar host resmi layer 3 jauh lebih sempit.
- **[terbukti]** Per halaman bukan resmi: scam 116 dari 29.392 (0,39%, interval ±0,07), legit 277 dari 58.451 (0,47%). Selisihnya kecil dan intervalnya hampir bertumpuk. **[dugaan]** tidak bermakna secara statistik; pada sampel ini "tertangkap" hampir tidak membedakan scam dari legit.
- **[terbukti]** Sebab legit yang kena: kombinasi `asks_otp` ikut di 194 dari 277 (70%): `asks_otp` + `asks_password` 184 (+3 dengan `new_domain`, +2 dengan `brand_logo_offsite`), `asks_pin` saja 25, `asks_password` + `asks_pin` 16, `asks_password` + `new_domain` 12, `new_domain` saja 12.
- **[terbukti]** Semua kecuali 4 adalah `https`; 148 `www.`, 129 tanpa `www.`.
- **[dugaan]** Bukti `website`, `locality`, `code` di `asks_otp`/`asks_pin` menandakan pencocokan nama kolom longgar (bagian 2). Kandidat perbaikan rule, di luar plan ini.
- **[terbukti]** `new_domain` menyala di 116 legit (umur < 90 hari), tertangkap 27. `urgent_language` menyala di 20 legit, tertangkap 1.

## 7. Perbandingan dengan v2, v3, dan v4-10k

| | v2 (500 link) | v3 (427 link) | v4-10k scam | v4-10k legit | **v4 penuh scam** | **v4 legit (sampel)** |
|---|---|---|---|---|---|---|
| Link (dinilai) | 500 | 427 | 5.000 | 5.000 | 49.257 hidup | 61.958 hidup |
| Terbuka | 456 (91,2%) | 398 (93,2%) | 787 (15,7%) | 3.805 (76,1%) | 31.700 (13,2% dari semua; 64,4% dari hidup) | 58.852 (95,0% dari hidup) |
| `kosong` dari terbuka | 150 (32,9%) | 44 (11,1%) | 61,0% | 7,3% | 58,2% | 6,3% |
| Tertangkap (bukan resmi) | 23 (5,0%) | 32 (8,0%) | 4 (0,5%) | 10 (0,26%) | **116 (0,39%)** | **277 (0,47%)** |
| Tertangkap tanpa `new_domain` | 15 | 12 | 3 | 10 | 75 | 253 |
| Tanpa sinyal | 333 dari 456 | 337 dari 398 | 91,8% | 92,3% | 89,9% | 91,9% |
| Skor maks | 65 | 65 | 40 | 40 | **75** | **75** |

Yang sama **[terbukti]**: password saja (15 poin) tidak cukup; yang tertangkap selalu kombinasi atau domain sangat muda; angka tertangkap v4 jauh di bawah v2/v3 (0,4–0,5% lawan 5–8%).

Yang beda:
- **[terbukti]** Skor maks naik jadi 75 (v2/v3/v4-10k: 40–65); hanya terlihat di sampel besar.
- **[terbukti]** Hosting gratis kini ada yang tertangkap (32), bukan 0 (bagian 3).
- **[terbukti]** Hasil v4-10k terkonfirmasi pada sampel 10× lebih besar: tertangkap scam 0,5% → 0,39%, legit 0,26% → 0,47%. Angka 10k itu tidak bergeser banyak, tapi legit 10k lebih rendah karena 10 halaman saja.
- **[dugaan]** Perbedaan besar dengan v2/v3: umur link. v2/v3 dari laporan baru (91–93% terbuka); data Kaggle ini lama, hanya 20,5% link scam yang hidup dan 58% dari yang terbuka kosong. Halaman scam dengan form lengkap kemungkinan paling dulu dimatikan.

## 8. Skema, `www.`, dan batas run

### Skema dan `www.` (dipisahkan menurut label)

Skema dan `www.` membedakan label karena cara pengumpulan data (legit 97,9% https; phishing 26,7% http), jadi hanya dibandingkan **dalam label yang sama** dan dalam sel yang sama.

Cek hidup, semua link (hidup = 3xx atau 2xx HTML):

| Sel | scam: link / DNS mati / hidup | legit: link / DNS mati / hidup |
|---|---|---|
| `https`, tanpa `www.` | 167.070 / 36,8% / 18,5% | 146.336 / 5,4% / 75,5% |
| `https`, `www.` | 9.422 / 45,4% / 20,9% | 185.244 / 1,4% / 80,6% |
| `http`, tanpa `www.` | 59.460 / 39,0% / 23,8% | 4.053 / 31,4% / 51,7% |
| `http`, `www.` | 4.884 / 44,3% / 44,5% | 3.050 / 12,5% / 74,9% |

Layer 3 pada link hidup (terbuka dan tertangkap dari bukan resmi):

| Sel | scam: terbuka / tertangkap | legit: terbuka / tertangkap |
|---|---|---|
| `https`, tanpa `www.` | 76,5% / 80 dari 22.107 (0,36%) | 94,5% / 126 dari 24.265 (0,52%) |
| `https`, `www.` | 71,7% / 2 dari 748 (0,27%) | 95,7% / 147 dari 33.360 (0,44%) |
| `http`, tanpa `www.` | 42,2% / 32 dari 5.912 (0,54%) | 81,2% / 3 dari 376 (0,80%) |
| `http`, `www.` | 29,0% / 2 dari 625 (0,32%) | 82,3% / 1 dari 450 (0,22%) |

- **[terbukti]** Di tiap sel skema + `www.` yang sama, selisih hidup scam lawan legit tetap 30–60 poin (misalnya `https` tanpa `www.`: 18,5% lawan 75,5%). Skema dan `www.` **tidak menjelaskan** selisih itu.
- **[terbukti]** Dalam scam, link `http` hidup lebih sering daripada `https` (23,8% lawan 18,5% tanpa `www.`), tapi lebih jarang terbuka di L3 (42,2% lawan 76,5%). **[dugaan]** link `http` yang hidup kebanyakan 3xx (ke `https` atau halaman lain) yang ujungnya mati; tidak diuji per sel.
- Angka tertangkap per sel di `http` (1–32 halaman) terlalu kecil untuk kesimpulan. **[terbukti]** tidak ada perbedaan tertangkap yang bisa dikaitkan dengan skema atau `www.` (0,22–0,80%, interval lebar).

### Batas run ini

- **HTML statis, tanpa JavaScript.** Form dan teks yang dibangun JavaScript tidak terlihat (18.459 scam dan 3.697 legit `kosong`). Angka tertangkap adalah **batas bawah**.
- **Layer 3 saja.** Layer 1–2 di ekstensi menambah poin dari bentuk link.
- **Definisi "hidup".** 3xx dihitung hidup; di layer 3, 35,6% scam hidup gagal (96% dari `http_4xx` itu 3xx). `host_skipped` (scam 1.297, legit 2) dan DNS tidak jelas (scam 4.406, legit 1.099) tidak diuji layer 3, jadi tidak ikut hitungan.
- **Data lama.** 79,5% link scam tidak hidup. Efektifnya 29.392 halaman scam bukan resmi, dan hitungan per halaman bukan sampel independen (per host tidak dihitung).
- **Legit hanya sampel.** 61.958 dari 264.135 link hidup (23,5%), diambil dari awal daftar yang sudah diacak dengan seed tetap, sehingga **[dugaan]** acak. Angka legit adalah perkiraan, bukan hitungan penuh. Link legit yang ditolak (`401/403/429`: 9,4% dari semua legit) condong tidak terwakili: false-positive diukur hanya pada situs yang melayani `GET` polos dari skrip.
- **RDAP 5 detik** (produksi 1 detik) dan tidak tersedia untuk TLD tertentu (bagian 5): `new_domain` buta pada 25,7% halaman terbuka bukan resmi (scam 16,4%, legit 30,5%).
- **Host resmi dibungkam:** 2.308 halaman scam terbuka (7,3%) tidak bisa tertangkap; dicek jumlahnya saja.
- **Penjaga `teks_ekstrem`.** `parseHtml` memakai regex email `/[A-Z0-9._%+-]+@.../gi` (`ai/eval/tools/patterns.mjs`) yang **kuadratik** pada deretan panjang karakter itu. Satu halaman (id 120774, deretan 1.034.606 karakter) membuat run macet 24 menit di CPU 100%. Di `run.mjs` v4 halaman dengan deretan ≥ 20.000 karakter tidak diparse dan dicatat `gagal` / `teks_ekstrem`: scam 142, legit 130 (±0,3% dan 0,2% dari link hidup). Halaman tipe itu tidak bisa tertangkap dan tidak masuk hitungan. **Regex-nya tidak diperbaiki** (di luar folder v4); regex email "spelled out" di file yang sama punya masalah serupa. Aturan di `ai/src` tidak mengandung pola itu menurut grep sempit, tapi belum diperiksa menyeluruh.
- **Concurrency berubah selama run** (8 → 16 → 32 → 16 → 48) dan beberapa snapshot awal dibuat saat thread pool DNS Node masih 4 (default), yang menyebabkan timeout palsu. Setelah `UV_THREADPOOL_SIZE=128` kecepatan naik dari ±3,7 ke ±22–36 link per detik (concurrency 16 → 48) dengan persen gagal setara (±11%). Timeout hanya 557 (scam) dan 736 (legit) pada link hidup, jadi dampaknya kecil.
- **`--retry-failed` tidak dijalankan.** Opsi itu mengulang **semua** link gagal (scam 17.557 hidup-gagal ditambah legit gagal), padahal yang mungkin berubah hanya gagal jaringan murni (scam 1.643). Tidak sebanding; kalau mau dijalankan, perlu keputusan Imelda.
- **Tidak dikerjakan:** pengelompokan password-scam menurut letak brand (bagian 4), judul berulang (bagian 3), isi `iframes` (scam 2.206 dan legit 22.897 halaman terbuka punya iframe; hanya dicatat jumlah), cek manual legit yang kena, dan jumlah host unik untuk yang tertangkap.
- Isi halaman tidak dibaca untuk analisis ini; tidak ada instruksi dari isi halaman yang perlu dicatat.
