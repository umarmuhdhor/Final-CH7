# backend/ — owner: Team App

Devices, family pairing, scans (Activity), verdicts, push, 14-day retention. Spec: contracts/api.md.

- No login: device token auth (PRD §10). Guardians only see devices linked to them.
- Family code: 6 digits, valid 30 min, reused while more than 5 min is left (`refresh` replaces it), rate-limited attempts, max 3 protected per guardian (GD-04, PR-03, PRD §10, issue #128).
- Verdicts apply per link (origin + path, #241): a `safe` opens one link, a `not_safe` covers the domain except on shared hosts. A `safe` verdict must reach the protected device's block screen (EX-06).
- Push via APNs straight from the Worker (no relay): a protected device's scan to its Guardian (GD-06), and the hourly scheduled pushes (protection off, weekly summary). Alert pushes only: the Dynamic Island (`POST /live`, EX-03) was removed in #555. APNs key only as a Worker secret / `.dev.vars`, never committed.
- Delete scans + screenshots + page replicas + favicons older than 14 days automatically.
- JSON shapes come from contracts/ only. If you need a change, PR to the lead first.
- Stack (chosen): Cloudflare Worker `shoo-api` (Hono) → Hyperdrive → Supabase Postgres, R2 for page replicas, Worker Cron Triggers. Schema, routes and runbooks live in `backend/README.md` and `backend/API.md`; keep `contracts/api.md` JSON shapes.
- Don't touch anything outside `backend/` and `ios/ShooApp/`.
- Everything must follow Apple security & privacy (plan/alief/SECURITY.md §3): no PII or tokens in logs, minimum data, and deletion or disconnect takes effect immediately (no cached/CDN copies of user data, `Cache-Control: private, no-store`). When in doubt, pick the most privacy-preserving option.
