# backend

API for devices, family, scans, verdicts, push. Spec: `contracts/api.md` (source of truth for every JSON shape).

Stack: Cloudflare Worker `shoo-api` (Hono, zod, postgres.js) → Hyperdrive (`--caching-disabled`) → Supabase Postgres + private Storage bucket `screenshots`. Plan: `plan/alief/ARCHITECTURE.md`.

```text
backend/
├── api/            Worker (TypeScript). src/{app,env,index}.ts, routes/, http/, db/, services/
├── db/supabase/    config.toml, migrations/, tests/ (pgTAP), seed.sql (local only)
└── ci/             draft GitHub Action (inert, see ci/README.md)
```

## Local setup

Needs Node 24, pnpm, Docker, Supabase CLI. Run from the repo root.

```bash
(cd backend/db && supabase start -x studio,imgproxy,edge-runtime,logflare,vector,mailpit,realtime,postgres-meta,supavisor)
(cd backend/db && supabase db reset && supabase test db)   # migrations + seed + pgTAP
pnpm -C backend/api install
pnpm -C backend/api typecheck && pnpm -C backend/api test  # vitest inside workerd, against local Postgres
cp backend/api/.dev.vars.example backend/api/.dev.vars     # once
pnpm -C backend/api dev                                    # http://localhost:8787
```

- The Worker reaches local Postgres through the Hyperdrive binding `DB` (`localConnectionString` in `api/wrangler.jsonc`) as role `shoo_api` with the dev-only password `shoo_api_local` from `seed.sql`.
- Tests empty all tables before each test (`api/test/helpers/resetDb.ts`). Run `supabase db reset` to get the seed data back.
- Seed devices (local only): `dev_me` (guardian), `dev_mom`, `dev_dad` (protected). Bearer value `shoo_local_<id>`, e.g. `curl localhost:8787/blocklist -H "authorization: Bearer shoo_local_dev_me"`.

## Endpoints (so far)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/healthz` | – | `{ ok: true }`, no DB |
| GET | `/healthz/db` | – | writes `ops_heartbeat` (keeps Supabase Free awake), 1/min per IP |
| POST | `/devices` | – | `{ name, mode, apnsToken? }` → `201 { deviceId, token, avatarId }`; 10/h per IP |
| GET | `/devices/me` | Bearer | `{ deviceId, name, avatarId, mode, language, guardian \| null }` |
| PATCH | `/devices/me` | Bearer | `{ name?, apnsToken?, language?, extensionLastSeenAt? }` → `{ ok: true }` |
| DELETE | `/devices/me` | Bearer | proposal C19: deletes the device and all its data → `{ ok: true }` |
| POST | `/family/code` | Bearer guardian | `{ code, expiresAt, inviteUrl }`, 60 s, replaces the old code; 6/min; `503 code_unavailable` |
| POST | `/family/join` | Bearer protected | `{ code }` → `{ guardian }`; failures 5/10 min per device, 20/10 min per IP (`too_many_attempts` + `Retry-After`) |
| GET | `/family/members` | Bearer guardian | `{ members: [{ deviceId, name, avatarId, extensionActive, lastScan }] }` |
| DELETE | `/family/members/{deviceId}` | Bearer guardian | `{ ok: true }`, 404 if not my member |
| DELETE | `/family/guardian` | Bearer protected | `{ ok: true }`, 404 if not connected |
| GET | `/join?code=` | – | HTML invite page (EN/ID by Accept-Language) → `shoo://join?code=`; strict CSP; no DB lookup |
| POST | `/scans` | Bearer | contract ScanResult body (+ `screenshotBase64?`) → `201 { id }`; owner = token device; 120/h per device. Screenshot: JPEG/PNG ≤ 150 KB, ≤ 1280 px, dedupe same domain 24 h, 50/24 h per device, otherwise dropped (scan still 201) |
| GET | `/scans?owner=me\|family\|<deviceId>&status=&cursor=&limit=` | Bearer | `{ items, nextCursor }`, newest first, limit 1–50 (20); `family` guardian only (403), unknown member 404 |
| GET | `/scans/{id}` | Bearer | one ScanResult, `screenshotUrl` = 1 h Worker link for this viewer; 404 unless own scan or my member's scan |
| GET | `/screenshots/{scanId}?v=&exp=&sig=` | link signature | the image, `Cache-Control: private, no-store`; access re-checked in the DB on every request (deleted scan, disconnect → 404 at once) |
| POST | `/verdicts` | Bearer guardian | `{ scanId, value: safe\|not_safe }` → `{ verdict }` for the scan's owner + domain; 404 unknown scan, 403 `verdict_not_allowed` (not mine and not my member's), 409 `verdict_not_allowed` (not blocked); 60/min. A `not_safe` on a connected member's scan queues the domain for review (allowlist excluded) |
| GET | `/verdicts?domain=` | Bearer | `{ verdict \| null }` for (me, domain); domain normalized (case, `www.`); 10 per 10 s per device with `Retry-After` |
| GET | `/blocklist?since=` | Bearer | approved global domains; `removed[]` only with `since`; `nextSince` has microseconds |
| POST | `/debug/apns-spike` | `x-spike-key` | fase 07 spike only, 404 unless `APNS_SPIKE=1` (removed in fase 11) |

Errors always `{ "error": { "code", "message" } }`; `429` carries `Retry-After`.
Every response is `Cache-Control: private, no-store` (user data, SECURITY §3 P13) except `GET /blocklist` (`private, max-age=300`). Workers invocation logs are off; logs never carry ids, names, URLs or tokens.

## Schema summary

Migrations: `db/supabase/migrations/20261021130000_init.sql`, `20261021150000_blocklist_times.sql`, `20261021160000_family.sql`, `20261021170000_screenshot_bucket.sql`, `20261021180000_verdicts.sql` (details: `plan/alief/ref/R2-skema-db.md`).

| Table | Purpose |
|---|---|
| `devices` | one row per installed app. `token_hash` = sha256(token), the token itself is never stored. `mode` immutable (trigger). `ext_last_seen_at` from `extensionLastSeenAt` |
| `family_links` | protected → guardian (PK on protected = one guardian each; trigger: modes match, max 3 per guardian) |
| `family_codes`, `join_attempts` | 4-digit codes (60 s) and join attempts for rate limiting; attempts keep `ip_hash` = sha256(`join:ip-or-/64`), never a raw IP |
| `scans` | Activity items, score 30–100, status consistent with score, domain lowercase without `www.`. `screenshot_path` = `<ownerId>/<scanId>.jpg\|png` in bucket `screenshots` (private, 150 KB, JPEG/PNG only); dedupe means several scans can share one path |
| `verdicts` | one per (owner, domain), last decision wins; `global_eligible` = blocklist eligibility snapshot taken at decision time (connected protected owner, not on `api/src/data/allowlist.ts`) |
| `blocklist_entries` | review queue + global list; only rows with `approved_at` (and no `removed_at`) are served |
| `ops_heartbeat` | one row per writer (`healthz`, `cron`) |
| `push_log` | push results for debugging and QA (fase 11) |
| `rate_limit_hits` | sliding-window counters; key is sha256(`bucket:ip-or-device`), never a raw IP |

Access: role `shoo_api` (no password in migrations) has CRUD on these tables only. `anon`/`authenticated` have no grants; RLS is on everywhere with a single `shoo_api` policy. No RPCs: the Worker uses plain SQL through postgres.js tagged templates.

Approving a blocklist domain (Supabase SQL editor). A trigger stamps `approved_at`/`removed_at` with `clock_timestamp()` on every UPDATE, so bulk approvals and re-approvals after a removal page correctly:

```sql
select domain, families, first_seen_at from blocklist_entries
 where approved_at is null and removed_at is null and families > 0 order by families desc, first_seen_at;
update blocklist_entries set approved_at = now(), approved_by = 'alief' where domain = 'example-scam.id';
update blocklist_entries set removed_at = now() where domain = 'false-positive.id';       -- take one off
update blocklist_entries set removed_at = null where domain = 'false-positive.id';        -- put it back (new addedAt)
```

## Env

Non-secret vars live in `api/wrangler.jsonc` `vars`. Secrets: `npx wrangler secret put <NAME>` (cloud) or `api/.dev.vars` (local, gitignored). Full list: `plan/alief/ref/R3-catatan-api.md` §7.

| Name | Kind | Now |
|---|---|---|
| `DB` | Hyperdrive binding | `shoo-db` (id filled in at first deploy) |
| `INVITE_BASE_URL` | var | Worker URL (used from fase 08) |
| `SUPABASE_URL` | var | `https://nmekxihgjszgcibqytyj.supabase.co` (public project URL); tests read the local one from `supabase status` |
| `SUPABASE_SERVICE_ROLE_KEY` | secret | Supabase secret key (`sb_secret_…`, name `shoo-worker`) for Storage only; unset → screenshots dropped |
| `SCREENSHOT_MAX_BYTES` | var | `153600` (same as the bucket `file_size_limit`) |
| `SCREENSHOT_URL_SECRET` | secret | HMAC key for screenshot links (`openssl rand -base64 32`); unset → `screenshotUrl` null; changing it invalidates every link |
| `APNS_SPIKE` | var | `"1"` only during the fase 07 spike |
| `SPIKE_KEY` | secret | header `x-spike-key` for the spike |

## Deploy (manual until the GitHub Action is on)

Cloud actions are always done by a person (plan/alief/README.md §6 rule 9). Step-by-step checklist: `plan/alief/log/fase-07.md` "LANGKAH MANUAL".

Cloud URL: `https://shoo-api.afindo-mi01.workers.dev` (shared with Imelda, TODO C7).
