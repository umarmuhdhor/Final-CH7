-- Fase 21a (B9, D-alief-B13): status of the last cron runs, read by GET /ops/status.
-- ops_heartbeat stays as it is (anti-pause, written first by retention): it cannot tell whether a
-- run finished. Add-only: the Worker that is live while this migration runs never touches the table.

-- `set local`: only this migration's transaction (see 20261029100000_page_replicas.sql).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table ops_jobs (
  job         text primary key check (job in ('retention', 'notifications')),
  started_at  timestamptz,
  ok_at       timestamptz,                                -- end of the last run with failed = 0
  failed      int not null default 0 check (failed >= 0), -- failed steps in the last run
  backlog     boolean not null default false,             -- retention left rows for the next run
  finished_at timestamptz
);

-- The Worker upserts rows; nobody deletes them.
grant select, insert, update on ops_jobs to shoo_api;
revoke all on ops_jobs from anon, authenticated, service_role;
alter table ops_jobs enable row level security;
create policy shoo_api_all on ops_jobs for all to shoo_api using (true) with check (true);
