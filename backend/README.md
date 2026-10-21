# backend

API for devices, family, scans, verdicts, push. Spec: `contracts/api.md` (source of truth for every JSON shape).

Stack: Cloudflare Worker `shoo-api` (Hono, zod, postgres.js) → Hyperdrive (`--caching-disabled`) → Supabase Postgres + private Storage bucket `screenshots`. Plan: `plan/alief/ARCHITECTURE.md`.

```text
backend/
├── api/            Worker (TypeScript). src/{app,env,index}.ts, routes/, http/, db/, services/, cron/
├── db/supabase/    config.toml, migrations/, tests/ (pgTAP), seed.sql (local only)
├── db/scripts/     quota-estimate.sql (local only)
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
- Seed devices (local only): `dev_me` (guardian), `dev_mom`, `dev_dad` (protected). Bearer value `shoo_local_<id>`, e.g. `T=shoo_local_dev_me; curl localhost:8787/blocklist -H "authorization: Bearer $T"`.

## Endpoints

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
| GET | `/privacy?lang=en\|id` | – | privacy policy page (SECURITY §3 P12), EN/ID by `lang` then Accept-Language; no DB |
| GET | `/join?code=` | – | HTML invite page (EN/ID by Accept-Language) → `shoo://join?code=`; strict CSP; no DB lookup |
| POST | `/scans` | Bearer | contract ScanResult body (+ `screenshotBase64?`) → `201 { id }`; owner = token device; 120/h per device. Screenshot: JPEG/PNG ≤ 150 KB, ≤ 1280 px, dedupe same domain 24 h, 50/24 h per device, otherwise dropped (scan still 201) |
| GET | `/scans?owner=me\|family\|<deviceId>&status=&cursor=&limit=` | Bearer | `{ items, nextCursor }`, newest first, limit 1–50 (20); `family` guardian only (403), unknown member 404 |
| GET | `/scans/{id}` | Bearer | one ScanResult, `screenshotUrl` = 1 h Worker link for this viewer; 404 unless own scan or my member's scan |
| GET | `/screenshots/{scanId}?v=&exp=&sig=` | link signature | the image, `Cache-Control: private, no-store`; access re-checked in the DB on every request (deleted scan, disconnect → 404 at once) |
| POST | `/verdicts` | Bearer guardian | `{ scanId, value: safe\|not_safe }` → `{ verdict }` for the scan's owner + domain; 404 unknown scan, 403 `verdict_not_allowed` (not mine and not my member's), 409 `verdict_not_allowed` (not blocked); 60/min. A `not_safe` on a connected member's scan queues the domain for review (allowlist excluded) |
| GET | `/verdicts?domain=` | Bearer | `{ verdict \| null }` for (me, domain); domain normalized (case, `www.`); 30 per 10 s per device with `Retry-After`. Disconnect or device deletion removes the ex-guardian's verdicts for that member |
| GET | `/blocklist?since=` | Bearer | approved global domains; `removed[]` only with `since`; `nextSince` has microseconds |

Errors always `{ "error": { "code", "message" } }`; `429` carries `Retry-After`.

Push (GD-06, fase 11): `POST /scans` from a protected device sends the guardian `{ aps: { alert: { body }, sound: "default" }, scanId }` straight from the Worker to APNs over HTTP/2 (D-alief-B01), text in the guardian's language, after the response (`waitUntil`). Only 410 `Unregistered`/`ExpiredToken` clears the guardian's `apns_token`; a push failure never fails the scan.
Every response also carries `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, HSTS and (unless the route sets its own) CSP `default-src 'none'; frame-ancestors 'none'`. No CORS headers (native clients only). A declared body over 256 KB → 413 before any DB work. Unknown bearer tokens are limited to 60 per 10 min per IP (then 429).
Every response is `Cache-Control: private, no-store` (user data, SECURITY §3 P13) except `GET /blocklist` (`private, max-age=300`). Workers invocation logs are off; logs never carry ids, names, URLs or tokens.

## Schema summary

Migrations: `db/supabase/migrations/20261021130000_init.sql`, `20261021150000_blocklist_times.sql`, `20261021160000_family.sql`, `20261021170000_screenshot_bucket.sql`, `20261021180000_verdicts.sql`, `20261022100000_push_log_privacy.sql` (details: `plan/alief/ref/R2-skema-db.md`).

| Table | Purpose |
|---|---|
| `devices` | one row per installed app. `token_hash` = sha256(token), the token itself is never stored. `mode` immutable (trigger). `ext_last_seen_at` from `extensionLastSeenAt` |
| `family_links` | protected → guardian (PK on protected = one guardian each; trigger: modes match, max 3 per guardian) |
| `family_codes`, `join_attempts` | 4-digit codes (60 s) and join attempts for rate limiting; attempts keep `ip_hash` = sha256(`join:ip-or-/64`), never a raw IP |
| `scans` | Activity items, score 30–100, status consistent with score, domain lowercase without `www.`. `screenshot_path` = `<ownerId>/<scanId>.jpg\|png` in bucket `screenshots` (private, 150 KB, JPEG/PNG only); dedupe means several scans can share one path |
| `verdicts` | one per (owner, domain), last decision wins; `global_eligible` = blocklist eligibility snapshot taken at decision time (connected protected owner, not on `api/src/data/allowlist.ts`) |
| `blocklist_entries` | review queue + global list; only rows with `approved_at` (and no `removed_at`) are served |
| `ops_heartbeat` | one row per writer (`healthz`, `cron`) |
| `push_log` | one row per push: guardian, scan, result code (`sent`, `logged`, `failed:<status> <reason>`, `failed:timeout\|network\|config`; CHECK). No notification text (D-alief-B11) |
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
| `SCREENSHOT_URL_SECRET` | secret | HMAC key for screenshot links (`openssl rand -base64 32`, ≥ 32 characters); unset or shorter → `screenshotUrl` null; changing it invalidates every link |
| `APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID` | secret | APNs token auth (`.p8` as one line of base64, B7). Any APNs value unset → pushes only logged (`push_log` `logged`) |
| `RATE_KEY_SECRET` | secret | HMAC key for rate-limit keys and join attempt IPs (`openssl rand -base64 32`, ≥ 32 characters). **Required**: unset or shorter → every rate-limited request is a 500 (fail closed). Set it before deploying. Changing it resets all counters once |
| `APNS_TOPIC` | var | bundle ID of the build that receives pushes (B6); `""` until then |
| `APNS_ENV` | var | `sandbox` (Debug builds) → `production` (TestFlight, fase 16) |

## Retention (daily cron)

`triggers.crons: ["0 19 * * *"]` (03:00 WITA) runs `src/cron/retention.ts`:
- writes `ops_heartbeat('cron')` first (anti-pause signal, also written by `/healthz/db`);
- scans older than 14 days in batches of 100, max 10 per run (1000/day; `backlog: true` in the log when more are left). Screenshot objects are deleted **before** their rows and only when no younger scan shares the path (dedupe); if Storage fails the rows stay and the batch is retried the next day. Verdicts stay with `scan_id` null (D-alief-14);
- `family_codes` expired > 1 h, `join_attempts` > 1 day, `push_log` > 14 days, `rate_limit_hits` > 1 day.

Logs: one `{"event":"retention", …counts}` line. Local trigger while `wrangler dev --test-scheduled` runs: `curl "http://localhost:8787/cdn-cgi/handler/scheduled?cron=0+19+*+*+*"`.

Check for a backlog (SQL editor): `select count(*) from scans where created_at < now() - interval '15 days';` should be 0.

## Quota (Supabase Free)

`db/scripts/quota-estimate.sql` (local, rolled back): 1000 realistic scans ≈ 1.4 MB with indexes (≈ 1.5 KB per scan); one block screen polling `GET /verdicts` all day ≈ 17k `rate_limit_hits` rows ≈ 4 MB (kept 1 day).
- DB 500 MB: ≈ 300k scans alive (14 days) ≈ 20k scans/day.
- Storage 1 GB: screenshots ≤ 150 KB, ≤ 50 per device per day, kept 14 days. Move to R2 (`ScreenshotStore`) when Storage > 700 MB.
- Egress 5 GB/month: every screenshot view streams from Storage (no cache, D-alief-B08) → ≈ 35k views/month at 150 KB. Move to R2 when egress > 3.5 GB.
- Check (SQL editor): `select pg_size_pretty(pg_database_size(current_database()));` and Storage usage in the Supabase dashboard (Settings → Usage).

## Rollback

- Worker: `npx wrangler rollback` (dashboard → Deployments shows versions). Secrets are not versioned.
- Database: migrations only move forward. Undo with a new migration; every migration must work with the Worker version that is still live (ci/README.md).

## Deploy (manual until the GitHub Action is on)

Cloud actions are always done by a person (plan/alief/README.md §6 rule 9). Step-by-step checklists: "LANGKAH MANUAL" in `plan/alief/log/fase-07.md` … `fase-12.md`. Order: `(cd backend/db && supabase db push)` first, then `pnpm -C backend/api run deploy`.

Cloud URL: `https://shoo-api.afindo-mi01.workers.dev` (shared with Imelda, TODO C7).
