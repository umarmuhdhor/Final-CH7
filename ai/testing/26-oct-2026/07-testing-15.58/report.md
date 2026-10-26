# Testing 07: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 15.58 · folder `26-oct-2026/07-testing-15.58` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
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
| 1–2 (detector, disimulasikan) | 0,88 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 15,2 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | 0,04 s / 0,05 s / 3,58 s / 0,68 s (n = 10 dari 10) |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | 0,04 s / 0,05 s / 0,11 s / 0,07 s (n = 3) |
| 4 (LLM), streaming: porsi waktu di fase reasoning | - |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | tidak ada |
| Sinyal layer 3 | asks_password (15) |
| Skor layer 3 | 15 |
| Lolos gerbang LLM | ya |
| Hasil 10 run layer 4 | flagged: 2, bad_schema: 8 |
| Timeout (batas 6 s) | 0 dari 10 (0%) |
| Skor akhir (min / maks) | 15 / 45 (ambang peringatan 30) |
| Skor ≥ 30 | 2 dari 10 run |

## 4. Analisis (diisi Claude setelah membaca data)

**Kesimpulan utama: hanya 2 dari 16 panggilan LLM yang benar-benar dijawab model. Sisanya (8 dari 10 run kode asli, 3 diagnosa, 3 stream) dijawab oleh proxy penyedia dengan teks galat, bukan oleh model.** Karena itu angka waktu di bagian 2 (median 0,05 s) bukan kecepatan LLM; itu kecepatan halaman galat.

**Apa yang terdeteksi dan lolos**
- Halaman DHL palsu: judul "DHL EXpress", teks cuma 87 karakter, satu form email + password. Layer 1–2 tidak memberi sinyal. Layer 3 hanya memberi `asks_password` (15). `brands` kosong, jadi aturan sidik jari merek tidak menyala: domain `cloudfront.net` dan tidak ada logo/teks merek yang cocok selain judul.
- Skor layer 3 saja = 15, di bawah ambang peringatan 30. **Tanpa LLM halaman ini lolos.** Hanya jawaban LLM (`page_type: courier`, `reasonable: false`, confidence 0,90 dan 0,92, evidence "DHL EXpress") yang menaikkan skor ke 45 lewat `unreasonable_request:30`.
- Kedua jawaban yang valid sama isinya (courier, password, tidak wajar), selisih confidence 0,02. Dua sampel terlalu sedikit untuk menilai konsistensi model.

**Hitungan 10 run kode asli:** flagged 2, wajar 0, timeout 0, `bad_schema` 8. `bad_schema` di sini bukan model yang melanggar format, melainkan `content` berisi teks "AI provider temporarily unavailable ... Request ID ..." dengan `finish: stop`, `usage` 1000/1000/1000 (angka tetap, bukan token sungguhan), dan `provider` disensor. Ini galat yang dibungkus HTTP 200 oleh proxy `bandelbanget.xyz`. Teks itu juga menyebut permintaan tetap ditagih minimum 1.000 token, jadi 14 panggilan gagal tetap memakan kuota.

**Kenapa waktunya begitu**
- 2 run sukses: 2,73 s dan 3,58 s, token reasoning 125 dan 182 dari completion 1181 dan 1238. Angka completion (±1200) tidak sebanding dengan jawaban JSON ±100 karakter; penyebabnya tidak bisa dipastikan dari data.
- Tabel streaming kosong (porsi reasoning "-") karena ketiga stream mendapat halaman galat. **Pertanyaan "berapa persen waktu habis di reasoning" tidak terjawab di testing ini.** Angka 94–96% dari testing 04 tidak boleh dipakai untuk halaman ini tanpa uji ulang.
- Diagnosa tanpa batas juga tidak informatif (0,04–0,11 s, semua galat).

**Perbandingan dengan baseline (bagian 6 plan)**
- Testing 03/04 (`helpnets[.]info`): 5 timeout, 4 wajar, 1 flagged, selesai 3,5–5,7 s. Sekarang 0 timeout tapi 8 galat penyedia, jadi bukan perbaikan: masalah berpindah dari "lambat" ke "gagal cepat".
- Dua run sukses (2,7–3,6 s) lebih cepat daripada baseline (3,5–5,7 s), tapi n = 2, beda link, dan beda prompt (v3 sekarang, v2 dulu), jadi tidak bisa dibandingkan secara adil.
- Saat galat, layer 4 berperilaku benar: skor jatuh ke 15 tanpa crash dan tanpa menunggu 6 s. Tapi artinya **di sini 80% run berakhir dengan halaman scam lolos (skor 15 < 30).**

**Yang tidak bisa disimpulkan**
- Laju galat proxy yang sebenarnya. Run 1–2 sukses, run 3–10 gagal beruntun dalam <0,2 s; pola ini mirip pembatasan laju atau penjaga kuota, bukan gangguan acak, tapi belum terbukti.
- Waktu layer 4 yang realistis, dan porsi reasoning.

**Rekomendasi (belum dijalankan, butuh permintaan terpisah)**
1. Tunggu beberapa menit lalu jalankan ulang plan yang sama satu kali (bisa dengan `pakai snapshot` agar halaman tidak diambil lagi). Jangan ulang sekarang: galat tetap ditagih.
2. Cek saldo, kuota, dan batas laju di dashboard `bandelbanget.xyz` sebelum run berikutnya.
3. Di `ai/src` pertimbangkan status terpisah `provider_error` untuk balasan galat penyedia, supaya tidak tercampur dengan `bad_schema` (model salah format). Ini perubahan kode, di luar plan ini.
4. Catatan runner: baris "run yang selesai ... n = 10 dari 10" menghitung run galat sebagai selesai, sehingga min/median menyesatkan. Perlu dipisah.

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
