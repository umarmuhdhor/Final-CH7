-- Fase 12 hardening (D-alief-B12): role timeouts, the Worker cannot approve blocklist domains (T5).
create extension if not exists pgtap with schema extensions;

begin;
select plan(19);

select ok(
  (select setconfig @> array['statement_timeout=10s'] from pg_db_role_setting where setrole = 'shoo_api'::regrole and setdatabase = 0),
  'shoo_api statement_timeout = 10s');
select ok(
  (select setconfig @> array['idle_in_transaction_session_timeout=15s'] from pg_db_role_setting where setrole = 'shoo_api'::regrole and setdatabase = 0),
  'shoo_api idle_in_transaction_session_timeout = 15s');
select ok(
  (select setconfig @> array['lock_timeout=5s'] from pg_db_role_setting where setrole = 'shoo_api'::regrole and setdatabase = 0),
  'shoo_api lock_timeout = 5s');

select ok(not has_table_privilege('shoo_api', 'blocklist_entries', 'UPDATE'), 'no table-wide UPDATE on blocklist_entries');
select ok(not has_table_privilege('shoo_api', 'blocklist_entries', 'INSERT'), 'no table-wide INSERT on blocklist_entries');
select ok(has_column_privilege('shoo_api', 'blocklist_entries', 'families', 'UPDATE'), 'UPDATE on families only');
select ok(not has_column_privilege('shoo_api', 'blocklist_entries', 'approved_at', 'UPDATE'), 'cannot approve (approved_at)');
select ok(not has_column_privilege('shoo_api', 'blocklist_entries', 'approved_at', 'INSERT'), 'cannot insert approved rows');
select ok(not has_column_privilege('shoo_api', 'blocklist_entries', 'removed_at', 'UPDATE'), 'cannot remove (removed_at)');

-- Fase 27c (F-B7, K5): the Worker re-queues a domain through public.queue_blocklist_domain, which
-- reads the reviewer's last decision itself. shoo_api still cannot read that history or write
-- rejected_at.
select ok(has_function_privilege('shoo_api', 'public.queue_blocklist_domain(text, integer)', 'EXECUTE'),
  'shoo_api may call queue_blocklist_domain');
select ok(not has_function_privilege('anon', 'public.queue_blocklist_domain(text, integer)', 'EXECUTE'),
  'anon may not call queue_blocklist_domain');
select ok(not has_function_privilege('authenticated', 'public.queue_blocklist_domain(text, integer)', 'EXECUTE'),
  'authenticated may not call queue_blocklist_domain');
select ok(not exists (
    select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'public.queue_blocklist_domain(text, integer)'::regprocedure and a.grantee = 0),
  'PUBLIC has no EXECUTE on queue_blocklist_domain');
select ok((select prosecdef from pg_proc where oid = 'public.queue_blocklist_domain(text, integer)'::regprocedure),
  'queue_blocklist_domain is security definer');
select is((select proconfig from pg_proc where oid = 'public.queue_blocklist_domain(text, integer)'::regprocedure),
  array['search_path=pg_catalog, pg_temp'], 'queue_blocklist_domain pins search_path');
select ok(not has_table_privilege('shoo_api', 'admin.review_decisions', 'SELECT'),
  'shoo_api still cannot read admin.review_decisions');
select ok(not has_column_privilege('shoo_api', 'blocklist_entries', 'rejected_at', 'UPDATE'),
  'shoo_api still cannot write rejected_at');
select throws_ok($$select public.queue_blocklist_domain('fase27c.example', 0)$$, '22023', 'invalid_families',
  'queue_blocklist_domain refuses families < 1');
select throws_ok($$select public.queue_blocklist_domain('fase27c.example', null)$$, '22023', 'invalid_families',
  'queue_blocklist_domain refuses null families');

select * from finish();
rollback;
