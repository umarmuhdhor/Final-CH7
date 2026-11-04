-- #270: RDAP registration date on public.scans and admin.scan_archive. Fixtures are made-up
-- `.test` domains only.
create extension if not exists pgtap with schema extensions;

begin;
select plan(11);

select has_column('public', 'scans', 'rdap_registered_at', 'scans.rdap_registered_at exists');
select col_type_is('public', 'scans', 'rdap_registered_at', 'date', 'scans.rdap_registered_at is a date');
select has_column('admin', 'scan_archive', 'rdap_registered_at', 'scan_archive.rdap_registered_at exists');
select has_trigger('public', 'scans', 'admin_scan_rdap', 'admin_scan_rdap on public.scans');
select ok((select prosecdef and proconfig @> array['lock_timeout=200ms'] from pg_proc
            where oid = 'admin.on_scan_rdap()'::regprocedure),
  'A8: on_scan_rdap is security definer with lock_timeout 200ms');
select ok(not has_function_privilege('shoo_api', 'admin.on_scan_rdap()', 'execute')
          and not has_function_privilege('shoo_admin', 'admin.on_scan_rdap()', 'execute'),
  'on_scan_rdap is executable by neither shoo_api nor shoo_admin');

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('r_p1', 'Ibu RDAP', 'protected', 'avatar_04', '\xd4');

insert into scans (id, owner_id, url, domain, score, status, detected_at, rdap_registered_at) values
  ('r_s1', 'r_p1', 'https://rdap-kenal.test/masuk', 'rdap-kenal.test', 85, 'blocked', now(), '2026-10-30'),
  ('r_s2', 'r_p1', 'https://rdap-kosong.test/masuk', 'rdap-kosong.test', 85, 'blocked', now(), null);

select is((select rdap_registered_at from admin.scan_archive where scan_id = 'r_s1'), date '2026-10-30',
  'insert: the archive row gets the date');

update scans set rdap_registered_at = '2026-09-01' where id = 'r_s2';
select is((select rdap_registered_at from admin.scan_archive where scan_id = 'r_s2'), date '2026-09-01',
  'first known date of a kept row reaches the archive');

update scans set rdap_registered_at = '2020-01-01' where id = 'r_s1';
select is((select rdap_registered_at from admin.scan_archive where scan_id = 'r_s1'), date '2026-10-30',
  'a known archive date is never overwritten');

select throws_ok($$insert into scans (id, owner_id, url, domain, score, status, detected_at, rdap_registered_at)
                   values ('r_s3', 'r_p1', 'https://rdap-tua.test/', 'rdap-tua.test', 85, 'blocked', now(), '1984-12-31')$$,
  '23514', null, 'a date before 1985 is refused by the floor check');

select columns_are('admin', 'v_scan_archive',
  array['scan_id', 'domain', 'path', 'page_title', 'score', 'status', 'signals', 'signal_ids', 'layers',
        'detected_at', 'created_at', 'owner_ref', 'verdict', 'verdict_at', 'by_ref', 'note',
        'fragments_key', 'fragments_bytes', 'stripped_at', 'rdap_registered_at'],
  'v_scan_archive shows rdap_registered_at');

select * from finish();
rollback;
