-- ADM-05 admin dashboard, second step of 20261103080245_admin_public_config.sql: validate the two
-- scans checks in their own transaction, so the full-table check runs under SHARE UPDATE EXCLUSIVE
-- and scan inserts keep going (20261022100000_push_log_privacy.sql pattern).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

alter table scans validate constraint scans_blocked_floor;
alter table scans validate constraint scans_thresholds_version_check;
