# Umur domain (RDAP) sebagai sinyal tanpa LLM

_Dibuat oleh `rdap_measure.py report`. Umur dihitung sampai 2026-11-16. Model: ours impersonation + popular 1.000, ambang iterasi 1b._

## Cakupan

| Kelompok | Halaman | Domain | Umur diketahui | Median umur (hari) | < 30 hari | < 90 hari | < 365 hari |
|---|---|---|---|---|---|---|---|
| scam_fresh_unseen | 139 | 135 | 121 | 299 | 26 (21%) | 41 (34%) | 66 (55%) |
| scam_fresh_seen | 12 | 11 | 12 | 4251 | 0 (0%) | 0 (0%) | 0 (0%) |
| scam_fresh_shared_host | 716 | (umur platform, tidak dipakai) | - | - | - | - | - |
| legit_kaggle_sample | 1500 | 1500 | 1420 | 8673 | 1 (0%) | 7 (0%) | 33 (2%) |
| legit_indonesian | 487 | 275 | 441 | 4438 | 5 (1%) | 6 (1%) | 13 (3%) |
| legit_manual | 10 | 10 | 10 | 5524 | 0 (0%) | 0 (0%) | 0 (0%) |

Status RDAP: `failed` 4, `http-404` 4, `no-date` 10, `no-rdap` 112, `ok` 1800

## Aturan yang dicoba

- **Model saja**: warn/block dari model (tanpa LLM, `gate` dihitung aman).
- **A**: umur < N hari saja sudah warn.
- **B**: model `gate` atau lebih **dan** umur < N hari jadi warn (umur menggantikan LLM untuk halaman `gate`).
- **C**: umur < N hari **dan** ada klaim brand (`brandInHost`, `brandOffsite`, `brandTextOffsite`) atau form sensitif jadi warn.

Umur tidak diketahui dihitung tidak muda.

| Aturan | N hari | Scam unseen ditandai | Scam seen ditandai | Legit Kaggle ditandai | Legit Indonesia ditandai | Link aman manual ditandai |
|---|---|---|---|---|---|---|
| Model saja | - | 74/139 (53,2%) | 1/12 (8,3%) | 63/1500 (4,2%) | 13/487 (2,7%) | 1/10 (10,0%) |
| A | 30 | 87/139 (62,6%) | 1/12 (8,3%) | 64/1500 (4,3%) | 15/487 (3,1%) | 1/10 (10,0%) |
| A | 90 | 93/139 (66,9%) | 1/12 (8,3%) | 69/1500 (4,6%) | 16/487 (3,3%) | 1/10 (10,0%) |
| A | 180 | 99/139 (71,2%) | 1/12 (8,3%) | 75/1500 (5,0%) | 17/487 (3,5%) | 1/10 (10,0%) |
| A | 365 | 106/139 (76,3%) | 1/12 (8,3%) | 94/1500 (6,3%) | 21/487 (4,3%) | 1/10 (10,0%) |
| B | 30 | 77/139 (55,4%) | 1/12 (8,3%) | 64/1500 (4,3%) | 15/487 (3,1%) | 1/10 (10,0%) |
| B | 90 | 80/139 (57,6%) | 1/12 (8,3%) | 68/1500 (4,5%) | 15/487 (3,1%) | 1/10 (10,0%) |
| B | 180 | 85/139 (61,2%) | 1/12 (8,3%) | 73/1500 (4,9%) | 15/487 (3,1%) | 1/10 (10,0%) |
| B | 365 | 91/139 (65,5%) | 1/12 (8,3%) | 83/1500 (5,5%) | 16/487 (3,3%) | 1/10 (10,0%) |
| C | 30 | 81/139 (58,3%) | 1/12 (8,3%) | 63/1500 (4,2%) | 15/487 (3,1%) | 1/10 (10,0%) |
| C | 90 | 82/139 (59,0%) | 1/12 (8,3%) | 64/1500 (4,3%) | 16/487 (3,3%) | 1/10 (10,0%) |
| C | 180 | 88/139 (63,3%) | 1/12 (8,3%) | 66/1500 (4,4%) | 17/487 (3,5%) | 1/10 (10,0%) |
| C | 365 | 94/139 (67,6%) | 1/12 (8,3%) | 72/1500 (4,8%) | 20/487 (4,1%) | 1/10 (10,0%) |


## Analisis

Ditulis 2026-11-16. **Terbukti** = angka dari tabel di atas. **Dugaan** = tafsir.

### Jawaban singkat

**Umur domain layak dipakai: aturan A (umur < 30 hari langsung warn) atau A-90.** Untuk scam yang memakai domain sendiri, recall tanpa LLM naik 9 sampai 14 poin, sedangkan salah tanda hampir tidak bertambah. Kelemahannya: hanya sekitar 1 dari 6 scam di feed yang memakai domain sendiri.

### Terbukti

- Scam segar unseen dengan domain sendiri: median umur **299 hari**. 21% di bawah 30 hari, 34% di bawah 90 hari, 55% di bawah 1 tahun. Legit: median 12 sampai 24 tahun, dan hanya 0 sampai 1% yang di bawah 90 hari.
- Model saja (tanpa LLM): scam unseen 53,2%, legit Kaggle 4,2%, legit Indonesia 2,7%.
  - **A-30:** scam **62,6%** (+9,4 poin), legit Kaggle 4,3% (+0,1), legit Indonesia 3,1% (+0,4).
  - **A-90:** scam **66,9%** (+13,7), legit 4,6% (+0,4) dan 3,3% (+0,6).
  - A-365: scam 76,3% (+23,1), tapi legit Kaggle naik ke 6,3% (+2,1).
- Aturan B (umur menggantikan LLM hanya untuk halaman `gate`) dan C (umur + klaim brand/form) lebih aman, tapi tambahannya lebih kecil daripada A. Scam baru sering tidak punya klaim brand yang terbaca dan tidak sampai `gate`.
- **Batas cakupan:** 716 dari 867 scam feed (83%) ada di hosting gratis (vercel, pages.dev, blogspot, carrd). Untuk mereka umur domain tidak berguna. Dihitung atas seluruh feed, A-30 hanya menambah sekitar 13 dari 867 halaman (+1,5 poin).
- Scam di situs lama yang diretas (12 halaman `seen`, median 11 tahun) juga tidak terbantu oleh umur domain.
- Domain tanpa RDAP: 112 domain (`no-rdap`, misalnya `.my`, `.co`, `.io`, `.me`). `.id` tercakup (PANDI).

### Dugaan dan batasan

- Legit di sini berasal dari daftar lama (Kaggle 2019-an, daftar legit Alief dan phishing-url), jadi condong ke domain tua. Di lalu lintas nyata ada lebih banyak situs sah yang baru (toko baru, kampanye, UMKM), jadi salah tanda sebenarnya kemungkinan lebih tinggi dari +0,1 sampai +0,8 poin. Karena itu **A-30 lebih aman daripada A-90** sampai ada data legit yang lebih baru.
- Untuk tampilan: domain muda tanpa sinyal lain sebaiknya mendapat `warn` (banner), bukan `block`.
- 139 scam unseen masih memakai label feed. Sekitar 1/3 mungkin sudah bersih (cek mata v7), jadi recall yang sebenarnya pada scam hidup lebih tinggi.

### Untuk hosting gratis (83% scam feed)

Umur domain tidak bisa dipakai. Pilihan tanpa LLM yang tersisa adalah perbaikan model (opsi 5: latih ulang, detektor bahasa, buang halaman parkir) dan aturan link keluar ke t.me/wa.me (opsi 4, perlu `links` di `PageSnapshot`).
