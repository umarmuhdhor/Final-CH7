-- #495 (contracts/api.md Verdicts lookup step 2): a not_safe made on a shared host covers only its own
-- link. The Worker's rule (findVerdict, selectScans, recordScan) now also skips a not_safe whose own link
-- is on, or under, a `hosting = 'host_path'` row (`public.verdict_shared(v.url, v.domain)`): older rows
-- and older extension builds file a scam Google Form under google.com, and it must not answer for
-- accounts.google.com. admin.v_scans repeats the rule inline (shoo_admin has no EXECUTE in public, see
-- 20261108100000_verdicts_per_link.sql), so it gets the same test here. Columns and grants unchanged
-- (`create or replace view` keeps them).
--
-- Rollback: re-run the admin.v_scans block of 20261108100000_verdicts_per_link.sql.

set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- As 20261108100000_verdicts_per_link.sql; only the not_safe fallback of the verdict join changed.
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
  cross join lateral (select lower(substring(v.url from '^[A-Za-z]+://([^/:]+)')) as host) vh
  where v.owner_id = s.owner_id
    and (v.url = k.link
         or (v.domain = s.domain and v.value = 'not_safe'
             and not exists (select 1 from admin.domain_lists r
                              where (r.hosting = 'host_path'
                                     and (k.host = r.domain or right(k.host, char_length(r.domain) + 1) = '.' || r.domain))
                                 or (r.hosting = 'subdomains' and r.domain = s.domain))
             -- #495: nor when the not_safe itself was made on a shared host_path host.
             and not exists (select 1 from admin.domain_lists r
                              where r.hosting = 'host_path'
                                and (vh.host = r.domain or right(vh.host, char_length(r.domain) + 1) = '.' || r.domain))))
  order by (v.url = k.link) desc, v.decided_at desc
  limit 1
) v on true
where s.created_at > now() - interval '14 days';
