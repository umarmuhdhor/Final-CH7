# PLAN: uji layer 1–4 (termasuk LLM) pada satu link

> File ini adalah instruksi untuk Claude. Imelda cukup mengirim satu prompt, lalu Claude menjalankan runner dan menulis seluruh folder testing.
> Dibuat 26 Okt 2026 dari testing 01–05. Runner: `ai/testing/tools/run-llm-plan.mjs`.

## 1. Cara pakai (untuk Imelda)

Kirim prompt seperti ini di chat (di folder `Final-CH7`):

```text
Jalankan plan ai/testing/PLAN-llm-test.md di link https://contoh.com/halaman-scam
```

Variasi yang didukung:

| Mau apa | Tambahkan ke prompt |
|---|---|
| Lebih banyak run (default 10) | `hanya 10 run` |
| Matikan reasoning (hanya untuk OpenRouter dan sejenisnya) | `dengan reasoning off` |
| Bandingkan model lain di penyedia yang sama | `bandingkan model glm-5.3-flash,deepseek-v4.1-flash` |
| Pakai snapshot yang sudah ada, tanpa mengambil halaman lagi | `pakai snapshot <path json>` |
| Tanpa LLM (gratis, hanya layer 1–3) | `tanpa LLM` |
| Catatan | `catatan: sesudah prompt v3` |

Beberapa link: satu prompt per link. Tiap link mendapat folder sendiri (nomor naik otomatis).

## 2. Prasyarat

- `ai/.env` terisi `LLM_API_KEY`, `LLM_MODEL`, `LLM_BASE_URL` (cek hanya panjang nilainya, jangan ditampilkan). Kalau kosong, layer 4 dilewati dan runner menulis alasannya; jangan minta key lewat chat, minta Imelda mengisinya di file.
- Berjalan dari repo `Final-CH7` (Node ≥ 22). Ada internet.
- Link adalah halaman phishing/scam. **Jangan dibuka di browser, jangan di-fetch dengan alat lain.** Satu-satunya cara mengambilnya: `ai/eval/tools/capture.mjs` (GET statis, tanpa JavaScript, tanpa cookie, host publik saja), yang sudah dipanggil oleh runner.

## 3. Langkah untuk Claude

1. **Baca file ini penuh.** Cek `ai/.env` hanya untuk keberadaan dan panjang `LLM_API_KEY` (contoh: `awk -F= '/^LLM_API_KEY/ {v=$0; sub(/^[^=]*=/,"",v); print length(v)}' ai/.env`). Cek branch dan commit (`git branch --show-current`, `git rev-parse --short HEAD`) supaya bisa dicatat.
2. **Umumkan satu kalimat** sebelum menjalankan: link (defanged), jumlah panggilan LLM yang akan terjadi, dan bahwa ini memakai API key Imelda (berbiaya). Default = 10 run kode asli + 3 diagnosa + 3 stream = **16 panggilan LLM**; `--models` menambah 2 per model.
3. **Jalankan runner sekali:**
   ```bash
   node ai/testing/tools/run-llm-plan.mjs "<LINK>" [--runs N] [--diag N] [--stream N] [--models a,b] [--reasoning off] [--snapshot file.json] [--no-llm] [--note "..."]
   ```
   Waktu ±1–3 menit untuk default (tiap panggilan 3–11 detik). Pakai `timeout` Bash besar (600000 ms) atau jalankan di background. Jangan jalankan dua kali "supaya yakin": itu menghabiskan uang dan menggandakan folder.
4. **Ambil `OUT=` dari baris terakhir keluaran**, lalu **baca** `report.md`, `link.md`, `llm-response.md` di folder itu (bukan hanya ringkasan terminal).
5. **Isi bagian "4. Analisis" di `report.md`** (satu-satunya bagian yang tidak otomatis; edit dengan Edit, jangan menimpa file). Wajib mencakup:
   - Apa yang terdeteksi, apa yang lolos, dan kenapa (lihat sinyal layer 3, input LLM, jawaban LLM).
   - Apakah jawaban LLM konsisten antar-run; hitung berapa run `flagged` vs `reasonable` vs `timeout` dari tabel.
   - Kenapa waktunya sebesar itu (pakai tabel streaming: porsi fase reasoning; bandingkan "lewat kode asli" vs "diagnosa tanpa batas").
   - Perbandingan dengan hasil sebelumnya (tabel baseline di bagian 6) dan apa yang berubah.
   - Rekomendasi, dan kalau datanya tidak cukup untuk menyimpulkan, **tulis itu**. Jangan mengarang hasil, jangan membulatkan angka ke arah yang lebih baik.
6. **Verifikasi:** jangan mencetak key untuk memeriksanya. Runner sudah memindai semua file keluaran terhadap key dan menghapus file yang bocor; cukup pastikan skrip selesai tanpa error "API key ditemukan". Cek juga `link.md` hanya memuat link versi defanged (`hxxps://...[.]...`).
7. **Balas Imelda** dengan ringkasan pendek: link (defanged), folder keluaran (sebagai link markdown), tabel waktu (layer 1–2, layer 3, layer 4: min/median/maks, timeout x dari N), hasil (flagged/reasonable/timeout, skor akhir), dua sampai tiga temuan, dan apa yang belum terbukti. Tawarkan langkah berikutnya, jangan jalankan sendiri.

## 4. Yang dibuat otomatis oleh runner

Folder (nomor dan jam otomatis; nomor = nomor terbesar hari itu + 1):

```text
ai/testing/
  <DD-mon-YYYY>/                 contoh: 26-oct-2026
    <NN>-testing-<HH.MM>/        contoh: 06-testing-15.45
      link.md                    dokumentasi link yang diuji
      llm-response.md            request + respons LLM mentah
      report.md                  setelan, waktu per layer, hasil, (analisis diisi Claude)
      captured-sample.json       snapshot halaman (redacted:false, email dimasking)
      raw/
        code-path.json           semua run lewat kode asli (termasuk body respons)
        diagnosa.json            panggilan non-stream tanpa batas 6 detik
        stream.json              garis waktu streaming
        models.json              hanya kalau --models dipakai
```

`link.md` berisi: link defanged, domain, waktu pengambilan, cara ambil, ukuran HTML, status redaksi, isi snapshot (title, lang, panjang teks, form dan field, imageAlts), hasil layer 1–3 beserta waktunya, skor, status gerbang LLM, dan JSON persis yang dikirim ke LLM.

`llm-response.md` memakai susunan yang sama dengan `26-oct-2026/04-testing-10.30/llm-response.md`, ditambah tabel kode asli:

| Bagian | Isi |
|---|---|
| 1 | Request (endpoint, header disensor, body lengkap) |
| 2 | Lewat kode asli (`createRealityCheck`, batas 6 detik): tiap run, hasil, token, sinyal akhir, skor, jawaban yang masuk |
| 3 | Panggilan non-stream tanpa batas (diagnosa): header tiba, selesai, finish, token, validitas jawaban |
| 4 | Respons mentah lengkap dari panggilan tercepat (termasuk `reasoning_content` kalau ada) |
| 5 | Streaming: byte pertama, reasoning mulai dan selesai, jawaban mulai, porsi reasoning |
| 5b | Model lain (hanya kalau `--models`) |
| 6 | System prompt lengkap beserta versinya |

## 5. Aturan keselamatan (tidak boleh dilanggar)

1. Link scam **tidak dibuka** di browser dan tidak diambil dengan `curl`/`WebFetch`. Hanya lewat runner (yang memanggil `capture.mjs`).
2. Link selalu ditulis **defanged** di semua dokumen (`hxxps://contoh[.]com/...`).
3. API key tidak pernah ditampilkan, dicetak, atau ditulis ke file. Runner memindai keluarannya.
4. Jangan mengubah kode di `ai/src`, `ai/prompts`, `detector/`, atau `ai/.env` selama plan ini. Plan ini hanya menguji. Perubahan kode = permintaan terpisah dengan catatan di `ai/testing/changes/`.
5. Tidak ada commit, push, issue, atau PR dari plan ini.
6. Satu run runner per permintaan (biaya). Menambah run hanya kalau Imelda minta.
7. Jangan memasukkan `captured-sample.json` ke `ai/eval/data/` sebelum diperiksa manual (`redacted: false`).
8. Kalau halaman gagal diambil (mati, bukan HTML, host non-publik), laporkan pesan runner apa adanya. Jangan mencoba link lain atau cara lain sendiri.

## 6. Baseline untuk perbandingan (hasil sebelumnya pada sampel `helpnets[.]info`)

| Testing | Setelan | Hasil |
|---|---|---|
| `26-oct-2026/03-testing-10.25` | bandelbanget, `deepseek-v4-flash`, prompt v2, 10 run kode asli | 5 timeout, 4 wajar, 1 flagged; waktu selesai 3,5–5,7 s (median 4,4 s); skor 15 (45 pada run flagged) |
| `26-oct-2026/04-testing-10.30` | sama, diagnosa dan streaming | non-stream 3,9–11,1 s; 94–96% waktu di fase reasoning; `max_tokens` diabaikan proxy |
| `26-oct-2026/04-testing-10.30` (10 run `deepseek-v4.1-flash`) | model lain | 3 timeout, 6 wajar, 1 flagged; selesai 3,6–5,5 s |
| `26-oct-2026/05-testing-10.54` | tes otomatis setelah perubahan | layer 3 skor 15 → 40 pada sampel yang sama; belum ada panggilan LLM dengan prompt v3 |

Catatan: sampel sebelum perubahan memakai prompt v2 dan layer 3 tanpa aturan sidik jari. Hasil sekarang memakai prompt v3 dan `brands` di input, jadi bandingkan dengan hati-hati dan sebutkan perbedaan setelannya.

## 7. Kalau ada masalah

| Gejala | Penyebab umum | Tindakan |
|---|---|---|
| `layer 4 mati: LLM_API_KEY / LLM_MODEL / LLM_BASE_URL belum lengkap` | `.env` kosong atau baris ter-comment | Minta Imelda mengisi `ai/.env`; hasil layer 1–3 tetap tersimpan |
| `Gagal mengambil halaman` | Situs sudah mati, bukan HTML, atau host non-publik | Laporkan; tawarkan `--snapshot` bila ada snapshot lama |
| Semua run `timeout` | Penyedia lambat (reasoning panjang) | Itu hasil, bukan bug: catat; bandingkan dengan tabel diagnosa dan streaming |
| Semua run `http_error` | Key salah, saldo habis, model tidak ada di penyedia | Lihat tabel diagnosa (kolom finish/error); jangan menebak, laporkan |
| `content` kosong, `finish: length` | Model reasoning menghabiskan `max_tokens` (terjadi di OpenRouter) | Coba `reasoning off`; catat bahwa itu berbeda dari kode produksi |
| Halaman tidak lolos gerbang LLM | Skor layer 3 < 15 atau situs resmi | Itu hasil: produksi juga tidak akan memanggil LLM |
| `node --test` ikut menjalankan runner | Nama file berakhiran `-test.mjs` | Jangan ganti nama runner jadi `*-test.mjs`, `*.test.mjs`, atau `test-*.mjs` |
