-- Fase 08 family tables (R2, D-alief-B06).
create extension if not exists pgtap with schema extensions;

begin;
select plan(6);

select hasnt_column('public', 'join_attempts', 'ip', 'join_attempts stores no raw IP');
select col_type_is('public', 'join_attempts', 'ip_hash', 'bytea', 'join_attempts.ip_hash is bytea');
select col_not_null('public', 'join_attempts', 'ip_hash', 'join_attempts.ip_hash is not null');
select has_index('public', 'join_attempts', 'join_attempts_ip_time', 'index on ip_hash + time');
select has_index('public', 'join_attempts', 'join_attempts_time', 'index on attempted_at');
select has_index('public', 'family_codes', 'family_codes_expires', 'index on expires_at');

select * from finish();
rollback;
