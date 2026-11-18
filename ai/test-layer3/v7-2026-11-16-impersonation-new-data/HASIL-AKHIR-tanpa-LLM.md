# Hasil akhir: layer 3 tanpa LLM

_Ditulis 2026-11-16. Menggabungkan `HASIL.md`, `ITERASI-1-ambang.md`, `LATIH-ULANG-v2.md`, `RDAP.md`, `LINKS.md`. Angka utama dibuat oleh `combine.py`._

> **Pembaruan 2026-11-17:** pipeline yang disarankan sekarang **v3g+umur**. Isinya model v2, saringan klaim v3 dengan perbaikan A+B, dan umur domain < 30 hari. Hasilnya:
> - Scam segar: 66,5% tertangkap.
> - Salah tanda: Kaggle legit 0,25%, legit Indonesia kalibrasi 1,5%, link aman manual 0 dari 15.
>
> Detail di `FP-ANALISIS.md` (bagian pembaruan) dan `shoo-impersonation-lab/out/impersonation-v3/eval-v3g.md`. Tabel di bawah adalah versi sebelum saringan klaim.

## Jawaban singkat

**Bisa tanpa LLM.** Pipeline akhir (model v2 + umur domain < 30 hari) menandai sekitar **69%** halaman phishing Indonesia yang segar dan belum pernah dilihat. Rules sekarang hanya 2%. Salah tanda pada situs sah sekitar 2 sampai 4%, tergantung data. Celah terbesar yang tersisa: situs kecil yang sah di hosting gratis ikut ditandai.

## Pipeline akhir

1. **Host resmi dan popular top 1.000** (Tranco, tanpa hosting bersama): `safe`.
2. **Model v2** (`shoo-impersonation-lab/out/impersonation-v2/model.joblib`, TF-IDF + regresi logistik + gradient boosting, tanpa bge-m3, tanpa GPU):
   - kelompok bahasa memakai detektor gabungan (Indonesia hanya kalau kata Indonesia lebih banyak dari kata fungsi bahasa asing);
   - ambang Indonesia dikalibrasi dari 429 halaman legit Indonesia di luar data latih (`thresholds-idcal.json`): warn 0,298, block 0,500. Bahasa lain: warn 0,612, block 0,873;
   - `warn` = banner peringatan, `block` = halaman diblokir. **`gate` dianggap aman**, karena tidak ada LLM.
3. **Umur domain < 30 hari** (RDAP, hanya untuk domain sendiri, bukan hosting gratis): `warn`, tidak pernah `block`.
4. Layer 1 (blocklist) tetap jalan seperti sekarang. Belum diukur di sini.

## Angka (tanpa LLM: hanya warn/block yang dihitung)

| Pipeline tanpa LLM | Scam feed segar, unseen (semua host) | Scam feed segar, unseen, domain sendiri | Scam feed segar, unseen, hosting gratis | Legit global (Kaggle, 1 halaman per situs, 1.500) | Legit Indonesia (bukan hosting gratis) | Link aman manual |
|---|---|---|---|---|---|---|
| Jumlah halaman | 856 | 140 | 716 | 1500 | 487 | 15 |
| Rules sekarang | 17 (2,0%) | 9 (6,4%) | 8 (1,1%) | 3 (0,2%) | 6 (1,2%) | 1 (6,7%) |
| Model v1 (1b) | 544 (63,6%) | 74 (52,9%) | 470 (65,6%) | 63 (4,2%) | 13 (2,7%) | 4 (26,7%) |
| Model v2 | 581 (67,9%) | 76 (54,3%) | 505 (70,5%) | 62 (4,1%) | 17 (3,5%) | 5 (33,3%) |
| **v2 + umur < 30 hari** | 594 (69,4%) | 89 (63,6%) | 505 (70,5%) | 63 (4,2%) | 19 (3,9%) | 5 (33,3%) |
| v2 + umur < 90 hari | 601 (70,2%) | 96 (68,6%) | 505 (70,5%) | 68 (4,5%) | 20 (4,1%) | 5 (33,3%) |

Salah tanda dari data uji lain (model v2, dari `LATIH-ULANG-v2.md`):

| Data legit | v2 warn/block | v2 block |
|---|---|---|
| Kaggle unseen, semua halaman (17.410) | 1,9% | 0,4% |
| phishing-url test unseen (5.170) | 2,8% | 0,7% |
| Test split Alief Indonesia, separuh B (323) | 0,3% | 0,0% |
| Halaman parkir/expired/cek bot (1.200) | 6,3% | 0,8% |

## Yang sudah terbukti dan yang belum

**Terbukti:**
- Model ringan kita lebih baik dari model Alief (bge-m3) dan jauh lebih baik dari rules sekarang di semua data uji.
- Label scam Kaggle sudah basi (0 dari 30 masih scam), jadi recall diukur di feed segar.
- Umur domain murah dan aman: +9 poin recall pada scam domain sendiri, salah tanda hampir tidak bertambah.
- Link t.me/wa.me tidak layak: situs Indonesia sah lebih sering memasangnya (28%) daripada scam (17%).

**Belum terbukti / batasan:**
- Feed segar berasal dari sumber yang sama dengan data latih Alief. Host-nya baru, tapi kit phishing-nya bisa sama. Untuk kit yang benar-benar baru, recall kemungkinan lebih rendah.
- Data legit condong ke situs lama dan daftar besar. UMKM dan situs Indonesia yang baru kurang terwakili, jadi salah tanda sebenarnya bisa lebih tinggi.
- Cek mata dilakukan oleh Claude dari teks tersimpan, belum oleh manusia.
- Halaman diambil tanpa JavaScript. Ekstensi melihat halaman yang sudah dirender.
- **Link aman manual: 5 dari 15 ditandai** (puskesmas dan SAR di vercel/netlify, `sakti.app`, `sites.google.com`). Ini masalah nyata yang belum dikerjakan (iterasi hosting gratis).

## Langkah berikutnya (urut)

1. **Hosting gratis:** di `vercel.app`, `netlify.app`, `pages.dev`, `sites.google.com`, `block` hanya kalau ada klaim brand atau form sensitif. Selain itu cukup `warn`. Ukur ulang di link aman manual dan feed segar.
2. **Data legit Indonesia yang lebih banyak dan baru** (situs `.go.id`, `.ac.id`, UMKM, toko), dicek manusia, untuk kalibrasi dan uji.
3. **Pasang di Shoo:** sidecar Python lokal untuk tes (`PROMPT.md` tahap 2), lalu ekspor bobot ke JSON untuk Worker. Model v2 kecil, tidak butuh GPU.
4. **Cek live di simulator** (`PROMPT.md` tahap 3).

## File

- Lab (`shoo-impersonation-lab/`): `train2.py`, `apply2.py`, `eval_v2.py`, `idcal.py`, `out/impersonation-v2/`, `iter1-idcal/`.
- Folder ini: `HASIL.md`, `ITERASI-1-ambang.md`, `LATIH-ULANG-v2.md`, `RDAP.md`, `LINKS.md`, ini, dan script `sample.py`, `fresh.mjs`, `fresh_sample.py`, `eyecheck_sample.py`, `report.py`, `rdap_measure.py`, `links_fetch.mjs`, `links_measure.py`, `combine.py`.
- Tidak ada file lama yang diubah. Belum ada yang di-commit. Sebelum commit: tambahkan `__pycache__/` ke `.gitignore`, dan periksa `detail.csv` (host sudah disamarkan, tapi repo-nya publik).
