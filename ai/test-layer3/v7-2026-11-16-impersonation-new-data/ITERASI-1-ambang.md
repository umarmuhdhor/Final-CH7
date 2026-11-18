# Iterasi 1: ambang bahasa Indonesia (v7)

> **Ralat (2026-11-16, ditulis setelah latih ulang v2):** klaim "dev split Alief hanya punya 30 halaman legit Indonesia" di bawah **salah**. Output hitungannya terpotong oleh `tail -30`. Di subset impersonation, dev punya sekitar 569 halaman legit Indonesia menurut detektor baru (576 menurut detektor lama). Penyebab ambang terlalu rendah yang benar: halaman legit Indonesia di dev berasal dari daftar yang sama dengan data latih (`hard_legit`, `legit_id`), jadi model sangat yakin pada halaman itu, sedangkan halaman Indonesia di luar daftar itu mendapat skor lebih tinggi. Perbaikannya tetap sama: kalibrasi ambang dari sumber luar (1b). Penyebab 2 (detektor bahasa) dan 3 (label kotor) tetap benar.

_Dibuat oleh `idcal.py fit2`. Model tidak dilatih ulang. Yang berubah hanya: (1) halaman mana yang masuk kelompok Indonesia, (2) ambang kelompok itu. Ambang bahasa lain tetap._

## Kenapa ada 1b

Saat membaca halaman legit dengan skor tertinggi di kalibrasi `fit`, banyak yang ternyata halaman Italia, Turki, dan Prancis (`is_indonesian` lolos hanya karena kata "di"), ditambah halaman judi/porno yang berlabel legit. Keduanya mendorong ambang terlalu tinggi.

## Ambang

Kalibrasi: **430** halaman legit Indonesia (201 phishing-url v4 train+dev, 229 separuh A test split Alief): lolos `indo_group`, bukan host resmi, bukan popular 1.000, tanpa kata judi/porno. Target 15% / 2% / 0,5%.

| | gate | warn | block |
|---|---|---|---|
| Lama (30 halaman dev Alief) | 0.0028 | 0.0910 | 0.3379 |
| **Baru (1b)** | 0.0199 | 0.3017 | 0.4414 |
| Bahasa lain (tetap) | 0.1969 | 0.6505 | 0.8830 |

## Hasil pada halaman yang dulu dianggap Indonesia (popular 1.000 aktif)

- **Sekarang**: detektor lama + ambang lama (yang terpasang di model).
- **Detektor baru saja**: halaman Italia/Turki/dll pindah ke ambang bahasa lain, ambang Indonesia tetap lama.
- **1b**: detektor baru + ambang Indonesia baru.

### Test split Alief (legit separuh B, semua scam)

| Versi | Scam | sampai L4 | warn/block | block | Legit | sampai L4 | warn/block | block |
|---|---|---|---|---|---|---|---|---|
| Sekarang | 33 | 32 (97,0%) | 30 (90,9%) | 28 (84,8%) | 323 | 51 (15,8%) | 3 (0,9%) | 1 (0,3%) |
| Detektor baru saja | 33 | 32 (97,0%) | 30 (90,9%) | 28 (84,8%) | 323 | 49 (15,2%) | 3 (0,9%) | 1 (0,3%) |
| **1b** | 33 | 31 (93,9%) | 29 (87,9%) | 27 (81,8%) | 323 | 17 (5,3%) | 1 (0,3%) | 0 (0,0%) |

### phishing-url v4 test (halaman v6)

| Versi | Scam | sampai L4 | warn/block | block | Legit | sampai L4 | warn/block | block |
|---|---|---|---|---|---|---|---|---|
| Sekarang | 17 | 13 (76,5%) | 10 (58,8%) | 8 (47,1%) | 47 | 21 (44,7%) | 6 (12,8%) | 3 (6,4%) |
| Detektor baru saja | 17 | 12 (70,6%) | 9 (52,9%) | 7 (41,2%) | 47 | 11 (23,4%) | 5 (10,6%) | 3 (6,4%) |
| **1b** | 17 | 10 (58,8%) | 8 (47,1%) | 7 (41,2%) | 47 | 7 (14,9%) | 3 (6,4%) | 2 (4,3%) |

### v7 Kaggle

| Versi | Scam | sampai L4 | warn/block | block | Legit | sampai L4 | warn/block | block |
|---|---|---|---|---|---|---|---|---|
| Sekarang | 119 | 59 (49,6%) | 24 (20,2%) | 6 (5,0%) | 109 | 80 (73,4%) | 32 (29,4%) | 16 (14,7%) |
| Detektor baru saja | 119 | 47 (39,5%) | 13 (10,9%) | 4 (3,4%) | 109 | 76 (69,7%) | 24 (22,0%) | 11 (10,1%) |
| **1b** | 119 | 31 (26,1%) | 5 (4,2%) | 3 (2,5%) | 109 | 60 (55,0%) | 13 (11,9%) | 10 (9,2%) |

### v7 link segar, semua kelompok

| Versi | Scam | sampai L4 | warn/block | block | Legit | sampai L4 | warn/block | block |
|---|---|---|---|---|---|---|---|---|
| Sekarang | 558 | 542 (97,1%) | 420 (75,3%) | 294 (52,7%) | 11 | 6 (54,5%) | 3 (27,3%) | 3 (27,3%) |
| Detektor baru saja | 558 | 542 (97,1%) | 419 (75,1%) | 294 (52,7%) | 11 | 6 (54,5%) | 2 (18,2%) | 2 (18,2%) |
| **1b** | 558 | 515 (92,3%) | 317 (56,8%) | 224 (40,1%) | 11 | 5 (45,5%) | 2 (18,2%) | 2 (18,2%) |

### v7 link segar, hanya unseen

| Versi | Scam | sampai L4 | warn/block | block | Legit | sampai L4 | warn/block | block |
|---|---|---|---|---|---|---|---|---|
| Sekarang | 40 | 26 (65,0%) | 17 (42,5%) | 12 (30,0%) | 4 | 1 (25,0%) | 0 (0,0%) | 0 (0,0%) |
| Detektor baru saja | 40 | 26 (65,0%) | 17 (42,5%) | 12 (30,0%) | 4 | 1 (25,0%) | 0 (0,0%) | 0 (0,0%) |
| **1b** | 40 | 22 (55,0%) | 13 (32,5%) | 10 (25,0%) | 4 | 0 (0,0%) | 0 (0,0%) | 0 (0,0%) |


## Analisis

Ditulis 2026-11-16. Kode: `shoo-impersonation-lab/idcal.py` (`prep`, `fit`, `fit2`). Ambang baru ada di `shoo-impersonation-lab/out/impersonation/thresholds-idcal2.json`. `model.joblib` tidak diubah.

### Penyebab (terbukti)

1. **Ambang Indonesia lama dihitung dari 30 halaman.** Dev split Alief hanya punya 30 halaman legit Indonesia (20 `legit_top` + 10 `legit_tail`, semuanya situs mudah). Dengan 30 halaman, ambang 0,5% dan 2% sama dengan skor tertinggi. Halaman `hard_legit` dan `legit_id` milik Alief semuanya masuk train dan test, tidak ada yang masuk dev.
2. **Detektor bahasa salah.** `is_indonesian` juga menyala di halaman Italia, Turki, dan Prancis karena kata seperti "di". Di data kalibrasi phishing-url, 171 dari 455 halaman "Indonesia" ternyata bukan bahasa Indonesia. Di Kaggle 34 dari 228. Halaman ini memakai ambang Indonesia yang rendah, jadi gampang ditandai.
3. **Label legit kotor.** Ada halaman judi/porno yang berlabel legit di data kalibrasi dan di data uji.

Percobaan pertama (`fit`, laporan `iter1-idcal/report.md`) memakai detektor lama dan menghasilkan ambang terlalu tinggi (block 0,58). Recall scam segar jatuh dari 52,7% ke 10,8% di block. Karena itu `fit2` dibuat.

### Hasil 1b (terbukti, popular 1.000 aktif)

| Data (halaman Indonesia) | Legit warn/block: sekarang → 1b | Scam warn/block: sekarang → 1b | Scam sampai L4: sekarang → 1b |
|---|---|---|---|
| Test split Alief, separuh B | 0,9% → 0,3% (gate 15,8% → 5,3%) | 90,9% → 87,9% | 97,0% → 93,9% |
| phishing-url test (v6) | 12,8% → 6,4% | 58,8% → 47,1% (17 halaman) | 76,5% → 58,8% |
| Kaggle v7 | 29,4% → 11,9% | (label basi, tidak dipakai) | |
| Link segar, semua | 27,3% → 18,2% (11 halaman) | 75,3% → 56,8% | 97,1% → 92,3% |
| Link segar, unseen | 0% → 0% (4 halaman) | 42,5% → 32,5% | 65,0% → 55,0% |

- **Terbukti:** dari 13 halaman "legit" Kaggle Indonesia yang masih ditandai 1b, 6 adalah situs judi di domain lama yang diambil alih, 1 halaman login palsu di `docs.google.com` (berlabel legit tapi sebenarnya phishing), 2 blogspot kosong, dan hanya 3 sampai 4 halaman yang benar-benar normal. **Dugaan:** salah tanda pada situs Indonesia yang benar-benar normal sekitar 3 sampai 4%. Targetnya 2%, jadi sudah dekat.
- **Harganya:** scam yang langsung ditampilkan tanpa LLM (warn/block) turun 3 sampai 18 poin, tergantung data. Scam yang sampai L4 tetap 92 sampai 94% di data yang cukup besar, jadi sebagian besar yang turun dari warn ke gate masih diperiksa layer 4.

### Kesimpulan iterasi 1

- **Pakai 1b** (detektor gabungan + ambang baru), jangan pakai `fit` pertama. Salah tanda situs Indonesia turun 2 sampai 3 kali lipat, dan scam masih hampir semua sampai L4.
- **Belum selesai:**
  - Detektor baru hanya dipakai untuk memilih ambang. Input `indo` di model masih memakai detektor lama. Melatih ulang dengan detektor baru adalah langkah berikutnya (perlu `train.py` baru, karena file lama tidak diubah).
  - Data kalibrasi 430 halaman, jadi ambang 0,5% bertumpu pada sekitar 2 halaman. Tambah halaman legit Indonesia (situs `.go.id`, `.ac.id`, toko, bank) supaya ambang `block` lebih stabil.
  - Iterasi 2 (halaman parkir/expired/cek bot) dan iterasi 3 (hosting gratis) dari `HASIL.md` belum dikerjakan.
