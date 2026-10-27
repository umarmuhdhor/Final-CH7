# Perbandingan: testing 11 (18.54) vs ulangan (19.46)

> 26 Okt 2026. Link sama: `hxxps://d33wubrfki0l68[.]cloudfront[.]net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123[.]html`
> Sumber: `report.md` + `llm-response.md` (testing 11), `rerun-19.46/report.md` + `rerun-19.46/llm-response.md` (ulangan). Kolom ketiga (testing 14, `deepseek-v4-flash`, folder `14-testing-19.19`) hanya sebagai pembanding model.

## 1. Setelan (sama kecuali jam)

| Item | Testing 11 (18.54) | Ulangan (19.46) | Testing 14 (19.19) |
|---|---|---|---|
| Model | `glm-5.3-flash` (env override) | `glm-5.3-flash` (env override) | `deepseek-v4-flash` (`ai/.env`) |
| Prompt | v3 | v3 | v3 |
| Penyedia | `bandelbanget.xyz` | `bandelbanget.xyz` | `bandelbanget.xyz` |
| `temperature` / `max_tokens` / format | 0 / 200 / `json_object` | sama | sama |
| Panggilan | 10 + 3 + 3 | 10 + 3 + 3 | 10 + 3 + 3 |
| Token prompt | 1.843 | 1.843 | 1.842 |

## 2. Hasil 10 run lewat kode asli (batas 6 s)

| | Testing 11 | Ulangan | Testing 14 |
|---|---|---|---|
| flagged (skor 45) | 6 | 6 | 4 |
| reasonable (lolos) | 1 | 0 | 0 |
| timeout | 3 | 3 | 6 |
| bad_schema | 0 | 1 | 0 |
| Skor ≥ 30 | 6 dari 10 | 6 dari 10 | 4 dari 10 |
| Halaman lolos (skor 15) | 4 dari 10 | 4 dari 10 | 6 dari 10 |

## 3. Waktu

| | Testing 11 | Ulangan | Testing 14 |
|---|---|---|---|
| Run selesai: min / median / maks | 1,74 / 3,60 / 4,95 s (n = 7) | 2,29 / 3,40 / 5,40 s (n = 7) | 3,49 / 4,09 / 5,53 s (n = 4) |
| Non-stream tanpa batas: min / median / maks | 2,33 / 3,21 / 5,50 s | 4,26 / 4,39 / 5,49 s | 4,79 / 5,31 / 7,13 s |
| Stream selesai | 2,9 / 6,1 / 9,4 s | 5,85 / 21,99 / 4,00 s | 10,17 / 7,32 / 8,00 s |
| Porsi waktu di reasoning | 95–100% | 82–96% | 97–100% |

## 4. Isi jawaban model

| | Testing 11 | Ulangan | Testing 14 |
|---|---|---|---|
| `page_type` | courier (semua yang flagged); 1 run `reasonable:true` | courier (semua yang selesai) | courier (semua) |
| Confidence yang flagged | 0,70–0,85 | 0,65–0,82 | 0,90–0,95 |
| `asks` | hampir selalu `["password"]` | `["password"]`; run 5 `["email","password"]` | `["password"]` atau `+personal_data` |

## 5. Apa yang sama, apa yang beda

**Sama:**
- Layer 1–2 nol sinyal, layer 3 hanya `asks_password` (15), gerbang LLM terbuka. Skor tanpa LLM = 15, halaman lolos.
- Timeout 3 dari 10 di kedua run `glm-5.3-flash`; flagged 6 dari 10; median selesai 3,4–3,6 s.
- Reasoning memakan hampir seluruh waktu.

**Beda:**
- Testing 11 punya 1 run `reasonable:true` (confidence 0,45), ulangan tidak punya. Ulangan punya 1 `bad_schema`. Run 5 itu bukan galat penyedia: jawabannya JSON valid tapi `asks` berisi `"email"`, nilai yang tidak ada di daftar yang diizinkan prompt (`pin, otp, password, card, cvv, id_number, selfie_id, personal_data, other`), jadi ditolak validasi. Jadi `glm-5.3-flash` kadang melanggar enum.
- Non-stream tanpa batas: median 3,21 s (testing 11) vs 4,39 s (ulangan). Jam dan beban penyedia berbeda.
- Stream#2 ulangan 22 s (reasoning 20,6 s), pencilan besar. Tidak ada padanan di testing 11.

**Selisih `glm-5.3-flash` vs `deepseek-v4-flash`** (indikatif, jam berbeda):
- glm: 3 timeout, 6 flagged. deepseek: 6 timeout, 4 flagged.
- deepseek lebih yakin (confidence 0,90–0,95 vs 0,65–0,85) tapi lebih lambat dan lebih sering timeout.

## 6. Kesimpulan dan batas

- Hasil `glm-5.3-flash` **sebanding** antara dua sesi: 6 flagged dan 3 timeout. Selisih lain (satu `reasonable`, satu `bad_schema`) masih wajar untuk n = 10. Jangan membaca selisih satu run sebagai perbaikan atau kemunduran.
- Hasil ini **tidak** membuktikan `glm-5.3-flash` lebih baik dari `deepseek-v4-flash`: jam beda, n = 10, satu link, dan kecepatan penyedia berubah menurut beban.
- Dua temuan baru layak diperhatikan: model bisa melanggar daftar `asks` (jadi `bad_schema`), dan latensi stream bisa melonjak sampai 22 s.
- Belum terbukti: akurasi pada halaman lain dan false positive, stabilitas di jam lain, perilaku di Cloudflare Worker.
- Di semua run `glm-5.3-flash`, 30% tetap timeout dan 4 dari 10 halaman lolos; turun dari 60% timeout (deepseek) tapi belum nol.
