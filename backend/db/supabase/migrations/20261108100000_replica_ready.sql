-- Fase 22 fix (EX-07, 8 Nov 2026, replica-e2e.sh --cloud --bench): reserveReplica writes replica_path
-- (and tombstones it) before the R2 put, so the quotas under lock (6, 0) count uploads in flight. But
-- GET /scans/{id} built pageReplicaUrl from replica_path alone: for a 307 KB replica the link showed
-- 379 ms after the 201 and 404'd until the put landed, and a 24-hour reuse could pick that path too.
-- replica_ready_at = when the object was confirmed in R2 (the original's put, or the reuse of a ready
-- original). Links, GET /replicas/{id} and reuse need it; quotas, retention, tombstones and
-- DELETE /devices/me keep reading replica_path, so in-flight uploads still count and are deleted.
-- admin.* functions/views (lead-owned, e.g. admin.replica_for, has_replica) still read replica_path
-- only and are deliberately not changed here (question to the lead in the PR).

-- `set local`: only this migration's transaction (see 20261029100000_page_replicas.sql). 1 s as
-- 20261104132829: add column locks public.scans; a short wait keeps POST /scans from queueing behind
-- the deploy. On lock timeout (55P03) the whole file rolls back; re-run it.
set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- Nullable without a default: a new row, or one whose upload is still running, is not ready.
-- Clearing the path clears it too (clearReplicaPath), so ready never outlives its path.
alter table scans
  add column replica_ready_at timestamptz,
  add constraint scans_replica_ready_has_path check (replica_ready_at is null or replica_path is not null);

-- Existing rows keep today's behaviour (a link whenever a path is set): their put finished, or it
-- failed and clearReplicaPath nulled the path (with ready_at). A put still in flight during the deploy
-- is the old race once more, at most for its last milliseconds. scans is small (14-day retention); no
-- trigger fires on this column (admin triggers are on insert or on other columns).
update scans set replica_ready_at = now() where replica_path is not null;
