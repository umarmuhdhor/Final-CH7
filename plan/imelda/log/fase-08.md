# Fase 08 — Deploy `/analyze` + `/public-blocklist` (M7)

**Status:** `[m]` kode, test, `wrangler.toml` dan smoke test siap. **Tidak ada deploy** (aksi cloud = LANGKAH MANUAL).
**Branch:** `feat/AI-M7-deploy` dari `feat/AI-M6-calibration` (stacked). 22 Okt 2026.

## Yang dikerjakan (TDD, `ai/test/hardening.test.mjs`, 9 test)
- Rate limit per IP untuk `/analyze` (300 / 10 menit, IPv6 per /64) dan `/public-blocklist` (30 / 10 menit). Permintaan yang ditolak tidak dibaca body-nya. Keduanya terpisah.
- Batas body: `/analyze` 200 KB (413, sudah ada); `/public-blocklist` menolak GET yang mengaku punya body > 1 KB (413).
- Header keamanan di SEMUA jawaban (200, 4xx, 429, preflight): `nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`, HSTS, CSP `default-src 'none'; frame-ancestors 'none'`, CORP `cross-origin`.
- CORS: preflight `OPTIONS` dijawab 204 tanpa menyentuh handler/limit; `Access-Control-Allow-Origin: *` (tanpa cookie/kredensial; D-imelda-32).
- Tanpa log: kode tidak pernah `console.*`; test memeriksa semua jalur; `wrangler.toml` mematikan observability dan invocation logs.
- `ai/wrangler.toml`, `ai/scripts/smoke.mjs` (cek kedua endpoint + header + p95), bagian README.

## Verifikasi
- `node --test --test-concurrency=1 detector/test ai/test ai/eval/test ios/ShooExtension/Tests`: 395 lolos, 0 gagal.
- `node ai/scripts/smoke.mjs http://127.0.0.1:8797 20` (dev server): semua `ok`, p95 3 ms (lokal; bukan angka produksi).

## DoD
- [ ] Kedua endpoint hidup di HTTPS publik; smoke test hijau (LANGKAH MANUAL).
- [x] Rate limit dan batas body teruji (429/413).
- [ ] p95 `/analyze` < 8 s tercatat dari URL publik (LANGKAH MANUAL; lokal 3 ms).
- [x] Tidak ada secret/URL halaman di log; `.env.example` terbaru.
- [ ] URL dikirim ke Umar dan Alief oleh Imelda (TODO C4).

## LANGKAH MANUAL (Imelda) — urutan
Batas Workers (halaman resmi Cloudflare, dibaca 22 Okt 2026): **Free = CPU 10 ms per request**, 100.000 request/hari; Paid = CPU default 30 s, tanpa batas harian. `/analyze` sekarang p50 ±2 ms, maks 20 ms di laptop (belum diukur di Workers); membangun daftar publik 200.000 entri butuh ±1 s CPU. Karena itu:
- [ ] (B2) Buat/login akun Cloudflare. Pilih paket: **Free cukup untuk uji** (daftar publik masih kosong), tetapi 10 ms CPU berisiko untuk `/analyze` yang berat (teks 20.000 karakter) dan 100.000 request/hari bisa habis. Rekomendasi: Workers Paid (±US$5/bulan) sebelum pengguna sungguhan. BELUM DIVERIFIKASI: harga terkini.
- [ ] `cd ai && npm install && npx wrangler login` (buka browser; kamu yang login).
- [ ] Deploy: `npx wrangler deploy` (nama `shoo-ai`, URL `https://shoo-ai.<akun>.workers.dev`).
- [ ] Layer 4 (opsional, setelah A2): `npx wrangler secret put LLM_API_KEY`, `... LLM_MODEL`, `... LLM_BASE_URL` (isi di prompt, jangan ditulis ke file). Atur batas pengeluaran di dashboard penyedia LLM.
- [ ] Aturan rate limit Cloudflare (WAF > Rate limiting) per IP untuk `/analyze` dan `/public-blocklist` sebagai pelindung sesungguhnya (limiter di kode hanya per isolate).
- [ ] Smoke test: `node ai/scripts/smoke.mjs https://shoo-ai.<akun>.workers.dev 30`. Tempel keluarannya (termasuk p95) ke sini.
- [ ] Cek: `curl -s -X OPTIONS -H 'origin: x' -H 'access-control-request-method: POST' -i $URL/analyze | head`.
- [ ] Kirim URL ke Umar (`ai.baseURL`) dan Alief (TODO C4). Agent tidak mengirim pesan.
- [ ] Fase 05: sumber daftar publik (A3) + daftar pra-bangun sebelum daftar nyata dipasang (CPU).

## Temuan keamanan
`ecc:security-reviewer`: tidak ada CRITICAL/HIGH. Diperbaiki: smoke test memakai host `.invalid` (tanpa lookup RDAP), `runs` dibatasi 50, menolak `http://` non-lokal, timeout 15 s, gagal bila sampel latensi < 5; `Access-Control-Expose-Headers: Retry-After`; test HEAD/slash/huruf besar; komentar `wrangler.toml` soal `workers_dev`, log zona, `[limits]`. Dicatat saja: (1) tanpa header `cf-connecting-ip` semua klien berbagi kunci `unknown` - aman di Cloudflare (selalu diisi), tetapi jangan jalankan kode ini di balik proxy lain tanpa mengubahnya; (2) tabel kunci limiter 10.000 entri bisa dikuras penyerang dengan banyak IP dan limiter per isolate - kontrol keras = aturan rate limit Cloudflare; (3) respons buatan platform (error 1101, 413 platform) tidak melewati middleware.

## Catatan handoff
- Limiter di memori per isolate: Cloudflare menjalankan banyak isolate, jadi ini hanya redam kebisingan. Kontrol keras = aturan rate limit Cloudflare di atas.
- `HSTS` tanpa `includeSubDomains`/`preload` (sengaja; domain workers.dev bukan milik kita).
