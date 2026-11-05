-- A device delete that hits the lock timeout waits in admin.label_forget until snapshot_daily. Its
-- title and owner are hidden from the moment it is queued; its page fragments have to be too, or they
-- stay viewable and exportable until the next run. create or replace keeps the grants.
create or replace view admin.v_scan_archive with (security_barrier = true) as
select a.scan_id, a.domain, admin.tokenize_path(a.url_path) as path,
       case when f.owner_gone then null else a.page_title end as page_title,
       a.score, a.status, a.signals, a.signal_ids, a.layers, a.detected_at, a.created_at,
       case when f.owner_gone then null else a.owner_ref end as owner_ref,
       case when f.pair_gone then null else a.verdict end as verdict,
       case when f.pair_gone then null else a.verdict_at end as verdict_at,
       case when f.owner_gone or f.pair_gone or f.by_gone then null else a.by_ref end as by_ref,
       case when f.pair_gone then null else a.note end as note,
       case when f.owner_gone then null else a.fragments_key end as fragments_key,
       case when f.owner_gone then null else a.fragments_bytes end as fragments_bytes,
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
