-- ADM-02 backfill (shoo-dashboard plan K7): what happened before the 02a triggers existed. A separate
-- migration so that the trigger creation (which locks scans/verdicts for writes) never waits on it.
-- Reads only: these SELECTs do not block backend inserts.
--   * domain_intel: scans still kept (≤ 14 days) created before admin.intel_state.intel_since,
--     added to the counters the triggers wrote since.
--   * domain_labels: one locked label per live verdict decided before intel_since whose slot has
--     no label yet (R4 §2).
-- Not recoverable: decisions made in the SQL editor before 01a, and scans already deleted by retention.
-- Known gap: an insert that waited on the trigger creation lock can carry created_at < intel_since
-- and also fire the trigger, so it counts twice (at most the inserts of those ≤ 5 s).
-- Idempotent: admin.intel_state.backfilled_at is set once. A function (postgres only, no grant) so
-- pgTAP can run it twice; this migration calls it once.

set local lock_timeout = '1s';
set local statement_timeout = '60s';

create function admin._backfill() returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_since timestamptz;
begin
  select intel_since into v_since from admin.intel_state where backfilled_at is null for update;
  if not found then
    return;
  end if;

  -- Signals per domain in one pass over scans (no index leads with domain for a per-group lookup).
  insert into admin.domain_intel as d
    (domain, first_seen_at, last_seen_at, scans, blocked, warning, max_score, sum_score, signal_counts)
  with agg as (
    select domain, min(created_at) as first_at, max(created_at) as last_at, count(*) as n,
           count(*) filter (where status = 'blocked') as nb, count(*) filter (where status = 'warning') as nw,
           max(score) as mx, sum(score) as sm
      from public.scans where created_at < v_since group by domain
  ), sig as (
    select domain, jsonb_object_agg(id, n) as counts
      from (select s.domain, e ->> 'id' as id, count(*) as n
              from public.scans s cross join lateral jsonb_array_elements(s.signals) e
             where s.created_at < v_since and e ->> 'id' ~ '^[a-z0-9_]{1,40}$'
             group by 1, 2) x
     group by domain
  )
  select a.domain, a.first_at, a.last_at, a.n, a.nb, a.nw, a.mx, a.sm, coalesce(g.counts, '{}')
    from agg a left join sig g on g.domain = a.domain
  on conflict (domain) do update set
    first_seen_at = least(d.first_seen_at, excluded.first_seen_at),
    last_seen_at  = greatest(d.last_seen_at, excluded.last_seen_at),
    scans         = d.scans + excluded.scans,
    blocked       = d.blocked + excluded.blocked,
    warning       = d.warning + excluded.warning,
    max_score     = greatest(d.max_score, excluded.max_score),
    sum_score     = d.sum_score + excluded.sum_score,
    signal_counts = admin._merge_counts(d.signal_counts, excluded.signal_counts),
    updated_at    = now();

  insert into admin.domain_labels (domain, is_scam, source, connected, ai_score, ai_status, owner_ref, by_ref, created_at)
  select v.domain, v.value = 'not_safe', 'guardian',
         v.owner_id = v.by_device_id
           or exists (select 1 from public.family_links f
                       where f.protected_id = v.owner_id and f.guardian_id = v.by_device_id),
         s.score, s.status::text, admin.owner_ref(v.owner_id), admin.owner_ref(v.by_device_id), v.decided_at
    from public.verdicts v
    left join public.scans s on s.id = v.scan_id
   where v.decided_at < v_since
     and not exists (select 1 from admin.domain_labels l
                      where l.owner_ref = admin.owner_ref(v.owner_id) and l.domain = v.domain and l.source = 'guardian')
   order by v.decided_at;

  update admin.intel_state set backfilled_at = clock_timestamp();
end $$;
revoke all on function admin._backfill() from public, anon, authenticated, service_role, shoo_api, shoo_admin;

select admin._backfill();
