# Testing 14: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 19.19 · folder `26-oct-2026/14-testing-19.19` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
> Penguji: Imelda (dijalankan bersama Claude lewat `PLAN-llm-test.md`, runner `tools/run-llm-plan.mjs`)
> Link yang diuji dan isi snapshot: lihat `link.md` · request/respons mentah: `llm-response.md` · data mentah: `raw/`
> Bagian "Analisis" di bawah ditulis setelah data dibaca; angka di tabel dihasilkan otomatis oleh runner.

## 1. Setelan

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://d33wubrfki0l68[.]cloudfront[.]net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123[.]html` |
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
| 1–2 (detector, disimulasikan) | 1,00 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 15,9 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | 3,49 s / 4,09 s / 5,53 s / 4,30 s (n = 4 dari 10) |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | 4,79 s / 5,31 s / 7,13 s / 5,74 s (n = 3) |
| 4 (LLM), streaming: porsi waktu di fase reasoning | 97–100% |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | tidak ada |
| Sinyal layer 3 | asks_password (15) |
| Skor layer 3 | 15 |
| Lolos gerbang LLM | ya |
| Hasil 10 run layer 4 | timeout: 6, flagged: 4 |
| Timeout (batas 6 s) | 6 dari 10 (60%) |
| Skor akhir (min / maks) | 15 / 45 (ambang peringatan 30) |
| Skor ≥ 30 | 4 dari 10 run |

## 4. Analisis (diisi Claude setelah membaca data)

**Kesimpulan utama: kali ini penyedia menjawab semua panggilan (tidak ada balasan galat seperti testing 07), dan masalahnya berpindah ke waktu. 6 dari 10 run timeout di batas 6 s; ketika selesai, LLM selalu menandai halaman sebagai scam.**

**Apa yang terdeteksi dan lolos**
- Sama dengan testing 07: layer 1–2 tidak ada sinyal, layer 3 hanya `asks_password` (15), `brands` kosong. Skor 15 < ambang 30, jadi tanpa LLM halaman DHL palsu ini lolos.
- 4 run selesai (2, 8, 9, 10): semuanya `page_type: courier`, `reasonable: false`, confidence 0,90–0,95, evidence "DHL EXpress" → skor 45 (flagged). Konsisten 4 dari 4. `asks` bervariasi (password saja di run 8, password + personal_data di run lain), tidak mengubah skor.
- 6 run timeout → skor 15 → **halaman lolos (60% run).** Jadi deteksi tergantung kecepatan penyedia, bukan kemampuan model.

**Hitungan 10 run kode asli:** flagged 4, wajar 0, timeout 6, galat lain 0.

**Kenapa waktunya begitu**
- Non-stream tanpa batas: 4,79 / 5,31 / 7,13 s (median 5,31 s), semua JSON valid. Satu dari tiga sudah melewati 6 s dengan sendirinya.
- Streaming: byte pertama 1,05–2,16 s, lalu 97–100% waktu total dihabiskan di fase reasoning (jawaban baru mulai di 7,3–7,8 s). Jawaban JSON itu sendiri hanya ±100 karakter. stream#1 bahkan sampai 10,17 s tanpa sempat menulis jawaban (386 potongan reasoning, 0 potongan jawaban).
- Token reasoning 153–497 per panggilan; completion 1212–1553 (jauh di atas jawaban ±100 karakter, mirip testing 07, penyebab tidak bisa dipastikan). `max_tokens: 200` tidak membatasi, sama seperti temuan testing 04 (diabaikan proxy).
- Run yang selesai (3,49–5,53 s) hanya sedikit di bawah batas 6 s; dengan sebaran 3,5–7,1 s, timeout 60% wajar. Batas 6 s berada di tengah sebaran waktu, bukan di ekor.

**Perbandingan**
- Testing 07 (jam 15.58, link sama): 2 sukses, 8 galat penyedia, 0 timeout. Tidak sebanding untuk waktu karena 8 run itu bukan jawaban model. Testing ini adalah data waktu nyata pertama untuk link DHL.
- Baseline 03/04 (`helpnets[.]info`, prompt v2): 5 timeout, 4 wajar, 1 flagged, selesai 3,5–5,7 s; reasoning 94–96%. Sekarang 6 timeout, 0 wajar, 4 flagged; selesai 3,5–5,5 s; reasoning 97–100%. Pola sama: model reasoning terlalu lambat untuk batas 6 s di penyedia ini. Beda link dan prompt (v3 vs v2), jadi perbandingan hanya indikatif.
- Run 1–2 di testing 07 (2,7–3,6 s) lebih cepat daripada testing ini; kecepatan penyedia berubah menurut beban/jam.

**Yang tidak bisa disimpulkan**
- Apakah timeout 60% stabil: satu sesi, satu link, n = 10.
- Apakah model lain/penyedia lain atau reasoning off menyelesaikan masalah; tidak diuji di sini.
- Penyebab testing 07 gagal (kuota/batas laju) tidak terulang di sini, jadi dugaan itu tetap tidak terbukti.

**Rekomendasi (belum dijalankan, butuh permintaan terpisah)**
1. Uji `bandingkan model ...` atau `dengan reasoning off` pada link yang sama untuk melihat apakah waktu turun di bawah 6 s tanpa mengubah verdict.
2. Pertimbangkan strategi produksi yang tidak bergantung pada satu jawaban dalam 6 s: mis. timeout lebih longgar untuk halaman yang skor layer 3-nya sudah ≥ 15 (batas total extension 8 s), atau model non-reasoning untuk layer 4.
3. Pisahkan status `provider_error` dari `bad_schema` di `ai/src` (temuan testing 07).

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
