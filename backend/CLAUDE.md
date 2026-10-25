# backend/ — owner: Team App

Devices, family pairing, scans (Activity), verdicts, push, 14-day retention. Spec: contracts/api.md.

- No login: device token auth (PRD §10). Guardians only see devices linked to them.
- Family code: 6 digits, valid 30 min, reused while more than 5 min is left (`refresh` replaces it), rate-limited attempts, max 3 protected per guardian (GD-04, PR-03, PRD §10, issue #128).
- Verdicts apply per domain (PRD §5). A `safe` verdict must reach the protected device's block screen (EX-06).
- Push via APNs when a protected device posts a scan (GD-06). APNs key only in `.env`, never committed.
- Delete scans + screenshots older than 14 days automatically.
- JSON shapes come from contracts/ only. If you need a change, PR to the lead first.
- Supabase recommended (DB + edge functions + cron + realtime). If you choose it, document schema + RPCs here and keep api.md JSON shapes.
- Don't touch anything outside `backend/` and `ios/ShooApp/`.
- Everything must follow Apple security & privacy (plan/alief/SECURITY.md §3): no PII or tokens in logs, minimum data, and deletion or disconnect takes effect immediately (no cached/CDN copies of user data, `Cache-Control: private, no-store`). When in doubt, pick the most privacy-preserving option.
