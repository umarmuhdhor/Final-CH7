-- #241: verdicts per link (migration 20261108100000_verdicts_per_link.sql).
create extension if not exists pgtap with schema extensions;

begin;
select plan(24);

-- ---------------------------------------------------------------- shape

select col_not_null('public', 'verdicts', 'url', 'verdicts.url is not null');
select col_is_pk('public', 'verdicts', array['owner_id', 'url'], 'primary key (owner_id, url)');
select has_index('public', 'verdicts', 'verdicts_notes_due', 'index for the 14-day notes cleanup');
select ok(has_function_privilege('shoo_api', 'public.verdict_link(text)', 'EXECUTE'), 'shoo_api may call verdict_link');
select ok(has_function_privilege('shoo_api', 'public.verdict_shared(text, text)', 'EXECUTE'), 'shoo_api may call verdict_shared');
select ok(not has_function_privilege('anon', 'public.verdict_link(text)', 'EXECUTE'), 'anon may not call verdict_link');

-- ---------------------------------------------------------------- verdict_link

select is(public.verdict_link('HTTPS://u:p@Login.Ex.COM:443/A/b?x=1#f'), 'https://login.ex.com/A/b',
  'link: lowercase origin, no userinfo, default port, query or fragment; path case kept');
select is(public.verdict_link('http://ex.com'), 'http://ex.com/', 'link: empty path becomes /');
select is(public.verdict_link('https://ex.com:8443/a'), 'https://ex.com:8443/a', 'link: other ports stay');
select is(public.verdict_link('ftp://ex.com/a'), null, 'link: only http(s)');
select is(public.verdict_link('https://ex.com:abc/'), null, 'link: a bad port is no link');

-- ---------------------------------------------------------------- verdict_shared

select ok(public.verdict_shared('https://sites.google.com/view/a', 'google.com'), 'shared: host_path host');
select ok(public.verdict_shared('https://x.vercel.app/', 'vercel.app'), 'shared: the platform itself is the domain');
select ok(not public.verdict_shared('https://evil.github.io/a', 'evil.github.io'), 'not shared: a tenant domain');
select ok(not public.verdict_shared('https://evil.test/a', 'evil.test'), 'not shared: an ordinary domain');

-- ---------------------------------------------------------------- rows

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('l_p', 'P', 'protected', 'avatar_01', '\x01'),
  ('l_g', 'G', 'guardian', 'avatar_01', '\x02');
insert into family_links (protected_id, guardian_id) values ('l_p', 'l_g');
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('l_s1', 'l_p', 'https://Login.Link.test/akun?x=1', 'link.test', 90, 'blocked', now() - interval '3 minutes'),
  ('l_s2', 'l_p', 'https://link.test/b', 'link.test', 90, 'blocked', now() - interval '2 minutes'),
  ('l_s3', 'l_p', 'https://other.test/a', 'link.test', 90, 'blocked', now() - interval '1 minute');

insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
values ('l_p', 'link.test', 'not_safe', 'l_s1', 'l_g', 'G');
select is((select url from verdicts where scan_id = 'l_s1'), 'https://login.link.test/akun',
  'a row without url gets its scan''s link');
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
values ('l_p', 'link.test', 'safe', 'l_s3', 'l_g', 'G');
select is((select url from verdicts where scan_id = 'l_s3'), 'https://link.test/',
  'a scan link outside the domain falls back to the front page');
select throws_ok(
  $$insert into verdicts (owner_id, url, domain, value, by_device_id, by_name)
    values ('l_p', 'https://link.test/a?x=1', 'link.test', 'safe', 'l_g', 'G')$$,
  '23514', null, 'url check: no query in a stored link');
select lives_ok(
  $$insert into verdicts (owner_id, url, domain, value, notes, by_device_id, by_name)
    values ('l_p', 'https://link.test/b', 'link.test', 'safe', 'aman', 'l_g', 'G')$$,
  'another link of the same domain is its own row');
select throws_ok(
  $$update verdicts set notes = repeat('x', 281) where url = 'https://link.test/b'$$,
  '23514', null, 'notes: at most 280 characters');
select throws_ok(
  $$update verdicts set notes = '' where url = 'https://link.test/b'$$,
  '23514', null, 'notes: no empty string (no note = null)');

-- ---------------------------------------------------------------- admin.v_scans

select is((select count(*)::int from admin.v_scans where id in ('l_s1', 'l_s2', 'l_s3')), 3,
  'v_scans: one row per scan, however many links its domain has');
select is((select verdict from admin.v_scans where id = 'l_s2'), 'safe', 'v_scans: the exact link''s verdict wins');
select is((select verdict from admin.v_scans where id = 'l_s1'), 'not_safe', 'v_scans: its own not_safe');

select * from finish();
rollback;
