-- EX-03 (#555): Shoo dropped the Dynamic Island (contracts/api.md "Live score", #557). The Live Activity
-- APNs tokens of 20261110100000_live_activity_tokens.sql are no longer needed, so they go (privacy rule:
-- data we no longer use is deleted, not kept): live_start_token, live_update_token, live_activity_id,
-- live_started_at, and the pair constraint devices_live_update_pair. Their single-column checks go with them.
--
-- Deploy order: CI runs `supabase db push` BEFORE `wrangler deploy` (.github/workflows/backend.yml). The
-- Worker that stopped reading and writing these columns (PR fix/EX-03-remove-live-backend) must already be
-- live, or PATCH /devices/me on the old Worker fails until the new one is out.
-- No view, index, function, trigger or policy uses these columns. DROP COLUMN only changes the catalog (no
-- table rewrite), so the ACCESS EXCLUSIVE lock is held for milliseconds; if it cannot get the lock within
-- lock_timeout, `db push` fails with nothing applied and the deploy job is simply re-run.
-- Rollback: a new migration with the DDL of 20261110100000_live_activity_tokens.sql (columns, their checks,
-- the pair constraint). The columns come back empty: the tokens are not recoverable, and nothing reads them.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

alter table devices
  drop constraint if exists devices_live_update_pair,
  drop column if exists live_start_token,
  drop column if exists live_update_token,
  drop column if exists live_activity_id,
  drop column if exists live_started_at;
