# Fase 12 — Retensi 14 hari, hardening, deploy cloud, workflow final

| Field | Nilai |
|---|---|
| Track | be |
| Branch | `feat/BE-retention-hardening` |
| Prasyarat | 11 |
| Requirement | Mandat Fase B Retensi + Keamanan; PRD §10 |
| Model | Opus 5.5 · `ecc:deployment-patterns` |
| Fase berikutnya | track be selesai → 13 (setelah 06Q) |

## Tujuan

Data scan + screenshot hilang otomatis setelah 14 hari, semua endpoint lolos review keamanan, stack cloud lengkap dan dipantau, dan draf GitHub Action siap dipasang Umar.

## Bacaan wajib

- `ref/R4` §5, `ref/R2` §6, `SECURITY.md` (seluruhnya), `ARCHITECTURE.md` §3

## Langkah kerja

1. `cron/retention.ts` (R4 §5) + `triggers.crons: ["0 19 * * *"]` di `wrangler.jsonc`. Test dengan `scheduled()` + data mundur 15 hari: scan terhapus, objek Storage terhapus, path dedupe yang masih dipakai tidak terhapus.
2. Hardening: body limit global, header keamanan (`x-content-type-options`, CSP di `/join`), CORS ditutup (klien native tidak butuh CORS), semua rate limit R3 §5 diuji, log tanpa PII/token (grep test).
3. Review penuh: `ecc:security-reviewer` + `ecc:database-reviewer` atas seluruh `backend/`. Tutup CRITICAL/HIGH. Ringkas di log.
4. Cek kuota: hitung ukuran DB + Storage di Supabase lokal untuk 1000 scan seed; ekstrapolasi terhadap 500 MB / 1 GB. Cek apakah query lewat pooler dihitung aktivitas (tanya docs Supabase "project pausing"); kalau tidak, monitor B9 diarahkan ke endpoint yang memakai Storage API.
5. Finalisasi `backend/ci/backend.yml` + `backend/ci/README.md`; tulis C2.
6. `backend/README.md` final: setup lokal, env, deploy manual, rollback (`wrangler rollback`, migrasi maju saja), cara mengecek kuota.
7. LANGKAH MANUAL deploy final + uji asap cloud (semua endpoint dengan dua device uji).

## Verifikasi

```bash
cd backend/db && supabase db reset && supabase test db
pnpm -C backend/api typecheck && pnpm -C backend/api test
gitleaks detect --source . --no-banner || true
```

## Kriteria selesai (DoD)

- [ ] Retensi terbukti (test) dan cron terdaftar di cloud (`wrangler deployments`/dashboard).
- [ ] Tidak ada temuan CRITICAL/HIGH terbuka.
- [ ] Uji asap cloud lulus; G6 `[x]`.
- [ ] C2 tertulis untuk Umar.
