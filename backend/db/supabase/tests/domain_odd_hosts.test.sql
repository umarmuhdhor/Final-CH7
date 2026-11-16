-- #487: a host with no registrable domain (contracts/api.md Scans "`domain`" case 4: `[2001:db8::1]`,
-- `router`, `www.co.id`, `www.com`), migration 20261116120000_domain_odd_hosts.sql.
create extension if not exists pgtap with schema extensions;

begin;
select plan(32);

-- ---------------------------------------------------------------- domain checks

select is_empty(
  $$select conrelid::regclass::text from pg_constraint
     where contype = 'c' and conname like '%\_domain\_check' and pg_get_constraintdef(oid) ~ 'www'
       and conrelid <> 'admin.domain_lists'::regclass$$,
  'no domain check refuses a leading www. any more (admin.domain_lists keeps registrable domains only)');
select set_eq(
  $$select c.conrelid::regclass::text from pg_constraint c join pg_class t on t.oid = c.conrelid
     where c.contype = 'c' and c.conname = t.relname || '_domain_check'
       and pg_get_constraintdef(c.oid) = 'CHECK ((domain = lower(domain)))'$$,
  array['scans', 'verdicts', 'blocklist_entries', 'admin.domain_intel', 'admin.domain_intel_label',
        'admin.domain_labels', 'admin.domain_review', 'admin.guardian_decisions', 'admin.scan_archive',
        'admin.case_library', 'admin.review_decisions'],
  'every replaced check keeps domain = lower(domain), under its old name');
select ok(
  (select pg_get_constraintdef(oid) ~ 'www' and pg_get_constraintdef(oid) ~ 'char_length'
     from pg_constraint where conname = 'domain_lists_domain_check'),
  'admin.domain_lists keeps its own check');

-- ---------------------------------------------------------------- verdict_link

select is(public.verdict_link('http://[2001:db8::1]/login'), 'http://[2001:db8::1]/login', 'link: IPv6 host');
select is(public.verdict_link('HTTP://u:p@[2001:DB8::1]:80/A?x=1#f'), 'http://[2001:db8::1]/A',
  'link: IPv6 lowercase, no userinfo, default port, query or fragment; path case kept');
select is(public.verdict_link('https://[::1]:8443'), 'https://[::1]:8443/', 'link: IPv6 with another port, empty path');
select is(public.verdict_link('http://[::ffff:192.0.2.1]/a'), 'http://[::ffff:192.0.2.1]/a', 'link: IPv6 with a dotted tail');
select is(public.verdict_link('http://[2001:db8::1]x/'), null, 'link: text after the brackets is no link');
select is(public.verdict_link('http://[2001:db8::1/'), null, 'link: an open bracket is no link');
select is(public.verdict_link('http://[ab:c]/'), 'http://[ab:c]/', 'link: the one change: a bracketed host with a colon (was null)');
select is(public.verdict_link('http://router/login'), 'http://router/login', 'link: single label');
select is(public.verdict_link('https://www.co.id/a'), 'https://www.co.id/a', 'link: www. stays');

-- The function before this migration, to show normal hosts get exactly the same link.
create function pg_temp.old_link(p_url text) returns text language sql immutable strict as $$
  select case
    when m is null or (m[4] <> '' and left(m[4], 1) <> '/') then null
    else lower(m[1]) || '://' || lower(m[2])
         || case when (lower(m[1]) = 'https' and m[3] = ':443') or (lower(m[1]) = 'http' and m[3] = ':80')
                 then '' else coalesce(m[3], '') end
         || coalesce(nullif(m[4], ''), '/')
  end
  from (select regexp_match(p_url, '^([A-Za-z]+)://(?:[^/?#]*@)?([^/?#:@]+)(:[0-9]{1,5})?([^?#]*)')) r(m)
  where char_length(p_url) <= 2048 and m[1] ~* '^https?$'
$$;
create temp table normal_urls (u text);
insert into normal_urls values
  ('HTTPS://u:p@Login.Ex.COM:443/A/b?x=1#f'), ('http://ex.com'), ('https://ex.com:8443/a'), ('ftp://ex.com/a'),
  ('https://ex.com:abc/'), ('http://192.168.1.1/a'), ('http://192.168.1.1:80'), ('https://ex.com?q'),
  ('https://ex.com#f'), ('https://a@b@ex.com/x'), ('https://ex.com/a:b@c'), ('https://ex.com:/a'),
  ('https://ex.com:123456/'), ('https://xn--bca-verifikasi-abc.site/%C3%A4'), ('https://ex.com/' || repeat('a', 2040)),
  ('https://ex.com\a'), ('http://ex.com./a'), ('https://'), ('not a url'), ('https://ex].com/'), ('https://e[x.com/'),
  -- A bracket that is no IPv6 literal falls to the old host rule (Postgres takes the longer alternative).
  ('http://[foo]/'), ('http://[abc]/'), ('http://[2001/x'), ('https://[/'), ('http://[::1/a');
select is_empty(
  $$select u from normal_urls where pg_temp.old_link(u) is distinct from public.verdict_link(u)$$,
  'link: every other url gives the same link as before');

-- ---------------------------------------------------------------- verdict_shared

create function pg_temp.old_shared(p_link text, p_domain text) returns boolean language sql stable as $$
  select exists (
    select 1 from admin.v_domain_lists_public r
    where (r.hosting = 'host_path' and (x.h = r.domain or right(x.h, char_length(r.domain) + 1) = '.' || r.domain))
       or (r.hosting = 'subdomains' and r.domain = p_domain))
  from (select lower(substring(p_link from '^[A-Za-z]+://([^/:]+)')) as h) x
$$;
create temp table normal_links (l text, d text);
insert into normal_links values
  ('https://sites.google.com/view/a', 'google.com'), ('https://sites.google.com:8443/view/a', 'google.com'),
  ('https://x.vercel.app/', 'vercel.app'), ('https://evil.github.io/a', 'evil.github.io'),
  ('https://evil.test/a', 'evil.test'), ('https://docs.google.com/forms/d/x', 'docs.google.com'),
  ('https://sway.cloud.microsoft/AbC', 'sway.cloud.microsoft'), ('https://accounts.google.com/', 'google.com'),
  ('http://192.168.1.1/', '192.168.1.1'), ('https://router/', 'router'), ('not a link', 'x.test'), (null, 'x.test');
select is_empty(
  $$select l from normal_links where pg_temp.old_shared(l, d) is distinct from public.verdict_shared(l, d)$$,
  'shared: every other link gives the same answer as before');
select ok(not public.verdict_shared('http://[2001:db8::1]/a', '[2001:db8::1]'), 'shared: an IPv6 host is no shared host');
select is((select provolatile from pg_proc where oid = 'public.verdict_shared(text, text)'::regprocedure), 's',
  'shared: still stable');
select ok((select provolatile = 'i' and proisstrict and proparallel = 's' from pg_proc
            where oid = 'public.verdict_link(text)'::regprocedure), 'link: still immutable, strict, parallel safe');
select ok(has_function_privilege('shoo_api', 'public.verdict_link(text)', 'EXECUTE')
          and has_function_privilege('shoo_api', 'public.verdict_shared(text, text)', 'EXECUTE')
          and not has_function_privilege('anon', 'public.verdict_link(text)', 'EXECUTE')
          and not has_function_privilege('anon', 'public.verdict_shared(text, text)', 'EXECUTE'),
  'grants unchanged');

-- ---------------------------------------------------------------- rows

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('o_p', 'P', 'protected', 'avatar_01', '\x21'),
  ('o_g', 'G', 'guardian', 'avatar_01', '\x22');
insert into family_links (protected_id, guardian_id) values ('o_p', 'o_g');

select lives_ok(
  $$insert into scans (id, owner_id, url, domain, score, status, detected_at) values
      ('o_s1', 'o_p', 'http://[2001:db8::1]/login', '[2001:db8::1]', 90, 'blocked', now() - interval '4 minutes'),
      ('o_s2', 'o_p', 'http://router/login', 'router', 90, 'blocked', now() - interval '3 minutes'),
      ('o_s3', 'o_p', 'https://www.co.id/login', 'www.co.id', 90, 'blocked', now() - interval '2 minutes'),
      ('o_s4', 'o_p', 'https://www.com/login', 'www.com', 90, 'blocked', now() - interval '1 minute')$$,
  'scans: the four hosts');
select throws_ok(
  $$insert into scans (id, owner_id, url, domain, score, status, detected_at)
    values ('o_s5', 'o_p', 'https://www.co.id/', 'WWW.co.id', 90, 'blocked', now())$$,
  '23514', null, 'scans: still lowercase only');
select is((select count(*)::int from admin.scan_archive where scan_id in ('o_s1', 'o_s2', 'o_s3', 'o_s4')), 4,
  'scan_archive: the trigger archives all four');

-- A row written without url (SQL editor) gets its scan's link, IPv6 included.
select lives_ok(
  $$insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
      ('o_p', '[2001:db8::1]', 'not_safe', 'o_s1', 'o_g', 'G'),
      ('o_p', 'router', 'not_safe', 'o_s2', 'o_g', 'G'),
      ('o_p', 'www.co.id', 'not_safe', 'o_s3', 'o_g', 'G'),
      ('o_p', 'www.com', 'safe', 'o_s4', 'o_g', 'G')$$,
  'verdicts: the four hosts');
select is((select url from verdicts where scan_id = 'o_s1'), 'http://[2001:db8::1]/login',
  'verdicts: an IPv6 row without url gets its scan''s link, not the front page');
select is((select url from verdicts where scan_id = 'o_s3'), 'https://www.co.id/login', 'verdicts: www.co.id link');
select throws_ok(
  $$insert into verdicts (owner_id, url, domain, value, by_device_id, by_name)
    values ('o_p', 'http://[2001:db8::1]/a?x=1', '[2001:db8::1]', 'safe', 'o_g', 'G')$$,
  '23514', null, 'url check: still no query, IPv6 too');
select throws_ok(
  $$insert into verdicts (owner_id, url, domain, value, by_device_id, by_name)
    values ('o_p', 'http://[::1/a', '[::1]', 'safe', 'o_g', 'G')$$,
  '23514', null, 'url check: an open bracket is no link');
select lives_ok(
  $$insert into verdicts (owner_id, url, domain, value, by_device_id, by_name)
    values ('o_p', 'http://[::1]:8080/a', '[::1]', 'safe', 'o_g', 'G')$$,
  'url check: an IPv6 link with a port');
select is((select count(*)::int from admin.guardian_decisions where scan_id in ('o_s1', 'o_s2', 'o_s3', 'o_s4')), 4,
  'guardian_decisions: the trigger records all four');
select is((select count(*)::int from admin.domain_labels
            where owner_ref = admin.owner_ref('o_p') and domain in ('[2001:db8::1]', 'router', 'www.co.id', 'www.com')), 4,
  'domain_labels: one label per host');
select lives_ok($$insert into blocklist_entries (domain, families) values ('www.co.id', 1)$$,
  'blocklist_entries: a www. name fits (the Worker never queues one, #546)');
select throws_ok($$insert into blocklist_entries (domain, families) values ('Router', 1)$$,
  '23514', null, 'blocklist_entries: still lowercase only');
select is((select verdict from admin.v_scans where id = 'o_s1'), 'not_safe', 'v_scans: the IPv6 verdict');

select * from finish();
rollback;
