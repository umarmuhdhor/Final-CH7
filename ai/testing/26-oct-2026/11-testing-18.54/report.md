# Testing 11: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 18.54 · folder `26-oct-2026/11-testing-18.54` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
> Penguji: Imelda (dijalankan bersama Claude lewat `PLAN-llm-test.md`, runner `tools/run-llm-plan.mjs`)
> Link yang diuji dan isi snapshot: lihat `link.md` · request/respons mentah: `llm-response.md` · data mentah: `raw/`
> Bagian "Analisis" di bawah ditulis setelah data dibaca; angka di tabel dihasilkan otomatis oleh runner.

## 1. Setelan

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://d33wubrfki0l68[.]cloudfront[.]net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123[.]html` |
| Penyedia / model | `bandelbanget.xyz` / `glm-5.3-flash` |
| Prompt | `reality-check.v3` |
| Reasoning | bawaan (tidak ada parameter `reasoning` yang dikirim, sama seperti kode produksi) |
| `temperature` / `max_tokens` / `response_format` | 0 / 200 / `json_object` |
| Batas waktu layer 4 | 6000 ms (`MAX_TIMEOUT_MS`); server `/analyze` 6.500 ms; extension 8.000 ms |
| `LLM_DAILY_CAP` | 5000 |
| Jumlah panggilan | 10 lewat kode asli, 3 diagnosa non-stream, 3 stream |
| RDAP | dimatikan (domain scam tidak dikirim ke registry) |
| Mesin | Apple M5, Node v26.8.1, darwin/arm64 |
| Catatan | model glm-5.3-flash via env override (ai/.env tidak diubah); ulang testing 10 yang salah ketik gim |

## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | 1,06 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 16,6 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | 1,74 s / 3,60 s / 4,95 s / 3,29 s (n = 7 dari 10) |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | 2,33 s / 3,21 s / 5,50 s / 3,68 s (n = 3) |
| 4 (LLM), streaming: porsi waktu di fase reasoning | 95–100% |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | tidak ada |
| Sinyal layer 3 | asks_password (15) |
| Skor layer 3 | 15 |
| Lolos gerbang LLM | ya |
| Hasil 10 run layer 4 | reasonable: 1, flagged: 6, timeout: 3 |
| Timeout (batas 6 s) | 3 dari 10 (30%) |
| Skor akhir (min / maks) | 15 / 45 (ambang peringatan 30) |
| Skor ≥ 30 | 6 dari 10 run |

## 4. Analisis (diisi Claude setelah membaca data)

**Konteks.** Ulangan testing 10 yang salah ketik (`gim-5.3-flash` tidak ada di daftar `/v1/models` proxy, jatuh ke `auto`). Di sini respons memantulkan `glm-5.3-flash`, yang memang terdaftar, jadi modelnya sesuai permintaan.

**Terdeteksi / lolos.** Layer 1–2 nol sinyal; layer 3 hanya `asks_password` (15), di bawah ambang 30. Layer 4 menaikkan ke 45 pada 6 dari 10 run (`reasonable: false`, courier, evidence "DHL EXpress"). `brands` kosong, jadi hanya LLM yang mengaitkan halaman dengan DHL. Tanpa layer 4 halaman lolos.

**Konsistensi.** 6 flagged, **1 reasonable**, 3 timeout. Run 1 menjawab `reasonable: true` (confidence 0,45), jadi satu halaman phishing dinilai wajar; skornya tetap 15. Prompt memang menyuruh "ragu → reasonable: true", dan confidence-nya rendah, tetapi tetap hasil yang lolos. Confidence yang flagged 0,70–0,85; `asks` hampir selalu `["password"]` (satu run + `personal_data`). Efektif, skor ≥ 30 hanya 6/10.

**Waktu.** Run yang selesai 1,74–4,95 s (median 3,60 s, n = 7); non-stream tanpa batas 2,33–5,50 s; stream selesai 2,9 / 6,1 / 9,4 s dengan 95–100% waktu di fase reasoning. 3 timeout (30%) tetap terjadi pada batas 6 s; latensi penyedia bervariasi besar (stream#3 9,4 s).

**Perbandingan dengan testing 10 (`auto`).** Halaman, prompt (v3), dan penyedia sama; model di testing 10 tidak diketahui. Timeout sama (3/10); median selesai 3,60 s vs 4,87 s (glm lebih cepat pada sampel ini); `prompt_tokens` 1.843 vs 18.569, jadi lonjakan 18 ribu token di testing 10 berasal dari sisi proxy/routing `auto`, bukan dari kode kita (data ini mendukung itu, belum dibuktikan sebab pastinya). glm menghasilkan satu `reasonable: true` yang tidak muncul di testing 10 (7/7 flagged). Dengan n = 10 per sisi, tidak cukup untuk menyimpulkan model mana yang lebih akurat.

**Rekomendasi (di luar plan ini).** (a) Ulangi di beberapa halaman scam dan sah sebelum memilih model. (b) Pertimbangkan DHL di `brands.json` supaya layer 3 tidak bergantung pada LLM (run 1 dan run timeout lolos tanpa peringatan). (c) Batas 6 s tetap mepet untuk model reasoning; butuh data lebih banyak sebelum diubah.

**Belum terbukti.** Akurasi pada halaman lain dan false positive; stabilitas latensi di jam lain; perilaku di Cloudflare Worker; layer 1 untuk domain ini.

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
