-- EGM audit B12: admin copies of a Guardian's note expire after 14 days, like public.verdicts.notes
-- (migration 20261119100000_admin_note_retention.sql).
create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

select has_function('admin', 'expire_notes', 'admin.expire_notes exists');
select has_trigger('public', 'verdicts', 'admin_verdict_notes_expire', 'the statement trigger is on public.verdicts');
select ok(not has_function_privilege('shoo_api', 'admin.expire_notes()', 'EXECUTE'), 'shoo_api cannot call admin.expire_notes (I2)');

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('n_p', 'P', 'protected', 'avatar_01', '\x21'),
  ('n_g', 'G', 'guardian', 'avatar_01', '\x22');
insert into family_links (protected_id, guardian_id) values ('n_p', 'n_g');
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('n_s1', 'n_p', 'https://note.test/old', 'note.test', 90, 'blocked', now() - interval '20 days'),
  ('n_s2', 'n_p', 'https://fresh.test/new', 'fresh.test', 90, 'blocked', now() - interval '1 minute');

-- The same upsert POST /verdicts runs (repo/verdicts.ts): the statement trigger must not break it.
insert into verdicts (owner_id, url, domain, value, notes, scan_id, by_device_id, by_name, decided_at)
values ('n_p', 'https://note.test/old', 'note.test', 'safe', 'reasons: official_site', 'n_s1', 'n_g', 'G', now())
on conflict (owner_id, url) do update set notes = excluded.notes;
insert into verdicts (owner_id, url, domain, value, notes, scan_id, by_device_id, by_name, decided_at)
values ('n_p', 'https://fresh.test/new', 'fresh.test', 'safe', 'reasons: used_before', 'n_s2', 'n_g', 'G', now())
on conflict (owner_id, url) do update set notes = excluded.notes;
select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('n_p') and note is not null), 2,
  'both decisions copied their note');

-- The old decision is 15 days old: its verdict and every admin copy.
update verdicts set decided_at = now() - interval '15 days' where url = 'https://note.test/old';
update admin.domain_labels set created_at = now() - interval '15 days' where owner_ref = admin.owner_ref('n_p') and domain = 'note.test';
update admin.guardian_decisions set created_at = now() - interval '15 days' where owner_ref = admin.owner_ref('n_p') and domain = 'note.test';
update admin.scan_archive set verdict_at = now() - interval '15 days', note = 'reasons: official_site' where scan_id = 'n_s1';

-- What the retention step verdict_notes does.
update verdicts set notes = null where notes is not null and decided_at < now() - interval '14 days';

select is((select notes from verdicts where url = 'https://note.test/old'), null, 'the verdict note is cleared (retention)');
select is((select count(*)::int from admin.domain_labels where domain = 'note.test' and note is not null), 0,
  'the label copy of the old note is cleared');
select is((select count(*)::int from admin.guardian_decisions where domain = 'note.test' and note is not null), 0,
  'the decision copy of the old note is cleared');
select is((select note from admin.scan_archive where scan_id = 'n_s1'), null, 'the archive copy of the old note is cleared');
select isnt((select note from admin.guardian_decisions where domain = 'fresh.test' and owner_ref = admin.owner_ref('n_p')), null,
  'a note younger than 14 days stays');
select isnt((select notes from verdicts where url = 'https://fresh.test/new'), null, 'its verdict note stays too');

select * from finish();
rollback;
