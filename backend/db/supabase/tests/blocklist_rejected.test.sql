-- Blocklist review: rejected state (issue #99 Q3). Only a reviewer (postgres) rejects; a rejected row is never served.
create extension if not exists pgtap with schema extensions;

begin;
select plan(7);

select has_column('public', 'blocklist_entries', 'rejected_at', 'blocklist_entries.rejected_at exists');
select has_column('public', 'blocklist_entries', 'rejected_by', 'blocklist_entries.rejected_by exists');
select ok(not has_column_privilege('shoo_api', 'blocklist_entries', 'rejected_at', 'UPDATE')
  and not has_column_privilege('shoo_api', 'blocklist_entries', 'rejected_by', 'UPDATE'), 'shoo_api cannot reject');
select ok(not has_column_privilege('shoo_api', 'blocklist_entries', 'rejected_at', 'INSERT'), 'shoo_api cannot insert rejected rows');

select throws_ok(
  $$insert into blocklist_entries (domain, rejected_at) values ('nb.example', now())$$,
  '23514', null, 'rejected needs rejected_by');
insert into blocklist_entries (domain, rejected_at, rejected_by) values ('rj.example', now(), 't');
select throws_ok(
  $$update blocklist_entries set approved_at = now(), approved_by = 't' where domain = 'rj.example'$$,
  '23514', null, 'a rejected row cannot be approved');
select lives_ok(
  $$update blocklist_entries set rejected_at = null, rejected_by = null, approved_at = now(), approved_by = 't'
    where domain = 'rj.example'$$,
  'clearing the rejection allows approval');

select * from finish();
rollback;
