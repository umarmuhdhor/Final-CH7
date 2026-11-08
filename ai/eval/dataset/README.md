# Layer 5 local dummy data

Dummy data for the layer 5 review pipeline (`POST /review`, `admin.ai_dataset`), **local database only**.
Plan: `plan/imelda/fase-09-layer5-review.md`. Dummy results are not evidence about real scams.

## Run

```bash
colima start
cd backend/db && npx -y supabase@2.114.0 start    # CLI 3.0 breaks, keep 2.114.0
npx -y supabase@2.114.0 migration up --local      # or: db reset
cd ../../ai && eval/dataset/seed-dummy.sh --export eval/dataset/out.jsonl
```

`seed-dummy.sh` refuses (before any query) unless the host in `DB_URL` / `AI_DB_URL` is `127.0.0.1` or
`localhost`. It is idempotent: it removes `*.shoo-dummy.test`, `sites.google.com` and `dummy_*` devices first.

## What it creates

Everything goes in through `public.*` (devices, scans, verdicts, blocklist_entries), so the backend's own
triggers and `admin.run_analysis` fill `admin.*` and the `admin.ai_dataset` view like in prod.

| Data | Rows | Note |
|---|---|---|
| Families | 6 | `dummy_g1..6` guardian, `dummy_p1..6` protected |
| `scam-01..08.shoo-dummy.test` | 8 | 2 to 5 families say not_safe, strong and weak signal mixes |
| `legit-01..05.shoo-dummy.test` | 5 | old domains; legit-05 has 2 N + 2 Y |
| `maybe-01..03.shoo-dummy.test` | 3 | 1 N + 1 Y |
| `sites.google.com` | 1 | shared host, must never reach the LLM |

## Files

- `dummy.mjs`: `buildDummySql({ seed })`, deterministic SQL for one transaction.
- `seed-dummy.sh`: guard, seed, checks, optional `--export out.jsonl` (as `shoo_ai`).
- `check-dummy.sql`: asserts row counts, RDAP age, layer score sums and that `admin.review_due` skips the shared host.
- `out*` is gitignored.
