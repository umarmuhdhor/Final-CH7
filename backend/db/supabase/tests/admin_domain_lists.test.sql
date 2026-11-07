-- ADM-09 admin dashboard: admin.domain_lists, the one list of protected / trusted / hosting domains
-- (dashboard plan phase 10a K1–K11, R2 §2–§4, invariants I16–I18; I14/I15 are vitest, the golden file
-- is not readable from SQL). Error codes: SA0xx (R2 §4). Fixtures are made-up `.test` domains, plus
-- seed rows (bca.co.id, github.io, ...).
create extension if not exists pgtap with schema extensions;

begin;
select plan(103);

-- One SELECT as shoo_admin: its first column, or 'ERR <sqlstate> <message>' (as admin_schema.test.sql).
create function pg_temp.as_admin(q text) returns text language plpgsql as $$
declare
  out text;
begin
  set local role shoo_admin;
  execute q into out;
  reset role;
  return coalesce(out, '');
exception when others then
  return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $$;

-- Same, but an error returns its DETAIL (already_blocked carries JSON there).
create function pg_temp.detail_of(q text) returns text language plpgsql as $$
declare
  v_state  text;
  v_detail text;
begin
  set local role shoo_admin;
  execute q;
  reset role;
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_detail = pg_exception_detail;
  return v_state || ' ' || coalesce(v_detail, '');
end $$;

create function pg_temp.version() returns bigint language sql as $$ select version from admin.domain_lists_meta $$;

-- ---------------------------------------------------------------- objects, seed

select has_table('admin', 'domain_lists', 'admin.domain_lists exists');
select has_table('admin', 'domain_lists_meta', 'admin.domain_lists_meta exists');
select has_view('admin', v, 'admin.' || v || ' exists')
from unnest(array['v_domain_lists', 'v_domain_lists_public', 'v_shared_hosts']) as v;
select hasnt_table('admin', 'shared_hosts', 'K11: admin.shared_hosts is gone');
select hasnt_function('admin', 'shared_hosts_set', 'K11: admin.shared_hosts_set is gone');
select is((select count(*)::int from admin.domain_lists), 276, 'seed: 276 rows (domain-lists-seed.mjs)');
select is((select count(*)::int from admin.domain_lists where not locked or updated_by <> 'seed'), 0, 'seed rows are locked, by seed');
select is((select count(*)::int from admin.domain_lists where hard_locked), 64, 'seed: 46 brand rows + 18 L4-only rows hard_locked');
select is((select count(*)::int from admin.domain_lists where brand_id is not null and not hard_locked), 0, 'every brand row is hard_locked');
select is((select count(*)::int from admin.admin_audit where action like 'domain_list.%'), 0, 'I17: the seed is not audited');
select is((select version from admin.domain_lists_meta), 1::bigint, 'the seed insert is version 1');

-- ---------------------------------------------------------------- domain_match (K2)

select is((select (protected, trusted, hosting)::text from admin.domain_match(h)), want, 'domain_match ' || h || ' = ' || want)
from (values
  ('bca.co.id',            '(t,t,none)'),
  ('x.bca.co.id',          '(t,t,none)'),
  ('bca.co.id.evil.test',  '(f,f,none)'),
  ('co.id',                '(t,f,none)'),
  ('scam.co.id',           '(f,f,none)'),
  ('pajak.go.id',          '(t,t,none)'),
  ('a.b.go.id',            '(t,f,none)'),
  ('x.ac.id',              '(f,f,none)'),
  ('docs.google.com',      '(t,f,host_path)'),
  ('x.docs.google.com',    '(t,f,host_path)'),
  ('github.io',            '(t,f,subdomains)'),
  ('x.github.io',          '(f,f,subdomains)'),
  ('medium.com',           '(t,t,subdomains)'),
  ('www.medium.com',       '(t,t,subdomains)'),
  ('alice.medium.com',     '(t,f,subdomains)'),
  ('storage.googleapis.com', '(t,f,host_path)'),
  ('bucket.s3.amazonaws.com', '(f,f,subdomains)'),
  ('forms.cloud.microsoft', '(f,f,host_path)'),
  ('nothing-here.test',    '(f,f,none)')
) as x(h, want);

-- ---------------------------------------------------------------- privileges (I2 is in admin_grants.test.sql)

select is(pg_temp.as_admin($$select count(*)::text from admin.v_domain_lists$$), '276', 'shoo_admin reads v_domain_lists');
select is(pg_temp.as_admin($$select count(*)::text from admin.domain_lists$$) like 'ERR 42501%', true, 'shoo_admin cannot read the table');
select is(pg_temp.as_admin($$select count(*)::text from admin.v_shared_hosts where host in ('github.io', 'docs.google.com')$$), '2',
  'v_shared_hosts = rows with hosting');
select ok(has_table_privilege('shoo_api', 'admin.v_domain_lists_public', 'select'), 'shoo_api reads v_domain_lists_public (W16)');
select ok(not has_table_privilege('shoo_api', t, 'select'), 'shoo_api cannot read ' || t)
from unnest(array['admin.v_domain_lists', 'admin.v_shared_hosts', 'admin.domain_lists']) as t;
select ok(not has_function_privilege('shoo_api', f, 'execute'), 'shoo_api cannot execute ' || f)
from unnest(array['admin.domain_match(text)', 'admin.domain_set(text,text,boolean,text,boolean,text,text,text,integer)',
                  'admin.domain_remove(text,text,text,text)']) as f;
select is((select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
            where table_schema = 'admin' and table_name = 'v_domain_lists_public'),
  'domain,protect,trusted,hosting', 'v_domain_lists_public has the four public columns only');
select ok(not has_table_privilege('shoo_ai', 'admin.v_shared_hosts', 'select'), 'shoo_ai has no grant on v_shared_hosts');

-- ---------------------------------------------------------------- domain_set (K5, K6)

select is(pg_temp.as_admin($$select admin.domain_set('newpage.test', 'apex', false, 'none', false, 'pendek', 'a@test')$$),
  'ERR SA003 note_required', 'note of at least 10 characters');
select is(pg_temp.as_admin($$select admin.domain_set('Bad Domain', 'apex', false, 'none', false, 'catatan cukup panjang', 'a@test')$$),
  'ERR SA014 invalid_domain', 'invalid domain');
select is(pg_temp.as_admin($$select admin.domain_set('newpage.test', 'wide', false, 'none', false, 'catatan cukup panjang', 'a@test')$$)
  like 'ERR 22023%', true, 'unknown protect value');
select is(pg_temp.as_admin($$select admin.domain_set('newpage.test', 'none', false, 'none', false, 'catatan cukup panjang', 'a@test')$$)
  like 'ERR 22023%', true, 'a row that does nothing is refused');

select lives_ok($$select pg_temp.as_admin($q$select admin.domain_set('newpage.test', 'apex', false, 'none', false, 'halaman resmi baru', 'a@test')$q$)$$,
  'apex, untrusted: no confirm needed');
select is((select (protect, trusted, hosting, locked, updated_by)::text from admin.domain_lists where domain = 'newpage.test'),
  '(apex,f,none,f,a@test)', 'new row stored, not locked');
select is((select (action, target, before is null, after ->> 'protect', note)::text from admin.admin_audit
            where action = 'domain_list.set' order by id desc limit 1),
  '(domain_list.set,newpage.test,t,apex,"halaman resmi baru")', 'I17: audit with before/after');

select is(pg_temp.as_admin($$select admin.domain_set('trusted-new.test', 'subtree', true, 'none', false, 'situs resmi baru ini', 'a@test')$$),
  'ERR SA011 confirm_required', 'K6: a new trusted/subtree row needs confirm');
select is(pg_temp.as_admin($$select admin.domain_set('trusted-new.test', 'subtree', true, 'none', false, 'situs resmi baru ini', 'a@test', 'trusted-new.tes')$$),
  'ERR SA011 confirm_required', 'K6: confirm must equal the domain');
select is(pg_temp.as_admin($$select admin.domain_set('trusted-new.test', 'subtree', true, 'none', false, 'situs resmi baru ini', 'a@test', 'trusted-new.test')$$),
  '', 'K6: with the domain typed again it is stored');
select is(pg_temp.as_admin($$select admin.domain_set('newpage.test', 'apex', true, 'none', false, 'jadi resmi sekarang', 'a@test')$$),
  'ERR SA011 confirm_required', 'K6: switching trusted on needs confirm');

select is(pg_temp.as_admin($$select admin.domain_set('co.id', 'apex', true, 'none', true, 'percobaan suffix resmi', 'a@test', 'co.id')$$),
  'ERR SA021 domain_not_registrable', 'K6: trusted on a public suffix');
-- Security review 10b: a stored public_suffix is sticky (cleared or re-added only by migration).
select is(pg_temp.as_admin($$select admin.domain_set('co.id', 'apex', true, 'none', false, 'percobaan suffix resmi', 'a@test', 'co.id')$$),
  'ERR SA021 domain_not_registrable', 'trusted on a public suffix while clearing the flag');
select is(pg_temp.as_admin($$select admin.domain_set('co.id', 'apex', false, 'none', false, 'hapus tanda suffix', 'a@test', 'co.id')$$),
  'ERR SA021 domain_not_registrable', 'a stored public_suffix cannot be cleared');
select is(pg_temp.as_admin($$select admin.domain_set('co.id', 'apex', false, 'none', null, 'catatan suffix baru', 'a@test', 'co.id')$$),
  '', 'public_suffix null keeps the stored value');
select is((select public_suffix from admin.domain_lists where domain = 'co.id'), true, 'co.id is still a public suffix');
select is(pg_temp.as_admin($$select admin.domain_set('sfx-dl.test', 'subtree', false, 'none', true, 'suffix dengan subtree', 'a@test', 'sfx-dl.test')$$),
  'ERR SA021 domain_not_registrable', 'a new subtree on a public suffix');
select is(pg_temp.as_admin($$select admin.domain_set('forms-x.test', 'apex', true, 'host_path', false, 'percobaan host path', 'a@test', 'forms-x.test')$$),
  'ERR SA021 domain_not_registrable', 'K6: trusted on a host_path row');
select is(pg_temp.as_admin($$select admin.domain_set('loose.test', 'none', false, 'subdomains', false, 'platform tanpa induk', 'a@test')$$),
  'ERR SA021 domain_not_registrable', 'I16: hosting without protect and without a subtree parent');
select is(pg_temp.as_admin($$select admin.domain_set('forms.trusted-new.test', 'none', false, 'host_path', false, 'formulir pengguna', 'a@test')$$),
  '', 'hosting without protect under a subtree parent is allowed');
select throws_ok($$insert into admin.domain_lists (domain, protect, trusted, hosting, updated_by) values ('chk.test', 'apex', true, 'host_path', 'test')$$,
  '23514', null, 'table check: host_path cannot be trusted');

-- locked / hard_locked
select is(pg_temp.as_admin($$select admin.domain_set('github.io', 'apex', false, 'subdomains', false, 'ubah catatan bawaan', 'a@test')$$),
  'ERR SA011 confirm_required', 'I16: a locked seed row needs confirm');
select is(pg_temp.as_admin($$select admin.domain_set('github.io', 'apex', false, 'subdomains', false, 'ubah catatan bawaan', 'a@test', 'github.io')$$),
  '', 'locked row with confirm');
select is((select (locked, note)::text from admin.domain_lists where domain = 'github.io'), '(t,"ubah catatan bawaan")',
  'an edited seed row stays locked');
select is(pg_temp.as_admin($$select admin.domain_set('bca.co.id', 'subtree', true, 'none', false, 'ubah baris brand', 'a@test', 'bca.co.id')$$),
  'ERR SA023 brand_locked', 'K6: a hard_locked row cannot be changed, even with confirm');
select is(pg_temp.as_admin($$select admin.domain_set('bankjago.com', 'subtree', true, 'none', false, 'jadikan resmi saja', 'a@test', 'bankjago.com')$$),
  'ERR SA023 brand_locked', 'K6: an L4-only hard_locked row cannot be changed');

-- ---------------------------------------------------------------- already_blocked (K7)

insert into blocklist_entries (domain, families, approved_at, approved_by) values
  ('newhost.test', 1, now(), 'seed@test'), ('tenant.newhost.test', 1, now(), 'seed@test'), ('other.test', 1, now(), 'seed@test');

select is(pg_temp.detail_of($$select admin.domain_set('newhost.test', 'subtree', false, 'none', false, 'host resmi perusahaan', 'a@test', 'newhost.test')$$),
  'SA020 {"total": 2, "domains": ["newhost.test", "tenant.newhost.test"]}', 'K7: confirm alone is not enough, DETAIL lists the domains');
select is(pg_temp.as_admin($$select admin.domain_set('newhost.test', 'subtree', false, 'none', false, 'host resmi perusahaan', 'a@test', 'newhost.test', 1)$$),
  'ERR SA020 already_blocked', 'K7: confirm_unblock must equal total');
select is(pg_temp.as_admin($$select admin.domain_set('newhost.test', 'subtree', false, 'none', false, 'host resmi perusahaan', 'a@test', null, 2)$$),
  'ERR SA011 confirm_required', 'K7: confirm_unblock does not replace confirm');
select is(pg_temp.as_admin($$select admin.domain_set('newhost.test', 'subtree', false, 'none', false, 'host resmi perusahaan', 'a@test', 'newhost.test', 2)$$),
  '', 'K7: confirm + confirm_unblock = total');
select is((select count(*)::int from blocklist_entries where domain like '%newhost.test' and removed_at is not null), 2,
  'K7: every blocked domain under the row is removed');
select is((select removed_at from blocklist_entries where domain = 'other.test'), null, 'K7: other domains stay blocked');
select is((select count(*)::int from admin.admin_audit where action = 'blocklist.remove' and target like '%newhost.test'), 2,
  'K7: each removal is audited');

-- ---------------------------------------------------------------- version (I17)

select is(pg_temp.as_admin($$select version::text from admin.domain_lists_version()$$), pg_temp.version()::text,
  'domain_lists_version() = meta row');
create temp table v0 as select pg_temp.version() as v;
do $d$ begin perform pg_temp.as_admin($$select admin.domain_set('newpage.test', 'apex', false, 'none', false, 'catatan versi kedua', 'a@test')$$); end $d$;
select is(pg_temp.version(), (select v + 1 from v0), 'I17: one domain_set = version + 1');
do $d$ begin perform pg_temp.as_admin($$select admin.domain_set('newpage.test', 'apex', true, 'none', false, 'gagal tanpa confirm', 'a@test')$$); end $d$;
select is(pg_temp.version(), (select v + 1 from v0), 'I17: a failed domain_set does not change the version');
update admin.domain_lists set note = note where domain = 'no-such-row.test';
select is(pg_temp.version(), (select v + 1 from v0), 'I17: a statement that changes 0 rows does not change the version');
update admin.domain_lists set note = note where domain in ('newpage.test', 'trusted-new.test');
select is(pg_temp.version(), (select v + 2 from v0), 'I17: one statement over 2 rows = version + 1');
do $d$ begin perform pg_temp.as_admin($$select admin.domain_set('version-new.test', 'apex', false, 'none', false, 'baris baru uji versi', 'a@test')$$); end $d$;
select is(pg_temp.version(), (select v + 3 from v0), 'I17: a new row (insert path of the upsert) = version + 1');
do $d$ begin perform pg_temp.as_admin($$select admin.domain_remove('version-new.test', 'hapus baris uji versi', 'a@test')$$); end $d$;
select is(pg_temp.version(), (select v + 4 from v0), 'I17: domain_remove = version + 1');

-- ---------------------------------------------------------------- domain_remove

select is(pg_temp.as_admin($$select admin.domain_remove('no-such-row.test', 'hapus yang tidak ada', 'a@test')$$),
  'ERR SA002 not_found', 'domain_remove: unknown domain');
select is(pg_temp.as_admin($$select admin.domain_remove('github.io', 'hapus baris bawaan', 'a@test')$$),
  'ERR SA011 confirm_required', 'I16: removing a locked row needs confirm');
select is(pg_temp.as_admin($$select admin.domain_remove('klikbca.com', 'hapus baris brand', 'a@test', 'klikbca.com')$$),
  'ERR SA023 brand_locked', 'I16: a hard_locked row cannot be removed');
select is(pg_temp.as_admin($$select admin.domain_remove('co.id', 'hapus suffix publik', 'a@test', 'co.id')$$),
  'ERR SA023 brand_locked', 'a public suffix row cannot be removed (it would come back without the flag)');
select is(pg_temp.as_admin($$select admin.domain_remove('newpage.test', 'tidak dipakai lagi', 'a@test')$$), '',
  'an unlocked row is removed without confirm');
select is((select (target, before ->> 'protect', after is null)::text from admin.admin_audit
            where action = 'domain_list.remove' order by id desc limit 1),
  '(newpage.test,apex,t)', 'I17: removal audited with before');

-- domain_list_full
insert into admin.domain_lists (domain, protect, updated_by)
select 'fill' || i || '.test', 'apex', 'test' from generate_series(1, 5000 - (select count(*) from admin.domain_lists)) i;
select is(pg_temp.as_admin($$select admin.domain_set('one-more.test', 'apex', false, 'none', false, 'baris ke 5001', 'a@test')$$),
  'ERR SA022 domain_list_full', 'K6: at most 5000 rows');
delete from admin.domain_lists where domain like 'fill%.test';

-- ---------------------------------------------------------------- vote / add_domain (K10, I18)

insert into blocklist_entries (domain, families) values ('bca.co.id', 2), ('login.bca.co.id', 2), ('antre-dl.test', 2);
select is(pg_temp.as_admin($$select admin.vote('bca.co.id', 'approve', 'phishing_bank', 'disetujui oleh admin', 'a@test')$$),
  'ERR SA019 allowlisted', 'I18: vote approve on a protected domain');
select is(pg_temp.as_admin($$select admin.vote('login.bca.co.id', 'approve', 'phishing_bank', 'disetujui oleh admin', 'a@test')$$),
  'ERR SA019 allowlisted', 'I18: vote approve on a subdomain of a subtree row');
select is(pg_temp.as_admin($$select admin.vote('bca.co.id', 'reject', null, 'bukan penipuan ini', 'a@test')$$), '',
  'reject still works on a protected domain');
select is(pg_temp.as_admin($$select admin.add_domain('x.bca.co.id', 'phishing_bank', 'tambah manual oleh admin', 'a@test')$$),
  'ERR SA019 allowlisted', 'I18: add_domain on a protected domain');
select is(pg_temp.as_admin($$select admin.add_domain('github.io', 'phishing_bank', 'tambah manual oleh admin', 'a@test')$$),
  'ERR SA019 allowlisted', 'I18: add_domain on an apex row');
select is(pg_temp.as_admin($$select admin.vote('antre-dl.test', 'approve', 'phishing_bank', 'disetujui oleh admin', 'a@test')$$), '',
  'vote approve on an unprotected domain still works');
select is(pg_temp.as_admin($$select admin.add_domain('evil.github.io', 'phishing_bank', 'tambah manual oleh admin', 'a@test')$$), '',
  'add_domain on a tenant of a subdomains row still works');

-- A parent of a hard_locked row stays unblockable even after its own row is removed (security review).
-- Since security review 10b a suffix row goes only by migration; a migration (superuser) removes it here.
delete from admin.domain_lists where domain = 'co.id';
select is((select count(*)::int from admin.domain_lists where domain = 'co.id'), 0, 'a migration can still remove a suffix row');
select is(pg_temp.as_admin($$select admin.add_domain('co.id', 'phishing_bank', 'tambah manual oleh admin', 'a@test')$$),
  'ERR SA019 allowlisted', 'add_domain refuses a parent of a hard_locked row (co.id above bca.co.id)');
select is(pg_temp.as_admin($$select admin.vote('co.id', 'approve', 'phishing_bank', 'disetujui oleh admin', 'a@test')$$),
  'ERR SA019 allowlisted', 'vote refuses a parent of a hard_locked row');

-- ---------------------------------------------------------------- review_due / ai_dataset (K11)

insert into blocklist_entries (domain, families) values ('tenant-dl.github.io', 2), ('plain-dl.test', 2);
select is(pg_temp.as_admin($$select string_agg(domain, ',' order by domain) from admin.review_due(100) where domain like '%-dl.%'$$),
  'plain-dl.test', 'K11: review_due skips a page on a shared host (x.github.io)');
insert into admin.domain_labels (domain, is_scam, source, connected, owner_ref, by_ref) values
  ('tenant-dl.github.io', true, 'guardian', true, 'a1a1a1a1a1a1a1a1', 'b1b1b1b1b1b1b1b1'),
  ('plain-dl.test', true, 'guardian', true, 'a1a1a1a1a1a1a1a1', 'b1b1b1b1b1b1b1b1');
select is((select string_agg(domain || '=' || shared_host, ',' order by domain) from admin.ai_dataset where domain like '%-dl.%'),
  'plain-dl.test=false,tenant-dl.github.io=true', 'K11: ai_dataset.shared_host from v_shared_hosts');

select * from finish();
rollback;
