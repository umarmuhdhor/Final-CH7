# TODO — yang dibutuhkan Imelda (dan diteruskan ke Umar/Alief)

Hal yang tidak bisa diputuskan atau dikerjakan agent sendiri. Centang kalau selesai, tulis jawabannya di kolom Status.

## A. Keputusan

| # | Pertanyaan | Usulan | Status |
|---|---|---|---|
| A1 | Stack service `/analyze` + `/public-blocklist` | Cloudflare Worker + Hono (sama dengan Alief, memudahkan M7) — D-imelda-01 | [x] dipakai Umar: `hono` + `wrangler` di `ai/package.json`, Worker `shoo-ai` live sejak 23 Okt 2026 (M7) |
| A2 | Model LLM untuk M4 | Pilih setelah eval ada. Kandidat (harga per 1 jt token masuk/keluar, 21 Okt 2026): Gemini 2.5 Flash-Lite $0.10/$0.40 · Claude Haiku 5.5 $0.10/$0.50 · GPT-5.4 nano $0.20/$1.25 (Deprecated) | [x] Umar, 23 Okt 2026: `deepseek-v4-flash` lewat `https://bandelbanget.xyz/v1` (D-imelda-36), eval L-5 di D-imelda-37, timeout 6 s di D-imelda-39 |
| A3 | Sumber daftar phishing publik (M5) | Pilih yang lisensinya boleh dipakai di app; catat di `ai/README.md`. Kandidat dicek di fase 05: tabel di `ai/README.md`; rekomendasi tanya PhishTank dulu (lihat log/fase-05.md) | [x] diambil alih Umar, 23 Okt 2026: Phishing.Database (MIT) + daftar pra-bangun di Workers KV (D-imelda-38). KV + secret Action terpasang dan build pertama sukses 24 Okt 2026 (190.000 domain) |
| A4 | Sumber sampel scam untuk M2 | Hanya lewat `capture.mjs`/laporan publik; jangan membuka URL di browser. Cek lisensi sumber | [~] fase 04: OpenPhish/PhishTank/URLhaus tidak dipakai (lisensi); butuh sumber scam nyata berlisensi atau izin tertulis (D-imelda-19) |
| A5 | Gerbang panggilan LLM (D-imelda-05) | Form ≥ 1 field dan skor sementara ≥ 15; situs resmi tidak memanggil | [x] dikonfirmasi Umar, 24 Okt 2026: sudah jalan di produksi (`ai/src/layer4/reality.js`, `GATE_MIN_SCORE = 15`), D-imelda-05 Berlaku |
| A6 | Kebijakan penyedia LLM: tidak melatih dari data API, retensi minimum (SECURITY Q3) | Catat kebijakan penyedia terpilih di DECISIONS saat memilih model. Review #59: penyedia **wajib** zero data retention atau no-training sebelum key dipasang (janji PRD: "dikirim ke `/analyze`, tidak disimpan"); label privasi App Store diperbarui di rilis yang sama | [x] diputuskan Umar dengan risiko (D-imelda-36): penyedia tidak punya kebijakan retensi/training yang bisa diverifikasi, jadi syarat zero data retention **belum terpenuhi**. Pembatas data D-imelda-27 tetap berlaku; privasi + label App Store di #97 (C5). Tinjau ulang bila ada penyedia dengan ZDR tertulis |
| A7 | Sinyal layer 4 tanpa `evidence` (D-imelda-29 vs SECURITY A5) | Tetap tampil tanpa evidence (kontrak: `evidence` opsional). Review #59 minta keputusan lead sebelum layer 4 dinyalakan | [x] #74: boleh tanpa evidence; tidak di-stabilo, label tetap tampil |

## B. Akun dan secret (memblokir fase 06 dan 08)

- [x] B1 Key API LLM (satu penyedia dulu) → `ai/.env` (gitignored). Agent tidak meminta key di chat. — 24 Okt 2026: `LLM_API_KEY`, `LLM_BASE_URL`, `LLM_MODEL` terpasang sebagai secret Worker (`wrangler secret list`, nama saja).
- [x] B2 Akun hosting untuk Worker/service (A1) + domain/URL HTTPS publik. — 23 Okt 2026: akun Cloudflare (Umar), `https://shoo-ai.uumaarrrrr22.workers.dev` (log/fase-08.md).
- [x] B3 Kalau RDAP/WHOIS butuh akun atau kuota berbayar: catat batasnya di fase 03. — Tidak perlu: server RDAP dipilih dari bootstrap publik IANA (`https://data.iana.org/rdap/dns.json`, `ai/src/rdap/rdap.js`), tanpa akun atau kuota berbayar.

## C. Pesan ke tim (Imelda yang mengirim, agent tidak)

| # | Ke | Isi | Status |
|---|---|---|---|
| C1 | Umar | Apakah snapshot menangkap **iframe**? `content.js`/`capture.js` tidak menyebut iframe dan `manifest.json` tanpa `all_frames`. Tanpa itu `asks_pin`/`asks_password` tidak menyala di situs seperti `lphone-login.com` (passcode 6 digit ada di iframe). | [x] #75: form di iframe same-origin dibaca (#79); cross-origin Fase 2 |
| C2 | Umar | `new_domain`: kontrak menulis layer 2, tapi dibuat server (RDAP). `pipeline.js` hanya menerima layer 3–4 dari `/analyze` (`validSignals(remote,[3,4])`), jadi sinyal layer 2 dari server dibuang diam-diam. Usulan: kontrak diubah jadi layer 3. | [x] terjawab: kontrak sudah layer 3 (f95b2ee, #36); fase 03 mengirim layer 3 |
| C3 | Umar | `brands.json` perlu verifikasi manual: `bankbsi.co.id`, `jet.co.id`, `bpjsketenagakerjaan.go.id`. | [x] #76: ketiganya resmi (dicek 23 Okt 2026), `brands.json` tidak diubah |
| C4 | Umar + Alief | Setelah fase 08: kirim URL publik `/analyze` (untuk `ai.baseURL`) dan `/public-blocklist`. | [x] `https://shoo-ai.uumaarrrrr22.workers.dev` (23 Okt 2026); Umar sudah punya, Alief lewat issue #82 |
| C5 | Alief + Umar | **Layer 4 sudah dibangun (mati sampai model dipilih):** host, title halaman dan label field halaman yang lolos gerbang akan dikirim ke penyedia LLM. Kalau data form dikirim ke penyedia LLM, kebijakan privasi/label App Store harus menyebutnya (SECURITY Q4). Kirim setelah model dipilih (fase 06). | [x] #97: dikirim ke Alief (penyedia `bandelbanget.xyz`, `deepseek-v4-flash`); layer 4 sudah live di Worker produksi sejak #95 dan tetap menyala; kebijakan privasi + label App Store menyusul |
| C6 | Umar | Bobot awal sinyal layer 3–4 (ref/R1) untuk dilihat sebelum fase 07 bila ambang 30/50/80 akan berubah. | [x] laporan [log/c6-weight-review.md](log/c6-weight-review.md) (24 Okt 2026): rekomendasi bobot tidak diubah; opsi `brand_logo_offsite` penuh 25 → 30 atau ambang blokir 75 (+2 scam ≥ 80 di tuning, tanpa salah blokir baru); layer 4 tetap 30. Usulan menunggu keputusan Umar |
| C7 | Umar | Sinyal `asks_*` membawa `evidence` = `name`/`id` field (teks dari halaman, bukan substring `snapshot.text`). Extension harus menampilkannya sebagai teks biasa (`textContent`), bukan HTML, dan tidak men-stabilo. | [x] #74: tetap; extension tidak men-stabilo `asks_*`, semua teks lewat `textContent` |
| C8 | Umar | Usulan: tambahkan `accept` (atribut input file) ke `PageSnapshot.forms[].fields` agar `asks_selfie_ktp` bisa memakai `accept=image/*`. Sekarang dipasangkan lewat label/nama. Perubahan kontrak. | [ ] |
| C10 | Umar | `ai/src/blocklist/domains.js` mengimpor `ios/ShooExtension/Resources/psl.js` dan `domain.js` (read-only) agar registrable domain sama dengan extension. Jangan pindahkan tanpa kabar. | [x] dicatat; `ai/` dan `ios/ShooExtension/` sekarang sama-sama dipegang Umar, penanda `TODO(sync:umar)` ada di `domains.js` |
| C9 | Umar | `new_domain` membawa `evidence` = umur dalam hari (string, perintah fase 03). Fixture `blocked-92` tidak punya evidence di sinyal itu. Pastikan extension tidak men-stabilo angka itu (hanya sinyal teks), atau minta kami menghapusnya. | [x] #74: hanya sinyal teks yang di-stabilo (#78); evidence `new_domain` tetap |
| C10 | Umar | `brand_logo_offsite`: evidence diambil dari `imageAlts`/title, yang tidak tampil di body. Extension mungkin tidak menemukannya untuk di-stabilo. Perlu aturan: abaikan saja, atau snapshot memuat teks logo? | [x] #74: abaikan; tanpa stabilo kalau teks tidak ada di body, alasan tetap tampil; snapshot tidak diubah |
| C11 | M7 | `/analyze` tanpa rate limit memicu 2 request keluar ke registry per host baru; cache 1000 entri bisa dibanjiri. Rate limit per IP wajib di M7 (SECURITY A9). Aktifkan adapter KV (`createKvCache`) di M7. | [x] rate limit per IP aktif di kedua endpoint (binding `ANALYZE_LIMITER`/`BLOCKLIST_LIMITER`, M7). Cache RDAP: memori lalu Workers KV (`RDAP_KV`, namespace `shoo-rdap-cache`), dipasang di `src/app.js` dengan anggaran per isolate (D-imelda-40, PR `feat/AI-M7-rdap-kv-cache`). Aktif di produksi setelah Umar menjalankan `cd ai && npm run deploy` |

## D. Langkah manual yang diketahui

- [~] D1 Kumpulkan/izinkan sumber sampel (fase 04): ≥ 50 scam, ≥ 50 legit mirip (login bank, checkout e-commerce). Jumlah terpenuhi (50 + 51), tapi scam nyata hanya 1; sisanya sintetis.
- [x] D2 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` bila ingin uji di simulator (butuh password; dilakukan Imelda). — 24 Okt 2026: `xcode-select -p` sudah `/Applications/Xcode.app/Contents/Developer`; build simulator lulus di #110.
- [ ] D3 Uji di iPhone/Safari sungguhan (belum pernah; risiko App Group di akun Apple gratis).

## E. Opsional

- [ ] E1 Visual hasil eval sebagai PNG untuk dibaca di HP.
