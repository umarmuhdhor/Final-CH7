# Testing 15: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 19.46 · folder `26-oct-2026/15-testing-19.46` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
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
| Catatan | ulang testing 11: glm-5.3-flash via env override (ai/.env tidak diubah) |

## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | 0,81 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 14,9 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | 2,29 s / 3,40 s / 5,40 s / 3,64 s (n = 7 dari 10) |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | 4,26 s / 4,39 s / 5,49 s / 4,71 s (n = 3) |
| 4 (LLM), streaming: porsi waktu di fase reasoning | 82–96% |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | tidak ada |
| Sinyal layer 3 | asks_password (15) |
| Skor layer 3 | 15 |
| Lolos gerbang LLM | ya |
| Hasil 10 run layer 4 | timeout: 3, flagged: 6, bad_schema: 1 |
| Timeout (batas 6 s) | 3 dari 10 (30%) |
| Skor akhir (min / maks) | 15 / 45 (ambang peringatan 30) |
| Skor ≥ 30 | 6 dari 10 run |

## 4. Analisis (diisi Claude setelah membaca data)

Ulangan testing 11 (`11-testing-18.54`) dengan setelan sama: `glm-5.3-flash` lewat env override, `ai/.env` tidak diubah. Analisis lengkap dan tabel perbandingan ada di `../compare.md`; ringkasnya:

- Layer 3 hanya `asks_password` (15), `brands` kosong; tanpa LLM halaman lolos. 6 dari 10 run flagged (skor 45), 3 timeout (30%), 1 `bad_schema`. 4 dari 10 run berakhir skor 15 (lolos).
- `bad_schema` run 5 adalah jawaban model yang valid JSON tapi `asks` berisi `"email"`, nilai di luar daftar yang diizinkan. Bukan galat penyedia seperti testing 07.
- Waktu: run selesai 2,29–5,40 s (median 3,40 s); non-stream tanpa batas 4,26–5,49 s; stream 82–96% di fase reasoning; stream#2 22 s adalah pencilan.
- Sebanding dengan testing 11 (6 flagged / 3 timeout di keduanya); selisih satu run tidak bermakna pada n = 10. Belum terbukti: akurasi di halaman lain, stabilitas di jam lain.

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
