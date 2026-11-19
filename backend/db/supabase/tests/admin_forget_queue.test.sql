-- EGM audit B13: a failed archive forget, of any kind, is queued for the drain instead of lost
-- (migration 20261119110000_admin_forget_queue_all_errors.sql).
create extension if not exists pgtap with schema extensions;

begin;
select plan(4);

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('q_p', 'P', 'protected', 'avatar_01', '\x31'),
  ('q_g', 'G', 'guardian', 'avatar_01', '\x32'),
  ('q_x', 'X', 'guardian', 'avatar_01', '\x33');
insert into family_links (protected_id, guardian_id) values ('q_p', 'q_g');

-- Not a held row: any other error inside the archive forget (rolled back with this test).
create or replace function admin._archive_forget(p_owner text, p_by text, p_at timestamptz) returns void
language plpgsql as $$ begin raise exception 'boom' using errcode = 'check_violation'; end $$;

delete from family_links where protected_id = 'q_p' and guardian_id = 'q_g';
select is((select count(*)::int from admin.label_forget
            where owner_ref = admin.owner_ref('q_p') and by_ref = admin.owner_ref('q_g')), 1,
  'an unlink whose archive forget fails is queued');
select is((select count(*)::int from family_links where protected_id = 'q_p'), 0, 'the unlink still committed');

delete from devices where id = 'q_x';
select is((select count(*)::int from admin.label_forget where owner_ref = admin.owner_ref('q_x') and by_ref is null), 1,
  'a device delete whose archive forget fails is queued');
select is((select count(*)::int from devices where id = 'q_x'), 0, 'the device delete still committed');

select * from finish();
rollback;
