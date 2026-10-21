# Fase 07 — rencana eksekusi (writing-plans, ringkas)

Branch `feat/BE-devices`, ditumpuk di atas `docs/alief-plan-sync` (PR #7, belum di-merge). Sumber: `fase-07-be-fondasi.md`, `contracts/api.md`, R2, R3, D-alief-38.

Catatan: rencana ditulis langsung oleh agent sesi (konteks plan sudah lengkap dibaca), tanpa memanggil agent `ecc:planner` terpisah.

| # | Langkah | Test dulu | Selesai kalau |
|---|---|---|---|
| 1 | `supabase init` di `backend/db`, `project_id = "shoo"`, `supabase start -x …` | – | container hidup |
| 2 | pgTAP `schema.test.sql` (I1–I6, I8) + `grants.test.sql` (I7, I9, RLS, bucket private) | ya | `supabase test db` hijau |
| 3 | Migrasi `…_init.sql`: enum, 9 tabel R2 + `rate_limit_hits` (D-alief-B02), trigger I1/I3/I4, role `shoo_api` tanpa password, grant, revoke anon/authenticated, RLS + policy, bucket `screenshots` private. `seed.sql`: password lokal, device fixture, 1 domain disetujui | – | `db reset` + pgTAP hijau |
| 4 | `backend/api`: package.json, tsconfig, wrangler.jsonc (Hyperdrive id placeholder + localConnectionString), vitest.config.ts (`cloudflareTest` + `miniflare.hyperdrives`) | – | `pnpm install`, `typecheck` |
| 5 | `http/`: errors (bentuk kontrak), validate (413/400/422), auth (Bearer → sha256 → principal), rateLimit, crypto | lewat test route | – |
| 6 | `POST /devices`, `PATCH /devices/me` (incl. `extensionLastSeenAt`) | `devices.test.ts` | 201, token sekali, hash, 401, 422, rate limit |
| 7 | `GET /blocklist?since=` (approved saja, `removed[]`, paging per waktu kejadian) | `blocklist.test.ts` | urutan, cursor mikrodetik, paging 1001 |
| 8 | `/healthz`, `/healthz/db` | `health.test.ts` | heartbeat ditulis, 429 |
| 9 | `services/push/jwt.ts` + `POST /debug/apns-spike` | `apns.test.ts` | JWT terverifikasi, 404 tanpa flag |
| 10 | Draf CI `backend/ci/backend.yml` + README | – | – |
| 11 | `backend/README.md`, `.gitignore`, `.env.example`, `.dev.vars.example` | – | – |
| 12 | Verifikasi lokal (blok Verifikasi fase), log, LANGKAH MANUAL, status `[m]`, push branch, BERHENTI | – | checklist di `log/fase-07.md` |

Setelah Alief menjalankan LANGKAH MANUAL: hasil spike → `D-alief-B01`, review (`ecc:typescript-reviewer`, `ecc:database-reviewer`, `ecc:security-reviewer`), PR ke `main` (reviewer umarmuhdhor, "Stacked on #7").
