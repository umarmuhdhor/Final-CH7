# Testing 12: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 18.59 · folder `26-oct-2026/12-testing-18.59` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
> Penguji: Imelda (dijalankan bersama Claude lewat `PLAN-llm-test.md`, runner `tools/run-llm-plan.mjs`)
> Link yang diuji dan isi snapshot: lihat `link.md` · request/respons mentah: `llm-response.md` · data mentah: `raw/`
> Bagian "Analisis" di bawah ditulis setelah data dibaca; angka di tabel dihasilkan otomatis oleh runner.

## 1. Setelan

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://bantuannbansos2026[.]blogspot[.]com/` |
| Penyedia / model | `bandelbanget.xyz` / `glm-5.3-flash` |
| Prompt | `reality-check.v3` |
| Reasoning | bawaan (tidak ada parameter `reasoning` yang dikirim, sama seperti kode produksi) |
| `temperature` / `max_tokens` / `response_format` | 0 / 200 / `json_object` |
| Batas waktu layer 4 | 6000 ms (`MAX_TIMEOUT_MS`); server `/analyze` 6.500 ms; extension 8.000 ms |
| `LLM_DAILY_CAP` | 5000 |
| Jumlah panggilan | 10 lewat kode asli, 3 diagnosa non-stream, 3 stream |
| RDAP | dimatikan (domain scam tidak dikirim ke registry) |
| Mesin | Apple M5, Node v26.8.1, darwin/arm64 |
| Catatan | model glm-5.3-flash via env LLM_MODEL (bukan .env) |

## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | 1,33 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 111,3 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | 2,75 s / 3,77 s / 4,59 s / 3,70 s (n = 6 dari 10) |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | 3,19 s / 3,84 s / 4,50 s / 3,84 s (n = 2) |
| 4 (LLM), streaming: porsi waktu di fase reasoning | 82–100% |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | tidak ada |
| Sinyal layer 3 | asks_otp (25), asks_password (15) |
| Skor layer 3 | 40 |
| Lolos gerbang LLM | ya |
| Hasil 10 run layer 4 | timeout: 4, flagged: 6 |
| Timeout (batas 6 s) | 4 dari 10 (40%) |
| Skor akhir (min / maks) | 40 / 70 (ambang peringatan 30) |
| Skor ≥ 30 | 10 dari 10 run |

## 4. Analisis (diisi Claude setelah membaca data)

**Terdeteksi.** Layer 1–2 tidak memberi sinyal (blocklist layer 1 tidak ikut dan domain `blogspot.com` memang domain umum). Layer 3 menangkap `asks_otp` (25) dan `asks_password` (15) dari field `otp` dan `pw`, skor 40, sudah di atas ambang peringatan 30 tanpa LLM. Lolos gerbang LLM. Pada 6 dari 10 run, LLM menambah `unreasonable_request` (30) sehingga skor akhir 70 (tinggi, ambang 50, belum sampai blokir 80). Pada 4 run yang timeout, skor tetap 40 dari layer 3 saja, jadi peringatan tetap muncul (10 dari 10 run ≥ 30).

**Konsistensi jawaban LLM.** Hasil: 6 flagged, 0 reasonable, 4 timeout. Semua jawaban yang selesai `reasonable:false`, `page_type:"other"`, `evidence:"CEK STATUS PENDAFTARAN"`, confidence 0,72–0,85. Arah keputusan konsisten, tetapi isi `asks` bergeser antar-run: run 6 dan 7 tidak mencantumkan `otp` padahal rule `asks_otp` sudah menyala, run 2 dan 7 menambah `"other"`. Karena skor hanya memakai `reasonable:false`, perbedaan ini tidak mengubah skor akhir, tetapi `asks` tidak bisa dipakai sebagai sumber kebenaran.

**Yang lolos / kurang.** `page_type` selalu `other`, tidak pernah `government` atau `prize`, padahal domainnya berpola bansos dan teks halaman berisi "Menghubungi server Telegram". `brands` kosong, dan teks halaman tidak ikut dikirim ke LLM (hanya title, field, brands, rules). Jadi LLM menilai dari "blog meminta password untuk cek status" saja. Ini pengamatan dari input; belum diuji apakah menambah teks mengubah hasil.

**Waktu.** Run kode asli yang selesai: 2,75–4,59 s (median 3,77 s). Timeout 4 dari 10 (40%), batas 6 s. Diagnosa tanpa batas: 4,50 s dan 3,19 s, sedangkan panggilan ketiga tidak selesai sampai 90 s (aborted), jadi ada ekor latensi panjang di penyedia; produksi tidak terdampak karena dipotong 6 s, tetapi itu menjelaskan timeout. Streaming: 82–100% waktu ada di fase reasoning (byte pertama sudah reasoning), jawaban sebenarnya hanya 8–10 potongan. `max_tokens: 200` tidak dihormati: completion 1214–1348 token walau reasoning hanya 152–281 token (selisih ±1000 token belum saya jelaskan; proxy tidak merinci). Yang bisa dikatakan: waktu tertinggi bukan di penulisan JSON.

**Dibanding baseline (bagian 6).** Baseline 03/04 memakai `deepseek-v4-flash`, prompt v2, sampel `helpnets[.]info`: 5 timeout / 4 wajar / 1 flagged, selesai 3,5–5,7 s (median 4,4 s). Sekarang `glm-5.3-flash`, prompt v3, sampel berbeda: 4 timeout / 0 wajar / 6 flagged, selesai 2,75–4,59 s (median 3,77 s). Angka timeout mirip, dan waktu selesai tampak sedikit lebih cepat. Tetapi model, prompt, sampel, dan jam semuanya berbeda, jadi ini **bukan perbandingan model yang adil**. Lebih banyak flagged hanya berarti sampel ini lebih jelas scam bagi prompt v3.

**Belum bisa disimpulkan.** (1) Apakah glm lebih cepat dari deepseek: satu sampel, n = 6 run selesai, dan ada satu panggilan 90 s. (2) Apakah glm akurat pada halaman yang sah (tidak ada sampel negatif di run ini; tidak ada data false positive). (3) Penyebab selisih ±1000 token completion. (4) Efek menambahkan teks halaman ke input.

**Rekomendasi (tidak dijalankan).** Untuk perbandingan model yang benar: jalankan sampel yang sama di kedua model dengan `--models glm-5.3-flash,deepseek-v4-flash`, dan tambah satu sampel halaman sah (mis. form login bank resmi) untuk mengukur false positive. Timeout 40% tetap risiko; keputusan menaikkan `MAX_TIMEOUT_MS` atau tidak butuh pertimbangan tersendiri karena server (6,5 s) dan extension (8 s) ikut terikat.

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
