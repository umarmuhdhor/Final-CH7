-- QA-D-H01: one dataset row per Guardian decision (migration 20261113030000_admin_guardian_decisions.sql).
create extension if not exists pgtap with schema extensions;

begin;
select plan(24);

-- ---------------------------------------------------------------- shape

select has_table('admin', 'guardian_decisions', 'admin.guardian_decisions exists');
select table_privs_are('admin', 'guardian_decisions', 'shoo_admin', array[]::text[], 'shoo_admin has no privileges');
select table_privs_are('admin', 'guardian_decisions', 'shoo_api', array[]::text[], 'shoo_api has no privileges');
select ok((select relrowsecurity from pg_class where oid = 'admin.guardian_decisions'::regclass), 'RLS on');

-- ---------------------------------------------------------------- per link, locked slot

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('d_p', 'P', 'protected', 'avatar_01', '\x11'),
  ('d_g', 'G', 'guardian', 'avatar_01', '\x12');
insert into family_links (protected_id, guardian_id) values ('d_p', 'd_g');
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('d_s1', 'd_p', 'https://dec.test/a', 'dec.test', 90, 'blocked', now() - interval '2 minutes'),
  ('d_s2', 'd_p', 'https://dec.test/b', 'dec.test', 80, 'blocked', now() - interval '1 minute');

insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
values ('d_p', 'dec.test', 'not_safe', 'd_s1', 'd_g', 'G');
select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('d_p')), 1,
  'a verdict adds one decision');
select is((select label_id from admin.guardian_decisions where scan_id = 'd_s1'),
  (select id from admin.domain_labels where owner_ref = admin.owner_ref('d_p') and domain = 'dec.test'),
  'the decision points at the label it made');

insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
values ('d_p', 'dec.test', 'not_safe', 'd_s2', 'd_g', 'G');
select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('d_p')), 2,
  'a second link of the same domain is its own decision');
select is((select count(*)::int from admin.domain_labels where owner_ref = admin.owner_ref('d_p')), 1,
  'still one learning label per owner + domain (Q33)');
select is((select label_id from admin.guardian_decisions where scan_id = 'd_s2'), null,
  'no label made: label_id null');
select is((select count(*)::int from admin.ai_dataset where domain = 'dec.test'), 2,
  'ai_dataset: one row per decision');
select is((select score from admin.ai_dataset where scan_id = 'd_s2'), 80, 'ai_dataset: the scan''s own score');

update verdicts set value = 'not_safe' where scan_id = 'd_s1';
select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('d_p')), 2,
  'an upsert with the same value adds nothing');
update verdicts set value = 'safe' where scan_id = 'd_s1';
select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('d_p') and not is_scam), 1,
  'a changed value is a new decision (revision = new row)');
select is((select count(*)::int from admin.domain_labels where owner_ref = admin.owner_ref('d_p')), 1,
  'the locked label stays (Q33)');

-- ---------------------------------------------------------------- forget

delete from family_links where protected_id = 'd_p';
select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('d_p')), 0,
  'unlink deletes the pair''s decisions');
select is((select count(*)::int from admin.ai_dataset where domain = 'dec.test'), 0, 'and ai_dataset shows none');

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('e_p', 'P', 'protected', 'avatar_01', '\x13'),
  ('e_g', 'G', 'guardian', 'avatar_01', '\x14');
insert into family_links (protected_id, guardian_id) values ('e_p', 'e_g');
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('e_s1', 'e_p', 'https://dev.test/a', 'dev.test', 90, 'blocked', now());
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
values ('e_p', 'dev.test', 'not_safe', 'e_s1', 'e_g', 'G');
delete from devices where id = 'e_g';
select is((select count(*)::int from admin.guardian_decisions where by_ref = admin.owner_ref('e_g')), 0,
  'device delete deletes its decisions');

insert into admin.guardian_decisions (domain, owner_ref, by_ref, is_scam, connected, created_at) values
  ('forget.test', 'aaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbb', true, true, clock_timestamp() - interval '1 minute');
insert into admin.label_forget (owner_ref, by_ref) values ('aaaaaaaaaaaaaaaa', null);
insert into admin.guardian_decisions (domain, owner_ref, by_ref, is_scam, connected, created_at) values
  ('forget.test', 'aaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbb', false, true, clock_timestamp() + interval '1 hour');
select is((select count(*)::int from admin.ai_dataset where domain = 'forget.test'), 1,
  'a queued forget hides older decisions at once');
delete from admin.label_forget where owner_ref = 'aaaaaaaaaaaaaaaa';
select is((select count(*)::int from admin.guardian_decisions where domain = 'forget.test'), 1,
  'the drain deletes the older decision');
select ok((select not is_scam from admin.guardian_decisions where domain = 'forget.test'),
  'a decision after the forget entry stays');

-- ---------------------------------------------------------------- backfill

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('b_p', 'P', 'protected', 'avatar_01', '\x15'),
  ('b_g', 'G', 'guardian', 'avatar_01', '\x16');
insert into family_links (protected_id, guardian_id) values ('b_p', 'b_g');
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('b_s1', 'b_p', 'https://bf.test/a', 'bf.test', 90, 'blocked', now() - interval '2 minutes'),
  ('b_s2', 'b_p', 'https://bf.test/b', 'bf.test', 90, 'blocked', now() - interval '1 minute');
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('b_p', 'bf.test', 'not_safe', 'b_s1', 'b_g', 'G'),
  ('b_p', 'bf.test', 'not_safe', 'b_s2', 'b_g', 'G');
delete from admin.guardian_decisions;
select admin._guardian_decisions_backfill(now() - interval '1 hour');

select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('b_p')), 2,
  'backfill: the label plus the per-link verdict it does not represent');
select is((select count(*)::int from admin.guardian_decisions g join admin.domain_labels l on l.id = g.id
            where g.owner_ref = admin.owner_ref('b_p') and g.label_id = g.id), 1,
  'backfill: a label keeps its id (label_id = id)');
select is((select label_id from admin.guardian_decisions where scan_id = 'b_s2'), null,
  'backfill: the extra row comes from the verdict');
select is((select count(*)::int from admin.guardian_decisions where owner_ref = admin.owner_ref('d_p')), 0,
  'backfill: an unlinked pair stays forgotten');

select * from finish();
rollback;
