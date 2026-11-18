# Latih ulang dengan situs bisnis kecil sebagai legit: ditolak

_Ditulis 2026-11-17. Kode: `shoo-impersonation-lab/train3.py`, model `out/impersonation-smallbiz/`. Perbandingan: `eval_v3.py --kaggle-half B`, laporan `out/impersonation-v3/eval-v3g-v2-kaggleB.md` dan `eval-v3g-smallbiz-kaggleB.md`. Tanpa LLM: hanya warn/block yang dihitung._

## Yang dicoba

Ide dari `FP-ANALISIS.md`: model v2 memberi skor tinggi pada situs bisnis kecil (dokter gigi, kontraktor, jasa limo). Dugaannya karena legit di data latih Alief kebanyakan situs besar.

Caranya:
1. Legit Kaggle v7 "unseen" dibelah per situs (`kaggle_half`).
   - Separuh A: 2.750 halaman ditambah ke train dan 682 ke dev, dari 2.717 situs.
   - Separuh B: 7.423 halaman, tidak pernah dilihat model. Dipakai sebagai uji.
2. Pembersihan:
   - Maksimal 3 halaman per situs.
   - Halaman mati atau judi/porno dibuang (847 halaman).
   - Situs yang muncul di set uji lain dibuang (3.257 halaman).
3. Selebihnya sama dengan `train2.py`. Ambang Indonesia dikalibrasi dari 429 halaman luar yang sama.

## Hasil (aturan v3g+umur, model v2 vs model smallbiz)

| Set | v2 scam | v2 legit | smallbiz scam | smallbiz legit |
|---|---|---|---|---|
| Link segar unseen (856 / 12) | **569 (66,5%)** | 0 | 422 (49,3%) | 0 |
| Link aman manual (15 legit) | - | 0 | - | 0 |
| phishing-url v6 (323 / 5.170) | 62 | **44 (0,9%)** | 62 | 51 (1,0%) |
| Test Alief Indonesia (33 / 323) | 28 | 0 | 28 | 0 |
| Kaggle legit separuh B (7.423) | - | 25 (0,3%) | - | **16 (0,2%)** |
| Kaggle legit Indonesia separuh B (38) | - | 1 | - | 1 |
| Legit Indonesia kalibrasi (805) | - | **12 (1,5%)** | - | 14 (1,7%) |

Model saja (tanpa saringan klaim), pada scam segar: v2 67,9%, smallbiz 48,8%. AUC di test split Alief hampir sama: 0,984.

## Kenapa gagal

- Untung di legit kecil: Kaggle separuh B turun 25 → 16 halaman (0,1 poin).
- Rugi besar di scam segar: 147 scam lagi lolos (−17 poin). Hampir semuanya scam berbahasa Indonesia.
- Penyebab yang terlihat: skor median scam segar Indonesia turun dari 0,477 (v2) ke 0,268 (smallbiz). Angka itu di bawah ambang warn Indonesia 0,29. Skor kata dan alamat hampir sama. Yang bergeser adalah penggabung (gradient boosting).
- Dugaan: halaman Kaggle diambil dengan pipeline snapshot yang sama dengan feed segar, dan semuanya berlabel legit. Model belajar "gaya halaman pipeline ini = legit". Data latih Alief tidak punya bias itu. Ini dugaan, belum dibuktikan.
- Di v6 dan legit Indonesia, salah tanda malah naik sedikit.

## Keputusan

**Ditolak.** Pipeline tanpa LLM tetap memakai **model v2 + v3g + umur < 30 hari**. Untuk salah tanda di situs kecil, v3g sudah memberi hampir semua keuntungannya: Kaggle separuh B turun dari 2,4% (v2) ke 0,3%.

Kalau mau dicoba lagi, ada dua syarat:
1. Legit tambahan harus dari pipeline snapshot yang sama dengan scam baru. Misalnya scam segar dari feed baru juga masuk ke train, supaya pipeline tidak jadi sinyal label.
2. Bobot halaman tambahan dikecilkan.

Model `out/impersonation-smallbiz/` disimpan sebagai catatan dan tidak dipakai.
