# Hasil tes manual 8 Nov 2026: layer 4 mati karena key LLM expired

Pemilik: Imelda (`ai/`). Tidak ada perubahan kode. Hanya secret `LLM_API_KEY` di Worker `shoo-ai` yang diganti.

## Gejala

Di hp (build `origin/main` `dfc0890`), halaman scam hanya kena sinyal layer 1-3. Layer 4 tidak pernah muncul.

## Penyebab

Key LLM expired sejak 2026-11-07. Provider membalas teks "Your subscription has expired" dalam hitungan milidetik. Balasan itu gagal di `parseVerdict`, jadi hasilnya `bad_schema`, `llm.check` balik `null`, dan tidak ada sinyal layer 4 tanpa error apa pun.

Gate layer 4 sendiri benar: `score >= 30 && score < 80` (`ai/src/layer4/reality.js`).

## Cara membuktikan dari luar (tanpa akses log)

Observability Worker mati, jadi dibandingkan latensi `POST /analyze` prod pada halaman yang sama, hanya skornya beda.

| Kondisi | Median latensi | Sinyal layer 4 |
|---|---|---|
| Di bawah gate (skor 25) | sekitar 61-84 ms | tidak ada |
| Di dalam gate (skor 60), key expired | sekitar 117-174 ms | tidak ada |
| Di dalam gate (skor 60), key baru | 1,5-4,5 detik | `unreasonable_request` (30) |

Latensi 134-162 ms di dalam gate terlalu cepat untuk panggilan LLM sungguhan. Selisih sekitar 55 ms dari "di bawah gate" menunjukkan jalur layer 4 sampai ke provider (bukan secret kosong, bukan `capped`).

## Perbaikan

Secret `LLM_API_KEY` di Worker `shoo-ai` diganti (`wrangler secret put`). `LLM_BASE_URL` dan `LLM_MODEL` sudah ada dan tidak diubah. Key di `ai/.env` lokal juga diganti. Kode tidak berubah.

## Hasil setelah perbaikan: `m-pajak.top`

Snapshot disusun dari HTML mentah (curl), bukan dari `snapshot.js` di Safari, jadi label field kosong. Sinyal yang menentukan (field `password`) tetap sama.

| Layer | Sinyal | Bobot |
|---|---|---|
| 2 | `cheap_tld` (`.top`) | 5 |
| 3 | `asks_password` | 15 |
| 3 | `new_domain` (didaftarkan 2026-10-05) | 10 |
| 4 | `unreasonable_request` | 50 |
| Total | | 80 (garis blokir) |

Sebelum perbaikan totalnya 30 (hanya peringatan). Setelah perbaikan 7 dari 8 percobaan kena 80. Satu percobaan pertama tidak memunculkan layer 4 (cold start, atau confidence di sekitar 0,7; belum bisa dibedakan dari luar).

## Catatan

- Extension hanya memanggil `/analyze` kalau consent online-check di app `granted` (`SessionStore.swift`: `aiBaseURL` hanya ditulis ke App Group saat itu).
- Key yang expired tidak kelihatan dari luar. Usul (belum diajukan): hitungan `bad_schema` dan `http_error` dijadikan alert.
- Layer 1 pada tes ini tidak mencari di blocklist (stub). Domain tidak ada di `/public-blocklist` saat dicek.
