# PLAN: bandingkan 3 model DeepSeek, thinking default vs thinking off

> Dibuat 26 Okt 2026. Turunan dari `PLAN-llm-test.md` (aturan keselamatan bagian 5 di sana tetap berlaku). Runner: `ai/testing/tools/run-model-compare.mjs`. Dijalankan tanpa pengawasan saat Imelda tidur; hasil ada di **satu folder**.

## 1. Pertanyaan

1. Dari tiga model di `bandelbanget.xyz` (`deepseek-v4-flash`, `deepseek-v4.1-flash`, `deepseek-v4-flash-0731`), mana yang paling sering selesai di bawah batas 6 s dan tetap menandai halaman scam?
2. Untuk tiap model: apakah thinking bisa dimatikan, dan kalau bisa, apa efeknya pada waktu, timeout, dan kualitas jawaban (`bad_schema`, verdict)?

Hasil lama: `reasoning: {enabled: false}` diabaikan proxy (testing 15). Jadi cara mematikan thinking harus diselidiki dulu, bukan diasumsikan.

## 2. Desain

| Item | Nilai |
|---|---|
| Model | `deepseek-v4-flash`, `deepseek-v4.1-flash`, `deepseek-v4-flash-0731` |
| Mode | **default** (tanpa field tambahan = produksi) dan **thinking off** (field hasil probe) |
| Sampel | 3 snapshot scam yang sudah tersimpan (tidak ada fetch baru): DHL cloudfront (`07-testing-15.58`), blogspot bansos (`08-testing-16.06`), klikbca (`09-testing-16.24`). Semua scam, jadi flagged = benar |
| Prompt dan parameter | persis produksi: prompt versi terbaru, `temperature` 0, `max_tokens` 200, `json_object` |
| Jalur | kode asli `createRealityCheck` (batas 6 s) + panggilan non-stream tanpa batas (untuk waktu sebenarnya dan token reasoning) |
| Jumlah | 10 putaran × 3 sampel × 6 konfigurasi = 180 panggilan kode asli, + 2 diagnosa × 3 sampel × 6 = 36, + probe ±18. Total ±235 panggilan, ±30 menit |
| Urutan | round-robin (putaran → sampel → konfigurasi) supaya beban penyedia merata, bukan satu konfigurasi dulu baru yang lain |

### Tahap A: probe cara mematikan thinking (per model)

Satu sampel, panggilan non-stream tanpa batas. Coba berurutan sampai satu menghilangkan reasoning (token reasoning 0 dan tidak ada `reasoning_content`):

1. `thinking: {type: "disabled"}`
2. `reasoning: {enabled: false}`
3. `reasoning_effort: "none"`
4. `chat_template_kwargs: {thinking: false}`
5. `enable_thinking: false`

"Efektif" hanya berarti thinking hilang. Validitas jawaban dicatat terpisah dan diukur di tahap B (mematikan thinking boleh merusak format JSON; itu temuan, bukan kegagalan probe). Kalau tidak ada yang efektif, baris "thinking off" model itu = default dan diberi tanda.

### Tahap B: matriks utama

Per konfigurasi dicatat: hasil layer 4 (`flagged` / `reasonable` / `timeout` / `bad_schema` / `http_error`), waktu, token reasoning, skor akhir (ambang peringatan 30), jawaban mentah.

## 3. Cara membaca hasil

| Pengamatan | Artinya |
|---|---|
| Timeout turun, flagged tetap | Thinking off layak dibawa ke produksi untuk model itu |
| Timeout turun tetapi `bad_schema` naik | Thinking off merusak format; jangan pakai tanpa memperbaiki prompt |
| Token reasoning masih > 0 di semua field | Proxy tidak mendukung mematikan thinking untuk model itu |
| Flagged turun (`reasonable` naik) | Kualitas turun; hitung berapa |
| Selisih 1–2 run | Belum cukup untuk menyimpulkan (n kecil, satu malam) |

## 4. Keluaran (satu folder)

`ai/testing/<tanggal>/<NN>-testing-<HH.MM>/`

| File | Isi |
|---|---|
| `conclusions.html` | Visualisasi kesimpulan: grafik batang (skor ≥ 30, timeout, waktu selesai, waktu non-stream, token reasoning), peta hasil per run, tabel ringkas, kesimpulan otomatis |
| `report.md` | Setelan, hasil probe, tabel per konfigurasi dan per sampel, kesimpulan otomatis; bagian 6 "Analisis" diisi Claude sesudah Imelda bangun |
| `llm-response.md` | Request contoh, jawaban tiap run yang selesai, system prompt |
| `results.json` | Data mentah semua run dan probe |

## 5. Cara menjalankan

```bash
caffeinate -i node ai/testing/tools/run-model-compare.mjs --runs 10 --diag 2 --note "model compare malam"
```

Opsi: `--models a,b,c`, `--samples p1.json,p2.json`, `--max-samples N`, `--out-root dir`. Runner berhenti sendiri bila 20 `http_error` berturut-turut (key/saldo/proxy bermasalah) dan tetap menulis hasil parsial. Satu kali jalan; jangan ulang "supaya yakin" (biaya).

## 6. Aturan keselamatan

Tidak ada fetch halaman scam (hanya snapshot tersimpan); link selalu defanged; API key tidak ditampilkan dan semua file keluaran dipindai terhadap key; tidak ada perubahan di `ai/src`, `ai/prompts`, `detector/`, `ai/.env`; tidak ada commit, push, issue, PR. Sampel `redacted: false`: jangan masuk eval set sebelum diperiksa.

## 7. Batasan

Satu penyedia, satu mesin, satu malam; n = 10 per sampel per konfigurasi; waktu penyedia berubah menurut beban; layer 1 dan RDAP tidak ikut. Hasil probe smoke 26 Okt malam (1 sampel): `chat_template_kwargs: {thinking: false}` menghilangkan reasoning di ketiga model, tetapi jawaban dua model (`deepseek-v4-flash`, `-0731`) tidak lolos skema pada satu panggilan itu; belum bisa disimpulkan dari n = 1.
