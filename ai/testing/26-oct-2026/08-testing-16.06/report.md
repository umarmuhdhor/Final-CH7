# Testing 08: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 16.06 · folder `26-oct-2026/08-testing-16.06` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
> Penguji: Imelda (dijalankan bersama Claude lewat `PLAN-llm-test.md`, runner `tools/run-llm-plan.mjs`)
> Link yang diuji dan isi snapshot: lihat `link.md` · request/respons mentah: `llm-response.md` · data mentah: `raw/`
> Bagian "Analisis" di bawah ditulis setelah data dibaca; angka di tabel dihasilkan otomatis oleh runner.

## 1. Setelan

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://bantuannbansos2026[.]blogspot[.]com/` |
| Penyedia / model | `bandelbanget.xyz` / `deepseek-v4-flash` |
| Prompt | `reality-check.v3` |
| Reasoning | bawaan (tidak ada parameter `reasoning` yang dikirim, sama seperti kode produksi) |
| `temperature` / `max_tokens` / `response_format` | 0 / 200 / `json_object` |
| Batas waktu layer 4 | 6000 ms (`MAX_TIMEOUT_MS`); server `/analyze` 6.500 ms; extension 8.000 ms |
| `LLM_DAILY_CAP` | 5000 |
| Jumlah panggilan | 10 lewat kode asli, 3 diagnosa non-stream, 3 stream |
| RDAP | dimatikan (domain scam tidak dikirim ke registry) |
| Mesin | Apple M5, Node v26.8.1, darwin/arm64 |
| Catatan | - |

## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | 1,35 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 94,2 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | 2,22 s / 3,01 s / 4,76 s / 3,29 s (n = 8 dari 10) |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | 4,51 s / 7,25 s / 8,41 s / 6,72 s (n = 3) |
| 4 (LLM), streaming: porsi waktu di fase reasoning | 86–97% |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | tidak ada |
| Sinyal layer 3 | asks_otp (25), asks_password (15) |
| Skor layer 3 | 40 |
| Lolos gerbang LLM | ya |
| Hasil 10 run layer 4 | timeout: 2, flagged: 8 |
| Timeout (batas 6 s) | 2 dari 10 (20%) |
| Skor akhir (min / maks) | 40 / 70 (ambang peringatan 30) |
| Skor ≥ 30 | 10 dari 10 run |

## 4. Analisis (diisi Claude setelah membaca data)

### 4.1 Apa yang terdeteksi dan apa yang lolos

- Layer 1–2: tidak ada sinyal. Wajar: `blogspot.com` adalah platform, bukan domain scam, dan tidak ada merek yang ditiru (`brands: []`).
- Layer 3 sudah cukup untuk memperingatkan sendirian: `asks_otp` (25, dari field `otp`) + `asks_password` (15, dari field `pw`) = **40**, di atas ambang peringatan 30. LLM menaikkan skor ke 70 (`unreasonable_request` +30): di atas ambang tinggi 50, di bawah ambang blokir 80.
- Yang lolos: teks halaman ("MOHON TUNGGU SEBENTAR Menghubungi server Telegram...", judul "CEK STATUS PENDAFTARAN" bergaya bantuan sosial) tidak jadi sinyal layer 3. LLM hanya menerima judul + label field, bukan teks halaman, jadi klaim "Telegram" dan konteks bansos tidak sampai ke LLM. Semua run menjawab `page_type: "other"`, bukan `government` atau `prize`; itu konsisten dengan input yang tidak memuat konteks tersebut.
- Pada link ini LLM menambah skor tetapi tidak mengubah keputusan (peringatan sudah tercapai tanpa LLM). Satu link tidak cukup untuk menyimpulkan nilai tambah LLM secara umum.

### 4.2 Konsistensi antar-run

- Lewat kode asli: **8 flagged, 0 reasonable, 2 timeout** (run 1 dan 5). Ke-8 jawaban `reasonable: false`, `confidence` 0,82–0,95, `evidence` selalu "CEK STATUS PENDAFTARAN" (valid, disalin dari judul).
- Isi `asks` berubah-ubah: `otp` ada di 5 dari 8 jawaban (run 3, 6, 8, 9, 10) dan tidak ada di run 2, 4, 7; `personal_data` ada di 6 dari 8. Keputusan `reasonable` konsisten, rinciannya tidak. Kode produksi memakai `reasonable` dan `confidence`, jadi variasi `asks` tidak mengubah skor di tes ini.
- Reasoning di diagnosa#1 menunjukkan model ragu apakah field `tel` kedua adalah OTP, tetapi tetap sampai pada `false`.

### 4.3 Kenapa waktunya sebesar itu

- Run yang selesai lewat kode asli: 2,22–4,76 s (median 3,01 s). Non-stream tanpa batas: 4,51 / 7,25 / 8,41 s; dua dari tiga melewati 6 s, sejalan dengan 2 dari 10 timeout di kode asli.
- Streaming: byte pertama 0,83–1,16 s, lalu **86–97% waktu di fase reasoning** (3,61–10,42 s) sebelum jawaban mulai; jawaban sendiri 0,2–0,6 s. Variasi waktu berasal dari panjang reasoning, bukan jaringan atau ukuran jawaban.
- `max_tokens: 200` diabaikan proxy lagi: `completion_tokens` 1195–1504. `reasoning_tokens` yang dilaporkan (131–439) jauh di bawah `completion_tokens`, jadi hitungan token reasoning dari proxy kemungkinan tidak lengkap; yang bisa dipercaya hanya garis waktu streaming. Ini pengamatan, belum diselidiki.
- Run yang timeout tidak punya data token (dibatalkan di 6 s). Bahwa reasoning-nya lebih panjang adalah dugaan yang konsisten dengan tabel stream, bukan bukti.

### 4.4 Perbandingan dengan baseline (bagian 6 plan)

| Hal | `03-testing-10.25` (helpnets[.]info, prompt v2) | Testing ini (blogspot, prompt v3) |
|---|---|---|
| Timeout / 10 | 5 | 2 |
| Selesai (min–maks) | 3,5–5,7 s (median 4,4 s) | 2,2–4,8 s (median 3,0 s) |
| Run flagged | 1 dari 10 | 8 dari 10 |
| Skor | 15 (45 pada flagged) | 40 (70 pada flagged) |

Perbedaan setelan: link dan snapshot lain, prompt v2 → v3 (ada `brands`), layer 3 sudah punya aturan sidik jari. Waktu lebih cepat dan timeout lebih sedikit, tetapi n = 10, satu jam, satu link, beban penyedia berubah-ubah: **perbaikan ini tidak bisa dikaitkan ke prompt v3**. Lonjakan flagged (1 → 8) wajar karena halaman ini memang meminta OTP dan password; itu bukan bukti kualitas prompt.

### 4.5 Rekomendasi dan yang belum terbukti

1. Layer 3 sudah memicu peringatan (40) tanpa LLM, dan itu bertahan saat 2 dari 10 panggilan timeout. Dari data ini tidak ada perubahan kode yang mendesak.
2. Usulan (belum diuji): masukkan petunjuk dari `text` halaman (mis. "Telegram", "bantuan") ke input LLM atau aturan layer 3 supaya `page_type` bisa `government`/`prize`. Perubahan kode = permintaan terpisah (aturan 4 plan).
3. Timeout ~20% pada batas 6 s masih ada; reasoning tidak bisa dibatasi dari sisi kita (`max_tokens` diabaikan). `dengan reasoning off` dan `bandingkan model ...` belum dijalankan, jadi belum ada data untuk memilih.
4. Belum terbukti: (a) tingkat timeout sebenarnya (n = 10), (b) nilai tambah LLM pada halaman yang lolos layer 3, (c) perilaku di Cloudflare Worker, (d) pengaruh layer 1 dan RDAP (tidak ikut). `captured-sample.json` belum diperiksa manual (`redacted: false`).

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
