-- Fase 18 (EX-07, D-alief-C23/C25/C26): page replicas. The objects live in the private Cloudflare
-- R2 bucket `shoo-replicas`, not in storage.buckets; Postgres only knows their paths. Same lifecycle
-- as screenshots: retention on day 14, DELETE /devices/me, storage_tombstones (D-alief-B12).

-- `set local`: only this migration's transaction, never the session the push or the Worker reuses.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- '<owner_id>/<scan_id>-replica.html.gz'. A scan of the same owner + domain within 24 h points at the
-- earlier scan's object (reuse, like screenshot dedupe). replica_bytes is set only on the row that
-- uploaded the object, so quotas never count a reuse twice; clearing the path clears both.
alter table scans
  add column replica_path text check (char_length(replica_path) between 3 and 300),
  add column replica_bytes int check (replica_bytes between 1 and 307200),
  add constraint scans_replica_bytes_has_path check (replica_bytes is null or replica_path is not null);

-- Retention's "no other scan shares this path" probe, the tombstone drain and clearReplicaPath.
create index scans_replica_path on scans(owner_id, replica_path) where replica_path is not null;

-- Original uploads: the per-device and global quotas (3000 uploads + 500 MB per 24 h) are an
-- index-only scan on this, inside the per-owner lock.
create index scans_original_replica on scans(created_at) include (owner_id, replica_bytes) where replica_bytes is not null;

-- Retention walks: a scan with only a replica still needs an R2 call, so it moves from the plain walk
-- to the stored-files walk. The new indexes are built before the old ones go: `drop index` takes an
-- ACCESS EXCLUSIVE lock on scans until commit, and CONCURRENTLY cannot run in a migration transaction.
-- scans is small (14-day retention), so the builds take seconds.
create index scans_plain_created_v2 on scans(created_at, id)
  where screenshot_path is null and favicon_path is null and replica_path is null;
create index scans_shot_created_v2 on scans(created_at, id)
  where screenshot_path is not null or favicon_path is not null or replica_path is not null;
drop index scans_plain_created;
drop index scans_shot_created;
alter index scans_plain_created_v2 rename to scans_plain_created;
alter index scans_shot_created_v2 rename to scans_shot_created;
