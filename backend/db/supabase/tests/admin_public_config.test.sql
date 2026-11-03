-- ADM-05 admin dashboard: GET /config/public reads admin.public_config as shoo_api (I2's one
-- exception), and scans keep only the fence (dashboard plan fase 05 K1, K2; Q47, Q48).
create extension if not exists pgtap with schema extensions;

begin;
select plan(18);

-- postgres cannot `set role shoo_api` on Supabase, so access is checked with has_*_privilege here;
-- the API tests read the view as shoo_api (backend/api/test/config-public.test.ts).

-- ---------------------------------------------------------------- I2: what shoo_api can read

select ok(has_table_privilege('shoo_api', 'admin.public_config', 'SELECT'), 'shoo_api can read public_config');
select ok(not has_table_privilege('shoo_api', 'admin.public_config', 'INSERT, UPDATE, DELETE, TRUNCATE'),
  'shoo_api cannot change public_config');
select ok(not has_table_privilege('shoo_api', t, 'SELECT'), 'shoo_api cannot read ' || t)
from unnest(array['admin.v_thresholds', 'admin.admin_config', 'admin.v_domain_intel']) as t;
select ok(not has_function_privilege('shoo_api', 'admin.set_thresholds(int, int, text, text, text)', 'EXECUTE'),
  'shoo_api cannot call set_thresholds');
select ok(not has_function_privilege('shoo_api', 'admin.set_config(text, text, text, text, text)', 'EXECUTE'),
  'shoo_api cannot call set_config');
select ok(not has_schema_privilege('shoo_api', 'admin', 'CREATE'), 'shoo_api cannot create in schema admin');

select is((select warn_at || '/' || block_at || '/' || version from admin.public_config), '30/80/0',
  'public_config is 30/80 version 0 while thresholds_live = false (I12)');
update admin.admin_config set value = to_jsonb(true) where key = 'thresholds_live';
update admin.admin_config set value = to_jsonb(35) where key = 'threshold_warn_at';
update admin.admin_config set value = to_jsonb(70) where key = 'threshold_block_at';
update admin.admin_config set value = to_jsonb(7) where key = 'thresholds_version';
select is((select warn_at || '/' || block_at || '/' || version from admin.public_config), '35/70/7',
  'public_config publishes the stored thresholds once live');

-- ---------------------------------------------------------------- K2: the fence on scans

insert into devices (id, name, mode, avatar_id, token_hash) values ('t05_p', 'P', 'protected', 'avatar_01', '\x05'::bytea);

select throws_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at)
    values ('t05_p', 'https://a.example', 'a.example', 29, 'warning', now())$$,
  '23514', null, 'score 29 still rejected');
select lives_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at, thresholds_version)
    values ('t05_p', 'https://a.example', 'a.example', 55, 'blocked', now(), 7)$$,
  'blocked at 55 accepted (blockAt may be 50–95)');
select throws_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at)
    values ('t05_p', 'https://a.example', 'a.example', 45, 'blocked', now())$$,
  '23514', null, 'blocked under 50 rejected (Q47 fence)');
select lives_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at)
    values ('t05_p', 'https://a.example', 'a.example', 85, 'warning', now())$$,
  'warning at 85 accepted: the per-version rule lives in the API');
select throws_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at, thresholds_version)
    values ('t05_p', 'https://a.example', 'a.example', 60, 'warning', now(), -1)$$,
  '23514', null, 'thresholds_version is never negative');
select is((select thresholds_version from scans where owner_id = 't05_p' and score = 55), 7, 'thresholds_version stored');
select is((select count(*)::int from scans where owner_id = 't05_p' and thresholds_version is null), 1,
  'thresholds_version stays null when not sent (old scans are not recomputed, Q48)');
select is((select count(*)::int from pg_constraint where conrelid = 'scans'::regclass and conname = 'scans_check'), 0,
  'the strict 80 rule is gone from the DB');

select * from finish();
rollback;
