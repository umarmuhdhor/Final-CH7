-- PF-01 profile redesign (Figma "Profile/Pribadi", "Profile/Guardian", "Guardian/Detail Orang Dilindungi").
-- Proposed contract additions, listed for the lead in the PR (contracts/ is read-only for Team App).

-- Lifetime counters for the profile stats. scans rows go after 14 days, so counting them would
-- shrink; these are plain numbers (no URL or domain) and go with the device on DELETE /devices/me.
alter table devices
  add column blocked_total integer not null default 0 check (blocked_total >= 0),
  add column warning_total integer not null default 0 check (warning_total >= 0),
  -- "iPhone 15 · iOS 26" on the guardian's member detail. Marketing name and major version only.
  add column device_model  text check (device_model ~ '^[A-Za-z0-9 ()]{1,40}$'),
  add column os_version    text check (os_version ~ '^[0-9]{1,3}$');

-- Existing devices start from what retention still holds (at most 14 days).
update devices d
set blocked_total = s.blocked, warning_total = s.warnings
from (
  select owner_id,
         count(*) filter (where status = 'blocked')::int as blocked,
         count(*) filter (where status = 'warning')::int as warnings
  from scans group by owner_id
) s
where s.owner_id = d.id;

-- "Kabari saya": the guardian's push for this member. Off skips the push; the scan still lands in Activity.
-- reminded_at: last "Ingatkan" push, at most one per 6 hours per member.
alter table family_links
  add column notify      boolean not null default true,
  add column reminded_at timestamptz;
