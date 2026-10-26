# Testing 2: setelan reasoning di OpenRouter (`deepseek/deepseek-v4-flash`)

> Tanggal: 26 Okt 2026, 10.05 · lanjutan dari `01-testing-09.58` · `main` @ `a035bb9` · tidak ada kode repo yang diubah
> Penguji: Imelda (dijalankan bersama Claude)

## 1. Tujuan

Layer 4 (LLM) tidak pernah menghasilkan sinyal di OpenRouter karena model menghabiskan `max_tokens` untuk reasoning (temuan T6 di testing 1). Tes ini mencari setelan reasoning yang membuat model benar-benar menjawab, dalam batas waktu kode (6 s).

## 2. Setelan tetap

| Item | Nilai |
|---|---|
| Penyedia | OpenRouter, `https://openrouter.ai/api/v1/chat/completions` |
| Model | `deepseek/deepseek-v4-flash` |
| Provider yang melayani | Relace (dilaporkan OpenRouter di tiap respons) |
| `temperature` | 0 |
| `response_format` | `{"type":"json_object"}` |
| Prompt | `reality-check.v2` (`ai/prompts/reality-check.js`), tanpa perubahan |
| Input | sama persis dengan testing 1 (`site`, `title`, 3 label field, `rules: ["asks_password"]`) |
| `ai/.env` | `LLM_MODEL=deepseek/deepseek-v4-flash`, `LLM_BASE_URL=https://openrouter.ai/api/v1`, `LLM_DAILY_CAP=5000`, `LLM_TIMEOUT_MS` = **salah isi** (lihat 6) |
| Batas di kode | `MAX_TIMEOUT_MS = 6000` (`ai/src/layer4/config.js`); server 6,5 s (`SERVER_DEADLINE_MS`) |

Parameter `reasoning` **tidak ada** di `ai/src/layer4/provider.js` dan tidak bisa diatur lewat `.env`. Semua variasi di bawah dikirim lewat skrip terpisah di scratchpad, bukan lewat kode repo.

## 3. Hasil: satu panggilan per setelan

Yang diubah hanya `max_tokens` dan parameter `reasoning` di body request.

| # | `max_tokens` | `reasoning` | Waktu | `finish_reason` | Token completion / reasoning | `content` |
|---|---|---|---|---|---|---|
| 0 | 200 | tidak dikirim (kode sekarang) | 6,6–8,1 s | `length` | 200 / 218 | kosong |
| M | 200 | `{effort: "medium"}` | 4,0 s | `length` | 200 / 212 | kosong |
| 1 | 200 | `{effort: "low"}` | 5,5 s | `length` | 200 / 215 | kosong |
| 2 | 200 | `{effort: "minimal"}` | 5,1 s | `length` | 200 / 213 | kosong |
| 3 | 1000 | `{effort: "low"}` | 29,0 s | `length` | 1000 / 1075 | kosong |
| 4 | 1000 | `{effort: "minimal"}` | **33,9 s** | `stop` | 936 / 938 | JSON valid |
| 5 | 200 | `{enabled: false}` | **2,8 s** | `stop` | 34 / 0 | JSON valid |

Biaya per panggilan: 0,0000343 USD (#5) sampai 0,000473 USD (#3).

Jawaban nyata:

- **#5 (reasoning mati):** `{"page_type":"other","asks":["password","personal_data"],"reasonable":true,"confidence":0.6,"evidence":"Sign in to your account"}`
- **#4 (minimal, 1000 token):** `{"page_type":"other","asks":["password","personal_data"],"reasonable":true,"confidence":0.9,"evidence":"Sign in to your account"}`

## 4. Kecepatan (semua pengukuran dari testing 1 dan 2)

Waktu dihitung dari request keluar sampai body respons diterima, dari Mac Imelda ke OpenRouter (bukan dari Cloudflare Worker, jadi di produksi angkanya bisa beda). Semua panggilan satu per satu, tanpa paralel, jumlahnya kecil.

| Setelan | Jumlah | Min | Median | Maks | Rata-rata | Menjawab? |
|---|---|---|---|---|---|---|
| Kode sekarang (reasoning bawaan, `max_tokens 200`) | 5 panggilan langsung | 2,6 s | 6,6 s | 8,1 s | 5,4 s | **tidak**, `content` kosong |
| `effort: "medium"`, 200 | 1 | 4,0 s | – | – | 4,0 s | tidak |
| `effort: "low"`, 200 | 1 | 5,5 s | – | – | 5,5 s | tidak |
| `effort: "minimal"`, 200 | 1 | 5,1 s | – | – | 5,1 s | tidak |
| `effort: "low"`, 1000 | 1 | 29,0 s | – | – | 29,0 s | tidak |
| `effort: "minimal"`, 1000 | 1 | 33,9 s | – | – | 33,9 s | ya, tapi terlalu lambat |
| **`reasoning: {enabled: false}`, 200** | **4** (3 langsung, 1 via kode) | **2,7 s** | **3,2 s** | **4,5 s** | **3,4 s** | **ya** |

Rincian 4 panggilan reasoning mati: 3,7 s, 2,7 s, 2,8 s (langsung), 4,5 s (lewat `createRealityCheck`).

Lewat jalur kode asli (batas 6 s): reasoning bawaan **timeout 2 dari 2** (6,0 s), `effort: "medium"` timeout 1 dari 1, reasoning mati **lolos 1 dari 1** (4,5 s).

Batas yang berlaku: layer 4 maks 6 s (`MAX_TIMEOUT_MS`), server `/analyze` menjawab maks 6,5 s sejak request masuk (`SERVER_DEADLINE_MS`), extension menyerah di 8 s. Reasoning mati (maks 4,5 s) muat di semua batas itu. Setelan lain tidak.

Jumlah token berbanding lurus dengan waktu: reasoning mati memakai 31–34 token, reasoning bawaan menghabiskan seluruh `max_tokens` (200) dan masih tidak menjawab. Biaya ikut turun (sekitar 0,00003 USD vs 0,0001–0,0005 USD per panggilan).

## 5. Temuan

**T1. `effort` diabaikan oleh provider.** Jumlah token reasoning hampir sama di semua nilai `effort` (212–218 pada `max_tokens: 200`). Relace tampaknya tidak mendukung parameter `effort`, jadi `low`, `medium`, dan `minimal` tidak mengurangi reasoning.

**T2. Hanya `reasoning: {enabled: false}` yang praktis.** Itu satu-satunya setelan yang menjawab dalam batas 6 s (2,8 s, 34 token). Setelan lain kosong, atau menjawab tapi memakai ±34 s (#4), jauh di atas batas kode dan batas 8 s extension.

**T3. Menaikkan `max_tokens` tidak menolong.** Reasoning membengkak ke jatah yang ada (200 → 212, 1000 → 1075). Pada 1000 token pun 3 dari 4 panggilan masih kosong.

**T4. Jawaban LLM sama di semua yang selesai: "wajar".** `reasonable: true` di #4 dan #5, jadi tidak ada sinyal `unreasonable_request` dan skor tetap 15. Konfidensinya berbeda (0,9 dengan reasoning, 0,6 tanpa), tapi keputusannya sama. Penyebabnya tetap input yang tidak menyebut Microsoft (T2 di testing 1), bukan reasoning.

**T5. `asks` tidak stabil.** Panggilan terpisah mengembalikan `["password"]` atau `["password","personal_data"]` untuk input yang sama pada `temperature: 0`.

## 6. Kesalahan konfigurasi yang ditemukan

Di `ai/.env`, teks `reasoning: {effort: "medium"}` tertulis di baris `LLM_TIMEOUT_MS=`, sehingga barisnya menjadi `LLM_TIMEOUT_MS= reasoning: {effort: "medium"}`. Kode membacanya sebagai angka, hasilnya NaN, dan jatuh ke default 6000 ms. Jadi baris itu tidak berefek apa pun, dan `reasoning` tidak pernah terkirim lewat `.env`. Perbaikan: `LLM_TIMEOUT_MS=6000` atau kosong.

## 7. Batasan

- Satu panggilan per setelan, jadi variasi latensi dan jawaban belum terukur.
- Satu sampel scam (halaman Microsoft palsu), nol sampel legit. Belum ada angka recall atau salah blokir.
- Provider dan versi model di OpenRouter belum tentu sama dengan proxy produksi (`bandelbanget.xyz`).
- `effort` mungkin berfungsi di provider OpenRouter lain (bisa dipaksa lewat `provider: {order: [...]}`), belum diuji.

## 8. Rekomendasi

1. **Pakai `reasoning: {enabled: false}`** untuk jalur OpenRouter. Perubahannya di `ai/src/layer4/provider.js` (milik Umar). Lihat draf issue di `../01-testing-09.58/issue-draft-reasoning.md`.
2. **Alternatif tanpa ubah kode:** ganti `LLM_MODEL` ke model non-reasoning di OpenRouter (misalnya `deepseek/deepseek-chat`) dan ulangi tes ini.
3. **Sebelum memutuskan, jalankan eval penuh (103 sampel)** dengan reasoning mati, untuk mengukur recall scam dan salah blokir legit. Tes ini belum membuktikan kualitasnya.
4. Perbaiki baris `LLM_TIMEOUT_MS` di `ai/.env` (bagian 6).
