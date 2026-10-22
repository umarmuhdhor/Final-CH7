# Fase 02 — `POST /analyze` + sinyal form sensitif (M3a)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M3-forms` |
| Prasyarat | Gate G1 (D-imelda-01: stack Worker + Hono) |
| Requirement | M3: service `/analyze`, `asks_pin`, `asks_otp`, `asks_password`, `asks_card`, `asks_cvv`, `asks_ktp`, `asks_selfie_ktp` |
| Review | `ecc:security-reviewer` wajib (menerima isi halaman) |
| Fase berikutnya | 03 |

## Tujuan

Service stateless yang menerima `PageSnapshot` dan mengembalikan sinyal layer 3 dari form. Sampel pembuktian: `lphone-login.com` (passcode iPhone 6 digit + login Apple ID) harus menghasilkan sinyal yang membawa skor total ke blokir.

## Bacaan wajib

- `contracts/api.md` bagian `/analyze` (bentuk request/respons persis), `contracts/detector-interface.md` (`PageSnapshot`)
- `contracts/fixtures/blocked-92.json`, `warning-63.json`
- `ai/eval/data/*/seed.json` (sampel `lphone-login`)
- `ai/CLAUDE.md`

## Langkah kerja

1. Struktur `ai/` (Worker + Hono) sesuai D-imelda-01; `ai/.env.example` tanpa nilai rahasia.
2. Validasi body: batas ukuran (±200 KB), tolak bentuk salah dengan error sesuai `contracts/api.md`.
3. Test dulu per sinyal: kata kunci Indonesia + English dari `forms[].fields` (`label`, `name`, `placeholder`, `autocomplete`). Contoh: "kode sandi", "passcode", "PIN", "OTP", "CVV", "KTP", "selfie".
4. Aturan false positive: kolom `type=password` di halaman login resmi tidak otomatis berbahaya; domain resmi (`brands.json`) → tanpa sinyal.
5. `label` dan `labelSimple` EN + ID per sinyal. `evidence` = nama/label field persis.
6. **Tanpa log** URL, teks, atau isi form. Hanya status dan durasi.
7. Jalankan sampel `lphone-login` lewat `ai/eval/run.mjs --analyze-url` dan catat skor total (perkiraan awal layer 3 ≈ +65 → 100).

## Verifikasi

```bash
node --test ai/ detector/test ai/eval/test ios/ShooExtension/Tests
node ai/eval/run.mjs --analyze-url http://localhost:8787
```

## Kriteria selesai (DoD)

- [ ] `/analyze` sesuai `contracts/api.md` (test kontrak dengan fixture).
- [ ] Setiap sinyal `asks_*` punya test positif (ID + EN) dan test negatif (form resmi/biasa).
- [ ] `lphone-login` mencapai ≥ 80 bersama layer 2 (atau catat selisih + alasan; iframe → TODO C1).
- [ ] Tidak ada log isi halaman (review + grep).
- [ ] Layer 3 menjawab tanpa LLM.

## Catatan handoff

- Jawaban Umar soal iframe (TODO C1) menentukan apakah sinyal ini nyala di lapangan.
