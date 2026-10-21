# Fase 10 — Verdicts per domain + blocklist dari verdict

| Field | Nilai |
|---|---|
| Track | be |
| Branch | `feat/BE-verdicts` |
| Prasyarat | 09 |
| Requirement | Mandat Fase B Verdicts (`POST /verdicts` per domain, `GET /verdicts?domain=`), Blocklist; EX-06 (sisi server), GD-07 (sisi server) |
| Model | Opus 5.5 |
| Fase berikutnya | 11 |

## Tujuan

Guardian memutuskan Safe / Not safe untuk satu domain milik pemilik scan, extension Protected bisa polling hasilnya untuk membuka layar blokir, dan domain Not safe masuk blocklist layer 1.

## Bacaan wajib

- `contracts/api.md` Verdicts + Blocklist, fixture `blocked-verified-scam.json`, `blocked-marked-safe.json`
- `ref/R2` verdicts + §5, `ref/R3` §3–§5, `ref/R4` §4, `SECURITY.md` T5, T10

## Langkah kerja

1. `POST /verdicts { scanId, value }` (guardian): scan harus milik saya atau Protected aktif saya (selain itu 404), status `blocked` (selain itu 409 `verdict_not_allowed`), upsert `(owner_id, domain)` → `{ verdict }`.
2. `GET /verdicts?domain=` (semua): normalisasi domain (lowercase, tanpa `www.`), `{ verdict: Verdict | null }` untuk `owner = me`. Rate limit 1 req/2 s.
3. `GET /blocklist` memakai verdict asli dengan filter bawaan R2 §5 (scan milik Protected terhubung, `BLOCKLIST_MIN_FAMILIES`, allowlist `src/data/allowlist.ts`). Kalau Umar/Imelda sudah menjawab C6, ikuti jawabannya. Usulan `removed` (D-alief-18) ditulis di PR.
4. Mapping `verdict` ke ScanResult (fase 09) memakai data asli, hanya untuk scan `blocked`; test cocok dengan dua fixture verdict.
5. `ecc:security-reviewer` fokus T5, T10.
6. LANGKAH MANUAL deploy + **uji cloud**: buat Guardian + Protected uji, join, `POST /scans` blocked, `POST /verdicts safe`, lalu ukur `GET /verdicts?domain=` sebagai Protected 20× melalui Worker cloud (bukan lokal) → harus `safe` di request pertama (≤ 1 s setelah POST) dan p95 < 300 ms. Tempel angka di log. Lalu kirim C8 ke Umar (G4).

## Verifikasi

```bash
pnpm -C backend/api exec vitest run verdicts blocklist
```

Test wajib: Protected → 403; Guardian lain → 404; scan warning → 409; safe lalu not_safe → keputusan terakhir menang; verdict berlaku untuk scan lain di domain sama milik pemilik sama; tidak berlaku untuk pemilik lain; `www.Example.com` = `example.com`; not_safe atas scan Protected muncul di `/blocklist?since=` dan `nextSince` maju; **Guardian baru + scan palsu miliknya sendiri + not_safe → TIDAK masuk `/blocklist`**; domain allowlist tidak pernah masuk; scan warning di domain ber-verdict tetap `verdict: null`.

## Kriteria selesai (DoD)

- [ ] Semua test hijau; bentuk `Verdict` cocok fixture.
- [ ] Uji cloud langkah 6: `safe` terlihat di `GET /verdicts` pertama setelah POST (cache Hyperdrive mati), p95 < 300 ms — bersama polling 5 s memenuhi "halaman terbuka ≤ 10 s".
- [ ] C6 dan C8 tertulis.
