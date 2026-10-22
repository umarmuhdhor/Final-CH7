-- Fase 12 security review (D-alief-B12).

-- HIGH: the Worker's Supabase secret key (Storage only) maps to service_role, which keeps
-- Supabase's default grants on public and bypasses RLS through the Data API. Nothing in this
-- project uses service_role for tables: the Worker talks to Postgres as shoo_api.
revoke all on all tables in schema public from service_role;
revoke all on all sequences in schema public from service_role;
revoke all on all functions in schema public from service_role;
alter default privileges in schema public revoke all on tables from service_role;
alter default privileges in schema public revoke all on sequences from service_role;
alter default privileges in schema public revoke all on functions from service_role;

-- The Worker may only delete review-queue rows nobody has decided on (recountFamilies);
-- approved and removed rows are the reviewer's record and the served list (T5).
drop policy shoo_api_all on blocklist_entries;
create policy shoo_api_read on blocklist_entries for select to shoo_api using (true);
create policy shoo_api_queue on blocklist_entries for insert to shoo_api
  with check (approved_at is null and removed_at is null);
create policy shoo_api_recount on blocklist_entries for update to shoo_api using (true) with check (true);
create policy shoo_api_drop_undecided on blocklist_entries for delete to shoo_api
  using (approved_at is null and removed_at is null);

-- Screenshot objects still to remove from Storage (SECURITY §3 P13). A path is written before
-- the object can exist (in the transaction that reserves an upload) and with the delete of its
-- rows (DELETE /devices/me). It goes only after Storage confirmed a remove, or once an upload
-- finished for a scan that still exists. The daily cron removes paths no scan points at that are
-- older than 10 minutes (an upload may still be landing), so no object is left untracked.
-- The CHECK is length only: a path that failed a stricter pattern would roll back DELETE /devices/me.
create table storage_tombstones (
  path        text primary key check (char_length(path) between 3 and 300),
  created_at  timestamptz not null default now(),
  attempts    int not null default 0,
  last_try_at timestamptz
);
create index storage_tombstones_due on storage_tombstones(last_try_at nulls first, created_at);
grant select, insert, delete on storage_tombstones to shoo_api;
grant update (attempts, last_try_at) on storage_tombstones to shoo_api;
revoke all on storage_tombstones from anon, authenticated, service_role;
alter table storage_tombstones enable row level security;
create policy shoo_api_all on storage_tombstones for all to shoo_api using (true) with check (true);

-- Original uploads (the path names the scan's own id). Dedupe and both quotas count only these, so
-- the global quota is an index-only scan instead of a sort over every scan of the last 24 h.
-- Queries must repeat this predicate verbatim for the planner to use the index.
create index scans_original_shot on scans(created_at)
  where screenshot_path = owner_id || '/' || id || '.jpg' or screenshot_path = owner_id || '/' || id || '.png';

-- Retention's "no other scan shares this path" probe and the tombstone drain look paths up per owner.
create index scans_shot_path on scans(owner_id, screenshot_path) where screenshot_path is not null;
