-- ADM-07 backfill (shoo-dashboard plan fase 07a K14): archive rows for the scans still kept (≤ 14
-- days) that the 07a scan trigger did not see, and their current Guardian decisions. Rows only:
-- no evidence fragments and no replica are copied (D-dash-17 #7). A separate migration so that the
-- previous file's locks never wait on it; reads of public.scans/verdicts do not block the backend.
-- Idempotent: scan_id is the key (on conflict do nothing) and a decision is written only on a row
-- without one, so running it twice changes nothing. A function (postgres only, no grant) so pgTAP
-- can run it twice; this migration calls it once.

set local lock_timeout = '1s';
set local statement_timeout = '60s';

create function admin._archive_backfill() returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  insert into admin.scan_archive
    (scan_id, domain, url_path, page_title, score, status, signals, signal_ids, layers,
     detected_at, created_at, owner_ref)
  select s.id, s.domain, admin._url_path(s.url), s.page_title, s.score, s.status::text, x.signals,
         coalesce((select array_agg(distinct e ->> 'id') from jsonb_array_elements(x.signals) e), '{}'),
         coalesce((select array_agg(distinct (e ->> 'layer')::smallint) from jsonb_array_elements(x.signals) e
                    where e ->> 'layer' ~ '^[1-5]$'), '{}'),
         s.detected_at, s.created_at, admin.owner_ref(s.owner_id)
    from public.scans s
    cross join lateral (select admin._archive_signals(s.signals) as signals) x
  on conflict (scan_id) do nothing;

  -- As the verdict trigger: the decision's scan, else the owner's latest scan of the domain before it.
  update admin.scan_archive a
     set verdict = v.value::text, verdict_at = v.decided_at, by_ref = admin.owner_ref(v.by_device_id)
    from public.verdicts v
   where a.verdict is null
     and a.scan_id = coalesce(v.scan_id,
           (select l.scan_id from admin.scan_archive l
             where l.owner_ref = admin.owner_ref(v.owner_id) and l.domain = v.domain and l.detected_at <= v.decided_at
             order by l.detected_at desc limit 1));
end $$;
revoke all on function admin._archive_backfill() from public, anon, authenticated, service_role, shoo_api, shoo_admin;

select admin._archive_backfill();
