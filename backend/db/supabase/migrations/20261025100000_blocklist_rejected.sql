-- Blocklist review: a "rejected" state (issue #99 Q3, C6 runbook).
-- A reviewer who rejects a queued domain records it here, so the queue query
-- (approved_at is null and rejected_at is null) stops showing it every session.
-- Set only by a person in the SQL editor as postgres: shoo_api has column grants on
-- (domain, families) only (hardening), so it cannot write these columns.
-- A rejected row is never served: it cannot be approved until rejected_at is cleared.
-- When every family withdraws support, recountFamilies still deletes it like any
-- undecided row (approved_at and removed_at are null): no browsing domain is kept
-- without a purpose (D-alief-40).

alter table blocklist_entries
  add column rejected_at timestamptz,
  add column rejected_by text,
  add constraint blocklist_rejected_needs_by check (rejected_at is null or rejected_by is not null),
  add constraint blocklist_rejected_not_approved check (rejected_at is null or approved_at is null);
