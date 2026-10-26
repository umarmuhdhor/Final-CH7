# Testing 13: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 19.06 · folder `26-oct-2026/13-testing-19.06` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
> Penguji: Imelda (dijalankan bersama Claude lewat `PLAN-llm-test.md`, runner `tools/run-llm-plan.mjs`)
> Link yang diuji dan isi snapshot: lihat `link.md` · request/respons mentah: `llm-response.md` · data mentah: `raw/`
> Bagian "Analisis" di bawah ditulis setelah data dibaca; angka di tabel dihasilkan otomatis oleh runner.

## 1. Setelan

| Item | Nilai |
|---|---|
| Link (defanged) | `hxxps://ibank[.]klikbca[.]com/` |
| Penyedia / model | (LLM tidak dipanggil) |
| Prompt | `reality-check.v3` |
| Reasoning | bawaan (tidak ada parameter `reasoning` yang dikirim, sama seperti kode produksi) |
| `temperature` / `max_tokens` / `response_format` | 0 / 200 / `json_object` |
| Batas waktu layer 4 | 6000 ms (`MAX_TIMEOUT_MS`); server `/analyze` 6.500 ms; extension 8.000 ms |
| `LLM_DAILY_CAP` | 5000 |
| Jumlah panggilan | 0 |
| RDAP | dimatikan (domain scam tidak dikirim ke registry) |
| Mesin | Apple M5, Node v26.8.1, darwin/arm64 |
| Catatan | model glm-5.3-flash via env override (ai/.env tetap deepseek-v4-flash) |

**LLM tidak dipanggil:** halaman tidak lolos gerbang LLM (skor layer 3 < 15 atau situs resmi), jadi produksi tidak akan memanggil LLM.

## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | 0,26 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 81,2 µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | - |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | - |
| 4 (LLM), streaming: porsi waktu di fase reasoning | - |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | tidak ada |
| Sinyal layer 3 | tidak ada |
| Skor layer 3 | 0 |
| Lolos gerbang LLM | tidak |


## 4. Analisis (diisi Claude setelah membaca data)

**Temuan utama**

- Link ini bukan scam. `ibank.klikbca.com` adalah halaman login internet banking BCA yang asli, jadi ini uji false positive, bukan uji deteksi. Teks "halaman phishing" di `link.md` adalah boilerplate runner.
- Halaman berhasil diambil statis (17.744 byte; 2 form, 2 field: `txt_user_id` text dan `txt_pswd` password). Layer 1–2 dan layer 3 tidak mengeluarkan sinyal, skor layer 3 = 0, jadi tidak ada false positive. Ini hasil yang benar.
- Gerbang LLM menutup (skor < 15 atau situs resmi). Produksi juga tidak memanggil LLM untuk halaman ini. Hasilnya: 0 panggilan, 0 biaya.

**Konsistensi dan waktu**

- Tidak ada run `flagged`, `reasonable`, atau `timeout` (0 dari 0), jadi konsistensi jawaban LLM tidak bisa dinilai. Tabel waktu layer 4, diagnosa, dan streaming kosong karena tidak ada panggilan.
- Waktu yang terukur hanya layer 1–2 (0,26 ms) dan layer 3 (81,2 µs). Keduanya jauh di bawah batas.

**Model glm-5.3-flash**

- Model dipasang lewat env `LLM_MODEL` untuk proses runner saja (`ai/.env` tetap `deepseek-v4-flash`). Request di `llm-response.md` bagian 1 memuat `glm-5.3-flash`, tetapi tidak pernah dikirim.
- Belum terbukti: apakah penyedia `bandelbanget.xyz` punya model `glm-5.3-flash`, dan seberapa cepat serta akurat dia. Tidak ada data untuk itu.

**Perbandingan dengan baseline (bagian 6 PLAN)**

- Baseline memakai sampel phishing `helpnets[.]info` yang lolos gerbang (skor 15, lalu 40). Sampel ini sebaliknya, jadi angka waktu LLM tidak bisa dibandingkan.

**Rekomendasi**

1. Untuk menguji glm-5.3-flash, kirim link scam yang lolos gerbang, atau pakai `pakai snapshot` dari sampel `helpnets[.]info`. Tambahkan `bandingkan model glm-5.3-flash,deepseek-v4-flash` kalau mau perbandingan langsung.
2. Simpan hasil ini sebagai contoh negatif (situs bank asli, skor 0) untuk eval set, setelah `captured-sample.json` diperiksa manual (`redacted: false`).
3. Data tidak cukup untuk menyimpulkan apa pun tentang layer 4.

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
