# Testing 4: kenapa layer 4 (LLM) sering lewat 6 detik di bandelbanget

> Tanggal: 26 Okt 2026, 10.30 · lanjutan dari testing 3 · `main` @ `a035bb9` · tidak ada kode repo yang diubah
> Sampel: `helpnets[.]info/0442827f…c.html/` (login Microsoft palsu), input ke LLM sama dengan testing 1–3
> Penguji: Imelda (dijalankan bersama Claude)
> File di folder ini: `report.md` (ini), `llm-response.md` (request + respons mentah + garis waktu), `diag-raw.json` (10 panggilan diagnosa), `models-raw.json` (12 panggilan per model)

## 1. Pertanyaan

Di testing 3, 5 dari 10 panggilan layer 4 melewati batas 6 detik dan dibatalkan. Apa yang membuat panggilan itu lama?

## 2. Jawaban singkat

**Model "berpikir" terlalu lama, dan proxy tidak memberi cara membatasinya.**

1. Hampir seluruh waktu habis di fase reasoning model (94–96% dari waktu streaming). Jawaban JSON-nya sendiri selesai ditulis dalam 0,15–0,25 detik.
2. Panjang reasoning berubah-ubah (185–1.024 token) untuk input yang sama, jadi waktunya juga berubah-ubah: 3,9 s sampai 11,1 s. Sekitar 9–12 ms per token reasoning.
3. Tidak ada tombol untuk membatasinya di bandelbanget: `max_tokens` diabaikan, dan parameter reasoning yang dicoba tidak mematikannya.
4. Mode non-stream membuat kode menunggu sampai seluruh respons selesai, jadi batas 6 s memotong jawaban yang sebenarnya hampir selesai.
5. **Jaringan bukan penyebabnya** (0,2–0,9 s).

## 3. Setelan

| Item | Nilai |
|---|---|
| Penyedia | `https://bandelbanget.xyz/v1` (OpenAI-compatible) |
| Model utama | `deepseek-v4-flash` (sama dengan produksi, D-imelda-36) |
| Reasoning | bawaan (menyala) kecuali disebut |
| `temperature` | 0 |
| `max_tokens` | 200 (setelan kode), kecuali disebut |
| `response_format` | `{"type":"json_object"}` |
| Prompt | `reality-check.v2`, tanpa perubahan |
| `LLM_TIMEOUT_MS` | 6000 (batas atas keras `MAX_TIMEOUT_MS` di `config.js`) |
| Batas server / extension | `/analyze` 6,5 s, extension menyerah di 8 s |
| Mesin | Mac Imelda, bukan dari Cloudflare Worker; angka produksi bisa berbeda |
| Jumlah panggilan | 10 diagnosa + 12 per-model + 10 run kode asli `deepseek-v4.1-flash` |

## 4. Bukti

### 4.1 Jaringan: bukan penyebab

GET kecil (`/v1/models`, tanpa auth), 5 kali: DNS 2–34 ms, connect 48–426 ms, TTFB 0,17–0,92 s. Ping rata-rata 103 ms (33–245 ms), 0% hilang. Satu panggilan LLM butuh 3,5–11 s, jadi jaringan paling banyak 10–15% dari waktunya.

### 4.2 Streaming: waktu habis di fase reasoning

Permintaan yang sama dengan `stream: true`, 3 kali. Waktu sejak request keluar:

| Run | Byte pertama | Reasoning selesai | Jawaban mulai | Selesai | Porsi reasoning |
|---|---|---|---|---|---|
| 1 | 0,62 s | 3,40 s | 3,43 s | 3,60 s | 94% |
| 2 | 0,87 s | 3,99 s | 3,99 s | 4,19 s | 95% |
| 3 | 1,64 s | 3,72 s | 3,74 s | 3,89 s | 96% |

Model mulai "berpikir" kurang dari 2 detik, lalu menulis ±1.650–1.880 karakter reasoning dalam ±150 potongan, dan baru menulis jawaban (7 potongan, ±0,2 s). Teks reasoning lengkap untuk satu run ada di `llm-response.md` bagian 3.

### 4.3 Non-stream: variasi besar untuk input yang sama

| Panggilan | Waktu | Token reasoning | Token completion |
|---|---|---|---|
| default#1 | **11,08 s** | 937 | 1.996 |
| default#2 | 6,02 s | 528 | 1.587 |
| default#3 | 3,86 s | 335 | 1.391 |
| (tes model) deepseek-v4-flash #1 | 7,62 s | 814 | 1.873 |
| (tes model) deepseek-v4-flash #2 | 5,82 s | 637 | 1.696 |

Waktu naik hampir lurus dengan token reasoning (335 → 3,9 s; 637 → 5,8 s; 814 → 7,6 s; 937 → 11,1 s). Pada panggilan non-stream, header respons baru datang bersama body (`headers_s` = `total_s`): proxy menahan semuanya sampai selesai, jadi kode tidak melihat apa pun selama menunggu.

### 4.4 Parameter untuk membatasi reasoning: tidak ada yang berhasil

Satu panggilan per setelan, non-stream:

| Setelan | Waktu | Token reasoning | Token completion | Hasil |
|---|---|---|---|---|
| (tanpa tambahan, `max_tokens: 200`) | 3,9–11,1 s | 335–937 | 1.391–1.996 | JSON valid |
| `max_tokens: 50` | 8,37 s | 945 | 2.001 | JSON valid; **`max_tokens` diabaikan** |
| `reasoning: {enabled: false}` | 5,21 s | 494 | 1.553 | reasoning **tetap jalan** |
| `thinking: {type: "disabled"}` | 4,30 s | 279 | 1.338 | reasoning **tetap jalan** (lebih pendek, mungkin kebetulan) |
| `reasoning_effort: "low"` | 9,97 s | **1.024** | **2.048** | `finish_reason: length`, **`content` kosong** |

Dua hal tambahan: (a) `max_tokens` tidak berpengaruh, jadi tidak bisa dipakai memotong biaya atau waktu; (b) ada batas tersembunyi di proxy sekitar 2.048 token completion / 1.024 token reasoning. Kalau reasoning menyentuh batas itu, jawabannya kosong (`bad_schema` di kode).

### 4.5 Model lain di bandelbanget

Proxy menawarkan 42 model. Dicoba 6 model "flash", 2 panggilan per model, non-stream:

| Model | Waktu (2 panggilan) | Token reasoning | Skema valid | Penilaian |
|---|---|---|---|---|
| deepseek-v4-flash | 7,62 s, 5,82 s | 814, 637 | 2 dari 2 | tidak wajar 0,78; wajar 0,6 |
| deepseek-v4-flash-0731 | 8,76 s, 6,91 s | 820, 601 | 2 dari 2 | wajar 0,55; wajar 0,45 |
| **deepseek-v4.1-flash** | **2,59 s, 2,60 s** | **209, 234** | 2 dari 2 | wajar 0,55; wajar 0,7 |
| glm-5.3-flash | 3,11 s, 2,08 s | 446, 314 | 2 dari 2 | tidak wajar 0,7; wajar 0,4 |
| glm-5.3-flashx | 3,93 s, 3,80 s | 689, 608 | 2 dari 2 | tidak wajar 0,78; wajar 0,4 |
| mimo-v2.6-flash | 3,00 s, 3,21 s | 185, 277 | 2 dari 2 | wajar 0,7; wajar 0,6 |

Semua model masih melakukan reasoning (185–820 token). Tidak ada yang tanpa reasoning.

### 4.6 Uji 10 run lewat kode asli: `deepseek-v4.1-flash` vs `deepseek-v4-flash`

| Model | Selesai | Timeout (6 s) | Waktu yang selesai (min / median / maks) | Flagged | Wajar |
|---|---|---|---|---|---|
| `deepseek-v4-flash` (testing 3) | 5 dari 10 | **5 dari 10** | 3,5 / 4,4 / 5,7 s | 1 | 4 |
| `deepseek-v4.1-flash` (testing 4) | 7 dari 10 | **3 dari 10** | 3,6 / 4,6 / 5,5 s | 1 | 6 |

**Koreksi atas kesan awal.** Pada 2 panggilan langsung di 4.5, `deepseek-v4.1-flash` hanya 2,6 s dan tampak jauh lebih cepat. Di 10 run lewat kode asli, waktunya 3,6–5,5 s (median 4,6 s), hampir sama dengan `deepseek-v4-flash`, dan masih timeout 3 dari 10. Selisih timeout 5 vs 3 dari 10 terlalu kecil untuk disebut perbaikan. Angka 2,6 s kemungkinan kebetulan (proxy sedang lengang), bukan sifat model.

## 5. Temuan

**T1. Penyebab utama: fase reasoning.** 94–96% waktu streaming habis sebelum jawaban pertama ditulis. Tugas klasifikasi ini sederhana, tapi model tetap "berpikir" 185–1.024 token.

**T2. Waktu tidak bisa diprediksi.** Input persis sama, `temperature: 0`: 3,9 s, 6,0 s, 11,1 s. Batas 6 s tidak bisa dipenuhi andal dengan setelan sekarang.

**T3. Proxy tidak memberi kendali.** `max_tokens`, `reasoning.enabled`, `thinking`, dan `reasoning_effort` tidak membatasi reasoning (atau malah memotong jawaban). Berbeda dengan OpenRouter, tempat `reasoning: {enabled: false}` berhasil (testing 2).

**T4. Mode non-stream membuang informasi.** Kode menunggu satu respons utuh. Kalau di detik ke-6 model sudah selesai berpikir dan tinggal menulis jawaban (±0,2 s), hasilnya tetap dibuang.

**T5. Token prompt tidak cocok.** Kita mengirim ±460 token, proxy melaporkan 1.747 (non-stream) dan 1.235 (stream, 131 di antaranya cache). Kemungkinan proxy menambahkan teks sendiri. Penyebab belum diketahui; relevan untuk biaya dan privasi.

**T6. Hasil penilaian tidak stabil.** Model yang sama memberi "tidak wajar" 0,78 dan "wajar" 0,6 untuk input yang sama. Jumlah jawaban "tidak wajar" per tes: testing 3 satu dari 5 jawaban, tes model (4.5) tiga dari 12, uji 10 run `deepseek-v4.1-flash` (4.6) satu dari 7. Konfidensi "wajar" juga bergeser 0,4–0,7.

**T7. Catatan tambahan.** Daftar model proxy memuat nama model dari banyak vendor (Claude, GPT, Gemini, Kimi, GLM). Itu menambah alasan memverifikasi kebijakan retensi data penyedia (D-imelda-36), tapi tidak dibuktikan di tes ini.

## 6. Batasan

- Satu sampel, satu mesin, satu jam. Kecepatan proxy kemungkinan bergantung beban; hasil jam lain bisa berbeda.
- 10 run per model terlalu sedikit untuk selisih kecil (5 vs 3 timeout).
- Dari Cloudflare Worker latensi ke proxy tidak diukur.
- Streaming hanya diukur 3 kali; kode asli tidak memakai streaming.
- Kebijakan retensi dan biaya sisi bandelbanget tidak diperiksa.

## 7. Rekomendasi

Semua perubahan kode ada di `ai/` (milik Umar), jadi lewat issue (aturan 7). Urut dari paling murah:

1. **Tanya Umar/bandelbanget cara mematikan atau membatasi reasoning** untuk `deepseek-v4-flash`. Ini akar masalahnya, dan hanya penyedia yang tahu parameternya.
2. **Naikkan batas layer 4 secara terukur.** Run yang selesai berada di 3,5–5,7 s dengan satu outlier 11 s. Batas 6 s memotong sekitar 30–50%. Server 6,5 s dan extension 8 s membatasi kenaikannya; layer 4 bisa diberi sampai ±7 s tanpa melewati batas extension, tapi itu mengubah janji "6,5 s" di `analyze.js`.
3. **Jadikan layer 4 tidak memblokir.** Layer 3 menjawab dalam <1 ms. Server bisa langsung mengembalikan sinyal layer 3 dan memberi hasil layer 4 belakangan (update skor), karena layer 4 hanya menambah skor (D-imelda-06). Perubahan desain, lebih besar.
4. **Cache hasil LLM per domain** (mirip cache RDAP di KV) supaya kunjungan berikutnya ke domain yang sama tidak menunggu.
5. **Jangan ganti ke `deepseek-v4.1-flash` dulu.** Bukti di 4.6 belum cukup. Kalau mau dicoba, ukur 30+ run di jam berbeda.
6. **Tanyakan T5** (kenapa prompt 1.747 token) ke Umar.
