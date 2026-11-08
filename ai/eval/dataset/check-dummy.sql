-- Sanity checks for the local dummy data (run by seed-dummy.sh as the `postgres` login, local DB only).
-- Any failed check raises an exception, so `psql -v ON_ERROR_STOP=1` exits non-zero.
-- Part 1 runs as shoo_ai (the role Team AI really uses) to prove admin.ai_dataset is readable by it.
begin;
set local role shoo_ai;

do $$
declare
  n int;
begin
  select count(*) into n from admin.ai_dataset where domain like '%.shoo-dummy.test';
  if n < 35 then raise exception 'check failed: only % dummy rows in admin.ai_dataset (need >= 35)', n; end if;

  if not exists (select 1 from admin.ai_dataset where domain like '%.shoo-dummy.test' and is_scam) then
    raise exception 'check failed: no is_scam dummy row';
  end if;
  if not exists (select 1 from admin.ai_dataset where domain like '%.shoo-dummy.test' and not is_scam) then
    raise exception 'check failed: no not-is_scam dummy row';
  end if;

  select count(*) into n from admin.ai_dataset
   where (domain like '%.shoo-dummy.test' or domain = 'sites.google.com') and rdap_age_days is null;
  if n > 0 then raise exception 'check failed: % dummy rows without rdap_age_days', n; end if;
end $$;
commit;

-- Part 2 as postgres: layer scores add up to the signal weights, review_due skips the shared host.
do $$
declare
  n int;
begin
  select count(*) into n
    from admin.ai_dataset d
    join admin.domain_labels l on l.id = d.label_id
    join admin.scan_archive a on a.scan_id = l.scan_id
   where d.domain like '%.shoo-dummy.test'
     and d.layer1_score + d.layer2_score + d.layer3_score + d.layer4_score
         is distinct from (select coalesce(sum((e ->> 'weight')::int), 0) from jsonb_array_elements(a.signals) e);
  if n > 0 then raise exception 'check failed: % rows where layer scores differ from signal weights', n; end if;

  if not exists (select 1 from admin.review_due(100) where domain like 'scam-%.shoo-dummy.test') then
    raise exception 'check failed: admin.review_due has no dummy scam domain';
  end if;
  if exists (select 1 from admin.review_due(100) where domain = 'sites.google.com') then
    raise exception 'check failed: admin.review_due returned the shared host sites.google.com';
  end if;
end $$;

select 'dummy checks passed' as result;
