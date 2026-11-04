-- #270 (layer 3 RDAP, for layer 5 #241): the domain's registration date per RDAP, as the extension
-- got it from POST /analyze (`rdapRegisteredAt`), on public.scans and on the permanent
-- admin.scan_archive row, so the age of a domain at scan time can be checked later. A registration
-- date is public registry data, not personal data. Null = not sent (older extension or ai/), RDAP
-- failed or timed out, or out of range: the API stores null instead of refusing the scan.
--   * new scan: the 07a insert trigger copies the date into the archive row.
--   * repeat visit of the same site (PR-05, the row is kept): the API fills the date only while it
--     is null, and admin_scan_rdap copies that first known date into the archive row. A known date
--     is never overwritten on either side.
-- Nothing reads the date yet; admin.ai_dataset (layer 5) will.
--
-- Emergency off switch for the new trigger (the archive write inside on_scan_insert has its own):
--   alter table public.scans disable trigger admin_scan_rdap;
-- Rollback (dates are lost):
--   drop trigger admin_scan_rdap on public.scans; drop function admin.on_scan_rdap();
--   alter table admin.scan_archive drop column rdap_registered_at;
--   alter table public.scans drop column rdap_registered_at;
--   then re-run the 07a admin.on_scan_insert() and admin.v_scan_archive definitions.

-- 1 s (as 07a): add column and create trigger lock public.scans; a short wait keeps POST /scans
-- from queueing behind the deploy. On lock timeout (55P03) the whole file rolls back; re-run it.
set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- columns

-- The floor matches the API's: no registry date before 1985 is real. The upper bound (tomorrow)
-- is checked in the API only, as now() cannot be in a check constraint.
alter table public.scans add column rdap_registered_at date
  constraint scans_rdap_registered_at_floor check (rdap_registered_at >= date '1985-01-01');
alter table admin.scan_archive add column rdap_registered_at date;

-- ---------------------------------------------------------------- triggers

-- 07a on_scan_insert + rdap_registered_at in the archive row. Nothing else changed.
create or replace function admin.on_scan_insert() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
begin
  begin
    insert into admin.domain_intel as d
      (domain, first_seen_at, last_seen_at, scans, blocked, warning, max_score, sum_score, signal_counts)
    values (new.domain, new.created_at, new.created_at, 1, (new.status = 'blocked')::int,
            (new.status = 'warning')::int, new.score, new.score, admin._signal_counts(new.signals))
    on conflict (domain) do update set
      first_seen_at = least(d.first_seen_at, excluded.first_seen_at),
      last_seen_at  = greatest(d.last_seen_at, excluded.last_seen_at),
      scans         = d.scans + 1,
      blocked       = d.blocked + excluded.blocked,
      warning       = d.warning + excluded.warning,
      max_score     = greatest(d.max_score, excluded.max_score),
      sum_score     = d.sum_score + excluded.sum_score,
      signal_counts = admin._merge_counts(d.signal_counts, excluded.signal_counts),
      updated_at    = now();
  exception when others then
    raise warning 'admin_trigger_failed on_scan_insert % %', sqlstate, sqlerrm;
  end;
  begin
    insert into admin.scan_archive
      (scan_id, domain, url_path, page_title, score, status, signals, signal_ids, layers,
       detected_at, created_at, owner_ref, rdap_registered_at)
    select new.id, new.domain, admin._url_path(new.url), new.page_title, new.score, new.status::text,
           s.signals,
           coalesce((select array_agg(distinct e ->> 'id') from jsonb_array_elements(s.signals) e), '{}'),
           coalesce((select array_agg(distinct (e ->> 'layer')::smallint) from jsonb_array_elements(s.signals) e
                      where e ->> 'layer' ~ '^[1-5]$'), '{}'),
           new.detected_at, new.created_at, admin.owner_ref(new.owner_id), new.rdap_registered_at
    from (select admin._archive_signals(new.signals) as signals) s
    on conflict (scan_id) do nothing;
  exception when others then
    raise warning 'admin_trigger_failed on_scan_archive % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- The first known date of a kept row (repeat visit, PR-05). Fills only an empty archive date.
create function admin.on_scan_rdap() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
begin
  begin
    update admin.scan_archive set rdap_registered_at = new.rdap_registered_at
     where scan_id = new.id and rdap_registered_at is null;
  exception when others then
    raise warning 'admin_trigger_failed on_scan_rdap % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

create trigger admin_scan_rdap after update of rdap_registered_at on public.scans
  for each row when (old.rdap_registered_at is null and new.rdap_registered_at is not null)
  execute function admin.on_scan_rdap();

-- ---------------------------------------------------------------- views

-- 07a v_scan_archive + rdap_registered_at at the end (create or replace keeps the grants).
create or replace view admin.v_scan_archive with (security_barrier = true) as
select a.scan_id, a.domain, admin.tokenize_path(a.url_path) as path,
       case when f.owner_gone then null else a.page_title end as page_title,
       a.score, a.status, a.signals, a.signal_ids, a.layers, a.detected_at, a.created_at,
       case when f.owner_gone then null else a.owner_ref end as owner_ref,
       case when f.pair_gone then null else a.verdict end as verdict,
       case when f.pair_gone then null else a.verdict_at end as verdict_at,
       case when f.owner_gone or f.pair_gone or f.by_gone then null else a.by_ref end as by_ref,
       case when f.pair_gone then null else a.note end as note,
       a.fragments_key, a.fragments_bytes,
       coalesce(a.stripped_at, case when f.owner_gone then now() end) as stripped_at,
       a.rdap_registered_at
from admin.scan_archive a
cross join lateral (
  select
    a.owner_ref is not null and exists (select 1 from admin.label_forget q
      where q.by_ref is null and q.owner_ref = a.owner_ref) as owner_gone,
    a.by_ref is not null and exists (select 1 from admin.label_forget q
      where q.by_ref is null and q.owner_ref = a.by_ref) as by_gone,
    a.owner_ref is not null and a.by_ref is not null and exists (select 1 from admin.label_forget q
      where q.owner_ref = a.owner_ref and q.by_ref = a.by_ref and a.verdict_at <= q.at) as pair_gone
) f;

-- ---------------------------------------------------------------- privileges

revoke all on function admin.on_scan_rdap() from public, anon, authenticated, service_role, shoo_api, shoo_admin;
