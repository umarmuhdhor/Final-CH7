-- ADM-01 admin dashboard: privileges of schema `admin` (I1, I2; dashboard plan R2 §1, §7).
-- I2 is a list of objects per dashboard phase: a later phase adds its objects here. Phase 05 added the
-- one allowed exception, `select` on admin.public_config for shoo_api.
create extension if not exists pgtap with schema extensions;

begin;
select plan(89);

-- I1: shoo_admin has no privilege on anything in public (tables, views, sequences, functions).
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and case when c.relkind in ('r', 'p', 'v', 'm', 'f') then has_table_privilege('shoo_admin', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') end),
  0, 'I1: shoo_admin has no privilege on any public table or view');
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and case when c.relkind = 'S' then has_sequence_privilege('shoo_admin', c.oid, 'USAGE, SELECT, UPDATE') end),
  0, 'I1: shoo_admin has no privilege on any public sequence');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('shoo_admin', p.oid, 'EXECUTE')),
  0, 'I1: shoo_admin cannot execute any public function');

-- I2: the 01a + 02a + 04a objects. Tables: nobody but postgres.
select table_privs_are('admin', t, r, array[]::text[], r || ' has no privileges on admin.' || t)
from unnest(array['secrets', 'admin_config', 'admin_audit', 'categories', 'review_decisions',
                  'domain_intel', 'domain_intel_label', 'domain_labels', 'label_forget', 'domain_dirty',
                  'stats_daily', 'analysis_runs', 'intel_state', 'case_library', 'ai_lessons', 'api_keys']) as t
cross join unnest(array['shoo_admin', 'shoo_api']) as r;

-- Views: SELECT for shoo_admin only.
select table_privs_are('admin', v, 'shoo_admin', array['SELECT'], 'shoo_admin SELECT only on admin.' || v)
from unnest(array['v_review_queue', 'v_blocklist', 'v_scans', 'v_ops_snapshot',
                  'v_audit', 'v_config', 'v_categories', 'v_feed',
                  'v_domain_intel', 'v_labels', 'v_analysis_runs', 'v_stats_daily',
                  'v_eval_summary', 'v_eval_curve', 'v_eval_labels', 'v_eval_signals', 'v_eval_targets',
                  'v_cases', 'v_lessons', 'v_thresholds', 'v_api_keys']) as v;

-- public_config: SELECT for shoo_api only (phase 05, GET /config/public), I2's one exception.
select table_privs_are('admin', 'public_config', 'shoo_admin', array[]::text[], 'shoo_admin has no privileges on admin.public_config');
select table_privs_are('admin', 'public_config', 'shoo_api', array['SELECT'], 'shoo_api SELECT only on admin.public_config');

-- No other role (PostgREST roles, shoo_api, PUBLIC) holds any privilege on an admin table, view or
-- sequence, apart from shoo_api on public_config.
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
    where n.nspname = 'admin' and a.grantee not in ('postgres'::regrole, 'shoo_admin'::regrole)
      and not (c.relname = 'public_config' and a.grantee = 'shoo_api'::regrole)
      -- Layer 5 (#241): Team AI's read-only role, SELECT on ai_dataset only (l5_review_data.test.sql).
      and not (c.relname = 'ai_dataset' and a.grantee = 'shoo_ai'::regrole and a.privilege_type = 'SELECT')),
  0, 'I2: only postgres and shoo_admin appear in admin relation ACLs (plus shoo_api on public_config, shoo_ai on ai_dataset)');

-- Functions: EXECUTE for shoo_admin on the API functions, nobody else; internal helpers for nobody.
select function_privs_are('admin', f, a, 'shoo_admin', array['EXECUTE'], 'shoo_admin EXECUTE on admin.' || f)
from (values
  ('vote', array['text', 'text', 'text', 'text', 'text']),
  ('unreject', array['text', 'text', 'text']),
  ('remove_domain', array['text', 'text', 'text']),
  ('add_domain', array['text', 'text', 'text', 'text']),
  ('replica_for', array['text']),
  ('set_config', array['text', 'text', 'text', 'text', 'text']),
  ('log_audit', array['text', 'text', 'text', 'text']),
  ('run_analysis', array['text', 'text', 'text']),
  ('snapshot_daily', array[]::text[]),
  ('set_thresholds', array['integer', 'integer', 'text', 'text', 'text']),
  ('reset_thresholds', array['text', 'text']),
  ('case_add', array['text', 'text', 'text', 'text', 'jsonb', 'text']),
  ('case_pin', array['bigint', 'boolean', 'text', 'text']),
  ('case_delete', array['bigint', 'text', 'text']),
  ('lesson_add', array['text', 'text', 'jsonb', 'bigint', 'text']),
  ('lesson_pin', array['bigint', 'boolean', 'text', 'text']),
  ('lesson_delete', array['bigint', 'text', 'text']),
  ('usage_record', array['text', 'bigint', 'integer', 'integer', 'integer']),
  ('api_key_create', array['text', 'text', 'text', 'integer', 'text']),
  ('api_key_revoke', array['bigint', 'text']),
  ('api_key_use', array['text'])
) as x(f, a);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'admin' and a.grantee not in ('postgres'::regrole, 'shoo_admin'::regrole)
      -- Layer 5: the two pure functions ai_dataset calls with shoo_ai's privileges.
      and not (a.grantee = 'shoo_ai'::regrole and p.proname in ('tokenize_path', 'mask_note'))),
  0, 'I2: PUBLIC, shoo_api and PostgREST roles cannot execute any admin function');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'admin' and p.proname like '\_%' and has_function_privilege('shoo_admin', p.oid, 'EXECUTE')),
  0, 'internal admin._* helpers are not executable by shoo_admin');

-- Every admin function pins search_path to admin + pg_temp; backend tables are always qualified.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'admin' and not (p.proconfig @> array['search_path=admin, pg_temp'])),
  0, 'every admin function pins search_path = admin, pg_temp (no public)');

-- A role that existed before the migration may carry old grants: no ACL anywhere outside admin
-- names shoo_admin (PUBLIC grants of Supabase extensions are listed in the PR, not here).
select is(
  (select count(*)::int from (
     select c.relnamespace as ns, a.grantee from pg_class c cross join lateral aclexplode(c.relacl) a
     union all
     select p.pronamespace, a.grantee from pg_proc p cross join lateral aclexplode(p.proacl) a
     union all
     select n.oid, a.grantee from pg_namespace n cross join lateral aclexplode(n.nspacl) a
      where n.nspname <> 'admin'
   ) x
   where x.grantee = 'shoo_admin'::regrole and x.ns <> 'admin'::regnamespace),
  0, 'no table, function or schema outside admin grants anything to shoo_admin');

-- Schema: usage for shoo_admin, and for shoo_api since dashboard phase 05 (to reach public_config).
select ok(has_schema_privilege('shoo_admin', 'admin', 'USAGE'), 'shoo_admin has USAGE on schema admin');
select ok(has_schema_privilege('shoo_api', 'admin', 'USAGE'), 'shoo_api has USAGE on schema admin (public_config)');
select ok(not has_schema_privilege('shoo_api', 'admin', 'CREATE'), 'shoo_api cannot create in schema admin');
select ok(not has_schema_privilege('anon', 'admin', 'USAGE') and not has_schema_privilege('authenticated', 'admin', 'USAGE'),
  'PostgREST roles have no USAGE on schema admin');

-- RLS on every admin table (second layer: no policy at all).
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'admin' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS enabled on every admin table');

select * from finish();
rollback;
