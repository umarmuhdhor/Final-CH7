-- EX-03 (#555): the Dynamic Island's APNs token columns are gone from devices.
create extension if not exists pgtap with schema extensions;

begin;
select plan(6);

select has_table('public', 'devices', 'devices exists (so the checks below cannot pass vacuously)');
select hasnt_column('public', 'devices', 'live_start_token', 'devices.live_start_token dropped');
select hasnt_column('public', 'devices', 'live_update_token', 'devices.live_update_token dropped');
select hasnt_column('public', 'devices', 'live_activity_id', 'devices.live_activity_id dropped');
select hasnt_column('public', 'devices', 'live_started_at', 'devices.live_started_at dropped');
select is_empty(
  $$select conname from pg_constraint where conrelid = 'public.devices'::regclass and conname like 'devices\_live\_%'$$,
  'no devices_live_* constraint left (devices_live_update_pair and the column checks)'
);

select * from finish();
rollback;
