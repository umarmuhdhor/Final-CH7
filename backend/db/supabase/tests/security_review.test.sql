-- Fase 12 security review (D-alief-B12).
create extension if not exists pgtap with schema extensions;

begin;
select plan(18);

select is(
  (select count(*)::int from information_schema.role_table_grants
    where grantee = 'service_role' and table_schema = 'public'),
  0, 'service_role has no privileges on public tables');
select ok(not has_table_privilege('service_role', 'blocklist_entries', 'UPDATE'), 'service_role cannot approve via the Data API');

select has_table('public', 'storage_tombstones', 'storage_tombstones exists');
select table_privs_are('public', 'storage_tombstones', 'shoo_api', array['SELECT', 'INSERT', 'DELETE'], 'shoo_api SELECT/INSERT/DELETE on tombstones');
select ok(has_column_privilege('shoo_api', 'storage_tombstones', 'attempts', 'UPDATE')
  and not has_column_privilege('shoo_api', 'storage_tombstones', 'path', 'UPDATE'), 'shoo_api updates only the retry columns');
select throws_ok($$insert into storage_tombstones (path) values (repeat('a', 301))$$, '23514', null, 'tombstone path length is checked');
select has_index('public', 'scans', 'scans_original_shot', 'partial index on original uploads');
select has_index('public', 'scans', 'scans_shot_path', 'index for path lookups per owner');

-- Fase 18 (EX-07): page replica columns.
insert into devices (id, name, mode, avatar_id, token_hash) values ('t_rp', 'Mom', 'protected', 'avatar_01', '\x10');
insert into scans (id, owner_id, url, domain, score, status, detected_at)
  values ('t_rs', 't_rp', 'https://a.example/', 'a.example', 92, 'blocked', now());
select throws_ok($$update scans set replica_path = repeat('a', 301) where id = 't_rs'$$, '23514', null, 'replica_path length is checked');
select throws_ok($$update scans set replica_path = 't_rp/t_rs-replica.html.gz', replica_bytes = 0 where id = 't_rs'$$, '23514', null, 'replica_bytes at least 1');
select throws_ok($$update scans set replica_path = 't_rp/t_rs-replica.html.gz', replica_bytes = 307201 where id = 't_rs'$$, '23514', null, 'replica_bytes at most 307 200');
select throws_ok($$update scans set replica_bytes = 10 where id = 't_rs'$$, '23514', null, 'replica_bytes needs replica_path');
select lives_ok($$update scans set replica_path = 't_rp/t_rs-replica.html.gz', replica_bytes = 307200 where id = 't_rs'$$, 'an original upload of 307 200 bytes');
select lives_ok($$update scans set replica_bytes = null where id = 't_rs'$$, 'a reuse row keeps the path without bytes');

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
