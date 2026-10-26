# Testing 09: layer 1–4 pada satu link

> Tanggal: 26 Okt 2026, 16.24 · folder `26-oct-2026/09-testing-16.24` · branch `docs/AI-layer-flow-proposal` @ `3aa89f1`
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
| Catatan | - |

**LLM tidak dipanggil:** halaman tidak lolos gerbang LLM (skor layer 3 < 15 atau situs resmi), jadi produksi tidak akan memanggil LLM.

## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | 0,28 ms |
| 3 (aturan, rata-rata 2.000 panggilan) | 80,7 µs |
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

**Sifat sampel.** `ibank.klikbca.com` adalah halaman login internet banking BCA yang asli, bukan scam. Jadi tes ini kontrol negatif (halaman sah), bukan uji deteksi phishing. Runner tetap memberi label `scam` di `captured-sample.json` dan kalimat "halaman phishing/scam" di `link.md` karena itu nilai bawaan; label itu salah untuk sampel ini dan harus diubah ke `legit` kalau file dipakai di eval set.

**Apa yang terdeteksi / lolos.**
- Layer 1–2: 0 sinyal. Layer 3: 0 sinyal, skor 0 (ambang peringatan 30). Tidak ada false positive pada halaman bank asli.
- Layer 3 hanya melihat 2 field (`txt_user_id` text, `txt_pswd` password) dengan label berupa nama field mentah, tanpa `lang`, tanpa `imageAlts`. Teks halaman berisi pernyataan izin OJK/BI dan LPS; tidak ada bahasa mendesak.
- `brands` memuat `BCA`, dan domain `klikbca.com` memang domain BCA. Apakah `klikbca.com` ada di daftar domain resmi merk belum terbukti dari data ini (tidak ada panggilan LLM, dan kode gerbang tidak dibaca di plan ini). Kalau tidak ada di daftar, pengaman satu-satunya adalah skor 0; kalau ada, sinyal merk memang sengaja diam.

**Layer 4 (LLM).** Tidak dipanggil: 0 panggilan, 0 biaya. Gerbang butuh skor ≥ 15 dan bukan situs resmi; skor 0, jadi produksi juga tidak akan memanggil LLM. Karena itu tidak ada data untuk konsistensi antar-run (flagged 0 / reasonable 0 / timeout 0 dari 0 run), waktu layer 4, atau porsi fase reasoning. `raw/` kosong. Tabel waktu layer 4 di bagian 2 berisi "-" karena tidak ada data, bukan karena error.

**Waktu.** Layer 1–2 0,28 ms; layer 3 80,7 µs per panggilan (rata-rata 2.000 panggilan). Seluruh jalur lokal jauh di bawah batas 8 detik extension.

**Perbandingan dengan baseline (bagian 6 PLAN).** Tidak sebanding: baseline memakai `helpnets[.]info` (phishing, skor 15–45, LLM dipanggil) dengan hasil 5 timeout / 4 wajar / 1 flagged dan waktu LLM 3,5–5,7 s. Sampel ini tidak memicu LLM, jadi tidak menambah informasi soal timeout, `max_tokens`, atau prompt v3.

**Belum terbukti.**
- Perilaku LLM pada halaman bank asli (apakah menjawab `reasonable: true` untuk `brands: ["BCA"]` di domain BCA). Gerbang mencegah panggilan.
- Hasil di Safari: halaman asli memakai JavaScript; snapshot statis bisa berbeda dari yang dibaca extension.
- Skor produksi (blocklist layer 1 dan RDAP tidak ikut).

**Rekomendasi.**
1. Catat hasil ini sebagai true negative: halaman bank asli, skor 0, LLM tidak dipanggil.
2. Runner perlu opsi `--label legit|scam` (atau teks `link.md` netral) supaya sampel sah tidak berlabel `scam`. Perubahan kode terpisah, di luar plan ini (aturan 4).
3. Untuk menguji layer 4 dan timeout, pakai link phishing sungguhan (mis. ulang `helpnets[.]info` agar sebanding dengan baseline) atau `--snapshot` dari sampel yang skornya ≥ 15.
4. Cek apakah `klikbca.com` ada di daftar domain resmi `BCA` (di `detector/`/`ai/`, bukan di plan ini).

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): `text` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (`new_domain`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: `redacted: false`; jangan masukkan ke eval set sebelum diperiksa manual.
