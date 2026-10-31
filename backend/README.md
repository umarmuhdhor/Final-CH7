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
SHOO_SLOW_TESTS=1 pnpm -C backend/api test                 # plus slow opt-in cases (all 10^6 family codes taken)
cp backend/api/.dev.vars.example backend/api/.dev.vars     # once
pnpm -C backend/api dev                                    # http://localhost:8787
```

- The Worker reaches local Postgres through the Hyperdrive binding `DB` (`localConnectionString` in `api/wrangler.jsonc`) as role `shoo_api` with the dev-only password `shoo_api_local` from `seed.sql`.
- Tests empty all tables before each test (`api/test/helpers/resetDb.ts`). Run `supabase db reset` to get the seed data back.
- Seed devices (local only): `dev_me` (guardian), `dev_mom`, `dev_dad` (protected). Bearer value `shoo_local_<id>`, e.g. `T=shoo_local_dev_me; curl localhost:8787/blocklist -H "authorization: Bearer $T"`.

## Endpoints

Full reference with what each endpoint is for, its input, output and errors: **[API.md](API.md)**.
The shared contract is [`contracts/api.md`](../contracts/api.md).

| Method | Path | Who calls it | What it is for |
|---|---|---|---|
| GET | [`/healthz`](API.md#get-healthz) | uptime monitor | Worker is up (no DB) |
| GET | [`/healthz/db`](API.md#get-healthzdb) | uptime monitor | DB is reachable; keeps Supabase Free awake |
| GET | [`/ops/status`](API.md#get-opsstatus) | ops-watch, backend owner | Cron health, DB size, blocklist queue (token, aggregates only) |
| POST | [`/devices`](API.md#post-devices) | app, onboarding | Register this phone, get its device token |
| GET | [`/devices/me`](API.md#get-devicesme) | app | My profile, and my Guardian if I am Protected |
| PATCH | [`/devices/me`](API.md#patch-devicesme) | app, extension | Rename, APNs token, language, extension heartbeat |
| DELETE | [`/devices/me`](API.md#delete-devicesme) | app, Profile | Delete my data now |
| POST | [`/family/code`](API.md#post-familycode) | Guardian app | 6-digit code + QR + invite link, valid 30 min; `refresh` makes a new one |
| POST | [`/family/join`](API.md#post-familyjoin) | Protected app | Connect to a Guardian with the code |
| GET | [`/family/members`](API.md#get-familymembers) | Guardian app | Family cards: members, extension status, last scan |
| DELETE | [`/family/members/{deviceId}`](API.md#delete-familymembersdeviceid) | Guardian app | Remove a member |
| DELETE | [`/family/guardian`](API.md#delete-familyguardian) | Protected app | Disconnect from my Guardian |
| POST | [`/scans`](API.md#post-scans) | extension | Report a warned or blocked page (+ page replica); pushes the Guardian |
| GET | [`/scans`](API.md#get-scans) | app, Activity | My or my family's scans, newest first, paged |
| GET | [`/scans/{id}`](API.md#get-scansid) | app, Detail | One scan with 1-hour replica (and, for older scans, screenshot) links |
| GET | [`/replicas/{scanId}`](API.md#get-replicasscanidvexpsig) | app, Detail | The page replica (gzip HTML) behind `pageReplicaUrl` (EX-07) |
| GET | [`/screenshots/{scanId}`](API.md#get-screenshotsscanidvexpsig) | app, Detail | The screenshot image behind that link (deprecated, 18c) |
| GET | [`/favicons/{scanId}`](API.md#get-faviconsscanidvexpsig) | app, Activity + Detail | The stored site icon behind a `faviconUrl` link (PR-05) |
| POST | [`/verdicts`](API.md#post-verdicts) | Guardian app | It's safe / Not safe for a blocked domain |
| GET | [`/verdicts?domain=`](API.md#get-verdictsdomain) | extension | Poll for the Guardian's decision on a block screen |
| GET | [`/blocklist?since=`](API.md#get-blocklistsince) | extension | Global approved scam domains for on-device checks |
| GET | [`/j/{code}`](API.md#get-jcode) | browser (WhatsApp / AirDrop link) | Invite page when the app is not installed: open Shoo, or copy + install |
| GET | [`/og/invite.jpg`](API.md#get-oginvitejpg) | WhatsApp / Messages crawler | Link preview image for `/j/{code}` |
| GET | [`/.well-known/apple-app-site-association`](API.md#get-well-knownapple-app-site-association) | iOS | Universal Link for `/j/*` |
| GET | [`/privacy`](API.md#get-privacylangenid) | browser | Privacy policy, EN/ID |

All errors are `{ "error": { "code", "message" } }`; `429` carries `Retry-After`. Every response is
`Cache-Control: private, no-store` except `GET /blocklist`. Details: [API.md, General rules](API.md#general-rules).

## Schema summary

Migrations: `db/supabase/migrations/20261021130000_init.sql`, `20261021150000_blocklist_times.sql`, `20261021160000_family.sql`, `20261021170000_screenshot_bucket.sql`, `20261021180000_verdicts.sql`, `20261022100000_push_log_privacy.sql` (details: `plan/alief/ref/R2-skema-db.md`).

| Table | Purpose |
|---|---|
| `devices` | one row per installed app. `token_hash` = sha256(token), the token itself is never stored. `mode` immutable (trigger). `ext_last_seen_at` from `extensionLastSeenAt` |
| `family_links` | protected → guardian (PK on protected = one guardian each; trigger: modes match, max 3 per guardian) |
| `family_codes`, `join_attempts` | 6-digit codes (30 min) and join attempts for rate limiting; attempts keep `ip_hash` = sha256(`join:ip-or-/64`), never a raw IP |
| `scans` | Activity items, score 30–100, status consistent with score, domain lowercase without `www.`. `screenshot_path` = `<ownerId>/<scanId>.jpg\|png` in bucket `screenshots` (private, 150 KB, JPEG/PNG only); dedupe means several scans can share one path. `favicon_path` = `<ownerId>/<scanId>-favicon.<png\|ico\|jpg\|gif\|webp>` in the same bucket, downloaded by the Worker from `favicon_url` (PR-05); reused the same way; `favicon_url` is never returned |
| `verdicts` | one per (owner, domain), last decision wins; `global_eligible` = blocklist eligibility snapshot taken at decision time (connected protected owner, not on `api/src/data/allowlist.ts`) |
| `blocklist_entries` | review queue + global list; only rows with `approved_at` (and no `removed_at`) are served. `rejected_at`/`rejected_by` = reviewer said no: out of the queue, cannot be approved until cleared, deleted like any undecided row when support ends |
| `ops_heartbeat` | one row per writer (`healthz`, `cron`) |
| `ops_jobs` | one row per cron job (`retention`, `notifications`): last start, last finish, last clean finish (`ok_at`), failed steps, backlog. Read by `GET /ops/status`; `shoo_api` cannot delete rows |
| `push_log` | one row per push: guardian, scan, result code (`sent`, `logged`, `failed:<status> <reason>`, `failed:timeout\|network\|config`; CHECK). No notification text (D-alief-B11) |
| `rate_limit_hits` | sliding-window counters; key is sha256(`bucket:ip-or-device`), never a raw IP |

Access: role `shoo_api` (no password in migrations) has CRUD on these tables only. `anon`/`authenticated` have no grants; RLS is on everywhere with a single `shoo_api` policy. No RPCs: the Worker uses plain SQL through postgres.js tagged templates.

Create tables **only through migrations**, never in the dashboard Table Editor or as `supabase_admin`. Migrations revoke `service_role`'s default grants for the migrating role, but the project's `postgres` role is not a member of `supabase_admin` and cannot change that role's defaults, so a table made from the dashboard would get `service_role` (Data API) access again (PR #20 security review, LOW 5). The Worker never uses the Data API for tables: keep `public` out of Settings → API → Exposed schemas on the cloud project.

Approving a blocklist domain (Supabase SQL editor). A trigger stamps `approved_at`/`removed_at` with `clock_timestamp()` on every UPDATE, so bulk approvals and re-approvals after a removal page correctly:

```sql
select domain, families, first_seen_at from blocklist_entries
 where approved_at is null and removed_at is null and rejected_at is null and families > 0 order by families desc, first_seen_at;
update blocklist_entries set approved_at = now(), approved_by = 'alief' where domain = 'example-scam.id';
update blocklist_entries set rejected_at = now(), rejected_by = 'alief' where domain = 'not-a-scam.id';    -- reject
update blocklist_entries set rejected_at = null, rejected_by = null where domain = 'not-a-scam.id';       -- undo reject
update blocklist_entries set removed_at = now() where domain = 'false-positive.id';       -- take one off
update blocklist_entries set removed_at = null where domain = 'false-positive.id';        -- put it back (new addedAt)
```

## Env

Non-secret vars live in `api/wrangler.jsonc` `vars`. Secrets: `npx wrangler secret put <NAME>` (cloud) or `api/.dev.vars` (local, gitignored). Full list: `plan/alief/ref/R3-catatan-api.md` §7.

| Name | Kind | Now |
|---|---|---|
| `DB` | Hyperdrive binding | `shoo-db` (id filled in at first deploy) |
| `INVITE_BASE_URL` | var | Worker URL (used from fase 08) |
| `APP_STORE_URL` | var | "Install" link on the invite page: TestFlight public link now, App Store later. Only `https://testflight.apple.com` / `https://apps.apple.com`; `""` or anything else → `https://apps.apple.com/` |
| `APPLINKS_APP_IDS` | var | Comma-separated `<Team ID>.<bundle ID>` listed in the AASA for the Universal Link (issue #129): `DWTZNGA7Y8.com.umarmuhdhor.shoo` (dev builds and TestFlight share that team and bundle ID); `""` → no app listed |
| `SUPABASE_URL` | var | `https://nmekxihgjszgcibqytyj.supabase.co` (public project URL); tests read the local one from `supabase status` |
| `SUPABASE_SERVICE_ROLE_KEY` | secret | Supabase secret key (`sb_secret_…`, name `shoo-worker`) for Storage only; unset → screenshots dropped |
| `REPLICAS` | R2 binding | Private bucket `shoo-replicas` (APAC hint, no `r2.dev`, no custom domain, no CORS, lifecycle `expire-17d`): page replicas and new favicons. Tests and `wrangler dev` use a local bucket |
| `REPLICAS_ENABLED` | var | `"true"`. Kill-switch: anything else stops storing and serving page replicas at once (deletes keep running), see [Kill-switch and takedown](#page-replicas-kill-switch-and-takedown) |
| `SCREENSHOT_MAX_BYTES` | var | `153600` (same as the bucket `file_size_limit`) |
| `SCREENSHOT_URL_SECRET` | secret | HMAC key for screenshot, favicon and replica links (`openssl rand -base64 32`, ≥ 32 characters); unset or shorter → `screenshotUrl` null; changing it invalidates every link |
| `APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID` | secret | APNs token auth (`.p8` as one line of base64, B7). Any APNs value unset → pushes only logged (`push_log` `logged`) |
| `RATE_KEY_SECRET` | secret | HMAC key for rate-limit keys and join attempt IPs (`openssl rand -base64 32`, ≥ 32 characters). **Required**: unset or shorter → every rate-limited request is a 500 (fail closed). Set it before deploying. Changing it resets all counters once, including the join-failure budget, so rotate it while no family code is shared and expect one deploy window where old and new isolates count apart |
| `APNS_TOPIC` | var | bundle ID of the build that receives pushes (B6); `""` until then |
| `APNS_ENV` | var | `sandbox` (Debug builds) → `production` (TestFlight, fase 16) |
| `OPS_STATUS_TOKEN` | secret | Bearer for `GET /ops/status` (`openssl rand -base64 32`, ≥ 32 characters, kept in the password manager). Unset or shorter → the route is a 404. Rotate with `wrangler secret put` + the GitHub Environment `ops` |

## Retention (daily cron)

`triggers.crons: ["0 19 * * *"]` (03:00 WITA) runs `src/cron/retention.ts`:
- writes `ops_heartbeat('cron')` first (anti-pause signal, also written by `/healthz/db`);
- scans older than 14 days without a screenshot, favicon or page replica in chunks of 2000, max 25 per run (no Storage call);
- scans older than 14 days with a screenshot, favicon and/or page replica in the same chunks of 2000, max 25 per run, so dedupe reuses never hold other users' rows past day 14 (PR #20 review, HIGH). Each chunk tombstones its unshared paths (dedupe) and deletes the rows in one transaction, then removes the objects oldest first, grouped per store: at most 10 Supabase Storage DELETEs of 100 paths per run (50 external subrequests per Cron) and at most 40 R2 deletes of 100 keys per run (R2 binding, shared with the tombstone step; `backlog: true` in the log when rows are left). Paths over a budget, or left by a store failure, stay tombstoned; a failing store stops only its own calls; the rows are gone on day 14 either way. Verdicts stay with `scan_id` null (D-alief-14);
- `storage_tombstones` (intent log of every screenshot, favicon and replica object, D-alief-B12): paths no scan points at, older than 10 min (retention's own are due at once: no upload can still land for a 14-day-old row), max 500 per run for Supabase plus what is left of the R2 budget. The store comes from the path: `-replica.html.gz` and `-icon.<ext>` are in R2, everything else in Supabase Storage. `REPLICAS_ENABLED` never stops deletes;
- `family_codes` expired > 1 h, `join_attempts` > 1 day, `push_log` > 14 days, `rate_limit_hits` > 1 day (chunks of 20000, max 50).

`scheduled()` awaits the run, so a failed step fails the Cron event.

Logs: one `{"event":"retention", …counts}` line. Local trigger while `wrangler dev --test-scheduled` runs: `curl "http://localhost:8787/cdn-cgi/handler/scheduled?cron=0+19+*+*+*"`.

## Notifications (hourly cron, PF-01 proposed)

`"5 * * * *"` runs `src/cron/notifications.ts` (`scheduled()` picks the job by `controller.cron`, see `CRONS` in `src/index.ts`): "Perlindungan mati" for members whose extension has been silent 24 h, and the Monday "Ringkasan mingguan", at most 40 pushes per run. Quiet hours (`devices.quiet_*` in `devices.time_zone`) are worked out in TypeScript with `Intl`. Migration `20261028130000_notification_settings.sql` adds the switches to `devices` and `family_links.off_notified_at`. Logs: one `{"event":"notifications","protectionOff":n,"summaries":n}` line. Local trigger: `curl "http://localhost:8787/cdn-cgi/handler/scheduled?cron=5+*+*+*+*"`.

Check for a backlog (SQL editor): `select count(*) from scans where created_at < now() - interval '15 days';` should be 0.

## Monitoring and alerts

`GET /ops/status` (fase 21a) judges the backend from the database: both crons write `ops_jobs` (a
failed write is one failed retention step, or one `ops_job_write_failed` log line for notifications,
and never stops the other work). Check it by hand, token typed from the password manager and never as
an argument:

```bash
read -rs OPS_STATUS_TOKEN
curl -s -H "Authorization: Bearer $OPS_STATUS_TOKEN" https://shoo-api.afindo-mi01.workers.dev/ops/status
```

Who gets alerts: Alief (backend owner). Umar only when the cause is in CI, the extension or `ai/`.
Never paste `wrangler tail` or Query Builder output that carries URLs (`/replicas/…?sig=`, `/j/<code>`)
into an issue, PR or plan log. Public places (issues, Actions logs) get codes only, no numbers.

| Code | Level | When | First step | Next step |
|---|---|---|---|---|
| `retention_stale` | alert | no clean retention run for 26 h (or never: right after the first deploy, until 19:00 UTC) | Query Builder: `event = retention_step_failed` (`step`, `error.name`, `error.code`) | Reproduce locally (`wrangler dev --test-scheduled`, trigger in [Retention](#retention-daily-cron)), fix through a PR. Do not run cloud retention by hand; the next run is 19:00 UTC |
| `retention_failed` | alert | the last run had a failed step | same as above | same as above |
| `retention_overdue` | alert | a scan is older than 15 days 6 h (the privacy page promises 14 days) | SQL editor: `select count(*) from scans where created_at < now() - interval '15 days'` | Backlog for more than 2 days → raise chunks/budget through a PR |
| `retention_backlog` | warn | the last run left rows for the next one | same as above | same as above |
| `tombstones_stuck` | warn | a tombstone older than 2 days | Query Builder: `screenshots_delete_failed`, `replica_clear_failed` | Check the R2 binding and the Supabase key |
| `notifications_stale` | alert | no notifications run for 2 h 15 min (or never) | Query Builder: `push_failed`, `push_config_incomplete`, `ops_job_write_failed`; Cron Events in the Worker dashboard | Fix through a PR |
| `db_size_high` | warn ≥ 350 MB, alert ≥ 450 MB | `pg_database_size` (Free: 500 MB) | `select relname, pg_size_pretty(pg_total_relation_size(oid)) from pg_class order by pg_total_relation_size(oid) desc limit 10` | Usually `rate_limit_hits` or `scans`: check retention first |
| `blocklist_queue` | warn | the oldest undecided domain waits more than 24 h (D9) | Review in the SQL editor ([Schema summary](#schema-summary)) | Note approvals and rejections in the active phase log |

`healthzAgeHours` (last `/healthz/db`) is a number only: it shows whether the ops-watch keep-alive
still runs. The workflow (fase 21b) adds `healthz_down`, `ops_status_unreachable`, `healthz_db_failed`,
`worker_*` and `r2_*`; their rows join this table with it.

## Quota (Supabase Free + R2)

`db/scripts/quota-estimate.sql` (local, rolled back): 1000 realistic scans ≈ 1.4 MB with indexes (≈ 1.5 KB per scan); one block screen polling `GET /verdicts` all day ≈ 17k `rate_limit_hits` rows ≈ 4 MB (kept 1 day).
- DB 500 MB: ≈ 300k scans alive (14 days) ≈ 20k scans/day.
- Supabase Storage 1 GB: screenshots only from older builds (≤ 150 KB, ≤ 50 per device and 300 in total per day, kept 14 days) and favicons stored before fase 18a (`-favicon.`, gone within 15 days). Both are removed in 18c.
- Supabase egress 5 GB/month: every screenshot view streams from Storage (no cache, D-alief-B08) → ≈ 35k views/month at 150 KB.
- R2 (`shoo-replicas`, free tier 10 GB-month, 1 M Class A, 10 M Class B, free egress, D-alief-C26): page replicas ≤ 300 KB gzip, ≤ 50 per device, 3000 and 500 MB in total per 24 h, ≤ 300 per IP per 24 h; objects live ≤ 16 days → ≤ 8 GB worst case. New favicons ≤ 64 KB, 1000 downloads per day in total → ≈ 1 GB worst case. Views: 10 per minute and 500 per day per viewer, no global cap (egress is free). Check: R2 dashboard → `shoo-replicas` → Metrics.
- Check (SQL editor): `select pg_size_pretty(pg_database_size(current_database()));` and Storage usage in the Supabase dashboard (Settings → Usage).

## Page replicas: kill-switch and takedown

- **Kill-switch** (D-alief-C25 d): set `"REPLICAS_ENABLED": "false"` in `api/wrangler.jsonc` and merge (CI deploys). From that deploy on, `POST /scans` stores no replica (scans and pushes go on), `pageReplicaUrl` is `null` and `GET /replicas/{id}` answers 404. Retention, tombstones and `DELETE /devices/me` keep deleting R2 objects. A dashboard-only change of the var is overwritten by the next CI deploy.
- **Takedown of one object** (SQL editor, as postgres), tombstone first so the cron removes the object even if the next steps fail:

  ```sql
  begin;
  insert into storage_tombstones (path, created_at) values ('<owner>/<scan>-replica.html.gz', now() - interval '1 hour')
    on conflict (path) do nothing;
  -- Every scan that reuses the object, not only the original.
  update scans set replica_path = null, replica_bytes = null
    where owner_id = '<owner>' and replica_path = '<owner>/<scan>-replica.html.gz';
  commit;
  ```

  The link answers 404 at once; the next retention run removes the object. To remove it right away as
  well: `npx wrangler r2 object delete shoo-replicas/<owner>/<scan>-replica.html.gz --remote` (without
  `--remote` Wrangler only touches the local bucket).

## Rollback

- Worker: `npx wrangler rollback` (dashboard → Deployments shows versions). Secrets are not versioned.
- Database: migrations only move forward. Undo with a new migration; every migration must work with the Worker version that is still live (ci/README.md).

## Deploy

Since #48 the GitHub Action (`.github/workflows/backend.yml`, see `ci/README.md`) runs `supabase db push` and then `wrangler deploy` on every push to `main` that touches `backend/**`. Deploy only through it: a Worker deployed from a branch is overwritten by the next `main` deploy (for fase 18 that older Worker would drop replica tombstones and orphan R2 objects, K18). Rollback is a forward fix through a new PR. Cloud actions outside CI are always done by a person (plan/alief/README.md §6 rule 9); checklists are the "LANGKAH MANUAL" blocks in `plan/alief/log/fase-*.md`. Bindings must exist before the deploy that uses them (R2 bucket `shoo-replicas`: created 29 Oct 2026).

Cloud URL: `https://shoo-api.afindo-mi01.workers.dev` (shared with Imelda, TODO C7).
