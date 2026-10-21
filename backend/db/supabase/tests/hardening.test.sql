-- Fase 12 hardening (D-alief-B12): role timeouts, the Worker cannot approve blocklist domains (T5).
create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

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

select * from finish();
rollback;
