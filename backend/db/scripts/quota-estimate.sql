-- Quota estimate (fase 12, ARCHITECTURE §3; admin.scan_archive, admin.domain_intel and push_log added in
-- fase 28, H5-01). Run locally only, as postgres:
--   (cd backend/db && supabase db query --local -f scripts/quota-estimate.sql)
-- Inserts 100 devices, 1000 realistic scans and 17000 rate-limit rows inside a transaction (the scan
-- trigger also writes admin.domain_intel and one admin.scan_archive row per scan), measures sizes, and
-- rolls everything back. Nothing is kept.
-- The size report between "report: start" and "report: end" only reads (catalog sizes and row counts,
-- no row content). To read another database without inserting anything, run only that part inside a
-- read-only transaction:
--   { echo 'begin read only;'; sed -n '/^-- report: start$/,/^-- report: end$/p' scripts/quota-estimate.sql;
--     echo 'rollback;'; } | psql "<db url>" -X -v ON_ERROR_STOP=1 -f -
begin;
insert into devices (id, name, mode, avatar_id, token_hash)
select 'q_dev_' || g, 'Name ' || g, case when g % 4 = 0 then 'guardian' else 'protected' end::device_mode,
       'avatar_' || lpad((g % 12 + 1)::text, 2, '0'), sha256(('q' || g)::bytea)
from generate_series(1, 100) g;

insert into scans (owner_id, url, domain, page_title, favicon_url, score, status, signals, detected_at, screenshot_path,
                   replica_path, replica_bytes)
select 'q_dev_' || (g % 100 + 1),
       'https://login-secure-' || g || '.example-bank-verify.com/account/verify?session=' || md5(g::text) || '&ref=sms-campaign-2026',
       'login-secure-' || g || '.example-bank-verify.com',
       'Verifikasi Akun Anda — Bank ' || g, 'https://login-secure-' || g || '.example-bank-verify.com/favicon.ico',
       30 + g % 71, case when 30 + g % 71 >= 80 then 'blocked' else 'warning' end::scan_status,
       (select jsonb_agg(jsonb_build_object('id', 'signal_' || s, 'layer', 1 + s % 4, 'weight', 5 + s,
          'label', 'Domain looks like a known bank but is not on the official list ' || s)) from generate_series(1, 20) s),
       now() - make_interval(mins => g), case when g % 3 = 0 then 'q_dev_' || (g % 100 + 1) || '/' || g || '.jpg' end,
       -- EX-07: most new scans carry a page replica (R2); a third reuse an earlier one (path, no bytes).
       case when g % 3 <> 0 then 'q_dev_' || (g % 100 + 1) || '/' || g || '-replica.html.gz' end,
       case when g % 3 = 1 then 20000 + g end
from generate_series(1, 1000) g;

insert into rate_limit_hits (bucket, key_hash) select 'verdicts_get', sha256(g::text::bytea) from generate_series(1, 17000) g;

analyze devices, scans, rate_limit_hits, push_log, admin.scan_archive, admin.domain_intel;

-- report: start
set local statement_timeout = '30s';
-- Every table in public and admin, largest first. rows_est = planner estimate (reltuples; null until the
-- table was first analyzed). Exact counts for the tables that matter are in the next query.
select n.nspname || '.' || c.relname as relation, nullif(c.reltuples, -1)::bigint as rows_est,
       pg_size_pretty(pg_total_relation_size(c.oid)) as total, pg_size_pretty(pg_relation_size(c.oid)) as heap,
       pg_size_pretty(pg_indexes_size(c.oid)) as indexes, pg_total_relation_size(c.oid) as bytes
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public', 'admin') and c.relkind = 'r' order by bytes desc;

-- The tables that grow with scans (exact counts). scans and push_log keep 14 days; admin.scan_archive
-- and admin.domain_intel are never deleted by retention (D-dash-17; the archive is only stripped).
with t as (
  select 'public.scans' as relation, (select count(*) from scans) as rows, pg_total_relation_size('public.scans') as bytes
  union all select 'admin.scan_archive', (select count(*) from admin.scan_archive), pg_total_relation_size('admin.scan_archive')
  union all select 'admin.domain_intel', (select count(*) from admin.domain_intel), pg_total_relation_size('admin.domain_intel')
  union all select 'public.push_log', (select count(*) from push_log), pg_total_relation_size('public.push_log')
)
select relation, rows, pg_size_pretty(bytes) as total, round(bytes::numeric / nullif(rows, 0)) as bytes_per_row from t;

-- Per live scan: scans + archive bytes divided by live scans. This leaves out push_log, domain_intel and
-- the small tables, so live_scans_at_500mb is an upper bound. It also holds only while the archive has about
-- one row per live scan (the first 14 days); after that the archive keeps growing and 500 MB comes sooner.
with sc as (
  select count(*) as live_scans, count(*) filter (where screenshot_path is not null) as screenshots,
         count(*) filter (where replica_path is not null) as replicas
  from scans
), ar as (
  select count(*) as archive_rows, count(*) filter (where created_at < now() - interval '14 days') as archive_older_than_14d,
         count(*) filter (where stripped_at is not null) as archive_stripped
  from admin.scan_archive
), b as (
  select pg_total_relation_size('public.scans') + pg_total_relation_size('admin.scan_archive') as scan_bytes
)
select pg_size_pretty(pg_database_size(current_database())) as database_size, live_scans, archive_rows,
       archive_older_than_14d, archive_stripped,
       round(scan_bytes::numeric / nullif(live_scans, 0)) as bytes_per_live_scan,
       floor(500 * 1024 * 1024 / nullif(scan_bytes::numeric / nullif(live_scans, 0), 0))::bigint as live_scans_at_500mb,
       screenshots, replicas
from sc, ar, b;
-- report: end
rollback;
