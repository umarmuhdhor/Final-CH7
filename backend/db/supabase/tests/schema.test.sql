-- Schema invariants I1–I6, I8 (plan/alief/ref/R2-skema-db.md §4).
create extension if not exists pgtap with schema extensions;

begin;
select plan(28);

select has_table('public', t, 'table ' || t || ' exists')
from unnest(array[
  'devices', 'family_links', 'family_codes', 'join_attempts', 'scans', 'verdicts',
  'blocklist_entries', 'ops_heartbeat', 'push_log', 'rate_limit_hits', 'ops_jobs'
]) as t;

select has_column('public', 'devices', 'ext_last_seen_at', 'devices.ext_last_seen_at exists');

-- Fixture devices
insert into devices (id, name, mode, avatar_id, token_hash) values
  ('t_g1', 'Guardian', 'guardian', 'avatar_01', '\x01'),
  ('t_g2', 'Other',    'guardian', 'avatar_02', '\x02'),
  ('t_p1', 'Mom',      'protected', 'avatar_03', '\x03'),
  ('t_p2', 'Dad',      'protected', 'avatar_04', '\x04'),
  ('t_p3', 'Aunt',     'protected', 'avatar_05', '\x05'),
  ('t_p4', 'Uncle',    'protected', 'avatar_06', '\x06');

-- I1
select throws_ok(
  $$update devices set mode = 'protected' where id = 't_g1'$$,
  '23514', 'device mode is immutable', 'I1: mode cannot change');

select lives_ok(
  $$update devices set name = 'Renamed' where id = 't_g1'$$,
  'I1: other columns can change');

-- I4
select throws_ok(
  $$insert into family_links (protected_id, guardian_id) values ('t_g2', 't_g1')$$,
  '23514', null, 'I4: protected side must be a protected device');
select throws_ok(
  $$insert into family_links (protected_id, guardian_id) values ('t_p1', 't_p2')$$,
  '23514', null, 'I4: guardian side must be a guardian device');

-- I3
insert into family_links (protected_id, guardian_id) values
  ('t_p1', 't_g1'), ('t_p2', 't_g1'), ('t_p3', 't_g1');
select throws_ok(
  $$insert into family_links (protected_id, guardian_id) values ('t_p4', 't_g1')$$,
  '23514', 'family_full', 'I3: max 3 protected per guardian');

-- I2
select throws_ok(
  $$insert into family_links (protected_id, guardian_id) values ('t_p1', 't_g2')$$,
  '23505', null, 'I2: one guardian per protected');

-- I5
select throws_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at)
    values ('t_p1', 'https://a.example', 'a.example', 29, 'warning', now())$$,
  '23514', null, 'I5: score below 30 rejected');
select throws_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at)
    values ('t_p1', 'https://a.example', 'a.example', 85, 'warning', now())$$,
  '23514', null, 'I5: status must match score');
select lives_ok(
  $$insert into scans (id, owner_id, url, domain, score, status, detected_at)
    values ('t_s1', 't_p1', 'https://a.example/x', 'a.example', 92, 'blocked', now())$$,
  'I5: valid blocked scan');

-- I8
select throws_ok(
  $$insert into scans (owner_id, url, domain, score, status, detected_at)
    values ('t_p1', 'https://www.a.example', 'www.a.example', 40, 'warning', now())$$,
  '23514', null, 'I8: domain without www.');
select throws_ok(
  $$insert into blocklist_entries (domain) values ('Bad.Example')$$,
  '23514', null, 'I8: blocklist domain lowercase');

-- blocklist review fields (D-alief-B05)
select throws_ok(
  $$insert into blocklist_entries (domain, removed_at) values ('r.example', now())$$,
  '23514', null, 'blocklist: removed needs approved');
select throws_ok(
  $$insert into blocklist_entries (domain, approved_at) values ('n.example', now())$$,
  '23514', null, 'blocklist: approved needs approved_by');
insert into blocklist_entries (domain) values ('q.example');
update blocklist_entries set approved_at = '2000-01-01', approved_by = 't' where domain = 'q.example';
select ok((select approved_at > now() - interval '1 minute' from blocklist_entries where domain = 'q.example'),
  'blocklist: approval by update uses clock_timestamp()');

-- I6
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
values ('t_p1', 'a.example', 'not_safe', 't_s1', 't_g1', 'Guardian');
select throws_ok(
  $$insert into verdicts (owner_id, domain, value, by_device_id, by_name)
    values ('t_p1', 'a.example', 'safe', 't_g1', 'Guardian')$$,
  '23505', null, 'I6: one verdict per (owner, domain)');

-- name length
select throws_ok(
  $$insert into devices (name, mode, avatar_id, token_hash) values ('', 'guardian', 'avatar_01', '\x10')$$,
  '23514', null, 'name must be 1-20 chars');

select * from finish();
rollback;
