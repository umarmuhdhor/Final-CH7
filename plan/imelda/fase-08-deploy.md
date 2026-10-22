# Fase 08 — Deploy `/analyze` + `/public-blocklist` (M7)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M7-deploy` |
| Prasyarat | Fase 02, 05 (dan idealnya 07). Akun hosting (TODO B2) |
| Requirement | M7: URL publik HTTPS, rate limit per IP, batas body ±200 KB, kedua endpoint di URL sama |
| Review | `ecc:security-reviewer` wajib |
| Sifat | Aksi cloud = **LANGKAH MANUAL**; status `[m]` |

## Tujuan

URL publik yang dipakai Umar (`ai.baseURL`) dan extension (daftar publik).

## Bacaan wajib

- `contracts/api.md`, `plan/alief/SECURITY.md` (pola Worker Alief sebagai rujukan), `ai/README.md`

## Langkah kerja

1. Tambah rate limit per IP dan batas ukuran body (413 lebih awal) untuk kedua endpoint. Test dulu.
2. Header keamanan, tanpa log URL/teks/form, CORS sesuai kebutuhan extension.
3. Siapkan perintah deploy + secret (`.env` → secret hosting) dan tulis checklist **LANGKAH MANUAL** di `log/fase-08.md`; set `[m]`, berhenti.
4. Setelah Imelda menempel hasil: smoke test `curl` ke URL publik (`/analyze` dengan fixture, `/public-blocklist`), ukur p95.
5. Imelda mengirim URL ke Umar dan Alief (TODO C4); agent tidak mengirim pesan.

## Verifikasi

```bash
curl -s -X POST "$AI_URL/analyze" -H 'content-type: application/json' -d @<fixture-snapshot>.json | head -c 400
curl -s "$AI_URL/public-blocklist" | head -c 200
```

## Kriteria selesai (DoD)

- [ ] Kedua endpoint hidup di HTTPS publik; smoke test hijau.
- [ ] Rate limit dan batas body teruji (429/413).
- [ ] p95 `/analyze` < 8 s tercatat.
- [ ] Tidak ada secret/URL halaman di log; `.env.example` terbaru.
- [ ] URL dikirim ke Umar dan Alief oleh Imelda (TODO C4 dicentang).
