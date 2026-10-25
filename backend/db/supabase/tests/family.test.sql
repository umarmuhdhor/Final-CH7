-- Fase 08 family tables (R2, D-alief-B06).
create extension if not exists pgtap with schema extensions;

begin;
select plan(8);

select hasnt_column('public', 'join_attempts', 'ip', 'join_attempts stores no raw IP');
select col_type_is('public', 'join_attempts', 'ip_hash', 'bytea', 'join_attempts.ip_hash is bytea');
select col_not_null('public', 'join_attempts', 'ip_hash', 'join_attempts.ip_hash is not null');
select has_index('public', 'join_attempts', 'join_attempts_ip_time', 'index on ip_hash + time');
select has_index('public', 'join_attempts', 'join_attempts_time', 'index on attempted_at');
select has_index('public', 'family_codes', 'family_codes_expires', 'index on expires_at');
select col_type_is('public', 'family_codes', 'code', 'character(6)', 'family_codes.code is 6 characters (PR-03, #128)');
select throws_ok(
  $$insert into family_codes (code, guardian_id, expires_at) values ('1234', 'nobody', now())$$,
  '23514', null, 'a 4-digit code is rejected');

select * from finish();
rollback;
