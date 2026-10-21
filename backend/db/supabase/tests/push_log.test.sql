-- push_log keeps no notification text and only short result codes (fase 11, D-alief-B11).
create extension if not exists pgtap with schema extensions;

begin;
select plan(7);

select hasnt_column('public', 'push_log', 'body', 'push_log has no body column (no copy of the name)');
select col_not_null('public', 'push_log', 'result', 'push_log.result is required');

insert into devices (id, name, mode, avatar_id, token_hash) values ('t_pg', 'G', 'guardian', 'avatar_01', '\x01');

select lives_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'sent')$$, 'sent is accepted');
select lives_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:410 Unregistered')$$, 'failed:<status> <reason> is accepted');
select lives_ok($$insert into push_log (to_device_id, result) values ('t_pg', 'failed:timeout')$$, 'failed:timeout is accepted');
select throws_ok(
  $$insert into push_log (to_device_id, result) values ('t_pg', 'failed:' || repeat('a', 64))$$,
  '23514', null, 'a token-like string is rejected');
select throws_ok(
  $$insert into push_log (to_device_id, result) values ('t_pg', 'failed:400 Bad token eyJhbGciOi')$$,
  '23514', null, 'free text with spaces is rejected');

select * from finish();
rollback;
