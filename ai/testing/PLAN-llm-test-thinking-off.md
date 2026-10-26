# PLAN (DRAFT, menunggu review Imelda): uji layer 4 dengan `thinking: {type: "disabled"}`

> Status: **belum dijalankan.** Dibuat 26 Okt 2026 setelah testing 15 (`reasoning: {enabled: false}`) terbukti tidak dihormati proxy `bandelbanget.xyz`. Plan ini turunan dari `PLAN-llm-test.md`; semua aturan keselamatan di sana (bagian 5) tetap berlaku.

## 1. Tujuan dan hipotesis

Pertanyaan: apakah mengirim `thinking: {"type": "disabled"}` (bukan `reasoning: {enabled: false}`) mematikan fase berpikir di proxy ini, sehingga layer 4 selesai di bawah batas 6 s?

Alasan mencoba: testing 14 dan 15 menunjukkan 94–100% waktu LLM habis di fase reasoning, padahal jawabannya hanya ±100 karakter. `reasoning: {enabled: false}` diabaikan (token reasoning tetap 176–634). `thinking` adalah nama field lain yang dipakai beberapa penyedia (gaya Anthropic/GLM).

Hipotesis yang bisa salah: proxy mengabaikan `thinking` juga. Itu hasil yang sah; plan ini dibuat untuk mengetahuinya, bukan untuk membuktikan satu arah.

Catatan istilah: di kode, LLM adalah **layer 4** (reality check); layer 3 tetap aturan form/isi tanpa LLM.

## 2. Setelan yang diuji

| Item | Nilai |
|---|---|
| Field yang dikirim ke body request | `"thinking": {"type": "disabled"}` |
| Setara variabel config | `LLM_REASONING=off`, `LLM_REASONING_FIELD=thinking` |
| Model | `deepseek-v4-flash` (dari `ai/.env`); opsi tambahan: `glm-5.3-flash` lewat `LLM_MODEL=glm-5.3-flash` |
| Prompt, `temperature`, `max_tokens`, `response_format` | sama seperti produksi (v3, 0, 200, `json_object`) |
| Link | `hxxps://d33wubrfki0l68[.]cloudfront[.]net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123[.]html` |

**Penting, soal `LLM_REASONING` dan `LLM_REASONING_FIELD`:** dua variabel ini **belum ada** di kode produksi. `grep` di `ai/src` dan `ai/prompts` tidak menemukan `LLM_REASONING`, `thinking`, atau `reasoning`, dan `ai/.env.example` hanya punya `LLM_API_KEY`, `LLM_MODEL`, `LLM_BASE_URL`, `LLM_TIMEOUT_MS`, `LLM_DAILY_CAP`. Provider produksi (`src/layer4/provider.js`) mengirim body tetap tanpa field tambahan. Jadi plan ini **tidak** mengubah produksi: runner menyuntikkan field ke body (seperti yang sudah dilakukan untuk `reasoning`). Menambah dua variabel itu ke config produksi adalah permintaan terpisah, hanya kalau hasil plan ini bagus (bagian 7).

## 3. Perubahan runner yang dibutuhkan (belum dikerjakan)

Runner `tools/run-llm-plan.mjs` sekarang hardcode `{ reasoning: { enabled: false } }` (baris 35). Perlu dua perubahan kecil, di `ai/testing/tools/` saja (bukan `ai/src`):

1. Opsi baru `--reasoning-field <nama>` (default `reasoning`). Bentuk body per nama field:
   - `reasoning` → `{"reasoning": {"enabled": false}}` (perilaku lama, tidak berubah)
   - `thinking` → `{"thinking": {"type": "disabled"}}`
2. Laporan (`report.md`, `llm-response.md`) menyebut field yang dipakai, bukan teks tetap `reasoning: {enabled: false}`.

Nama file runner tidak boleh berakhiran `-test.mjs`, `.test.mjs`, atau berawalan `test-` (aturan lama `node --test`). Kalau Imelda lebih suka runner tidak diubah, alternatif: skrip kecil terpisah. Rekomendasi: ubah runner, diff-nya kecil dan bisa direview.

## 4. Langkah (setelah Imelda menyetujui plan ini)

1. **Baca plan ini dan `PLAN-llm-test.md` penuh.** Cek `ai/.env` hanya untuk panjang `LLM_API_KEY`, catat branch dan commit.
2. **Terapkan perubahan runner bagian 3.** Tampilkan diff ke Imelda sebelum lanjut.
3. **Tahap A: smoke test murah (3 panggilan).** Satu run kode asli, satu diagnosa, satu stream:
   ```bash
   node ai/testing/tools/run-llm-plan.mjs "<LINK>" --reasoning off --reasoning-field thinking --runs 1 --diag 1 --stream 1 --note "smoke thinking disabled"
   ```
   Baca hasilnya. **Berhenti dan lapor** kalau token reasoning tetap > 0 atau stream masih menampilkan potongan reasoning. Itu berarti field tidak dihormati; tidak ada gunanya 16 panggilan penuh.
4. **Tahap B: run penuh (16 panggilan)** hanya kalau tahap A menunjukkan token reasoning turun jauh (kriteria bagian 5) dan Imelda menyetujui:
   ```bash
   node ai/testing/tools/run-llm-plan.mjs "<LINK>" --reasoning off --reasoning-field thinking --note "thinking disabled"
   ```
   Satu kali saja. Jangan ulang "supaya yakin".
5. **Isi bagian "4. Analisis"** di `report.md`, bandingkan dengan testing 14 dan 15 (tabel di bagian 6).
6. **Balas Imelda** dengan ringkasan dan langkah berikutnya; jangan jalankan lanjutannya sendiri.

## 5. Kriteria baca hasil

| Pengamatan | Artinya |
|---|---|
| Token reasoning ≈ 0 (atau kolom `-`) dan stream tanpa potongan reasoning | Field dihormati |
| Waktu selesai turun jauh (target: median < 3 s, timeout ≤ 1 dari 10) | Layak dibawa ke produksi |
| Token reasoning masih 150–600 dan reasoning 90–100% di stream | Field diabaikan, sama seperti `reasoning`; hentikan jalur ini |
| Verdict berubah (mis. `reasonable:true` pada halaman DHL) | Mematikan thinking menurunkan kualitas; catat jumlahnya, jangan dibulatkan |
| `bad_schema` meningkat atau `http_error` 400 | Proxy menolak field baru; lapor pesan apa adanya |

Satu sesi dan n kecil: kalau hasil campuran, tulis "belum cukup untuk menyimpulkan".

## 6. Baseline untuk perbandingan (link DHL yang sama)

| Testing | Setelan | Hasil |
|---|---|---|
| `14-testing-19.19` | `deepseek-v4-flash`, reasoning bawaan | 4 flagged, 6 timeout; median selesai 4,09 s; non-stream 4,79–7,13 s; reasoning 97–100% |
| `15-testing-19.54` | `deepseek-v4-flash`, `reasoning: {enabled: false}` | 4 flagged, 6 timeout; median 4,96 s; non-stream 5,40–8,69 s; token reasoning 176–634 (diabaikan) |
| `11-testing-18.54` + `rerun-19.46` | `glm-5.3-flash`, reasoning bawaan | 6 flagged, 3 timeout (kedua sesi); median 3,4–3,6 s; satu `bad_schema` karena `"email"` di `asks` |

## 7. Setelah plan ini (bukan bagian dari plan)

Hanya kalau tahap B bagus dan Imelda minta: perubahan produksi terpisah dengan catatan di `ai/testing/changes/<tanggal>/NN-changes-HH.MM/`:
- `LLM_REASONING=off` dan `LLM_REASONING_FIELD=thinking` di `readConfig` dan `.env.example`;
- `provider.js` menambahkan `{ [field]: <bentuk sesuai nama field> }` ke body hanya bila `LLM_REASONING=off`;
- tes otomatis untuk bentuk body.
`ai/` dimiliki Lead sekarang; perubahan config dan kontrak lewat issue sesuai aturan 7 kalau menyentuh `contracts/`.

## 8. Aturan keselamatan

Sama dengan `PLAN-llm-test.md` bagian 5: link tidak dibuka di browser, selalu defanged, API key tidak pernah ditampilkan atau ditulis, tidak mengubah `ai/src` / `ai/prompts` / `detector/` / `ai/.env` selama plan, tidak ada commit/push/issue/PR, satu run runner per tahap per permintaan (biaya).
