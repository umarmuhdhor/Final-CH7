-- Fase 24a-1 (E7): the daily retention run finds devices nobody has used for 90 days, or
-- registrations never used again for 30 days (src/db/repo/devices.ts inactiveDeviceIds). Both
-- walks start from last_seen_at; without an index every run reads the whole devices table, which
-- can grow by 1000 rows a day (POST /devices global limit). Add-only: no column or data changes.

-- `set local`: only this migration's transaction (see 20261029100000_page_replicas.sql). devices is
-- small, so a plain build holds its SHARE lock on devices for well under a second; CONCURRENTLY
-- cannot run inside the migration transaction.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create index devices_last_seen on devices(last_seen_at);
