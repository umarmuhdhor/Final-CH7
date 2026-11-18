-- #487 (contracts/api.md Scans "`domain`" case 4, #541): a host with no registrable domain is sent as the
-- full host: an IPv6 literal in brackets (`[2001:db8::1]`), a single label (`router`), or a name that is
-- literally `www.<public suffix>` (`www.co.id`, `www.com`). IPv4 already fitted.
--
--   * The `domain !~ '^www\.'` checks go: `www.co.id` must fit. The DB keeps no Public Suffix List, so it
--     cannot tell `www.co.id` from `www.bca.co.id`; the extension decides (it strips `www.` from every
--     registrable domain) and the Worker checks the shape (backend/api/src/http/validate.ts DOMAIN). Each
--     check keeps `domain = lower(domain)` under its old name. admin.domain_lists keeps its own check:
--     a dashboard list row is always a registrable domain or a suffix, never one of these hosts.
--   * public.verdict_link and public.verdict_shared read the host up to the first `:`, so an IPv6 host was
--     cut at `[2001` and verdict_link('http://[2001:db8::1]/login') was null (POST /verdicts then stored
--     the https front page instead of the link). A bracketed IPv6 host is now read whole. Any other host
--     gives exactly the same result as before (tests/domain_odd_hosts.test.sql compares both).
--   * verdicts_url_link and public.verdicts_default_url read the host the same way.
--
-- Not changed (dashboard only, no behaviour change today):
--   * admin.on_scan_insert stores scan_archive.host cut at the first `:` for an IPv6 host: `[2001`, not
--     null (the archive row and its domain are right). Nothing joins it to a list row that could be IPv6.
--   * admin.v_scans (20261116100000) reads the host the old way too; no admin.domain_lists row is an IPv6
--     host or a parent of one, so its verdict is the same as with verdict_shared.
--   * admin._check_domain still refuses `www.` for the review queue RPCs (admin.vote, unreject,
--     remove_domain, domain_remove): a name with no registrable domain never enters the queue
--     (contracts/api.md Blocklist 1, src/db/repo/domainLists.ts lacksRegistrableDomain), and
--     admin.domain_lists keeps its own check.
--
-- Rollback (one transaction; only while no row holds one of the new values, else delete those first):
--   re-add `and domain !~ '^www\.'` to each of the 11 checks below (lines "domain checks"), put
--   verdicts_url_link back as in 20261108100000_verdicts_per_link.sql, and run verdict_link,
--   verdict_shared and verdicts_default_url from that file as `create or replace`.

set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- domain checks

alter table public.scans
  drop constraint scans_domain_check,
  add constraint scans_domain_check check (domain = lower(domain));
alter table public.verdicts
  drop constraint verdicts_domain_check,
  add constraint verdicts_domain_check check (domain = lower(domain));
alter table public.blocklist_entries
  drop constraint blocklist_entries_domain_check,
  add constraint blocklist_entries_domain_check check (domain = lower(domain));
alter table admin.scan_archive
  drop constraint scan_archive_domain_check,
  add constraint scan_archive_domain_check check (domain = lower(domain));
alter table admin.guardian_decisions
  drop constraint guardian_decisions_domain_check,
  add constraint guardian_decisions_domain_check check (domain = lower(domain));
alter table admin.domain_labels
  drop constraint domain_labels_domain_check,
  add constraint domain_labels_domain_check check (domain = lower(domain));
alter table admin.domain_intel
  drop constraint domain_intel_domain_check,
  add constraint domain_intel_domain_check check (domain = lower(domain));
alter table admin.domain_intel_label
  drop constraint domain_intel_label_domain_check,
  add constraint domain_intel_label_domain_check check (domain = lower(domain));
alter table admin.domain_review
  drop constraint domain_review_domain_check,
  add constraint domain_review_domain_check check (domain = lower(domain));
alter table admin.case_library
  drop constraint case_library_domain_check,
  add constraint case_library_domain_check check (domain = lower(domain));
alter table admin.review_decisions
  drop constraint review_decisions_domain_check,
  add constraint review_decisions_domain_check check (domain = lower(domain));

-- ---------------------------------------------------------------- links

-- As 20261108100000_verdicts_per_link.sql; the host is now `\[[0-9A-Fa-f:.]+\]` (IPv6) or, as before,
-- `[^/?#:@]+`. Postgres takes the longer alternative, so a bracketed IPv6 host is never cut at its first
-- colon, and any other host matches exactly as before.
create or replace function public.verdict_link(p_url text) returns text
language sql immutable strict parallel safe set search_path = pg_catalog, pg_temp as $$
  select case
    when m is null or (m[4] <> '' and left(m[4], 1) <> '/') then null
    else lower(m[1]) || '://' || lower(m[2])
         || case when (lower(m[1]) = 'https' and m[3] = ':443') or (lower(m[1]) = 'http' and m[3] = ':80')
                 then '' else coalesce(m[3], '') end
         || coalesce(nullif(m[4], ''), '/')
  end
  from (select regexp_match(p_url,
          '^([A-Za-z]+)://(?:[^/?#]*@)?(\[[0-9A-Fa-f:.]+\]|[^/?#:@]+)(:[0-9]{1,5})?([^?#]*)')) r(m)
  where char_length(p_url) <= 2048 and m[1] ~* '^https?$'
$$;

-- As 20261108100000_verdicts_per_link.sql, with the same host rule. No list row is an IPv6 host, so an
-- IPv6 link is never shared; it is now read whole all the same.
create or replace function public.verdict_shared(p_link text, p_domain text) returns boolean
language sql stable set search_path = pg_catalog, pg_temp as $$
  select exists (
    select 1 from admin.v_domain_lists_public r
    where (r.hosting = 'host_path' and (x.h = r.domain or right(x.h, char_length(r.domain) + 1) = '.' || r.domain))
       or (r.hosting = 'subdomains' and r.domain = p_domain))
  from (select lower(substring(p_link from '^[A-Za-z]+://(\[[0-9A-Fa-f:.]+\]|[^/:]+)')) as h) x
$$;

-- `create or replace` keeps the grants of 20261108100000 (shoo_api only); restated so this file stands alone.
revoke all on function public.verdict_link(text), public.verdict_shared(text, text) from public, anon, authenticated;
grant execute on function public.verdict_link(text), public.verdict_shared(text, text) to shoo_api;

-- A stored link: as before, plus a bracketed IPv6 host.
alter table public.verdicts
  drop constraint verdicts_url_link,
  add constraint verdicts_url_link
    check (char_length(url) <= 2048 and url ~ '^https?://(\[[0-9a-f:.]+\]|[^/?#@:]+)(:[0-9]{1,5})?/[^?#]*$');

-- As 20261108100000_verdicts_per_link.sql, with the same host rule.
create or replace function public.verdicts_default_url() returns trigger
language plpgsql set search_path = pg_catalog, pg_temp as $$
declare
  v_link text;
  v_host text;
begin
  if new.url is null then
    select public.verdict_link(s.url) into v_link from public.scans s where s.id = new.scan_id;
    v_host := substring(v_link from '^[a-z]+://(\[[0-9a-f:.]+\]|[^/:]+)');
    new.url := case when v_host = new.domain or v_host like '%.' || new.domain then v_link
                    else 'https://' || new.domain || '/' end;
  end if;
  return new;
end $$;
