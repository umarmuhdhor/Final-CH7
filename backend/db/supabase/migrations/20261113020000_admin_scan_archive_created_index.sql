-- QA-D-H02 (dashboard fase 13): index for the scans.jsonl export.
--
-- The dashboard's /api/v1/training/scans.jsonl pages admin.v_scan_archive in insert order, keyset on
-- (created_at, scan_id), and now reads only rows older than the last full hour minus 5 minutes (a scan
-- whose transaction started earlier but committed late can no longer slip behind a stored cursor).
-- Without this index every page sorts the whole archive (dashboard fase 13 EXPLAIN, O1).
--
-- Rollback: drop index admin.scan_archive_created;

set local lock_timeout = '1s';
set local statement_timeout = '60s';

create index scan_archive_created on admin.scan_archive (created_at, scan_id);
