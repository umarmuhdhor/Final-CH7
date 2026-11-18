# Latih ulang: model v2 dibanding v1

_Dibuat oleh `eval_v2.py`. Keduanya: popular 1.000 aktif, ambang Indonesia dikalibrasi dari set luar yang sama. **Tampilan utama tanpa LLM**: hanya warn/block yang dihitung tertangkap. Gate ditulis sebagai pembanding._

Ambang v2: Indonesia gate 0.0165 / warn 0.2981 / block 0.5001 (kalibrasi 429 halaman); bahasa lain 0.1746 / 0.6125 / 0.8728. Ambang v1 (1b): Indonesia 0.0199 / 0.3017 / 0.4414; bahasa lain 0.1969 / 0.6505 / 0.8830.

### Link segar, unseen (definisi diperbaiki)

Scam 856, legit 12.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | 544 (63,6%) | 380 (44,4%) | 788 (92,1%) | 4 (33,3%) | 3 (25,0%) | 8 (66,7%) |
| **v2** | 581 (67,9%) | 284 (33,2%) | 800 (93,5%) | 5 (41,7%) | 2 (16,7%) | 8 (66,7%) |

### Link segar, semua

Scam 867, legit 15.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | 545 (62,9%) | 381 (43,9%) | 792 (91,3%) | 4 (26,7%) | 3 (20,0%) | 9 (60,0%) |
| **v2** | 582 (67,1%) | 285 (32,9%) | 805 (92,8%) | 5 (33,3%) | 2 (13,3%) | 8 (53,3%) |

### Link aman manual (legit)

Scam 0, legit 15.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | - | - | - | 4 (26,7%) | 3 (20,0%) | 9 (60,0%) |
| **v2** | - | - | - | 5 (33,3%) | 2 (13,3%) | 8 (53,3%) |

### phishing-url test (v6), unseen

Scam 323, legit 5170.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | 132 (40,9%) | 79 (24,5%) | 227 (70,3%) | 124 (2,4%) | 27 (0,5%) | 839 (16,2%) |
| **v2** | 135 (41,8%) | 79 (24,5%) | 217 (67,2%) | 146 (2,8%) | 34 (0,7%) | 893 (17,3%) |

### Test split Alief, Indonesia (legit separuh B, semua scam)

Scam 33, legit 323.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | 29 (87,9%) | 27 (81,8%) | 31 (93,9%) | 1 (0,3%) | 0 (0,0%) | 17 (5,3%) |
| **v2** | 28 (84,8%) | 28 (84,8%) | 31 (93,9%) | 1 (0,3%) | 0 (0,0%) | 16 (5,0%) |

### Kaggle v7 unseen, legit saja (label scam basi)

Scam 0, legit 17410.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | - | - | - | 329 (1,9%) | 80 (0,5%) | 1876 (10,8%) |
| **v2** | - | - | - | 326 (1,9%) | 67 (0,4%) | 1845 (10,6%) |

### Kaggle v7 unseen, legit mirip parkir/error

Scam 0, legit 1200.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | - | - | - | 132 (11,0%) | 36 (3,0%) | 381 (31,8%) |
| **v2** | - | - | - | 76 (6,3%) | 10 (0,8%) | 263 (21,9%) |

### Kaggle v7 unseen, legit Indonesia

Scam 0, legit 87.

| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |
|---|---|---|---|---|---|---|
| v1 (1b) | - | - | - | 6 (6,9%) | 5 (5,7%) | 44 (50,6%) |
| **v2** | - | - | - | 9 (10,3%) | 6 (6,9%) | 47 (54,0%) |


## Analisis

Ditulis 2026-11-16. Kode: `shoo-impersonation-lab/train2.py`, `apply2.py`, `eval_v2.py`. Model: `out/impersonation-v2/model.joblib`. Ambang: `out/impersonation-v2/thresholds-idcal.json`. `train.py`, `apply.py`, dan model v1 tidak diubah.

### Yang diubah di v2

1. Detektor bahasa gabungan (iterasi 1b) dipakai sebagai input model dan untuk memilih ambang.
2. 63 halaman scam yang mirip parkir/expired/cek bot dibuang dari train dan dev.
3. 261 halaman legit berisi kata judi/porno dibuang dari train dan dev.
4. 324 halaman legit Indonesia dipindah dari train ke dev. **Ternyata tidak perlu:** dev sudah punya sekitar 569 halaman legit Indonesia (lihat ralat di `ITERASI-1-ambang.md`).

### Hasil (terbukti)

- **Masalah halaman parkir membaik:** di halaman legit yang mirip parkir/error, warn/block turun dari 11,0% ke **6,3%** dan block dari 3,0% ke **0,8%**.
- **Link segar** (definisi unseen diperbaiki, 856 scam): warn/block naik dari 63,6% ke **67,9%**, tapi block turun dari 44,4% ke 33,2%. Banyak halaman yang dulu block sekarang hanya warn. Kalau tanpa LLM keduanya dihitung "ditandai", jadi ini tidak merugikan.
- **phishing-url test (v6) unseen:** scam hampir sama (40,9% → 41,8%). Legit warn/block sedikit naik (2,4% → 2,8%, +22 halaman), kebanyakan halaman login sah berbahasa Turki dan Spanyol.
- **Test split Alief Indonesia:** sama (legit warn/block 0,3%).
- **Kaggle legit Indonesia:** 6,9% → 10,3%, tapi 3 halaman tambahannya adalah situs judi di domain yang diambil alih (ROYALTOGEL, PENYU178). Benar ditandai, hanya labelnya legit.

### Kesimpulan latih ulang

- **v2 sedikit lebih baik dari v1, bukan lompatan.** Yang jelas membaik: salah tanda pada halaman parkir (turun hampir separuh) dan recall tanpa LLM di link segar (+4 poin). Yang sedikit memburuk: salah tanda legit bahasa lain (+0,4 poin).
- **Temuan penting dari definisi unseen yang diperbaiki:** pada feed phishing Indonesia, model tanpa LLM menandai **64 sampai 68%** scam (warn/block), dan **92 sampai 94%** sampai `gate`. Sebelumnya saya mengira hanya 140 halaman yang unseen. Sekarang terlihat hampir semua halaman feed di hosting gratis memang belum pernah dilihat sebagai host. **Dugaan:** banyak yang memakai kit phishing yang sama dengan data latih Alief, karena feed-nya dari sumber yang sama. Untuk kit baru, angkanya bisa lebih rendah.
- **Celah tanpa LLM:** sekitar 25 sampai 28% scam ada di tingkat `gate` (model ragu). Untuk menutupnya tanpa LLM, pilihannya: (a) `gate` dijadikan banner ringan, tapi salah tanda legit naik ke 10 sampai 17%, terlalu banyak; (b) umur domain (hanya untuk domain sendiri, lihat `RDAP.md`); (c) aturan link t.me/wa.me (perlu `links` di snapshot); (d) data latih Indonesia yang lebih banyak dan lebih segar.

### Batasan

- Link aman manual hanya 15 halaman, dan 5 di antaranya di-warn/block oleh kedua model (situs puskesmas/SAR di vercel/netlify, `sakti.app`). Masalah hosting gratis (iterasi 3) belum dikerjakan.
- Cek mata belum diulang untuk v2.
