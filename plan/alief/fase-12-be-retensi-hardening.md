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

1. `cron/retention.ts` (R4 §5: maks 10 batch per run, satu `DELETE /storage/v1/object/screenshots` dengan `prefixes` per batch, lalu upsert `ops_heartbeat`) + `triggers.crons: ["0 19 * * *"]` di `wrangler.jsonc`. Test vitest memanggil handler `scheduled()` + data mundur 15 hari: scan terhapus, objek Storage terhapus (Storage lokal Supabase), path dedupe yang masih dipakai scan < 14 hari tidak terhapus, > 10 batch → sisa dihapus run berikutnya. Uji lokal: `curl "http://localhost:8787/cdn-cgi/local/scheduled?cron=0+19+*+*+*"` (butuh `wrangler dev --test-scheduled`).
2. Hardening: body limit global, header keamanan (`x-content-type-options`, CSP di `/join`), CORS ditutup (klien native tidak butuh CORS), semua rate limit R3 §5 diuji, log tanpa PII/token (grep test).
3. Review penuh: `ecc:security-reviewer` + `ecc:database-reviewer` atas seluruh `backend/`. Tutup CRITICAL/HIGH. Ringkas di log.
4. Cek kuota: hitung ukuran DB + Storage di Supabase lokal untuk 1000 scan seed; ekstrapolasi terhadap 500 MB DB / 1 GB Storage / 5 GB egress. Pemicu migrasi ke R2 (`ScreenshotStore`): Storage > 700 MB atau egress > 3,5 GB (ARCHITECTURE §3). Anti-pause: cron harian + `/healthz/db` sama-sama menulis `ops_heartbeat` (bukan `select 1`), monitor B9 memanggil `/healthz/db`.
5. Finalisasi `backend/ci/backend.yml` + `backend/ci/README.md`; tulis C2.
6. `backend/README.md` final: setup lokal, env, deploy manual, rollback (`wrangler rollback`, migrasi maju saja), cara mengecek kuota.
7. LANGKAH MANUAL deploy final dari `main` setelah PR 07–11 di-merge (D-alief-27) + uji asap cloud (semua endpoint dengan dua device uji, CPU per request dari `wrangler tail`).

## Verifikasi

```bash
(cd backend/db && supabase start && supabase db reset && supabase test db)
pnpm -C backend/api typecheck && pnpm -C backend/api test
(pnpm -C backend/api exec wrangler dev --test-scheduled > /tmp/shoo-dev.log 2>&1 &) && pnpm -C backend/api exec wait-on tcp:8787
curl -s "http://localhost:8787/cdn-cgi/local/scheduled?cron=0+19+*+*+*"
pkill -f "wrangler dev" || true
gitleaks detect --source . --no-banner   # harus 0 temuan
```

## Kriteria selesai (DoD)

- [ ] Retensi terbukti (test + trigger lokal) dan cron terdaftar di cloud (screenshot dashboard Worker → Settings → Triggers), satu run cloud tercatat di `ops_heartbeat` (query SQL editor).
- [ ] Tidak ada temuan CRITICAL/HIGH terbuka.
- [ ] Uji asap cloud lulus. G6 terpenuhi setelah semua PR 07–12 di-merge Umar (diperbarui di PROMPT langkah 1).
- [ ] `gitleaks` 0 temuan.
- [ ] C2 tertulis untuk Umar.
