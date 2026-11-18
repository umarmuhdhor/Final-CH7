# Layer 2: link di hosting gratis dengan brand/kata umpan masih berbobot kecil

**Masalah.** Link scam di blogspot/netlify/vercel dengan nama brand atau kata umpan di subdomain hanya dapat skor layer 2 kecil:

| Contoh (disamarkan) | Layer 2 sekarang |
|---|---|
| `lazada-tbk-59.blogspot[.]com` | 10 (nama brand di domain tak terdaftar) |
| `undian-tiktok[.]online` | 5 (TikTok tidak ada di `brands.json`) |
| `undian-tselpoin-2015.blogspot[.]com` | 18 ("tsel" = Telkomsel tidak dikenali) |
| `program-hadiah-pt-android.blogspot[.]com` | 21 |

**Usulan** (`detector/src/detector.js`, `detector/data/brands.json`):

- **A.** Nama brand di subdomain hosting gratis: `lookalike_domain` level 1 dari 10 → 25.
- **B.** Kata umpan di nama hosting gratis (`free_name_bait`): 10 → 15 (2+ kata: 16 → 20).
- **C.** Brand baru: Telkomsel (`telkomsel`, `tsel`), Indosat (`indosat`, `im3`), TikTok. Pertimbangkan `poin` sebagai kata kunci (tselpoin).
- **D.** `free_name_number`: semua angka 2+ digit, bukan hanya `20xx` atau nominal.

**Hasil ukur** (layer 2 saja, ambang 30; varian dijalankan pada salinan `detector.js` hasil build, tanpa mengubah repo):

| Set | Sekarang | A+B+C+D |
|---|---|---|
| Scam segar (867 URL) | 35 (4,0%) | 164 (18,9%) |
| Legit Kaggle unseen (17.410) | 11 | 11 |
| Legit Indonesia, Alief separuh B (323) | 0 | 0 |
| Legit segar/manual (15) | 0 | 0 |

Hanya 2 legit yang skornya naik (11 → 16, karena D), tetap di bawah 30.

**Catatan.** `brands.json` juga dibaca model layer 3 (fitur brand). Menambah brand menggeser fitur model untuk halaman dengan nama itu:
ukur ulang `eval_v3.py` setelah diubah.
