-- PF-01 settings: notification switches, quiet hours, time zone, protection-off mark.
create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

select col_default_is('public', 'devices', 'notify_blocked', 'true', 'Situs diblokir is on by default');
select col_default_is('public', 'devices', 'weekly_summary', 'false', 'weekly summary is off by default');
select col_default_is('public', 'devices', 'quiet_start', '1320', 'quiet hours start at 22:00');
select col_default_is('public', 'devices', 'quiet_end', '360', 'quiet hours end at 06:00');
select col_default_is('public', 'devices', 'time_zone', 'Asia/Jakarta', 'WIB until the phone says otherwise');
select has_column('public', 'family_links', 'off_notified_at', 'family_links.off_notified_at exists');

insert into devices (id, name, mode, avatar_id, token_hash) values ('t_ns', 'Mom', 'protected', 'avatar_01', '\x02');

select lives_ok($$update devices set time_zone = 'America/Argentina/Buenos_Aires', quiet_start = 0, quiet_end = 1439 where id = 't_ns'$$, 'three-part zone and edge minutes accepted');
select throws_ok($$update devices set quiet_start = 1440 where id = 't_ns'$$, '23514', null, 'minute past midnight rejected');
select throws_ok($$update devices set time_zone = 'Asia/Jakarta; drop table devices' where id = 't_ns'$$, '23514', null, 'zone with other characters rejected');
select throws_ok($$update devices set time_zone = repeat('A', 41) where id = 't_ns'$$, '23514', null, 'zone over 40 characters rejected');

select * from finish();
rollback;
