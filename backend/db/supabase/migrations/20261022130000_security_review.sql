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

-- Screenshot objects still to remove from Storage (SECURITY §3 P13). A path is written in the
-- same transaction that deletes its rows (DELETE /devices/me) or when an object could not be
-- removed; the row goes only after Storage confirmed. The daily cron retries what is left.
create table storage_tombstones (
  path       text primary key check (path ~ '^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+\.(jpg|png)$'),
  created_at timestamptz not null default now()
);
create index storage_tombstones_created on storage_tombstones(created_at);
grant select, insert, delete on storage_tombstones to shoo_api;
revoke all on storage_tombstones from anon, authenticated, service_role;
alter table storage_tombstones enable row level security;
create policy shoo_api_all on storage_tombstones for all to shoo_api using (true) with check (true);
