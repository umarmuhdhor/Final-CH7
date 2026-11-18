# Hasil v7: model impersonation pada data maliciousphish (database-link-label.csv)

_Dibuat oleh `report.py` dari `.hasil/`. Host ditulis dengan `[.]`: jangan dibuka. Repo publik: baca sebelum commit._

## 0. Cara membaca

- **Data:** `test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/database-link-label.csv` (177.648 link, label Kaggle `malicious_phish`). Halaman tidak dibuka ulang: dipakai snapshot yang sudah tersimpan di `train-page.jsonl` (id sama). Hanya halaman yang terbuka dengan isi dan tidak pindah host.
- **Pipeline:** rules sekarang (`analyzeSnapshot`), Alief (bge-m3), dan model kita. Layer 1, 2, 4 dan umur domain mati, jadi ini hasil layer 3 saja.
- **Unseen** = situs yang tidak ada di train/dev Alief (model kita juga dilatih dari data Alief). Ini perbandingan yang adil.
- **Peringatan besar:** laporan v4 data ini menemukan 92 dari 100 halaman berlabel scam sudah bukan scam lagi. Bagian 3 (cek mata) mengulang pemeriksaan itu. Angka di bagian 2 memakai label mentah dan **tidak** mengukur kemampuan menangkap scam sungguhan.

## 1. Halaman

| Tahap | Jumlah |
|---|---|
| Link di CSV | 177.648 (scam 88.607, normal 89.041) |
| Halaman `ok` di CSV | 46.957 |
| Dibuang: pindah ke host lain | 12.960 |
| Dibuang: kosong / tidak ada di CSV | 11.855 / 117 |
| **Dinilai** | **34.004** halaman dari 13.635 situs |
| unseen | scam 12.367, legit 17.410 |
| seen-by-alief | scam 1.287, legit 2.940 |
| Sudah dipakai di v5 (unseen) | 3.990 |
| Domain di Tranco top 1.000 | 6.507 (scam 1.663, legit 4.844) |

## 2. Hasil dengan label mentah

### Situs unseen (perbandingan adil)

Scam 12.367 halaman, legit 17.410 halaman.

| Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block | Legit: block | AUC |
|---|---|---|---|---|---|---|---|
| Rules sekarang | 4 dari 12.367 (0,0%) | 4 dari 12.367 (0,0%) | 0 dari 12.367 (0,0%) | 10 dari 17.410 (0,1%) | 10 dari 17.410 (0,1%) | 0 dari 17.410 (0,0%) | 0,497 |
| Alief (bge-m3) | 2.730 dari 12.367 (22,1%) | 508 dari 12.367 (4,1%) | 49 dari 12.367 (0,4%) | 2.213 dari 17.410 (12,7%) | 432 dari 17.410 (2,5%) | 64 dari 17.410 (0,4%) | 0,639 |
| Alief + popular 1.000 | 2.702 dari 12.367 (21,8%) | 500 dari 12.367 (4,0%) | 44 dari 12.367 (0,4%) | 1.654 dari 17.410 (9,5%) | 347 dari 17.410 (2,0%) | 64 dari 17.410 (0,4%) | 0,639 |
| Ours, semua tipe scam | 2.596 dari 12.367 (21,0%) | 503 dari 12.367 (4,1%) | 49 dari 12.367 (0,4%) | 1.997 dari 17.410 (11,5%) | 337 dari 17.410 (1,9%) | 33 dari 17.410 (0,2%) | 0,641 |
| Ours, impersonation | 3.742 dari 12.367 (30,3%) | 725 dari 12.367 (5,9%) | 234 dari 12.367 (1,9%) | 2.726 dari 17.410 (15,7%) | 521 dari 17.410 (3,0%) | 157 dari 17.410 (0,9%) | 0,673 |
| **Ours, impersonation + popular 1.000** | 3.694 dari 12.367 (29,9%) | 714 dari 12.367 (5,8%) | 226 dari 12.367 (1,8%) | 1.895 dari 17.410 (10,9%) | 344 dari 17.410 (2,0%) | 82 dari 17.410 (0,5%) | 0,673 |

### Situs unseen, belum pernah dipakai di v5 (data baru sungguhan)

Scam 10.377 halaman, legit 15.410 halaman.

| Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block | Legit: block | AUC |
|---|---|---|---|---|---|---|---|
| Rules sekarang | 4 dari 10.377 (0,0%) | 4 dari 10.377 (0,0%) | 0 dari 10.377 (0,0%) | 8 dari 15.410 (0,1%) | 8 dari 15.410 (0,1%) | 0 dari 15.410 (0,0%) | 0,497 |
| Alief (bge-m3) | 2.338 dari 10.377 (22,5%) | 431 dari 10.377 (4,2%) | 40 dari 10.377 (0,4%) | 1.921 dari 15.410 (12,5%) | 366 dari 15.410 (2,4%) | 48 dari 15.410 (0,3%) | 0,645 |
| Alief + popular 1.000 | 2.315 dari 10.377 (22,3%) | 426 dari 10.377 (4,1%) | 37 dari 10.377 (0,4%) | 1.378 dari 15.410 (8,9%) | 283 dari 15.410 (1,8%) | 48 dari 15.410 (0,3%) | 0,645 |
| Ours, semua tipe scam | 2.230 dari 10.377 (21,5%) | 428 dari 10.377 (4,1%) | 39 dari 10.377 (0,4%) | 1.740 dari 15.410 (11,3%) | 288 dari 15.410 (1,9%) | 26 dari 15.410 (0,2%) | 0,647 |
| Ours, impersonation | 3.162 dari 10.377 (30,5%) | 616 dari 10.377 (5,9%) | 202 dari 10.377 (1,9%) | 2.411 dari 15.410 (15,6%) | 447 dari 15.410 (2,9%) | 140 dari 15.410 (0,9%) | 0,677 |
| **Ours, impersonation + popular 1.000** | 3.122 dari 10.377 (30,1%) | 608 dari 10.377 (5,9%) | 197 dari 10.377 (1,9%) | 1.598 dari 15.410 (10,4%) | 274 dari 15.410 (1,8%) | 66 dari 15.410 (0,4%) | 0,677 |

### Situs unseen, maksimal 3 halaman per situs

Scam 9.151 halaman, legit 7.826 halaman.

| Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block | Legit: block | AUC |
|---|---|---|---|---|---|---|---|
| Rules sekarang | 4 dari 9.151 (0,0%) | 4 dari 9.151 (0,0%) | 0 dari 9.151 (0,0%) | 10 dari 7.826 (0,1%) | 10 dari 7.826 (0,1%) | 0 dari 7.826 (0,0%) | 0,495 |
| Alief (bge-m3) | 2.164 dari 9.151 (23,6%) | 427 dari 9.151 (4,7%) | 41 dari 9.151 (0,4%) | 1.307 dari 7.826 (16,7%) | 281 dari 7.826 (3,6%) | 49 dari 7.826 (0,6%) | 0,625 |
| Alief + popular 1.000 | 2.158 dari 9.151 (23,6%) | 424 dari 9.151 (4,6%) | 39 dari 9.151 (0,4%) | 1.273 dari 7.826 (16,3%) | 272 dari 7.826 (3,5%) | 49 dari 7.826 (0,6%) | 0,625 |
| Ours, semua tipe scam | 2.083 dari 9.151 (22,8%) | 423 dari 9.151 (4,6%) | 44 dari 9.151 (0,5%) | 1.231 dari 7.826 (15,7%) | 237 dari 7.826 (3,0%) | 27 dari 7.826 (0,3%) | 0,629 |
| Ours, impersonation | 2.996 dari 9.151 (32,7%) | 620 dari 9.151 (6,8%) | 169 dari 9.151 (1,8%) | 1.440 dari 7.826 (18,4%) | 327 dari 7.826 (4,2%) | 80 dari 7.826 (1,0%) | 0,668 |
| **Ours, impersonation + popular 1.000** | 2.985 dari 9.151 (32,6%) | 617 dari 9.151 (6,7%) | 166 dari 9.151 (1,8%) | 1.398 dari 7.826 (17,9%) | 312 dari 7.826 (4,0%) | 74 dari 7.826 (0,9%) | 0,668 |

### Situs unseen, halaman dengan password field

Scam 251 halaman, legit 519 halaman.

| Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block | Legit: block | AUC |
|---|---|---|---|---|---|---|---|
| Rules sekarang | 3 dari 251 (1,2%) | 3 dari 251 (1,2%) | 0 dari 251 (0,0%) | 10 dari 519 (1,9%) | 10 dari 519 (1,9%) | 0 dari 519 (0,0%) | 0,529 |
| Alief (bge-m3) | 85 dari 251 (33,9%) | 23 dari 251 (9,2%) | 0 dari 251 (0,0%) | 47 dari 519 (9,1%) | 17 dari 519 (3,3%) | 3 dari 519 (0,6%) | 0,699 |
| Alief + popular 1.000 | 84 dari 251 (33,5%) | 23 dari 251 (9,2%) | 0 dari 251 (0,0%) | 45 dari 519 (8,7%) | 17 dari 519 (3,3%) | 3 dari 519 (0,6%) | 0,699 |
| Ours, semua tipe scam | 87 dari 251 (34,7%) | 24 dari 251 (9,6%) | 3 dari 251 (1,2%) | 46 dari 519 (8,9%) | 10 dari 519 (1,9%) | 2 dari 519 (0,4%) | 0,711 |
| Ours, impersonation | 92 dari 251 (36,7%) | 32 dari 251 (12,7%) | 15 dari 251 (6,0%) | 49 dari 519 (9,4%) | 15 dari 519 (2,9%) | 5 dari 519 (1,0%) | 0,728 |
| **Ours, impersonation + popular 1.000** | 88 dari 251 (35,1%) | 32 dari 251 (12,7%) | 15 dari 251 (6,0%) | 45 dari 519 (8,7%) | 15 dari 519 (2,9%) | 5 dari 519 (1,0%) | 0,728 |

### Semua halaman, termasuk situs yang dilatih Alief

Scam 13.654 halaman, legit 20.350 halaman.

| Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block | Legit: block | AUC |
|---|---|---|---|---|---|---|---|
| Rules sekarang | 5 dari 13.654 (0,0%) | 5 dari 13.654 (0,0%) | 0 dari 13.654 (0,0%) | 10 dari 20.350 (0,0%) | 10 dari 20.350 (0,0%) | 0 dari 20.350 (0,0%) | 0,497 |
| Alief (bge-m3) | 3.009 dari 13.654 (22,0%) | 661 dari 13.654 (4,8%) | 54 dari 13.654 (0,4%) | 3.153 dari 20.350 (15,5%) | 476 dari 20.350 (2,3%) | 72 dari 20.350 (0,4%) | 0,609 |
| Alief + popular 1.000 | 2.948 dari 13.654 (21,6%) | 650 dari 13.654 (4,8%) | 48 dari 13.654 (0,4%) | 2.573 dari 20.350 (12,6%) | 377 dari 20.350 (1,9%) | 72 dari 20.350 (0,4%) | 0,609 |
| Ours, semua tipe scam | 2.880 dari 13.654 (21,1%) | 663 dari 13.654 (4,9%) | 74 dari 13.654 (0,5%) | 2.994 dari 20.350 (14,7%) | 386 dari 20.350 (1,9%) | 46 dari 20.350 (0,2%) | 0,611 |
| Ours, impersonation | 4.114 dari 13.654 (30,1%) | 939 dari 13.654 (6,9%) | 331 dari 13.654 (2,4%) | 4.022 dari 20.350 (19,8%) | 659 dari 20.350 (3,2%) | 189 dari 20.350 (0,9%) | 0,641 |
| **Ours, impersonation + popular 1.000** | 3.991 dari 13.654 (29,2%) | 918 dari 13.654 (6,7%) | 322 dari 13.654 (2,4%) | 3.170 dari 20.350 (15,6%) | 466 dari 20.350 (2,3%) | 103 dari 20.350 (0,5%) | 0,641 |

## 3. Cek mata (dari teks tersimpan, tanpa membuka link)

Situs unseen, model ours + popular 1.000, maksimal 1 halaman per situs, seed tetap. Dibaca oleh Claude dari judul, 400 karakter pertama, dan jenis field form. Belum dicek manusia.

| Kelompok | Ukuran kelompok | Dibaca | `masih_scam` | `mati_parkir` | `normal` | `konten_buruk` | `tidak_jelas` |
|---|---|---|---|---|---|---|---|
| S1 Label scam, ours warn/block | 714 | 30 | 1 | 10 | 15 | 0 | 4 |
| S2 Label legit, ours warn/block | 344 | 30 | 0 | 17 | 9 | 2 | 2 |
| S3 Label scam + password field, ours safe | 163 | 30 | 0 | 0 | 30 | 0 | 0 |
| S4 Label scam, acak | 12.360 | 30 | 0 | 3 | 27 | 0 | 0 |
| S5 Label legit, ours gate | 1.551 | 15 | 0 | 4 | 11 | 0 | 0 |

`mati_parkir`: dijual, kedaluwarsa, diparkir, segera hadir, halaman default server, cek bot, halaman error. `konten_buruk`: judi atau porno di domain yang diambil alih, bukan peniruan brand.

## 4. Halaman tanpa isi situs (parkir, error, cek bot)

Ditandai dengan pola teks sederhana di `report.py` (`DEAD`). Perkiraan kasar: bisa salah ke dua arah.

| Situs unseen | Halaman | Bagian dari semua warn/block ours (+popular) di label ini | Ours warn/block di kelompok ini |
|---|---|---|---|
| scam, mirip parkir/error | 887 | 215 dari 714 (30,1%) | 215 dari 887 (24,2%) |
| scam, lainnya | 11.480 | 499 dari 714 (69,9%) | 499 dari 11.480 (4,3%) |
| legit, mirip parkir/error | 1.200 | 133 dari 344 (38,7%) | 133 dari 1.200 (11,1%) |
| legit, lainnya | 16.210 | 211 dari 344 (61,3%) | 211 dari 16.210 (1,3%) |

## 5. Contoh (situs unseen)

**Legit yang paling yakin di-warn/block ours (bukan parkir/error)**

| id | host | judul | rules | ours (+popular) |
|---|---|---|---|---|
| `mp_k0a4a2dc2ff` | `conroyclass[.]weebly[.]com` | `roofers in memphis` | 0 | 0.99 block |
| `mp_k9f8bebedd6` | `trainweb[.]org` | `` | 0 | 0.99 block |
| `mp_kd33ca2a9cc` | `lastpass[.]com` | `` | 0 | 0.98 block |
| `mp_k94fe5820c8` | `lastpass[.]com` | `` | 0 | 0.98 block |
| `mp_kd722d45f67` | `eagleeyeadvisors[.]com` | `eagleeyeadvisors[.]com` | 0 | 0.98 block |
| `mp_ke0c3650e9f` | `zionservices[.]net` | `ZION SERVICES GROUP INC.` | 0 | 0.97 block |
| `mp_k62d1da0b05` | `iavbbs[.]com` | `InterActiVision` | 0 | 0.97 block |
| `mp_k8cc876dd5b` | `trainweb[.]org` | `` | 0 | 0.95 block |

**Scam dengan password field yang ours anggap aman (skor terendah)**

| id | host | judul | rules | ours (+popular) |
|---|---|---|---|---|
| `mp_k0ec1fc976e` | `tidbits[.]com` | `Down the Gopher Hole - TidBITS` | 15 | 0.00 safe |
| `mp_k4dab044e57` | `www[.]orafaq[.]com` | `OraFAQ Forum: Welcome to the forum` | 15 | 0.00 safe |
| `mp_kffa3f27e81` | `www[.]virtualsalt[.]com` | `Gullibility Virus Warning` | 15 | 0.00 safe |
| `mp_k7a92543155` | `www[.]fantasyflightgames[.]com` | `Homepage Standard - Fantasy Flight Games` | 15 | 0.00 safe |
| `mp_kfdb87db87f` | `www[.]marketingforsuccess[.]com` | `Charlie Cook\'s Small Business Marketing Blog` | 15 | 0.00 safe |
| `mp_k33aab53c38` | `www[.]winlog[.]it` | `Winlog Forum - Index page` | 15 | 0.00 safe |
| `mp_kb7a768b88e` | `www[.]aatseel[.]org` | `Slavic fonts & keyboard drivers` | 15 | 0.00 safe |
| `mp_k41fe45b4cf` | `www[.]power-technology[.]com` | `North Luzon Wind Power Project, Philippines - Power Technolo` | 15 | 0.00 safe |

## 6. Link segar: feed phishing Alief 2026-11-09 dan daftar manual (diambil ulang hari ini)

Baris non-Kaggle di CSV tidak punya snapshot. `fresh.mjs` mengambil tiap link sekali (GET statis, tanpa JavaScript, sama seperti `pages.mjs`). Terbuka dengan isi dan tidak pindah host: **882** dari 1.239 (kosong 178, gagal 123, pindah host 56). Sebagian besar situs feed ini ada di data latih Alief (`seen`), jadi hanya baris `unseen` yang adil.

| Kelompok | Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block |
|---|---|---|---|---|---|---|
| unseen | Rules sekarang | 9 dari 140 (6,4%) | 9 dari 140 (6,4%) | 0 dari 140 (0,0%) | 1 dari 7 (14,3%) | 1 dari 7 (14,3%) |
| unseen | Alief (bge-m3) | 101 dari 140 (72,1%) | 72 dari 140 (51,4%) | 24 dari 140 (17,1%) | 2 dari 7 (28,6%) | 0 dari 7 (0,0%) |
| unseen | **Ours, impersonation + popular 1.000** | 106 dari 140 (75,7%) | 79 dari 140 (56,4%) | 52 dari 140 (37,1%) | 4 dari 7 (57,1%) | 1 dari 7 (14,3%) |
| test split Alief | Rules sekarang | 6 dari 60 (10,0%) | 6 dari 60 (10,0%) | 0 dari 60 (0,0%) | 0 dari 2 (0,0%) | 0 dari 2 (0,0%) |
| test split Alief | Alief (bge-m3) | 60 dari 60 (100,0%) | 48 dari 60 (80,0%) | 35 dari 60 (58,3%) | 2 dari 2 (100,0%) | 2 dari 2 (100,0%) |
| test split Alief | **Ours, impersonation + popular 1.000** | 60 dari 60 (100,0%) | 52 dari 60 (86,7%) | 47 dari 60 (78,3%) | 2 dari 2 (100,0%) | 2 dari 2 (100,0%) |
| train/dev Alief | Rules sekarang | 2 dari 667 (0,3%) | 2 dari 667 (0,3%) | 0 dari 667 (0,0%) | 0 dari 6 (0,0%) | 0 dari 6 (0,0%) |
| train/dev Alief | Alief (bge-m3) | 644 dari 667 (96,6%) | 380 dari 667 (57,0%) | 148 dari 667 (22,2%) | 3 dari 6 (50,0%) | 2 dari 6 (33,3%) |
| train/dev Alief | **Ours, impersonation + popular 1.000** | 653 dari 667 (97,9%) | 517 dari 667 (77,5%) | 352 dari 667 (52,8%) | 4 dari 6 (66,7%) | 2 dari 6 (33,3%) |

**Cek mata link segar (unseen, label scam), dibaca Claude dari teks tersimpan**

| Kelompok | Ukuran kelompok | Dibaca | `masih_scam` | `mati_parkir` | `normal` | `konten_buruk` | `tidak_jelas` |
|---|---|---|---|---|---|---|---|
| S6 ours safe (semua) | 34 | 34 | 4 | 0 | 22 | 1 | 7 |
| S7 ours gate/warn/block (acak) | 106 | 25 | 16 | 2 | 2 | 1 | 4 |

**Link aman manual (`manual_link_aman`) yang ours tandai warn/block**

| host | judul | kelompok | ours (+popular) |
|---|---|---|---|
| `dainty-queijadas-9ac794[.]netlify[.]app` | `Portal Registrasi Radio Beacon - Layanan Keselamatan SAR` | train | 0.51 block |
| `sites[.]google[.]com` | `LOGIN PAGE` | dev | 0.52 block |
| `petasan-5102[.]vercel[.]app` | `Petasan` | test | 0.49 block |
| `sakti[.]app` | `SAKTi   Sistem Aplikasi Kepegawaian Terintegrasi` | unseen | 0.76 warn |
| `ning-dila-pkmgabus2[.]vercel[.]app` | `UPT Puskesmas Gabus 2   Kab. Pati` | test | 0.98 block |

<!-- ANALISIS: tulisan di bawah baris ini tidak ditimpa oleh report.py -->

## Analisis dan kesimpulan

Ditulis 2026-11-16. **Terbukti** = angka dari tabel di atas. **Dugaan** = tafsir, belum dites. Model yang dinilai: Ours impersonation + popular top 1.000 (keputusan K1 di `PROMPT.md`).

### Jawaban singkat

**Cukup efektif untuk pola utama, tapi belum siap dipasang tanpa iterasi.** Model kita menangkap sebagian besar phishing Indonesia yang segar dan belum pernah dilihat (rules sekarang hampir buta). Ada tiga masalah yang harus diperbaiki dulu: ambang bahasa Indonesia terlalu galak, halaman parkir/expired/cek bot dianggap scam, dan situs kecil yang sah di hosting gratis kena block.

**Dibanding Alief (bge-m3), terbukti:** ours sama atau lebih baik di semua potongan. Di link segar unseen, ours sampai L4 75,7% (Alief 72,1%), warn/block 56,4% (51,4%), dan block **37,1% (17,1%)**. Di data Kaggle unseen, AUC ours 0,673 (Alief 0,639), dengan legit warn/block yang sama setelah popular 1.000 (2,0% lawan 2,0%). Syarat berhenti di `PROMPT.md` (ours lebih buruk lebih dari 0,03 AUC) tidak terpenuhi. Membuang bge-m3 tetap keputusan yang benar.

### 1. Data Kaggle (34.004 halaman) tidak bisa mengukur kemampuan menangkap scam

- **Terbukti:** cek mata 30 halaman scam acak: **0** yang masih scam (bagian 3, S4). Laporan v4 data ini: 3 dari 100. Dari 30 halaman scam yang ours warn/block, hanya 1 yang masih scam (S1).
- Jadi AUC 0,67 di bagian 2 mengukur "link ini pernah dilaporkan", bukan "halaman ini scam hari ini". Angka itu tidak boleh dipakai sebagai ukuran recall.
- Yang **bisa** diukur dari data ini: berapa banyak halaman nyata yang salah ditandai. Hampir semua halaman di sini, apa pun labelnya, praktis bukan scam.

### 2. Salah tanda pada halaman nyata (data Kaggle, situs unseen)

- **Terbukti:** legit warn/block **2,0%**, block **0,5%**, gate **10,9%**. Targetnya 2% / 0,5% / 15%, jadi kalibrasi umum bertahan di data baru. Halaman label scam (yang praktis bukan scam lagi): warn/block 5,8%.
- **Terbukti:** dari 30 legit yang ours warn/block (S2), **17 halaman parkir/expired/segera hadir/cek bot/default server**, 9 situs normal, 2 judi/porno di domain diambil alih, 2 tidak jelas.
- **Dugaan:** salah tanda pada situs yang benar-benar hidup sekitar 0,6 sampai 0,7% dari halaman legit (344 × 9–11/30 ÷ 17.410).
- **Terbukti, dan paling penting untuk Shoo:** halaman **legit berbahasa Indonesia**: 109 halaman di data Kaggle, **73% sampai L4, 29% warn/block, 15% block**. Di link aman manual, 3 dari 11 halaman Indonesia di-block. Ambang Indonesia di model (`gate` 0,0028, `warn` 0,091, `block` 0,338) jauh lebih rendah dari ambang bahasa lain (0,197 / 0,651 / 0,883). **Dugaan:** dev set Alief punya sedikit sekali halaman legit Indonesia, sehingga ambangnya dipasang terlalu rendah. Jumlah halaman masih kecil (109 + 11), jadi besarnya angka belum pasti, tapi arahnya jelas.

### 3. Link segar (feed phishing Alief 2026-11-09, diambil ulang hari ini): ukuran recall yang paling jujur

- **Terbukti (unseen, 140 scam):** ours **75,7%** sampai L4, **56,4%** warn/block, **37,1%** block. Rules sekarang 6,4% / 6,4% / 0%.
- **Terbukti (cek mata):** dari 34 yang ours loloskan, hanya **4** yang masih scam (2 situs info bansos palsu yang meniru Kemensos, 1 situs desa diretas berisi "Call Center Atome" palsu, 1 toko tiruan) dan 7 tidak jelas. Sisanya 22 halaman normal: phishing-nya sudah dihapus atau situsnya sudah bersih. Dari 25 sampel acak yang ours tandai, 16 memang scam (klaim hadiah palsu, login BRI/Microsoft palsu, WhatsApp/Roblox palsu, undian TikTok), 2 parkir, 2 normal (keduanya hanya di gate), 4 tidak jelas.
- **Dugaan:** recall pada halaman yang masih scam hari ini sekitar **86 sampai 95%**, dan presisi di antara yang ditandai sekitar 64 sampai 80%. Basisnya 140 halaman dan satu pembaca, jadi rentangnya lebar.
- Feed ini kebanyakan berasal dari situs yang dilatih Alief (667 dari 867). Di situ ours sampai L4 97,9%, tapi itu tidak adil dan tidak dipakai untuk kesimpulan.

### 4. Pola yang lolos

- Scam tanpa form: situs info bansos palsu, CS palsu di situs desa yang diretas, artikel "saldo DANA gratis". Model kita mencari halaman yang meniru brand **dan** meminta sesuatu, sedangkan halaman ini hanya mengarahkan ke WhatsApp/Telegram. **Dugaan:** ini bagian layer 4 atau aturan link keluar (wa.me, t.me), bukan layer 3.
- Domain typosquat dengan isi blog biasa (`steamcommunity[.]id`, `googleusercontent[.]my[.]id`). Isi halamannya tidak meniru apa-apa, jadi lebih cocok ditangkap di layer 2 (alamat).

### 5. Yang perlu diiterasi (urut prioritas)

1. **Ambang bahasa Indonesia.** Tetapkan ulang dengan lebih banyak halaman legit Indonesia (misalnya halaman `ok` legit Indonesia dari data ini, situs `.go.id`/`.ac.id`/`.co.id`, dan link aman manual), dengan target yang sama (15% / 2% / 0,5%). Tanpa ini, banyak situs Indonesia yang sah akan diperingatkan.
2. **Halaman tanpa isi situs** (parkir, dijual, expired, segera hadir, cek bot, default server, error). Deteksi dulu, beri tier `safe` atau tier netral, dan buang halaman seperti ini dari baris scam di data latih. **Dugaan:** artefak ini muncul dari label scam basi di data Alief: domain scam yang mati menjadi halaman parkir, lalu model belajar "parkir = scam". Perkiraan efek: warn/block pada legit turun 40 sampai 55%.
3. **Hosting gratis** (`vercel.app`, `netlify.app`, `pages.dev`, `sites.google.com`). Jangan block hanya karena host-nya. Wajibkan klaim brand atau form sensitif untuk `block`. Contoh salah block: situs puskesmas dan portal registrasi SAR di link aman manual.
4. **Test set baru yang dicek manusia.** Pakai feed harian (bukan Kaggle) ditambah legit Indonesia, minimal 200 scam unseen dan 500 legit Indonesia. Cek mata di laporan ini dilakukan Claude dari teks tersimpan, bukan manusia.

### Batasan

- Halaman diambil tanpa JavaScript. Ekstensi melihat halaman yang sudah dirender, jadi isinya bisa berbeda.
- Cek mata: 135 + 59 halaman, satu pembaca (Claude), hanya dari teks tersimpan.
- Link segar diambil sekali, 7 hari setelah feed dibuat. Sebagian phishing mungkin sudah dihapus atau menampilkan isi berbeda untuk bot.
- Tahap 2 (sidecar di Shoo) dan tahap 3 (cek live di simulator) dari `PROMPT.md` **belum dikerjakan**. Imelda meminta tidak ada file yang diubah, sedangkan pemasangan harus mengubah `ai/src`.
