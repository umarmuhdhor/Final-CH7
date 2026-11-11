-- Fase 27k F-B8 (PR-05): a favicon's path is written (and tombstoned) before the R2 put, like a
-- replica's (20261108110000_replica_ready.sql). GET /scans, GET /scans/{id} and GET /favicons/{id}
-- built faviconUrl from favicon_path alone, so the link showed and 404'd until the put landed, and
-- a 24-hour reuse could pick that path too. favicon_ready_at = when the object was confirmed in R2
-- (the original's put, or the reuse of a ready original). Links, GET /favicons/{id} and reuse need
-- it; retention, tombstones and DELETE /devices/me keep reading favicon_path, so an in-flight upload
-- is still deleted.

-- `set local`: only this migration's transaction. 1 s as 20261108110000: add column locks
-- public.scans; a short wait keeps POST /scans from queueing behind the deploy. On lock timeout
-- (55P03) the whole file rolls back; re-run it.
set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- Nullable without a default: a new row, or one whose upload is still running, is not ready.
-- Clearing the path clears it too (clearFaviconPath), so ready never outlives its path.
alter table scans
  add column favicon_ready_at timestamptz,
  add constraint scans_favicon_ready_has_path check (favicon_ready_at is null or favicon_path is not null);

-- Existing rows keep today's behaviour (a link whenever a path is set): their put finished, or it
-- failed and clearFaviconPath nulled the path. A put still in flight during the deploy is the old
-- race once more, at most for its last milliseconds. scans is small (14-day retention); no trigger
-- fires on this column (admin triggers are on insert or on other columns).
update scans set favicon_ready_at = now() where favicon_path is not null;
