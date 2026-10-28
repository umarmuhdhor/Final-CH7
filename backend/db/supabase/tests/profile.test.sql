-- PF-01 profile redesign: lifetime counters, device info, "Kabari saya" and "Ingatkan" columns.
create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

select col_default_is('public', 'devices', 'blocked_total', '0', 'blocked_total starts at 0');
select col_default_is('public', 'devices', 'warning_total', '0', 'warning_total starts at 0');
select col_default_is('public', 'family_links', 'notify', 'true', 'Kabari saya is on by default');
select has_column('public', 'family_links', 'reminded_at', 'family_links.reminded_at exists');

insert into devices (id, name, mode, avatar_id, token_hash) values ('t_pf', 'Mom', 'protected', 'avatar_01', '\x01');

select lives_ok($$update devices set device_model = 'iPhone 15 Pro Max', os_version = '26' where id = 't_pf'$$, 'model and major version accepted');
select throws_ok($$update devices set device_model = '<script>' where id = 't_pf'$$, '23514', null, 'model with markup rejected');
select throws_ok($$update devices set device_model = repeat('a', 41) where id = 't_pf'$$, '23514', null, 'model over 40 characters rejected');
select throws_ok($$update devices set os_version = '26.1' where id = 't_pf'$$, '23514', null, 'minor version rejected');
select throws_ok($$update devices set blocked_total = -1 where id = 't_pf'$$, '23514', null, 'negative counter rejected');

select * from finish();
rollback;
