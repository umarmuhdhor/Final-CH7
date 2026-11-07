-- E7 (fase 24a-1): the inactive-devices retention step walks devices by last_seen_at.
create extension if not exists pgtap with schema extensions;

begin;

select plan(3);

select has_index('public', 'devices', 'devices_last_seen', array['last_seen_at'], 'inactive-devices walk (K1/K4)');
select ok((select indexdef from pg_indexes where indexname = 'devices_last_seen') !~ ' WHERE ', 'devices_last_seen is not partial');
select ok((select i.indisvalid from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'devices_last_seen'),
  'devices_last_seen is valid');

select * from finish();
rollback;
