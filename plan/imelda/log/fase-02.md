# Log fase 02 — `POST /analyze` + sinyal form sensitif (M3, bagian pertama)

**Status:** `[~]` kode selesai dan ter-commit di `feat/AI-M3-forms` (dicabangkan dari `feat/AI-M5-detector`, atas pilihan Imelda). Belum push, belum PR (D-imelda-03).
**Tanggal:** 22 Okt 2026

## Rencana singkat
1. D-imelda-01 dijawab: Worker + Hono, JS ESM + JSDoc, `node --test` lewat `app.request()`.
2. Test dulu (kontrak, validasi, 413, batas, 405, tiap sinyal ID+EN+negatif, domain resmi, performa, tanpa log), lihat gagal.
3. Implementasi: aturan kata kunci per kata utuh, tanpa regex, tanpa model.
4. Jalankan lokal, skor sampel eval, dua reviewer, perbaiki temuan.

## File diubah
- `ai/package.json` (+lock, satu dependensi: `hono` 4.13.13, `engines` node ≥ 22), `ai/.gitignore`, `ai/.env.example` (nama saja)
- `ai/src/`: `index.js`, `app.js`, `http.js`, `validate.js`, `limits.js`, `analyze.js`, `dev-server.mjs`, `layer3/{text,forms,signals,official}.js`
- `ai/test/`: `analyze.test.mjs`, `forms.test.mjs`, `helpers.mjs` (62 test)
- `ai/README.md`, `plan/imelda/log/DECISIONS.md`, `TODO.md`, `PROGRESS.md`, `docs/mandates/imelda.md` (centang 2 butir M3)

## Hasil verifikasi (keluaran asli)
- `node --test ai/ detector/test ai/eval/test ios/ShooExtension/Tests` → tests 204, pass 204, fail 0 (sebelumnya 141 + 63 baru).
- `grep -rnE "console\.(log|info|debug)" ai/src` → kosong. Satu `process.stdout.write` di `dev-server.mjs` mencetak hanya alamat dan port.
- `gitleaks protect --staged` → no leaks found. `gitleaks detect` (seluruh riwayat) menemukan 5 hal lama di `backend/` (`push-apns.test.ts`, `README.md`, `vitest.config.ts`), bukan dari fase ini; milik Alief, perlu dilihat.
- Waktu: 190 KB input terbesar lewat curl ≈ 2,5 ms; test unit < 100 ms untuk 300 field × teks 20.000 karakter.

### Skor sampel eval (`node ai/eval/run.mjs --analyze-url http://localhost:8787`)
| Sampel | Layer 2 | Skor total | Sinyal layer 3 |
|---|---|---|---|
| lphone-login (scam) | 39 | **39** | tidak ada |
| fixture-bca-verifikasi, fixture-promo-shopee, fixture-bansos-kemensos (scam, URL saja) | 29 | 29 | tidak ada |
| synthetic-p0stindonesia (scam) | 25 | 25 | tidak ada |
| 8 sampel legit | 0–10 | 0–10 | tidak ada (0 false positive) |

**`lphone-login` belum ≥ 80 (skor 39). Sebabnya:** sampel seed itu `forms: []`; passcode 6 digit dan login Apple ID ada di iframe (`meta.iframes`), tidak ada di `snapshot.forms`. Snapshot extension kemungkinan juga tidak menangkap iframe (TODO C1, belum dijawab Umar). Sampel URL-saja lain juga tanpa form. Ini bukan kegagalan aturan.
Bukti aturan bekerja bila iframe ikut tertangkap (uji ad-hoc lewat curl, bukan sampel eval): field `password` + `passcode` di `lphone-login.com` → `asks_pin` 35 + `asks_password` 15 = 50; 39 + 50 = **89 ≥ 80**. (Perkiraan R1 "+65 → 100" terlalu tinggi karena tidak ada field OTP/kartu di halaman itu.)

## DoD
- [x] `/analyze` sesuai `contracts/api.md`; test kontrak membandingkan bentuk dengan `blocked-92.json` dan `warning-63.json` (`asks_pin`, `asks_ktp`: kunci sama, evidence sama, bobot dalam ±10).
- [x] Tiap `asks_*`: test positif ID + EN, negatif; domain resmi tanpa sinyal.
- [~] `lphone-login`: skor tercatat jujur = 39; alasan di atas, rujuk TODO C1.
- [x] Tanpa log isi halaman: grep kosong + test spy console/stdout/stderr di semua jalur + review.
- [x] Layer 3 tanpa LLM, tanpa jaringan.
- [x] security-reviewer dijalankan; tak ada CRITICAL; satu HIGH ditutup.

## Temuan review
**security-reviewer** (0 CRITICAL):
- HIGH H1 — subdomain konten-pengguna dari domain resmi (`docs.google.com/forms`, `sites.google.com`, `forms.office.com`) ikut dikecualikan → form scam di sana lolos. **Ditutup:** daftar host konten-pengguna (`official.js`), test.
- MEDIUM M1 — kata "negatif" di atribut lain mematikan sinyal (`{name:"pin", id:"zip"}`). **Ditutup:** pengecualian hanya berlaku di atribut yang sama; test.
- MEDIUM M2 — karakter tak terlihat, huruf full-width, homoglif Cyrillic. **Ditutup:** NFKC + buang karakter tak terlihat + peta homoglif Cyrillic (`text.js`); test. Sisa: homoglif non-Cyrillic lain belum dipetakan.
- LOW: host > 253 karakter **ditutup** (ditolak 400); `engines` **ditambah**. Content-Type tidak dicek (tanpa CORS dan tanpa state, dampak nol). L1 `evidence` = nama field bukan substring teks → catatan kontrak di TODO C7. L4 pastikan wrangler membundel JSON dari `detector/` (cek di fase 08).
- A1, A2 n/a (tanpa LLM/jaringan keluar). A3, A4, Q1, Q2 PASS. A5 sebagian (lihat C7). A9 ditunda ke fase 08 (sesuai rencana).

**code-reviewer** (0 CRITICAL, 2 HIGH): semua ditutup lewat test baru.
- "kode keamanan"/"security code" (captcha) menyalakan `asks_cvv` → sekarang butuh konteks kartu.
- "Nomor Induk Mahasiswa"/"Employee ID card number" menyalakan `asks_ktp`/`asks_card` → "nomor induk kependudukan" saja; kartu sekolah/kantor dikecualikan.
- "One-time donation", "Pin location", NBSP/ellipsis, "Kode Pos / PIN" (tidak lagi ditekan), mpin, selfie profil + NIK tidak lagi berpasangan, kode mati `PRIORITY` dihapus.
- Tidak diambil: password hanya `type=password` (sesuai spesifikasi h); nama depan "Nik" (jarang).

## Deviasi dari prompt
- Cabang dari `feat/AI-M5-detector`, bukan `origin/main` (pilihan Imelda; M5 belum merge).
- Test "kode keamanan"/"security code" polos diubah jadi butuh konteks kartu setelah review (perubahan perilaku disengaja, bukan melemahkan test).
- Format error 405 `method_not_allowed` tidak ada di daftar kode `contracts/api.md` (D-imelda-09).
- Batas rate limit (A9, test 429) belum dibuat; fase 08/M7.
- Sampel "wajib" asks_selfie_ktp memakai pasangan field karena `PageSnapshot` tidak punya atribut `accept` (TODO C8).

## Catatan handoff
- Fase 03 menambah `urgent_language`, `brand_logo_offsite`, `new_domain` di `src/analyze.js` (satu titik sambung) dan perlu jawaban C2.
- Risiko false positive yang diketahui, dikalibrasi fase 06/07: situs non-brand yang sah meminta OTP/kartu/KTP (mis. KYC fintech) akan memicu 30–35 sendirian; R1 menetapkan bobot ini, D-imelda-04 menyarankan kasus ambigu < 30.
- Sinyal ini baru menyala di lapangan jika iframe tertangkap (C1).
