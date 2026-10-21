-- Blocklist cursor safety (fase 07 review, D-alief-B05).
-- GET /blocklist pages by event time, so approval and removal times set by UPDATE
-- (the manual review path) come from clock_timestamp(): unique per row, and a
-- re-approved domain gets a new addedAt that clients past the old one still see.

alter table blocklist_entries
  add constraint blocklist_removed_needs_approved check (removed_at is null or approved_at is not null),
  add constraint blocklist_approved_needs_by check (approved_at is null or approved_by is not null);

create function blocklist_entries_times() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.approved_at is not null and (
       new.approved_at is distinct from old.approved_at
       or (old.removed_at is not null and new.removed_at is null)) then
    new.approved_at := clock_timestamp();
  end if;
  if new.removed_at is not null and new.removed_at is distinct from old.removed_at then
    new.removed_at := clock_timestamp();
  end if;
  return new;
end $$;

create trigger blocklist_entries_times
  before update on blocklist_entries
  for each row execute function blocklist_entries_times();

revoke all on function blocklist_entries_times() from anon, authenticated, public;
