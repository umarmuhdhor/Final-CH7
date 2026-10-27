# Testing 15: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 19.54 · folder `26-oct-2026/15-testing-19.54` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
> Penguji: Imelda (dijalankan bersama Claude lewat `PLAN-llm-test.md`, runner `tools/run-llm-plan.mjs`)
> Link yang diuji dan isi snapshot: lihat `link.md` · request/respons mentah: `llm-response.md` · data mentah: `raw/`
> Bagian "Analisis" di bawah ditulis setelah data dibaca; angka di tabel dihasilkan otomatis oleh runner.

## 1. Setelan

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://d33wubrfki0l68[.]cloudfront[.]net/a24ce9fe-3a25-440e-923c-70c96b668dc8/dhl123[.]html` |
| Penyedia / model | `bandelbanget.xyz` / `deepseek-v4-flash` |
| Prompt | `reality-check.v3` |
| Reasoning | **dimatikan** (`reasoning: {enabled: false}` ditambahkan oleh runner; BERBEDA dari kode produksi) |
| `temperature` / `max_tokens` / `response_format` | 0 / 200 / `json_object` |
| Batas waktu layer 4 | 6000 ms (`MAX_TIMEOUT_MS`); server `/analyze` 6.500 ms; extension 8.000 ms |
| `LLM_DAILY_CAP` | 5000 |
| Jumlah panggilan | 10 lewat kode asli, 3 diagnosa non-stream, 3 stream |
| RDAP | dimatikan (domain scam tidak dikirim ke registry) |
| Mesin | Apple M5, Node v26.8.1, darwin/arm64 |
| Catatan | reasoning off (parameter reasoning dikirim; beda dari kode produksi) |

## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | 1,59 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 28,4 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | 2,75 s / 4,96 s / 5,89 s / 4,64 s (n = 4 dari 10) |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | 5,40 s / 6,78 s / 8,69 s / 6,95 s (n = 3) |
| 4 (LLM), streaming: porsi waktu di fase reasoning | 94–100% |

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

**Kesimpulan utama: `reasoning: {enabled: false}` tidak dihormati oleh proxy `bandelbanget.xyz`. Parameter terkirim (terlihat di request di `llm-response.md`), tetapi model tetap berpikir: token reasoning 176–634 per panggilan dan 94–100% waktu stream masih di fase reasoning. Hasilnya tidak lebih cepat; 6 dari 10 run tetap timeout.**

**Terdeteksi / lolos.** Sama dengan testing sebelumnya: layer 3 hanya `asks_password` (15), `brands` kosong; tanpa LLM halaman lolos. 4 run selesai semuanya flagged (courier, `reasonable:false`, skor 45); 6 timeout (skor 15, lolos). Tidak ada `reasonable`, tidak ada `bad_schema`, tidak ada galat penyedia.

**Hitungan 10 run:** flagged 4, timeout 6 (60%), lainnya 0.

**Waktu.** Run selesai 2,75–5,89 s (median 4,96 s, n = 4); non-stream tanpa batas 5,40 / 6,78 / 8,69 s; stream 5,7 / 10,8 / 45,7 s. Stream#1 mencapai 45,7 s (reasoning dari 4,8 s sampai 44,1 s) dan stream#3 selesai di 10,8 s tanpa sempat menjawab. Pencilan besar, mirip lonjakan 22 s di ulangan testing 11.

**Perbandingan.**
- Testing 14 (`deepseek-v4-flash`, reasoning bawaan, jam 19.19): 6 timeout, 4 flagged, median selesai 4,09 s, non-stream 4,79–7,13 s, reasoning 97–100%. Sekarang (reasoning off): 6 timeout, 4 flagged, median 4,96 s, non-stream 5,40–8,69 s, reasoning 94–100%. **Tidak ada perbaikan; angkanya sama atau sedikit lebih buruk**, dalam rentang variasi penyedia.
- Token reasoning: testing 14 153–497; sekarang 176–634. Tidak turun.

**Yang tidak bisa disimpulkan.** Apakah ada cara lain mematikan reasoning di proxy ini (nama parameter berbeda, model berbeda); apakah model non-reasoning sungguhan akan lebih cepat. Hasil ini hanya membuktikan bahwa `reasoning: {enabled: false}` tidak berpengaruh di `bandelbanget.xyz` untuk `deepseek-v4-flash`. Plan (bagian 1) sudah memperingatkan parameter ini hanya untuk OpenRouter dan sejenisnya; ini mengonfirmasi untuk proxy ini.

**Rekomendasi (di luar plan ini).**
1. Jangan memakai `reasoning off` sebagai solusi kecepatan di penyedia ini.
2. Uji model yang memang non-reasoning di proxy yang sama (`bandingkan model ...`), atau tanya penyedia parameter yang benar.
3. Kalau tidak ada model cepat, pertimbangkan batas waktu layer 4 lebih longgar; memisah verdict dari penjelasan hanya berguna kalau model non-reasoning terbukti ada.

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
