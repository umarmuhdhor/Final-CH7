-- push_log keeps no notification text and only short result codes (fase 11, D-alief-B11).
create extension if not exists pgtap with schema extensions;

begin;
select plan(15);

select hasnt_column('public', 'push_log', 'body', 'push_log has no body column (no copy of the name)');
select col_not_null('public', 'push_log', 'result', 'push_log.result is required');
select has_check('public', 'push_log', 'push_log has a check constraint');
select has_index('public', 'push_log', 'push_log_device_created', array['to_device_id', 'created_at'], 'cap count index (guardian, time)');
select hasnt_index('public', 'push_log', 'push_log_device', 'old single-column index replaced');
select has_index('public', 'push_log', 'push_log_created', 'retention index kept');

insert into devices (id, name, mode, avatar_id, token_hash) values ('t_pg', 'G', 'guardian', 'avatar_01', '\x01');
insert into scans (id, owner_id, url, domain, score, status, detected_at)
  values ('t_scan', 't_pg', 'https://x.example/', 'x.example', 92, 'blocked', now());

select lives_ok($$insert into push_log (to_device_id, scan_id, result) values ('t_pg', 't_scan', 'sent')$$, 'sent is accepted');
select lives_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:410 Unregistered')$$, 'failed:<status> <reason> is accepted');
select lives_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:timeout')$$, 'failed:timeout is accepted');

select throws_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:' || repeat('a', 64))$$,
  '23514', null, 'a token-like string is rejected');
select throws_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:400 Bad token eyJhbGciOi')$$,
  '23514', null, 'free text with spaces is rejected');
select throws_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'sent' || E'\n')$$,
  '23514', null, 'a trailing newline is rejected');
select throws_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:4100')$$,
  '23514', null, 'a 4-digit status is rejected');
select throws_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:410 Unregistered extra')$$,
  '23514', null, 'a second word is rejected');

delete from scans where id = 't_scan';
select is((select count(*)::int from push_log where scan_id = 't_scan'), 0, 'deleting the scan removes its push rows (P13)');

select * from finish();
rollback;
