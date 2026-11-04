-- ADM-08 (#241, D-imelda-53): the training API (dashboard /api/v1/training/dataset.jsonl) serves
-- admin.ai_dataset as Team AI asked for it. Two columns are appended so a decision row can be joined
-- to its scan without another table:
--   * scan_id: the archive row's scan id, the key of /api/v1/training/fragments/:scanId and of
--     scans.jsonl (null when the decision has no archived scan, e.g. labels from before L5).
--   * has_fragments: whether that scan has an HTML fragments object to download.
-- Everything else is unchanged (create or replace only appends; grants stay: shoo_admin, shoo_ai).
--
-- Rollback: re-run the admin.ai_dataset definition from 20261104133527_l5_review_data.sql after
--   drop view admin.ai_dataset; and its grant (select to shoo_admin, shoo_ai).

set local lock_timeout = '1s';
set local statement_timeout = '60s';

create or replace view admin.ai_dataset with (security_barrier = true) as
select
  l.id,
  l.id as label_id,
  case when a.scan_id is not null
       then 'https://' || coalesce(a.host, a.domain) || admin.tokenize_path(a.url_path) end as url,
  l.domain,
  a.rdap_registered_at,
  (a.detected_at at time zone 'UTC')::date - a.rdap_registered_at as rdap_age_days,
  coalesce(p.layer1, '[]') as layer1,
  coalesce(p.layer2, '[]') as layer2,
  coalesce(p.layer3, '[]') as layer3,
  coalesce(p.layer4, '[]') as layer4,
  coalesce(p.layer1_score, 0) as layer1_score,
  coalesce(p.layer2_score, 0) as layer2_score,
  coalesce(p.layer3_score, 0) as layer3_score,
  coalesce(p.layer4_score, 0) as layer4_score,
  coalesce(a.score, l.ai_score) as score,
  coalesce(a.status, l.ai_status) as status,
  l.thresholds_version,
  a.detected_at as scanned_at,
  l.is_scam,
  admin.mask_note(l.note) as note,
  l.created_at as decided_at,
  l.owner_ref is null as anonymous,
  d.scans as domain_scans,
  case when d.scans > 0 then round(d.sum_score::numeric / d.scans)::int end as domain_avg_score,
  d.max_score as domain_max_score,
  dl.families_safe,
  dl.families_not_safe,
  dl.label as final_label,
  exists (select 1 from admin.shared_hosts h where l.domain = h.host or l.domain like '%.' || h.host) as shared_host,
  rv.result as review_result,
  rv.suggestion as review_suggestion,
  rv.decision as review_decision,
  a.scan_id,
  a.fragments_key is not null as has_fragments
from admin.domain_labels l
left join admin.scan_archive a on a.scan_id = l.scan_id
left join lateral (
  select
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '1') as layer1,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '2') as layer2,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '3') as layer3,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '4') as layer4,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '1')::int as layer1_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '2')::int as layer2_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '3')::int as layer3_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '4')::int as layer4_score
  from jsonb_array_elements(coalesce(a.signals, '[]')) e
  where (e ->> 'weight') ~ '^[0-9]{1,3}$'
) p on true
left join admin.domain_intel d on d.domain = l.domain
left join admin.domain_intel_label dl on dl.domain = l.domain
left join lateral (
  select r.result, r.suggestion, r.decision
  from admin.domain_review r where r.domain = l.domain
  order by r.reviewed_at desc, r.id desc limit 1
) rv on true
where l.source = 'guardian'
  and not (l.owner_ref is not null and exists (
    select 1 from admin.label_forget f
     where l.created_at <= f.at
       and ((f.by_ref is null and (f.owner_ref = l.owner_ref or f.owner_ref = l.by_ref))
            or (f.owner_ref = l.owner_ref and f.by_ref = l.by_ref))));
