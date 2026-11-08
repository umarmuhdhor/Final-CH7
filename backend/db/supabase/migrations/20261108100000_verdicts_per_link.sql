-- #241 (contracts/api.md "Verdicts (per link)", #303): a verdict applies to one link, not a whole domain.
--   * verdicts.url: the link = origin + path, no userinfo, query or fragment (`shareableUrl` in the
--     extension). The primary key becomes (owner_id, url); `domain` stays for the review queue, the
--     domain locks and the not_safe fallback.
--   * verdicts.notes: the Guardian's reason (optional, at most 280 characters). Never returned in a
--     Verdict. Cleared after 14 days by retention; the decision row stays (D-alief-14).
--   * public.verdict_link(url): the one normalisation of a link, used by POST /verdicts (from the
--     scan's url), GET /verdicts?url= and the Activity join.
--   * public.verdict_shared(link, domain): true when one page says nothing about the rest of the
--     domain, so a not_safe on one link must not cover the others (contract lookup step 2). Read from
--     admin.v_domain_lists_public (ADM-09), the backend keeps no list in code.
--   * public.verdicts_default_url: a row inserted without url (SQL editor, scripts) gets the backfill's link.
--   * admin.on_verdict: copies the note, masked (admin.mask_note), to the label and the archive row.
--   * admin.v_scans: the verdict follows the same lookup rule (it joined per domain before, which
--     would now repeat a scan once per link of its domain).
--
-- Existing rows (one per owner + domain): url from the verdict's scan where it still exists, else
-- `https://<domain>/`. A not_safe keeps covering its whole domain through the fallback; a safe now
-- opens that one link (the scan's page, or the domain's front page).
--
-- Rollback (one transaction, before any second link of a domain is decided):
--   alter table public.verdicts drop constraint verdicts_pkey, add primary key (owner_id, domain);
--   alter table public.verdicts drop column url, drop column notes;
--   drop trigger verdicts_default_url on public.verdicts; drop function public.verdicts_default_url();
--   drop function public.verdict_shared(text, text), public.verdict_link(text);
--   then re-run admin.on_verdict from 20261104133527_l5_review_data.sql and admin.v_scans from
--   20261102190630_admin_schema.sql, and `git revert` the backend change.

set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- functions

-- https://Host:443/a/b?x#y → https://host/a/b. Null when the input is not an http(s) URL with a host.
-- The browser already gives lowercase hosts and encoded paths, so this equals origin + pathname of
-- the URL the extension sees.
create function public.verdict_link(p_url text) returns text
language sql immutable strict parallel safe set search_path = pg_catalog, pg_temp as $$
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

-- A shared host (contract lookup step 2): the link's host is on, or under, a platform where anyone
-- publishes under a path (docs.google.com, bit.ly), or the registrable domain itself is a platform
-- where anyone gets a subdomain (the tenant was not split off, e.g. vercel.app). A tenant domain such
-- as evil.github.io belongs to one owner, so its pages share a fallback.
create function public.verdict_shared(p_link text, p_domain text) returns boolean
language sql stable set search_path = pg_catalog, pg_temp as $$
  select exists (
    select 1 from admin.v_domain_lists_public r
    where (r.hosting = 'host_path' and (x.h = r.domain or right(x.h, char_length(r.domain) + 1) = '.' || r.domain))
       or (r.hosting = 'subdomains' and r.domain = p_domain))
  from (select lower(substring(p_link from '^[A-Za-z]+://([^/:]+)')) as h) x
$$;

revoke all on function public.verdict_link(text), public.verdict_shared(text, text) from public, anon, authenticated;
grant execute on function public.verdict_link(text), public.verdict_shared(text, text) to shoo_api;

-- ---------------------------------------------------------------- verdicts

alter table public.verdicts
  add column url text,
  add column notes text check (char_length(notes) between 1 and 280);

update public.verdicts v set url = public.verdict_link(s.url)
  from public.scans s
 where s.id = v.scan_id;
-- The link must belong to the verdict's domain; anything else (no scan, odd url) gets the front page.
update public.verdicts v set url = 'https://' || v.domain || '/'
 where v.url is null
    or not (substring(v.url from '^[a-z]+://([^/:]+)') = v.domain
            or substring(v.url from '^[a-z]+://([^/:]+)') like '%.' || v.domain);

alter table public.verdicts
  alter column url set not null,
  add constraint verdicts_url_link check (char_length(url) <= 2048 and url ~ '^https?://[^/?#@:]+(:[0-9]{1,5})?/[^?#]*$'),
  drop constraint verdicts_pkey,
  add primary key (owner_id, url);

-- The Worker always sends url. A row written without one (SQL editor, scripts, older fixtures) gets
-- the same link as the backfill above: its scan's link when it belongs to the domain, else the front page.
create function public.verdicts_default_url() returns trigger
language plpgsql set search_path = pg_catalog, pg_temp as $$
declare
  v_link text;
  v_host text;
begin
  if new.url is null then
    select public.verdict_link(s.url) into v_link from public.scans s where s.id = new.scan_id;
    v_host := substring(v_link from '^[a-z]+://([^/:]+)');
    new.url := case when v_host = new.domain or v_host like '%.' || new.domain then v_link
                    else 'https://' || new.domain || '/' end;
  end if;
  return new;
end $$;
create trigger verdicts_default_url before insert on public.verdicts
  for each row execute function public.verdicts_default_url();
-- A trigger function needs no EXECUTE to fire (admin_grants I1: shoo_admin executes nothing in public).
revoke all on function public.verdicts_default_url() from public, anon, authenticated;

-- Retention clears notes after 14 days (only rows that still have one).
create index verdicts_notes_due on public.verdicts (decided_at) where notes is not null;

-- ---------------------------------------------------------------- admin.on_verdict

-- As 20261104133527_l5_review_data.sql, plus the masked note on the label and on the archive row.
create or replace function admin.on_verdict() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_ref  text;
  v_by   text;
  v_scam boolean;
  v_last admin.domain_labels;
  v_scan text;
  v_note text;
begin
  begin
    v_ref := admin.owner_ref(new.owner_id);
    v_by  := admin.owner_ref(new.by_device_id);
    v_note := admin.mask_note(new.notes);
  exception when others then
    raise warning 'admin_trigger_failed on_verdict % %', sqlstate, sqlerrm;
    return null;
  end;
  -- Its own block: a failed archive lookup leaves scan_id null, never loses the label.
  begin
    v_scan := coalesce(new.scan_id,
                (select l.scan_id from admin.scan_archive l
                  where l.owner_ref = v_ref and l.domain = new.domain and l.detected_at <= new.decided_at
                  order by l.detected_at desc limit 1));
  exception when others then
    raise warning 'admin_trigger_failed on_verdict_scan % %', sqlstate, sqlerrm;
    v_scan := new.scan_id;
  end;
  <<label>>
  begin
    v_scam := new.value = 'not_safe';
    select * into v_last from admin.domain_labels l
     where l.owner_ref = v_ref and l.domain = new.domain and l.source = 'guardian'
       and not admin._forgotten(l.owner_ref, l.by_ref, l.created_at)
     order by l.id desc limit 1;
    if found and (v_last.analyzed_at is null or v_last.is_scam = v_scam) then
      exit label;   -- locked (Q33), or the same decision again (upsert with the same value)
    end if;
    insert into admin.domain_labels (domain, is_scam, source, connected, ai_score, ai_status,
                                     thresholds_version, owner_ref, by_ref, revision_of, scan_id, note)
    select new.domain, v_scam, 'guardian',
           new.owner_id = new.by_device_id
             or exists (select 1 from public.family_links f
                         where f.protected_id = new.owner_id and f.guardian_id = new.by_device_id),
           s.score, s.status::text, (select version from admin.public_config), v_ref, v_by, v_last.id, v_scan,
           v_note
    from (select 1) one
    left join public.scans s on s.id = new.scan_id;
  exception when others then
    raise warning 'admin_trigger_failed on_verdict % %', sqlstate, sqlerrm;
  end;
  begin
    update admin.scan_archive a set verdict = new.value::text, verdict_at = new.decided_at, by_ref = v_by,
                                    note = v_note
     where a.scan_id = v_scan;
  exception when others then
    raise warning 'admin_trigger_failed on_verdict_archive % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- ---------------------------------------------------------------- admin.v_scans

-- As 20261102190630_admin_schema.sql; only the verdict join changed. The link and the shared-host
-- test are inline, like the masking: a function called from a view runs with the caller's EXECUTE
-- privilege, and shoo_admin has none in public.
create or replace view admin.v_scans as
select
  s.id,
  s.domain,
  m.origin || regexp_replace(substr(m.u, char_length(m.origin) + 1),
                             '(?<=/)[^/]*(@|[0-9]{6,}|[A-Za-z0-9_-]{16,})[^/]*', '…', 'g') as url_masked,
  s.score,
  s.status::text as status,
  coalesce((select array_agg(e ->> 'id' order by o)
              from jsonb_array_elements(s.signals) with ordinality as x(e, o)
             where e ->> 'id' is not null), '{}') as signal_ids,
  s.detected_at,
  s.replica_path is not null as has_replica,
  v.value::text as verdict
from public.scans s
cross join lateral (
  select regexp_replace(regexp_replace(s.url, '^([a-z][a-z0-9+.-]*://)[^/]*@', '\1', 'i'), '[?#].*$', '') as u
) m0
cross join lateral (
  select m0.u, coalesce(substring(m0.u from '(?i)^[a-z][a-z0-9+.-]*://[^/]*'), '') as origin
) m
cross join lateral (
  select lower(m.origin) || coalesce(nullif(substr(m.u, char_length(m.origin) + 1), ''), '/') as link,
         lower(substring(m.origin from '(?i)^[a-z]+://([^/:]+)')) as host
) k
left join lateral (
  select v.value from public.verdicts v
  where v.owner_id = s.owner_id
    and (v.url = k.link
         or (v.domain = s.domain and v.value = 'not_safe'
             and not exists (select 1 from admin.domain_lists r
                              where (r.hosting = 'host_path'
                                     and (k.host = r.domain or right(k.host, char_length(r.domain) + 1) = '.' || r.domain))
                                 or (r.hosting = 'subdomains' and r.domain = s.domain))))
  order by (v.url = k.link) desc, v.decided_at desc
  limit 1
) v on true
where s.created_at > now() - interval '14 days';
