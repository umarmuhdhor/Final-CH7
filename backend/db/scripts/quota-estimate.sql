-- Quota estimate (fase 12, ARCHITECTURE §3). Run locally only, as postgres:
--   (cd backend/db && supabase db query --local -f scripts/quota-estimate.sql)
-- Inserts 1000 realistic scans (+ verdicts, push_log, rate-limit rows) inside a transaction,
-- measures table sizes, and rolls everything back. Nothing is kept.
begin;
insert into devices (id, name, mode, avatar_id, token_hash)
select 'q_dev_' || g, 'Name ' || g, case when g % 4 = 0 then 'guardian' else 'protected' end::device_mode,
       'avatar_' || lpad((g % 12 + 1)::text, 2, '0'), sha256(('q' || g)::bytea)
from generate_series(1, 100) g;

insert into scans (owner_id, url, domain, page_title, favicon_url, score, status, signals, detected_at, screenshot_path)
select 'q_dev_' || (g % 100 + 1),
       'https://login-secure-' || g || '.example-bank-verify.com/account/verify?session=' || md5(g::text) || '&ref=sms-campaign-2026',
       'login-secure-' || g || '.example-bank-verify.com',
       'Verifikasi Akun Anda — Bank ' || g, 'https://login-secure-' || g || '.example-bank-verify.com/favicon.ico',
       30 + g % 71, case when 30 + g % 71 >= 80 then 'blocked' else 'warning' end::scan_status,
       (select jsonb_agg(jsonb_build_object('id', 'signal_' || s, 'layer', 1 + s % 4, 'weight', 5 + s,
          'label', 'Domain looks like a known bank but is not on the official list ' || s)) from generate_series(1, 20) s),
       now() - make_interval(mins => g), case when g % 3 = 0 then 'q_dev_' || (g % 100 + 1) || '/' || g || '.jpg' end
from generate_series(1, 1000) g;

insert into rate_limit_hits (bucket, key_hash) select 'verdicts_get', sha256(g::text::bytea) from generate_series(1, 17000) g;

analyze devices, scans, rate_limit_hits;
select relname as table, pg_size_pretty(pg_total_relation_size(c.oid)) as size, pg_total_relation_size(c.oid) as bytes
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' order by bytes desc;
select pg_size_pretty(pg_database_size(current_database())) as database_size,
       (select count(*) from scans where screenshot_path is not null) as screenshots;
rollback;
