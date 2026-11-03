-- ADM-05 admin dashboard (shoo-dashboard plan fase 05, K1, K2; Q47, Q48): the backend serves the
-- score thresholds the admins set (GET /config/public) and scans accept any thresholds inside the
-- fence, so a threshold change in the dashboard can take effect once the extension reads it.
--
-- admin.public_config (04a) still publishes 30/80 version 0 until thresholds_live is switched on
-- (I12), so nothing the extension does changes with this migration alone.
--
-- shoo_api gets usage on schema admin and select on that one view (I2's one exception). The view
-- has no security_invoker, so it reads admin_config as its owner; shoo_api can read nothing else in
-- admin and still executes no admin function (01a K6 revoked EXECUTE from PUBLIC).
--
-- scans: `score between 30 and 100` stays (PM decision, contracts/api.md, /privacy). The strict
-- `(status = 'blocked') = (score >= 80)` becomes the fence `blocked => score >= 50` (blockAt is
-- 50–95); the per-version rule lives in the API, where it is tested. thresholds_version records the
-- version the extension used (null for older extensions); old scans are not recomputed (Q48).
--
-- Rollback (only while no scan breaks the old rule; check first:
--   select count(*) from scans where (status = 'blocked') <> (score >= 80);  -- must be 0):
--   alter table scans add constraint scans_check check ((status = 'blocked') = (score >= 80));
--   alter table scans drop constraint scans_blocked_floor, drop constraint scans_thresholds_version_check;
--   alter table scans drop column thresholds_version;
--   revoke select on admin.public_config from shoo_api; revoke usage on schema admin from shoo_api;

-- `set local`: only this migration's transaction (see 20261029100000_page_replicas.sql).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

grant usage on schema admin to shoo_api;
grant select on admin.public_config to shoo_api;

-- Nullable, no default: no table rewrite.
alter table scans add column thresholds_version int;

-- not valid + validate: the full-table check runs under SHARE UPDATE EXCLUSIVE, not ACCESS EXCLUSIVE
-- (20261022100000_push_log_privacy.sql). Every stored scan passes: the old rule implies both.
alter table scans add constraint scans_blocked_floor check (status <> 'blocked' or score >= 50) not valid;
alter table scans add constraint scans_thresholds_version_check check (thresholds_version >= 0) not valid;
alter table scans validate constraint scans_blocked_floor;
alter table scans validate constraint scans_thresholds_version_check;

alter table scans drop constraint scans_check;
