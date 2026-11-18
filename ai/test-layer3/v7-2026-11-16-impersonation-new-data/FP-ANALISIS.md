# Kenapa v3f masih banyak salah tanda

Ditulis 2026-11-16. Diambil dari semua halaman berlabel legit yang masih ditandai warn/block oleh v3f (`eval_v3.py`): **162 halaman**. Rinciannya: Kaggle unseen 87 dari 17.410, phishing-url v6 63 dari 5.170, legit Indonesia kalibrasi 11 dari 805, link aman manual 1 dari 15. Tanpa LLM.

## Akar masalah

### 1. Model v2 memberi skor tinggi pada situs bisnis kecil biasa (penyebab utama)

Contohnya dokter gigi, jasa limo, kontraktor, studio DJ, kiropraktor, dan klub baseball. Skor kata 0,3 sampai 0,7, skor alamat 0,2 sampai 0,8.
**Dugaan:** di data latih, legit kebanyakan situs besar dan populer, jadi situs kecil yang asing dianggap mirip scam. Selain itu, ambang warn sengaja disetel supaya **2% halaman legit dev** lolos ke warn (`TIERS` di `train.py`). Di lalu lintas nyata yang banyak berisi situs kecil, 2% berarti banyak banner.

Aturan klaim (iterasi 3) hanya menyaring hasil model. Kalau saringannya bocor, salah tanda model ikut lolos.

### 2. Saringan klaim bocor (terbukti)

Pemicu klaim pada 162 halaman (satu halaman bisa punya beberapa pemicu):

| Pemicu | Halaman | Kenapa bocor |
|---|---|---|
| Brand **hanya di teks** (`brandsInText` + `brandTextOffsite`) | **53 (satu-satunya pemicu)** | Footer menyebut Facebook, Google, WhatsApp, Instagram ("Follow us", ikon sosial media). Sinyal ini menyala untuk hampir semua situs bisnis. |
| Kata pancingan bahasa Inggris yang umum | sekitar 35 | `claim`, `customer service`, `profit`, `reward`, `refund`, `gratis` muncul di situs sah (toko, asuransi, investasi). |
| Kolom password + skor kata ≥ 0,75 | 12 | Login forum, sekolah, aplikasi kecil. |
| Kata kredensial (`email password`, `webmail`) | 8 | Halaman login hosting dan webmail sah. |

### 3. Sebagian "salah tanda" sebenarnya bukan legit

21 dari 162 berisi judi atau dewasa (domain diambil alih: "OVO288 Slot Gacor", "VAVADA casino"). 10 halaman parkir atau mati ("Porkbun Marketplace"). Jadi sekitar **19%** salah tanda yang tersisa adalah label yang basi.

## Perbaikan yang diukur

- **A:** brand yang hanya ada di teks baru dihitung kalau halaman punya form (password, atau form dengan minimal 2 kolom) atau kata pancingan. Brand di judul, host, atau logo tetap langsung dihitung.
- **B:** kata pancingan dipersempit. Kata umum dibuang (`claim`, `reward`, `refund`, `profit`, `customer service`, `gratis`, `saldo`, `menang`, `verifikasi`, ...). Yang dipertahankan: frasa scam (`claim your/now`, `you have won`, `congratulations`, `verify your`) dan kata Indonesia yang kuat (hadiah, undian, bansos, pencairan, pembatalan, call center).
- **C:** ambang kolom password + skor kata dinaikkan dari 0,75 ke 0,85.

| Set | v3f scam | v3f legit | **A+B scam** | **A+B legit** | A+B+C scam | A+B+C legit |
|---|---|---|---|---|---|---|
| Link segar unseen (856 / 12) | 552 | 1 | **548** | **0** | 546 | 0 |
| phishing-url v6 (323 / 5.170) | 75 | 63 | 62 | **46** | 58 | 39 |
| Test Alief Indonesia (33 / 323) | 28 | 0 | 28 | 0 | 28 | 0 |
| Kaggle legit (17.410) | - | 87 (0,50%) | - | **45 (0,26%)** | - | 43 |
| Legit Indonesia kalibrasi (805) | - | 11 | - | **8** | - | 8 |

**A+B** memangkas salah tanda Kaggle hampir separuh (87 → 45). Scam Indonesia segar hanya turun 4 dari 552. C menambah sedikit, dengan biaya recall v6.

Kalau banner hanya untuk tingkat `block`, sesudah A+B: Kaggle legit 12, v6 legit 12. Tapi scam segar ikut turun separuh (548 → 274). **Tidak disarankan.**

## Kesimpulan

- Penyebab utama ada dua: (1) model v2 menganggap situs kecil biasa mencurigakan, dan ambang warn sengaja menerima sekitar 2% legit; (2) saringan klaim bocor lewat footer sosial media dan kata pancingan bahasa Inggris yang umum.
- Perbaikan cepat tanpa latih ulang: **A+B (v3g)**. Salah tanda legit turun lagi sekitar 45%, recall scam Indonesia hampir sama.
- Perbaikan yang lebih dalam (perlu latih ulang): tambah situs bisnis kecil dan lama sebagai legit di data latih, misalnya dari daftar Kaggle legit yang bukan split uji. Lalu kalibrasi ulang ambang warn dengan legit yang mirip lalu lintas nyata, bukan hanya situs besar.

## Pembaruan 2026-11-17: v3g terpasang

A+B sekarang ada di `shoo-impersonation-lab/eval_v3.py` sebagai varian **v3g**. Ada juga **v3g+umur**: domain sendiri yang umurnya < 30 hari minimal `warn`. Tabel lengkap ada di `out/impersonation-v3/eval-v3g.md`. `eval.md` yang lama tidak diubah.

Catatan B: kata Indonesia `klaim` dan `pemenang` **tetap dipakai**. Kalau dibuang, 6 scam hadiah Indonesia di feed segar hilang (M-KIOS, Telkomsel, "cek tunai", portal klaim bonus), dan legit tidak berkurang sama sekali. Yang dibuang hanya `claim` versi Inggris dan kata umum lainnya.

| Set | v3f scam | v3f legit | **v3g scam** | **v3g legit** | v3g+umur scam | v3g+umur legit |
|---|---|---|---|---|---|---|
| Link segar unseen (856 / 12) | 552 | 1 | **548** | **0** | 569 (66,5%) | 0 |
| Link aman manual (15 legit) | - | 1 | - | **0** | - | 0 |
| phishing-url v6 (323 / 5.170) | 75 | 63 | 62 | **44** | 62 | 44 |
| Test Alief Indonesia (33 / 323) | 28 | 0 | 28 | 0 | 28 | 0 |
| Kaggle legit (17.410) | - | 87 (0,50%) | - | **43 (0,25%)** | - | 44 |
| Kaggle legit Indonesia (87) | - | 7 | - | **2** | - | 2 |
| Legit Indonesia kalibrasi (805) | - | 11 | - | **8** | - | 12 |

Cek mata 50 halaman:
- Legit yang memang sah tapi masih ditandai: v3f 4, v3g **1**.
- Legit yang labelnya salah tapi masih ditandai: v3f 4, v3g **2**.
- Scam asli yang masih ditandai: 13 dan 13. Tidak ada scam yang hilang.

Umur < 30 hari:
- Tambahan: 21 scam segar (+2,5 poin).
- Biaya: 4 legit Indonesia kalibrasi dan 1 Kaggle.
- Umur hanya diketahui untuk link segar, 1.500 Kaggle, dan legit Indonesia kalibrasi. Di set lain angkanya sama dengan v3g.

**Rekomendasi: v3g+umur** sebagai pipeline tanpa LLM. Dibanding v2 saja:
- Salah tanda Kaggle: 1,9% → 0,25%.
- Recall scam Indonesia segar: 67,9% → 66,5%.
