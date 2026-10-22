# backend/ci — draft GitHub Action (TODO C2)

`backend.yml` is a **draft**. It does nothing here: GitHub only runs files in `.github/workflows/`, which belongs to the lead.

## For Umar: how to turn it on

1. Move `backend/ci/backend.yml` to `.github/workflows/backend.yml`.
2. Add 5 repository secrets (Settings → Secrets and variables → Actions):
   - `SUPABASE_ACCESS_TOKEN` (Supabase account → Access tokens)
   - `SUPABASE_PROJECT_REF` (project ref of `shoo-demo`)
   - `SUPABASE_DB_PASSWORD` (database password of the project, used by `supabase link`)
   - `CLOUDFLARE_API_TOKEN` (template "Edit Cloudflare Workers")
   - `CLOUDFLARE_ACCOUNT_ID`
3. Optional: create the `production` environment with a required reviewer so deploys wait for approval.

What it does:
- `test` (every PR touching `backend/**`): local Supabase in Docker, pgTAP (`supabase test db`), `typecheck`, vitest, `wrangler deploy --dry-run` (bundle + config check), `gitleaks dir .` (no secrets in the files).
- `deploy` (push to `main`): `supabase db push` then `wrangler deploy`. Worker secrets (`wrangler secret put …`) are set once by hand and are not part of this workflow.

Order matters: migrations run **before** the new Worker is live, so every migration must work with the Worker version still running (add first, remove one deploy later). Worker secrets (`SUPABASE_SERVICE_ROLE_KEY`, `SCREENSHOT_URL_SECRET`, `RATE_KEY_SECRET`, APNs keys) are set once by hand.

History scan: `gitleaks detect --gitleaks-ignore-path backend/.gitleaksignore` lists known false positives by commit; after a rebase the fingerprints change, so CI scans the files (`gitleaks dir`) instead.

Until this is active, Alief deploys by hand from Alief's Mac (backend/README.md).
