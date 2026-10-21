-- Fase 10 verdicts (R2 §5, D-alief-25).
-- Blocklist eligibility is decided once, at POST /verdicts, and kept as a snapshot: a later
-- disconnect does not silently change what reviewers see in blocklist_entries.
alter table verdicts add column global_eligible boolean not null default false,
  add constraint verdicts_eligible_not_safe check (not global_eligible or value = 'not_safe');

-- families = count(distinct by_device_id) of eligible not_safe verdicts for a domain.
create index verdicts_eligible_domain on verdicts(domain, by_device_id)
  where value = 'not_safe' and global_eligible;
