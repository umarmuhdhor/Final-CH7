-- PF-01 settings (Figma "Pengaturan/Notifikasi"): which pushes a device wants, and when not.
-- Proposed contract additions, listed for the lead in the PR (contracts/ is read-only for Team App).

alter table devices
  -- "Situs berbahaya" / "Situs diblokir": a push about the device's own warning / blocked scans.
  add column notify_warning        boolean not null default true,
  add column notify_blocked        boolean not null default true,
  -- Guardian: "Aktivitas orang dilindungi" (all members' scans; "Kabari saya" still applies per member)
  -- and "Perlindungan mati" (a member's extension stopped reporting).
  add column notify_family         boolean not null default true,
  add column notify_protection_off boolean not null default true,
  -- "Ringkasan mingguan": Monday 08:00 local. summary_sent_on = the local Monday it last went out.
  add column weekly_summary        boolean not null default false,
  add column summary_sent_on       date,
  -- "Jam tenang": minutes after local midnight. Blocked-site pushes still go out (Figma note).
  add column quiet_hours           boolean not null default true,
  add column quiet_start           smallint not null default 1320 check (quiet_start between 0 and 1439),
  add column quiet_end             smallint not null default 360 check (quiet_end between 0 and 1439),
  -- IANA zone from the phone, for quiet hours and the summary. Indonesia's most common zone until known.
  add column time_zone             text not null default 'Asia/Jakarta' check (time_zone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}$' and char_length(time_zone) <= 40);

-- "Perlindungan mati": when the guardian was told about this off period. Cleared once the member
-- reports again, so the next off period pushes once more.
alter table family_links
  add column off_notified_at timestamptz;
