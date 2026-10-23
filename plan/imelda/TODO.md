# TODO — yang dibutuhkan Imelda (dan diteruskan ke Umar/Alief)

Hal yang tidak bisa diputuskan atau dikerjakan agent sendiri. Centang kalau selesai, tulis jawabannya di kolom Status.

## A. Keputusan

| # | Pertanyaan | Usulan | Status |
|---|---|---|---|
| A1 | Stack service `/analyze` + `/public-blocklist` | Cloudflare Worker + Hono (sama dengan Alief, memudahkan M7) — D-imelda-01 | [ ] tunggu Imelda |
| A2 | Model LLM untuk M4 | Pilih setelah eval ada. Kandidat (harga per 1 jt token masuk/keluar, 21 Okt 2026): Gemini 2.5 Flash-Lite $0.10/$0.40 · Claude Haiku 5.5 $0.10/$0.50 · GPT-5.4 nano $0.20/$1.25 (Deprecated) | [ ] |
| A3 | Sumber daftar phishing publik (M5) | Pilih yang lisensinya boleh dipakai di app; catat di `ai/README.md`. Kandidat dicek di fase 05: tabel di `ai/README.md`; rekomendasi tanya PhishTank dulu (lihat log/fase-05.md) | [ ] tunggu Imelda |
| A4 | Sumber sampel scam untuk M2 | Hanya lewat `capture.mjs`/laporan publik; jangan membuka URL di browser. Cek lisensi sumber | [~] fase 04: OpenPhish/PhishTank/URLhaus tidak dipakai (lisensi); butuh sumber scam nyata berlisensi atau izin tertulis (D-imelda-19) |
| A5 | Gerbang panggilan LLM (D-imelda-05) | Form ≥ 1 field dan skor sementara ≥ 15; situs resmi tidak memanggil | [ ] tunggu Imelda |
| A6 | Kebijakan penyedia LLM: tidak melatih dari data API, retensi minimum (SECURITY Q3) | Catat kebijakan penyedia terpilih di DECISIONS saat memilih model | [ ] |

## B. Akun dan secret (memblokir fase 06 dan 08)

- [ ] B1 Key API LLM (satu penyedia dulu) → `ai/.env` (gitignored). Agent tidak meminta key di chat.
- [ ] B2 Akun hosting untuk Worker/service (A1) + domain/URL HTTPS publik.
- [ ] B3 Kalau RDAP/WHOIS butuh akun atau kuota berbayar: catat batasnya di fase 03.

## C. Pesan ke tim (Imelda yang mengirim, agent tidak)

| # | Ke | Isi | Status |
|---|---|---|---|
| C1 | Umar | Apakah snapshot menangkap **iframe**? `content.js`/`capture.js` tidak menyebut iframe dan `manifest.json` tanpa `all_frames`. Tanpa itu `asks_pin`/`asks_password` tidak menyala di situs seperti `lphone-login.com` (passcode 6 digit ada di iframe). | [ ] |
| C2 | Umar | `new_domain`: kontrak menulis layer 2, tapi dibuat server (RDAP). `pipeline.js` hanya menerima layer 3–4 dari `/analyze` (`validSignals(remote,[3,4])`), jadi sinyal layer 2 dari server dibuang diam-diam. Usulan: kontrak diubah jadi layer 3. | [x] terjawab: kontrak sudah layer 3 (f95b2ee, #36); fase 03 mengirim layer 3 |
| C3 | Umar | `brands.json` perlu verifikasi manual: `bankbsi.co.id`, `jet.co.id`, `bpjsketenagakerjaan.go.id`. | [ ] |
| C4 | Umar + Alief | Setelah fase 08: kirim URL publik `/analyze` (untuk `ai.baseURL`) dan `/public-blocklist`. | [ ] |
| C5 | Alief + Umar | Kalau data form dikirim ke penyedia LLM, kebijakan privasi/label App Store harus menyebutnya (SECURITY Q4). Kirim setelah model dipilih (fase 06). | [ ] |
| C6 | Umar | Bobot awal sinyal layer 3–4 (ref/R1) untuk dilihat sebelum fase 07 bila ambang 30/50/80 akan berubah. | [ ] |
| C7 | Umar | Sinyal `asks_*` membawa `evidence` = `name`/`id` field (teks dari halaman, bukan substring `snapshot.text`). Extension harus menampilkannya sebagai teks biasa (`textContent`), bukan HTML, dan tidak men-stabilo. | [ ] |
| C8 | Umar | Usulan: tambahkan `accept` (atribut input file) ke `PageSnapshot.forms[].fields` agar `asks_selfie_ktp` bisa memakai `accept=image/*`. Sekarang dipasangkan lewat label/nama. Perubahan kontrak. | [ ] |
| C10 | Umar | `ai/src/blocklist/domains.js` mengimpor `ios/ShooExtension/Resources/psl.js` dan `domain.js` (read-only) agar registrable domain sama dengan extension. Jangan pindahkan tanpa kabar. | [ ] |
| C9 | Umar | `new_domain` membawa `evidence` = umur dalam hari (string, perintah fase 03). Fixture `blocked-92` tidak punya evidence di sinyal itu. Pastikan extension tidak men-stabilo angka itu (hanya sinyal teks), atau minta kami menghapusnya. | [ ] |
| C10 | Umar | `brand_logo_offsite`: evidence diambil dari `imageAlts`/title, yang tidak tampil di body. Extension mungkin tidak menemukannya untuk di-stabilo. Perlu aturan: abaikan saja, atau snapshot memuat teks logo? | [ ] |
| C11 | M7 | `/analyze` tanpa rate limit memicu 2 request keluar ke registry per host baru; cache 1000 entri bisa dibanjiri. Rate limit per IP wajib di M7 (SECURITY A9). Aktifkan adapter KV (`createKvCache`) di M7. | [ ] |

## D. Langkah manual yang diketahui

- [~] D1 Kumpulkan/izinkan sumber sampel (fase 04): ≥ 50 scam, ≥ 50 legit mirip (login bank, checkout e-commerce). Jumlah terpenuhi (50 + 51), tapi scam nyata hanya 1; sisanya sintetis.
- [ ] D2 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` bila ingin uji di simulator (butuh password; dilakukan Imelda).
- [ ] D3 Uji di iPhone/Safari sungguhan (belum pernah; risiko App Group di akun Apple gratis).

## E. Opsional

- [ ] E1 Visual hasil eval sebagai PNG untuk dibaca di HP.
