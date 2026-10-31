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

History scan: `gitleaks detect --gitleaks-ignore-path backend/.gitleaksignore` lists known false positives by commit; after a rebase the fingerprints change, so CI scans the files (`gitleaks dir`) instead.

Manual deploys from Alief's Mac still work as a fallback (backend/README.md).
