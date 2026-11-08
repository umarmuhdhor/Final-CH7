# backend/ci — backend GitHub Action

The workflow lives in `.github/workflows/backend.yml` (lead's folder, live since #48). This README lists what it needs.

## Secrets

3 secrets in the `production` environment (Settings → Environments → `production`), so only the `deploy` job can read them (#68):
- `SUPABASE_DB_URL`: session pooler connection string of `shoo-demo` (Dashboard → Connect → Session pooler, port `5432`), with the database password filled in and percent-encoded. Runners are IPv4-only, so the direct host does not work.
- `CLOUDFLARE_API_TOKEN` (template "Edit Cloudflare Workers", this account only)
- `CLOUDFLARE_ACCOUNT_ID`

No Supabase access token: CI runs `supabase db push --db-url` and never `supabase link`, which needs a token that can also read the project's API secret keys (#68). Values go to the lead through a password manager, never chat or git.

What it does:
- `test` (every PR touching `backend/**`): local Supabase in Docker, pgTAP (`supabase test db`), `typecheck`, vitest, `wrangler deploy --dry-run` (bundle + config check), `gitleaks dir .` (no secrets in the files).
- `deploy` (push to `main`): `supabase db push --db-url "$SUPABASE_DB_URL"` then `wrangler deploy`. Worker secrets (`wrangler secret put …`) are set once by hand and are not part of this workflow.

Order matters: migrations run **before** the new Worker is live, so every migration must work with the Worker version still running (add first, remove one deploy later). Worker secrets (`SUPABASE_SERVICE_ROLE_KEY`, `SCREENSHOT_URL_SECRET`, `RATE_KEY_SECRET`, APNs keys) are set once by hand.

History scan: `gitleaks detect --gitleaks-ignore-path backend/.gitleaksignore` lists known false positives by commit; after a rebase the fingerprints change, so CI scans the files (`gitleaks dir`) instead. That scan covers the whole repo, not only `backend/`: a finding in another folder (the extension, say) also stops the deploy, and those folders have no CI of their own to catch it first. A string that only looks like a key gets `// gitleaks:allow` on its line.

Manual deploys from Alief's Mac still work as a fallback (backend/README.md).

## ops-watch (fase 21b, TODO B9)

`.github/workflows/ops-watch.yml` runs `node backend/ci/ops-watch.mjs`:

- **quick**, cron `7,22,37,52 * * * *`: `GET /healthz` (3 tries, 20 s apart), then `GET /ops/status` with `Authorization: Bearer $OPS_STATUS_TOKEN`. The codes in its `failing[]` are passed on as they are.
- **daily**, cron `41 20 * * *` (04:41 WITA, ~1.5 h after retention): the quick checks, `GET /healthz/db` (writes `ops_heartbeat('healthz')`, the second Supabase keep-alive next to the cron Worker) and Cloudflare GraphQL analytics for the last 24 h (Workers) and the current month (R2).

Alert codes open one issue labelled `ops-alert`, assigned to `aliefauzan`; GitHub emails the assignee. A new alert code adds one comment at once; a code that went away is noted at most once an hour, so a flapping check does not send a mail every 15 minutes. The issue closes itself after 2 green runs in a row. `warn` codes only go to the job summary. Quick runs keep the alert codes of the last daily run until the next daily run. `ops_status_limited` and `cf_analytics_unavailable` mean the monitor could not see: such a run never counts as green and never drops a code, it can only add one. The issue state is a hidden marker in the workflow's own comments; only issues and comments by `github-actions` count, so a public commenter cannot close or silence it (people with write access can, as they can anyway). The token is only sent to `https://<name>.<account>.workers.dev`, and redirects are not followed.

The repo is public: the script prints codes and levels only. No numbers (DB size, queue length, request counts), no URLs, no tokens, no response bodies, in the log, the job summary or the issue. The numbers stay behind `GET /ops/status` (token holders). R2 metrics are grouped by `actionType` only, never `objectName` (object keys carry device ids).

| Code (workflow) | Level | When |
|---|---|---|
| `healthz_down` | alert | `/healthz` not 200 three times in a row |
| `ops_status_unreachable` | alert | `/ops/status` not 200 (404 = wrong or missing token), or no token in the environment |
| `ops_status_limited` | warn | `/ops/status` 429: only token holders count toward the 30/h, so it says nothing about the backend |
| `healthz_db_failed` | alert | daily `/healthz/db` not 200 |
| `worker_exceeded_cpu` | alert | `shoo-api` had an `exceededResources` invocation in 24 h |
| `worker_errors` | alert | `shoo-api` errors above 1 % of at least 50 requests in 24 h |
| `worker_requests_high` | warn | all Workers of the account ≥ 80 000 requests in 24 h (Free: 100 000/day per account) |
| `r2_class_a_high` / `r2_class_b_high` | warn | ≥ 500 000 class A / ≥ 5 000 000 class B operations this month |
| `r2_storage_high` | warn | ≥ 5 GB stored |
| `cf_analytics_unavailable` | warn | no token/account id, or GraphQL answered with an error |

Setup (lead, once; values from Alief through the password manager, never chat or git):

1. Settings → Environments → New environment `ops`, deployment branches: `main` only.
2. Environment secrets:
   - `OPS_STATUS_TOKEN`: the same value as the `shoo-api` Worker secret.
   - `CF_ANALYTICS_TOKEN`: API token with only Account → Account Analytics → Read, Shoo account only.
   - `CLOUDFLARE_ACCOUNT_ID`: the Shoo account id (32 hex).
3. Repository variable `OPS_WATCH_ENABLED` = `true` (set it to `false` to stop the workflow without a PR). Optional variable `OPS_API_URL` (default `https://shoo-api.afindo-mi01.workers.dev`).
4. Actions → ops-watch → Run workflow, mode `daily`: the run should end with `issue: none`.

Alert test (backend untouched): Run workflow with `simulate` = `retention_failed` → an `ops-alert` issue opens; two normal runs close it.

Locally, without touching GitHub: `OPS_DRY_RUN=1 OPS_STATUS_TOKEN=… node backend/ci/ops-watch.mjs --quick` (token from the password manager through `read -rs`, never as an argument). Tests: `node --test 'backend/ci/*.test.mjs'` (also run by `backend.yml`).

Scheduled workflows only run on the default branch and GitHub turns them off after 60 days without repository activity; nothing alerts when that happens (accepted in fase 21 "Risiko & rollback"): after a quiet period, check Actions → ops-watch. Runs share one concurrency group, so two runs never open two issues; a daily run that waits behind a slow quick run can be replaced by the next quick run (rare: quick runs end within a minute). The cron Worker keeps Supabase awake on its own; `healthzAgeHours` in `/ops/status` shows whether the daily keep-alive still runs.
