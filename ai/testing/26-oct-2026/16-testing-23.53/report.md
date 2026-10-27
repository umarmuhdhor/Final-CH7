# Testing 17: bandingkan model x thinking on/off

> Tanggal: 26 oct 2026, 23.53 · folder `26-oct-2026/16-testing-23.53` · branch `docs/AI-llm-latency-testing` @ `b0e0bca` · plan `PLAN-model-compare.md`, runner `tools/run-model-compare.mjs`
> Visualisasi: `conclusions.html` · data mentah: `results.json` · request/jawaban: `llm-response.md`

## 1. Setelan

| Item | Nilai |
|---|---|
| Penyedia | `bandelbanget.xyz` |
| Model | `deepseek-v4-flash`, `deepseek-v4.1-flash`, `deepseek-v4-flash-0731` |
| Mode | default (tanpa field tambahan, = produksi) vs thinking off (field hasil probe tahap A) |
| Prompt | `reality-check.v3` · `temperature` 0 · `max_tokens` 200 · `json_object` |
| Batas layer 4 | 6000 ms (kode asli `createRealityCheck`) |
| Run | 8 putaran × 3 sampel × 6 konfigurasi, + 2 panggilan tanpa batas waktu per sampel per konfigurasi |
| Sampel (snapshot tersimpan, tidak diambil ulang) | `hxxps://d33wubrfki0l68[.]cloudfront[.]net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123[.]html` (skor layer 3 15), `hxxps://bantuannbansos2026[.]blogspot[.]com/?m=REDACTED` (skor layer 3 40), `hxxps://ibank[.]klikbca[.]com/` (skor layer 3 0) |
| Tidak lolos gerbang LLM (dilewati) | klikbca.com |
| Catatan | - |

## 2. Tahap A: bisakah thinking dimatikan?

| Model | Default: token reasoning | Field yang dicoba (urut) | Hasil | Dipakai untuk "off" |
|---|---|---|---|---|
| `deepseek-v4-flash` | 547 (2418 char) | `thinking:{type:disabled}`, `reasoning:{enabled:false}`, `reasoning_effort:none`, `chat_template_kwargs:{thinking:false}` | reasoning 338, reasoning 938, reasoning 1024, **efektif** (jawaban valid) | `chat_template_kwargs:{thinking:false}` |
| `deepseek-v4.1-flash` | 812 (3621 char) | `thinking:{type:disabled}`, `reasoning:{enabled:false}`, `reasoning_effort:none`, `chat_template_kwargs:{thinking:false}` | reasoning 569, reasoning 1024, reasoning 1024, **efektif** (jawaban valid) | `chat_template_kwargs:{thinking:false}` |
| `deepseek-v4-flash-0731` | 134 (508 char) | `thinking:{type:disabled}`, `reasoning:{enabled:false}`, `reasoning_effort:none`, `chat_template_kwargs:{thinking:false}` | reasoning 1024, reasoning 122, reasoning 418, **efektif** (jawaban valid) | `chat_template_kwargs:{thinking:false}` |

## 3. Hasil per konfigurasi

| Konfigurasi | n | flagged | timeout | bad_schema | http_error | skor ≥ 30 (inflasi layer 3) | selesai: median / p90 | non-stream: median / maks | token reasoning (median) |
|---|---|---|---|---|---|---|---|---|---|
| deepseek-v4-flash · default | 20 | 4 | 16 | 0 | 0 | 12 | 3,83 s / 5,46 s | 12,63 s / 18,86 s | 520.5 |
| deepseek-v4-flash · thinking off | 20 | 8 | 11 | 1 | 0 | 12 | 3,04 s / 4,76 s | 6,28 s / 15,66 s | 0 |
| deepseek-v4.1-flash · default | 20 | 3 | 17 | 0 | 0 | 11 | 3,66 s / 4,14 s | 7,23 s / 53,37 s | 405.5 |
| deepseek-v4.1-flash · thinking off | 20 | 9 | 10 | 0 | 0 | 13 | 2,25 s / 4,92 s | 3,04 s / 5,37 s | 0 |
| deepseek-v4-flash-0731 · default | 20 | 4 | 16 | 0 | 0 | 11 | 4,59 s / 5,33 s | 16,77 s / 18,63 s | 550.5 |
| deepseek-v4-flash-0731 · thinking off | 20 | 5 | 10 | 3 | 0 | 10 | 2,42 s / 3,95 s | 7,12 s / 10,76 s | 0 |

## 4. Per sampel (flagged / timeout dari n)

| Konfigurasi | d33wubrfki0l68.cloudfront.net | bantuannbansos2026.blogspot.com | klikbca.com |
|---|---|---|---|
| deepseek-v4-flash · default | 2 / 8 dari 10 | 2 / 8 dari 10 | - |
| deepseek-v4-flash · thinking off | 2 / 7 dari 10 | 6 / 4 dari 10 | - |
| deepseek-v4.1-flash · default | 1 / 9 dari 10 | 2 / 8 dari 10 | - |
| deepseek-v4.1-flash · thinking off | 3 / 6 dari 10 | 6 / 4 dari 10 | - |
| deepseek-v4-flash-0731 · default | 1 / 9 dari 10 | 3 / 7 dari 10 | - |
| deepseek-v4-flash-0731 · thinking off | 0 / 5 dari 10 | 5 / 5 dari 10 | - |

## 5. Kesimpulan otomatis

- Paling sering menandai scam (flagged = LLM selesai < 6 s dan benar): **deepseek-v4.1-flash · thinking off**, 9/20 run, timeout 10/20, median selesai 2,25 s. Skor akhir ≥ 30 sengaja tidak dipakai: sampel blogspot sudah 40 dari layer 3 tanpa LLM.
- deepseek-v4-flash: thinking bisa dimatikan lewat `chat_template_kwargs:{thinking:false}`. Timeout 16/20 → 11/20; median non-stream 12,63 s → 6,28 s; flagged 4/20 → 8/20.
- deepseek-v4.1-flash: thinking bisa dimatikan lewat `chat_template_kwargs:{thinking:false}`. Timeout 17/20 → 10/20; median non-stream 7,23 s → 3,04 s; flagged 3/20 → 9/20.
- deepseek-v4-flash-0731: thinking bisa dimatikan lewat `chat_template_kwargs:{thinking:false}`. Timeout 16/20 → 10/20; median non-stream 16,77 s → 7,12 s; flagged 4/20 → 5/20.
- Satu sesi, 3 sampel scam (semua seharusnya terdeteksi), n kecil per konfigurasi: selisih satu dua run bukan bukti. Waktu penyedia berubah menurut beban (urutan run di-interleave supaya adil).

## 6. Analisis (ditulis Claude setelah membaca `results.json`)

Catatan data: klikbca tidak lolos gerbang LLM (skor layer 3 = 0), jadi tiap konfigurasi hanya 20 run (10 putaran × 2 sampel: DHL dan blogspot). Kolom "skor ≥ 30" tidak dipakai untuk menilai: blogspot sudah 40 dari layer 3 tanpa LLM. Ukuran yang dipakai adalah `flagged` (LLM selesai dalam 6 s dan benar menandai halaman scam).

**1. Thinking bisa dimatikan, tetapi hanya lewat satu field.** Hanya `chat_template_kwargs: {thinking: false}` yang membuat token reasoning jadi 0 di ketiga model. `thinking: {type: "disabled"}`, `reasoning: {enabled: false}`, dan `reasoning_effort: "none"` diabaikan proxy (token reasoning tetap 122–1.024). `enable_thinking` tidak sempat dicoba karena field ke-4 sudah efektif.

**2. Mematikan thinking mempercepat dan menaikkan jumlah deteksi.**

| Model | flagged default → off | timeout default → off | median selesai (yang tidak timeout) default → off | median non-stream default → off (n = 4) |
|---|---|---|---|---|
| `deepseek-v4-flash` | 4 → 8 dari 20 | 16 → 11 | 3,83 → 3,04 s | 12,63 → 6,28 s |
| `deepseek-v4.1-flash` | 3 → 9 dari 20 | 17 → 10 | 3,66 → 2,25 s | 7,23 → 3,04 s |
| `deepseek-v4-flash-0731` | 4 → 5 dari 20 | 16 → 10 | 4,59 → 2,42 s | 16,77 → 7,12 s |

Di mode default, 80–85% run timeout (batas 6 s): reasoning 300–1.000 token membuat waktu non-stream 7–17 s (satu panggilan `deepseek-v4.1-flash` sampai 53 s). Run default yang selesai (3 sampai 4 per konfigurasi) semuanya benar (`flagged`).

**3. Harga yang dibayar: kualitas jawaban turun, paling parah di `-0731`.** Dari run off yang selesai:

| Model | selesai | benar (flagged) | salah (`reasonable: true`, lolos) | `bad_schema` |
|---|---|---|---|---|
| `deepseek-v4-flash` | 9 | 8 | 0 | 1 |
| `deepseek-v4.1-flash` | 10 | 9 | 1 | 0 |
| `deepseek-v4-flash-0731` | 10 | 5 | 2 | 3 |

Keempat `bad_schema` punya pola sama: `"asks": ["email", "password"]`, padahal skema layer 4 hanya menerima nilai di `ASK_KINDS` dan `"email"` ditolak. Semuanya di sampel DHL. Tanpa thinking, model lebih sering memakai kata "email". Ketiga jawaban `reasonable: true` juga semuanya di DHL (confidence 0,35–0,55). DHL adalah sampel tersulit: skor layer 3 hanya 15 (tepat di gerbang), jadi LLM satu-satunya penentu.

**4. Per sampel (flagged dari 10, default → off).** DHL: `v4-flash` 2 → 2, `v4.1-flash` 1 → 3, `-0731` 1 → 0. Blogspot: 2 → 6, 2 → 6, 3 → 5. Hampir seluruh keuntungan thinking off ada di blogspot; di DHL hasilnya campuran dan `-0731` justru turun.

**5. Timeout tidak hilang walau thinking off.** Mode off masih timeout 10–11 dari 20 (50–55%). Panggilan non-stream tanpa batas waktu di mode off kadang tetap 8–16 s tanpa satu pun token reasoning (mis. `deepseek-v4-flash` 15,7 s, `-0731` 10,8 s di blogspot). Jadi sebagian keterlambatan berasal dari proxy `bandelbanget.xyz` (antrean atau latensi ekor), bukan dari thinking. Jumlah timeout run 1–5 dan 6–10 mirip (mis. v4-flash off 5 vs 6), jadi tidak terlihat tren memburuk sepanjang malam.

**6. Peringkat (dalam batas data ini).**
1. `deepseek-v4.1-flash` + thinking off: flagged 9/20, 1 lolos, 0 skema salah, median selesai 2,25 s. Satu-satunya konfigurasi yang masuk akal untuk batas 6 s.
2. `deepseek-v4-flash` + thinking off: flagged 8/20, 1 skema salah. Dekat dengan nomor 1; selisih 1 run bukan bukti.
3. `deepseek-v4-flash-0731` + thinking off: kecepatan setara (median 2,42 s) tetapi paling tidak andal (5 dari 10 yang selesai gagal atau lolos).
4. Ketiga model default: sama-sama jarang selesai dalam 6 s (3–4 dari 20).

**7. Rekomendasi (bukan perubahan yang sudah dikerjakan).**
- Kalau produksi tetap memakai batas 6 s, mematikan thinking dengan `chat_template_kwargs: {thinking: false}` adalah satu-satunya jalan yang terbukti memangkas waktu. Pasangkan dengan `deepseek-v4.1-flash`.
- Perbaiki penolakan `"email"`: longgarkan parser (buang nilai `asks` yang tidak dikenal alih-alih menolak seluruh jawaban) atau tegaskan di prompt bahwa `email` bukan nilai yang valid. Itu menyelamatkan 4 dari 4 `bad_schema` di data ini. Ini perubahan `ai/src` atau `ai/prompts`, jadi perlu permintaan terpisah dengan catatan di `ai/testing/changes/`.
- Kalau tetap ada ±50% timeout, pertimbangkan batas yang lebih longgar atau hasil layer 3 tetap tampil sendiri, karena penyebab sisanya ada di proxy.

**8. Belum terbukti.**
- Tidak ada halaman **sah** di data ini, jadi belum diketahui apakah thinking off menaikkan false positive. Itu wajib dites sebelum dibawa ke produksi.
- Hanya 2 sampel scam, satu malam, satu mesin. Pola DHL (3 lolos, 4 skema salah) bisa spesifik sampel itu.
- Non-stream tanpa batas hanya n = 4 per konfigurasi; median-nya kasar.
- `enable_thinking: false` tidak dicoba (probe berhenti di field efektif pertama), jadi tidak diketahui apakah field itu juga bekerja.

## 7. Batasan

- Satu penyedia, satu mesin, satu malam. n kecil. Sampel dari snapshot lama (`redacted: false`, jangan masuk eval set sebelum diperiksa).
- "flagged" = layer 4 menandai tidak wajar; semua sampel adalah halaman scam, jadi flagged = benar, reasonable = lolos (salah), timeout = tidak ada hasil.
- Layer 1 (blocklist) dan RDAP tidak ikut.
