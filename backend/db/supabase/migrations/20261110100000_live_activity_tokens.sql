-- EX-03 path C (issue #49): Dynamic Island through push-to-start. The device keeps two APNs
-- tokens for the Live Activity, never the page it shows:
--   live_start_token   push-to-start token (Activity.pushToStartTokenUpdates), one per app install.
--   live_update_token  update token of the running activity (Activity.pushTokenUpdates), with its
--                      activity id. Cleared when the island ends.
--   live_started_at    when the last start push went out. While no update token arrived yet, POST /live
--                      sends no second start (no stacked islands); after LIVE_START_WAIT it starts again.
-- Domain and score of POST /live are forwarded into the APNs payload and stored nowhere (#49 decision 3).
-- DELETE /devices/me removes the row, so the tokens go with it. Add-only: nullable columns, no rewrite.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

alter table devices
  add column live_start_token text check (live_start_token ~ '^[0-9a-fA-F]{32,200}$'),
  add column live_update_token text check (live_update_token ~ '^[0-9a-fA-F]{32,200}$'),
  add column live_activity_id text check (live_activity_id ~ '^[A-Za-z0-9-]{1,64}$'),
  add column live_started_at timestamptz,
  -- The update token and its activity id are set and cleared together.
  add constraint devices_live_update_pair check ((live_update_token is null) = (live_activity_id is null));
