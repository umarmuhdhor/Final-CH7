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
3. `GET /blocklist` memakai verdict asli. Test peracunan dicatat (T5) dan usulan C6 ditulis di PR.
4. Mapping `verdict` ke ScanResult (fase 09) memakai data asli; test cocok dengan dua fixture verdict.
5. `ecc:security-reviewer` fokus T5, T10.
6. LANGKAH MANUAL deploy, lalu kirim C8 ke Umar (G4).

## Verifikasi

```bash
pnpm -C backend/api test -- verdicts blocklist
```

Test wajib: Protected → 403; Guardian lain → 404; scan warning → 409; safe lalu not_safe → keputusan terakhir menang; verdict berlaku untuk scan lain di domain sama milik pemilik sama; tidak berlaku untuk pemilik lain; `www.Example.com` = `example.com`; not_safe muncul di `/blocklist?since=` dan `nextSince` maju.

## Kriteria selesai (DoD)

- [ ] Semua test hijau; bentuk `Verdict` cocok fixture.
- [ ] Polling `GET /verdicts?domain=` p95 < 300 ms di cloud (ukur 20 request, catat di log) — memenuhi "Halaman langsung terbuka" bersama polling 5 s.
- [ ] C6 dan C8 tertulis.
