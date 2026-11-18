-- ADM-07 admin dashboard: the permanent scan archive (dashboard plan fase 07a K5, K8–K12, K14, K15;
-- D-dash-17; invariants I5, I11 single-session part, I13 as amended by K15). Fixtures are made-up
-- `.test` domains only.
create extension if not exists pgtap with schema extensions;

begin;
select plan(61);

-- QA-D-H02: the dashboard scans.jsonl export pages on (created_at, scan_id) up to an hour cutoff.
select has_index('admin', 'scan_archive', 'scan_archive_created', array['created_at', 'scan_id'],
  'index for the scans.jsonl keyset (created_at, scan_id)');

create function pg_temp.as_role(r text, q text) returns text language plpgsql as $$
declare
  out text;
begin
  execute format('set local role %I', r);
  execute q into out;
  reset role;
  return coalesce(out, '');
exception when others then
  reset role;
  return 'ERR ' || sqlstate;
end $$;

-- Character class per position: digit 0, lower a, upper A, others as they are.
create function pg_temp.shape(p text) returns text language sql as $$
  select regexp_replace(regexp_replace(regexp_replace(p, '[0-9]', '0', 'g'), '[a-z]', 'a', 'g'), '[A-Z]', 'A', 'g')
$$;

create function pg_temp.arc(p_id text) returns admin.scan_archive language sql as $$
  select * from admin.scan_archive where scan_id = p_id
$$;

-- ---------------------------------------------------------------- objects

select has_table('admin', 'scan_archive', 'admin.scan_archive exists');
select has_trigger('public', 'scans', 'admin_scan_fragments', 'admin_scan_fragments on public.scans');
select has_trigger('admin', 'label_forget', 'admin_archive_forget', 'admin_archive_forget on admin.label_forget');
select columns_are('admin', 'v_scan_archive',
  array['scan_id', 'domain', 'path', 'page_title', 'score', 'status', 'signals', 'signal_ids', 'layers',
        'detected_at', 'created_at', 'owner_ref', 'verdict', 'verdict_at', 'by_ref', 'note',
        'fragments_key', 'fragments_bytes', 'stripped_at', 'rdap_registered_at'],
  'K15: v_scan_archive columns (pseudonyms, never owner_id/by_device_id/name/raw URL)');
select hasnt_column('admin', 'scan_archive', c, 'admin.scan_archive has no ' || c)
from unnest(array['owner_id', 'by_device_id', 'by_name', 'name', 'url']) as c;
select is((select count(*)::int from pg_proc
            where pronamespace = 'admin'::regnamespace
              and proname in ('on_scan_insert', 'on_verdict', 'on_device_delete', 'on_family_unlink', 'on_scan_fragments')
              and proconfig @> array['lock_timeout=200ms'] and prosecdef),
  5, 'A8: archive trigger functions are security definer with lock_timeout 200ms');

select is((select value from admin.v_config where key = 'archive_warn_mb'), '5120'::jsonb, '07b K9: archive_warn_mb default');

-- ---------------------------------------------------------------- fixtures

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('a_g1', 'Guardian Arsip', 'guardian',  'avatar_01', '\xc1'),
  ('a_p1', 'Ibu Arsip',      'protected', 'avatar_04', '\xc4'),
  ('a_p2', 'Ayah Arsip',     'protected', 'avatar_05', '\xc5'),
  ('a_p3', 'Sendiri Arsip',  'protected', 'avatar_06', '\xc6');
insert into family_links (protected_id, guardian_id) values ('a_p1', 'a_g1'), ('a_p2', 'a_g1');

-- ---------------------------------------------------------------- K9 scan insert

insert into scans (id, owner_id, url, domain, page_title, score, status, signals, detected_at) values
  ('a_s1', 'a_p1', 'https://login.arsip.test/akun/masuk?otp=123456#top', 'arsip.test', 'Masuk Akun', 85, 'blocked',
   '[{"id": "asks_otp", "layer": 3, "weight": 30, "label": {"en": "x", "id": "x"}, "labelSimple": {"en": "y", "id": "y"}, "evidence": "Kode OTP"},
     {"id": "new_domain", "layer": 1, "weight": 20, "label": {"en": "x", "id": "x"}, "labelSimple": {"en": "y", "id": "y"}},
     {"id": "Bad Id!", "layer": 2, "weight": 5}]',
   '2026-11-04 10:17:43+00');

select is((pg_temp.arc('a_s1')).url_path, '/akun/masuk', 'K8: query string and fragment are not kept');
select is((pg_temp.arc('a_s1')).owner_ref, admin.owner_ref('a_p1'), 'K9: owner_ref of the owner');
select is((pg_temp.arc('a_s1')).signals,
  '[{"id": "asks_otp", "layer": 3, "weight": 30, "evidence": "Kode OTP"}, {"id": "new_domain", "layer": 1, "weight": 20}]'::jsonb,
  '#12b: signals keep id, layer, weight, evidence only; junk ids dropped');
select is((select array(select unnest((pg_temp.arc('a_s1')).signal_ids) order by 1)), array['asks_otp', 'new_domain'],
  '#12c: signal_ids');
select is((select array(select unnest((pg_temp.arc('a_s1')).layers) order by 1)), array[1, 3]::smallint[], '#12c: layers');
select is((select scans from admin.domain_intel where domain = 'arsip.test'), 1::bigint,
  '#12e: the same trigger still counts domain_intel');
select is((pg_temp.arc('a_s1')).fragments_key, null, 'no fragments until the API stores them');

-- I5: a failing archive write keeps the scan and the domain_intel count (id longer than the archive allows).
select lives_ok($$insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  (repeat('z', 80), 'a_p1', 'https://arsip.test/', 'arsip.test', 40, 'warning', now())$$,
  'I5: a failed archive write does not fail the scan insert');
select is((select scans from admin.domain_intel where domain = 'arsip.test'), 2::bigint,
  'I5: domain_intel counted although the archive write failed');
select is((select count(*)::int from admin.scan_archive where scan_id = repeat('z', 80)), 0, 'I5: no archive row for it');

-- ---------------------------------------------------------------- K5 fragments key

update scans set fragments_bytes = 1200 where id = 'a_s1';
select is((pg_temp.arc('a_s1')).fragments_key, 'a_s1.fragments.html.gz', 'K5: fragments key copied from the scan');
select is((pg_temp.arc('a_s1')).fragments_bytes, 1200, 'K5: fragments bytes copied');

-- ---------------------------------------------------------------- K10 feedback

insert into scans (id, owner_id, url, domain, score, status, signals, detected_at) values
  ('a_s2', 'a_p2', 'https://aman.test/x', 'aman.test', 45, 'warning', '[{"id": "new_domain", "layer": 1, "weight": 20}]', now() - interval '2 hours'),
  ('a_s3', 'a_p2', 'https://aman.test/y', 'aman.test', 50, 'warning', '[{"id": "new_domain", "layer": 1, "weight": 20}]', now() - interval '1 hour');
update scans set fragments_bytes = 800 where id = 'a_s3';
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('a_p1', 'arsip.test', 'not_safe', 'a_s1', 'a_g1', 'Guardian Arsip');
select is((pg_temp.arc('a_s1')).verdict, 'not_safe', 'K10: verdict on the scan row');
select is((pg_temp.arc('a_s1')).by_ref, admin.owner_ref('a_g1'), 'K10: by_ref of the deciding Guardian');
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('a_p2', 'aman.test', 'safe', null, 'a_g1', 'Guardian Arsip');
select is((pg_temp.arc('a_s3')).verdict, 'safe', 'K10: scan_id null → the owner''s latest scan of the domain');
select is((pg_temp.arc('a_s2')).verdict, null, 'K10: older scans of that domain untouched');
update verdicts set value = 'not_safe' where owner_id = 'a_p2' and domain = 'aman.test';
select is((pg_temp.arc('a_s3')).verdict, 'not_safe', 'K10: a changed decision updates the row');

-- ---------------------------------------------------------------- K15 view, tokens and grants

select is((select path from admin.v_scan_archive where scan_id = 'a_s1'), '/akun/masuk', 'K15: plain path shown as is');
select is(admin.tokenize_path('/verify-account-now/step2'), '/verify-account-now/step2', 'K13: words stay readable');
select isnt(admin.tokenize_path('/r/0123456789abcdef0123'), '/r/0123456789abcdef0123', 'K13: a hex token is replaced');
select is(pg_temp.shape(admin.tokenize_path('/r/0123456789abcdef0123')), pg_temp.shape('/r/0123456789abcdef0123'),
  'K13: same length and character class per position');
select is(pg_temp.shape(admin.tokenize_path('/t/eyJhbGciOiJIUzI1NiJ9.abc')), pg_temp.shape('/t/eyJhbGciOiJIUzI1NiJ9.abc'),
  'K13: a base64url token keeps its shape, dots kept');
select isnt(admin.tokenize_path('/r/0123456789abcdef0123'), admin.tokenize_path('/r/0123456789abcdef0123'),
  'K13: new random value on every call');
select isnt(admin.tokenize_path('/order/8841027'), '/order/8841027', 'audit: a numeric id is replaced');
select is(pg_temp.shape(admin.tokenize_path('/u/budi1984')), pg_temp.shape('/u/budi1984'), 'audit: a short id keeps its shape');
select isnt(admin.tokenize_path('/u/budi1984'), '/u/budi1984', 'audit: a short id is replaced');
select is(admin.tokenize_path('/2026/11/05/klaim-hadiah'), '/2026/11/05/klaim-hadiah', 'audit: a date path and words stay readable');
select is(pg_temp.as_role('shoo_admin', $$select count(*)::text from admin.v_scan_archive where scan_id like 'a\_%'$$), '3', 'shoo_admin reads the view');
select is(pg_temp.as_role('shoo_admin', $$select count(*)::text from admin.scan_archive$$), 'ERR 42501', 'shoo_admin cannot read the table');
select is(pg_temp.as_role('shoo_api', $$select count(*)::text from admin.v_scan_archive$$), 'ERR 42501', 'shoo_api cannot read the view');
select is(pg_temp.as_role('shoo_admin', $$select fragment_bytes::text from admin.v_archive_size$$), '2000', '07b K9: archive size');

-- ---------------------------------------------------------------- K11 disconnect

delete from family_links where protected_id = 'a_p2' and guardian_id = 'a_g1';
select is((pg_temp.arc('a_s3')).verdict, null, 'K11: disconnect clears the pair''s feedback');
select is((pg_temp.arc('a_s3')).owner_ref, admin.owner_ref('a_p2'), 'K11: disconnect keeps the owner link');

-- ---------------------------------------------------------------- K11 + K12 account deletion

delete from devices where id = 'a_p2';
select is((pg_temp.arc('a_s3')).owner_ref, null, 'K11: delete strips owner_ref');
select isnt((pg_temp.arc('a_s3')).stripped_at, null, 'K11: stripped_at set');
select is((select count(*)::int from admin.scan_archive where scan_id in ('a_s2', 'a_s3')), 2, 'K11: rows kept, not deleted');
select is((pg_temp.arc('a_s3')).detected_at, date_trunc('hour', (pg_temp.arc('a_s3')).detected_at), 'K11: time rounded to the hour');
select is((pg_temp.arc('a_s3')).fragments_key, null, 'K12: fragments of a domain without scam evidence go');
select is((select count(*)::int from storage_tombstones where path = 'a_s3.fragments.html.gz'), 1,
  'K12: their object is tombstoned for the cron');

delete from devices where id = 'a_p1';
select is((pg_temp.arc('a_s1')).fragments_key, 'a_s1.fragments.html.gz', 'K12: a not_safe domain keeps its fragments');
select is((pg_temp.arc('a_s1')).page_title, null, 'K11: page title stripped');
select is((pg_temp.arc('a_s1')).verdict, 'not_safe', 'K11: the decision stays, unlinked');
select is((pg_temp.arc('a_s1')).by_ref, null, 'K11: by_ref stripped');

-- ---------------------------------------------------------------- I11 queue

insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('a_s4', 'a_p3', 'https://antre.test/', 'antre.test', 40, 'warning', now());
update admin.scan_archive set fragments_key = 'a_s4.fragments.html.gz', fragments_bytes = 5 where scan_id = 'a_s4';
insert into admin.label_forget (owner_ref, by_ref) values (admin.owner_ref('a_p3'), null);
select is((select fragments_key from admin.v_scan_archive where scan_id = 'a_s4'), null, 'I11: a queued forget hides the fragments');
select is((select fragments_bytes from admin.v_scan_archive where scan_id = 'a_s4'), null, 'I11: and their size');
select is((select owner_ref from admin.v_scan_archive where scan_id = 'a_s4'), null, 'I11: a queued forget hides owner_ref at once');
delete from admin.label_forget where owner_ref = admin.owner_ref('a_p3');
select is((pg_temp.arc('a_s4')).owner_ref, null, 'I11: draining the queue applies the strip');

-- ---------------------------------------------------------------- K14 backfill

alter table public.scans disable trigger admin_scan_intel;
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('a_s5', 'a_p3', 'https://lama-arsip.test/a?b=c', 'lama-arsip.test', 40, 'warning', now());
alter table public.scans enable trigger admin_scan_intel;
select admin._archive_backfill();
select admin._archive_backfill();
select is((select count(*)::int from admin.scan_archive where scan_id = 'a_s5'), 1, 'K14: backfill twice adds the row once');
select is((pg_temp.arc('a_s5')).url_path, '/a', 'K14: backfill drops the query string');

select * from finish();
rollback;
