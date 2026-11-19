-- #241 / contracts/api.md "Verdicts": the Guardian's note is cleared after 14 days. Retention clears
-- public.verdicts.notes (cron/retention.ts step verdict_notes), but admin.on_verdict copies the masked note
-- into admin.domain_labels.note, admin.guardian_decisions.note and admin.scan_archive.note, and nothing
-- expired those copies: they stayed until the device was deleted or unlinked (EGM audit B12).
--
-- Fix: admin.expire_notes() clears every admin copy older than 14 days (the age of the decision it came
-- from: created_at for labels and decisions, verdict_at for the archive). It runs
--   * once now, for the copies already past 14 days;
--   * from a statement trigger on public.verdicts each time an UPDATE turns a note into null. That is the
--     retention step's own update, so the copies go the same day as the original. It is a sweep, not a
--     per-row match: a copy whose verdict row was overwritten by a later decision (no null transition for
--     that note) still goes once it is 14 days old.
-- A trigger function needs no EXECUTE grant to fire, so shoo_api still executes no admin function
-- (admin_grants I2). A held row or any other error never fails the retention update: it is skipped with a
-- warning and the next sweep (next day at the latest) clears it.
--
-- Partial indexes keep the sweep cheap: only rows that still hold a note are scanned.
-- Rollback: drop trigger admin_verdict_notes_expire on public.verdicts; drop function
-- admin.on_verdict_notes_cleared(); drop function admin.expire_notes(); drop the three *_note_due indexes.
-- The notes already cleared stay cleared (not recoverable, by design).

set local lock_timeout = '5s';
set local statement_timeout = '120s';

create index if not exists domain_labels_note_due on admin.domain_labels (created_at) where note is not null;
create index if not exists guardian_decisions_note_due on admin.guardian_decisions (created_at) where note is not null;
create index if not exists scan_archive_note_due on admin.scan_archive (verdict_at) where note is not null;

create function admin.expire_notes() returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_cutoff timestamptz := now() - interval '14 days';
begin
  update admin.domain_labels set note = null where note is not null and created_at < v_cutoff;
  update admin.guardian_decisions set note = null where note is not null and created_at < v_cutoff;
  update admin.scan_archive set note = null where note is not null and verdict_at < v_cutoff;
end $$;

create function admin.on_verdict_notes_cleared() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
begin
  if exists (
    select 1 from old_rows o join new_rows n on n.owner_id = o.owner_id and n.url = o.url
     where o.notes is not null and n.notes is null
  ) then
    perform admin.expire_notes();
  end if;
  return null;
exception when others then
  raise warning 'admin_trigger_failed on_verdict_notes_cleared % %', sqlstate, sqlerrm;
  return null;
end $$;

-- Transition tables cannot be combined with an UPDATE OF column list, so the trigger fires on every
-- UPDATE statement of verdicts and checks the transition itself (a one-row join for POST /verdicts).
create trigger admin_verdict_notes_expire after update on public.verdicts
  referencing old table as old_rows new table as new_rows
  for each statement execute function admin.on_verdict_notes_cleared();

revoke all on function admin.expire_notes() from public, anon, authenticated, service_role, shoo_api, shoo_admin, shoo_ai;
revoke all on function admin.on_verdict_notes_cleared() from public, anon, authenticated, service_role, shoo_api, shoo_admin, shoo_ai;

select admin.expire_notes();
