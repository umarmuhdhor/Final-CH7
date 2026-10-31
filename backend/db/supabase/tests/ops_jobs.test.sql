-- Fase 21a (B9): cron job status for GET /ops/status.
create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

select has_table('public', 'ops_jobs', 'ops_jobs exists');
select col_is_pk('public', 'ops_jobs', 'job', 'job is the primary key');
select throws_ok($$insert into ops_jobs (job) values ('x')$$, '23514', null, 'job must be retention or notifications');
select lives_ok($$insert into ops_jobs (job) values ('retention'), ('notifications')$$, 'both jobs can be stored');
select throws_ok($$update ops_jobs set failed = -1 where job = 'retention'$$, '23514', null, 'failed is never negative');
select table_privs_are('public', 'ops_jobs', 'shoo_api', array['SELECT', 'INSERT', 'UPDATE'],
  'shoo_api SELECT/INSERT/UPDATE on ops_jobs, no DELETE');
select table_privs_are('public', 'ops_jobs', r, array[]::text[], r || ' has no privileges on ops_jobs')
from unnest(array['anon', 'authenticated', 'service_role']) as r;
select ok((select relrowsecurity from pg_class where oid = 'public.ops_jobs'::regclass), 'RLS enabled on ops_jobs');

select * from finish();
rollback;
