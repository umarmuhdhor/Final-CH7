-- Fase 12 security review (D-alief-B12).
create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

select is(
  (select count(*)::int from information_schema.role_table_grants
    where grantee = 'service_role' and table_schema = 'public'),
  0, 'service_role has no privileges on public tables');
select ok(not has_table_privilege('service_role', 'blocklist_entries', 'UPDATE'), 'service_role cannot approve via the Data API');

select has_table('public', 'storage_tombstones', 'storage_tombstones exists');
select table_privs_are('public', 'storage_tombstones', 'shoo_api', array['SELECT', 'INSERT', 'DELETE'], 'shoo_api SELECT/INSERT/DELETE on tombstones');
select throws_ok($$insert into storage_tombstones (path) values ('../etc/passwd')$$, '23514', null, 'tombstone path format is checked');

-- The test runner cannot switch to shoo_api, so the policies are checked in the catalog.
select policies_are('public', 'blocklist_entries',
  array['shoo_api_read', 'shoo_api_queue', 'shoo_api_recount', 'shoo_api_drop_undecided'],
  'blocklist_entries has per-command policies only');
select is((select cmd from pg_policies where tablename = 'blocklist_entries' and policyname = 'shoo_api_drop_undecided'),
  'DELETE', 'drop policy is DELETE only');
select ok((select qual from pg_policies where tablename = 'blocklist_entries' and policyname = 'shoo_api_drop_undecided')
  ~ 'approved_at IS NULL.*removed_at IS NULL', 'shoo_api deletes only undecided rows');
select ok((select with_check from pg_policies where tablename = 'blocklist_entries' and policyname = 'shoo_api_queue')
  ~ 'approved_at IS NULL.*removed_at IS NULL', 'shoo_api inserts only undecided rows');

select * from finish();
rollback;
