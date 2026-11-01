-- Grants, RLS and role (I7, I9; SECURITY T8).
create extension if not exists pgtap with schema extensions;

begin;
select plan(37);

select has_role('shoo_api', 'role shoo_api exists');
select ok(not rolbypassrls and not rolsuper and rolcanlogin, 'shoo_api: login, no superuser, no bypassrls')
from pg_roles where rolname = 'shoo_api';

-- I9: shoo_api has exactly CRUD on our tables
select table_privs_are('public', t, 'shoo_api',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'shoo_api CRUD on ' || t)
from unnest(array[
  'devices', 'family_links', 'family_codes', 'join_attempts', 'scans', 'verdicts',
  'ops_heartbeat', 'push_log', 'rate_limit_hits'
]) as t;
-- blocklist_entries: table-wide SELECT + DELETE, INSERT/UPDATE per column (fase 12, hardening.test.sql)
select table_privs_are('public', 'blocklist_entries', 'shoo_api',
  array['SELECT', 'DELETE'], 'shoo_api SELECT + DELETE on blocklist_entries (column grants for the rest)');
-- ops_jobs (fase 21a): cron status, never deleted by the Worker
select table_privs_are('public', 'ops_jobs', 'shoo_api',
  array['SELECT', 'INSERT', 'UPDATE'], 'shoo_api SELECT/INSERT/UPDATE on ops_jobs');

-- I7: PostgREST roles have nothing
select table_privs_are('public', t, r, array[]::text[], r || ' has no privileges on ' || t)
from unnest(array[
  'devices', 'family_links', 'family_codes', 'join_attempts', 'scans', 'verdicts',
  'blocklist_entries', 'ops_heartbeat', 'push_log', 'rate_limit_hits', 'ops_jobs'
]) as t
cross join unnest(array['anon', 'authenticated']) as r;

-- RLS enabled on every table in public
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS enabled on every public table');

-- Screenshots bucket is private
select is((select public from storage.buckets where id = 'screenshots'), false, 'bucket screenshots is private');

select * from finish();
rollback;
