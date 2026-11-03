-- ADM-01 admin dashboard: privileges of schema `admin` (I1, I2; dashboard plan R2 §1, §7).
-- I2 is a list of objects per dashboard phase: a later phase adds its objects here (and 05 adds the
-- one allowed exception, `select` on admin.public_config for shoo_api).
create extension if not exists pgtap with schema extensions;

begin;
select plan(59);

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

-- I2: the 01a + 02a objects. Tables: nobody but postgres.
select table_privs_are('admin', t, r, array[]::text[], r || ' has no privileges on admin.' || t)
from unnest(array['secrets', 'admin_config', 'admin_audit', 'categories', 'review_decisions',
                  'domain_intel', 'domain_intel_label', 'domain_labels', 'label_forget', 'domain_dirty',
                  'stats_daily', 'analysis_runs', 'intel_state']) as t
cross join unnest(array['shoo_admin', 'shoo_api']) as r;

-- Views: SELECT for shoo_admin only.
select table_privs_are('admin', v, 'shoo_admin', array['SELECT'], 'shoo_admin SELECT only on admin.' || v)
from unnest(array['v_review_queue', 'v_blocklist', 'v_scans', 'v_ops_snapshot',
                  'v_audit', 'v_config', 'v_categories', 'v_feed',
                  'v_domain_intel', 'v_labels', 'v_analysis_runs', 'v_stats_daily']) as v;

-- No other role (PostgREST roles, shoo_api, PUBLIC) holds any privilege on an admin table, view or sequence.
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
    where n.nspname = 'admin' and a.grantee not in ('postgres'::regrole, 'shoo_admin'::regrole)),
  0, 'I2: only postgres and shoo_admin appear in admin relation ACLs');

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
  ('run_analysis', array['text', 'text']),
  ('snapshot_daily', array[]::text[])
) as x(f, a);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where n.nspname = 'admin' and a.grantee not in ('postgres'::regrole, 'shoo_admin'::regrole)),
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

-- Schema: usage for shoo_admin only (shoo_api gets usage in dashboard phase 05).
select ok(has_schema_privilege('shoo_admin', 'admin', 'USAGE'), 'shoo_admin has USAGE on schema admin');
select ok(not has_schema_privilege('shoo_api', 'admin', 'USAGE'), 'shoo_api has no USAGE on schema admin');
select ok(not has_schema_privilege('anon', 'admin', 'USAGE') and not has_schema_privilege('authenticated', 'admin', 'USAGE'),
  'PostgREST roles have no USAGE on schema admin');

-- RLS on every admin table (second layer: no policy at all).
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'admin' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS enabled on every admin table');

select * from finish();
rollback;
