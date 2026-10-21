-- Shoo backend: initial schema (plan/alief/ref/R2-skema-db.md).
-- All client access goes through the Cloudflare Worker as role `shoo_api`.
-- PostgREST roles (anon, authenticated) get no grants at all.

create type device_mode as enum ('guardian', 'protected');
create type scan_status as enum ('warning', 'blocked');
create type verdict_value as enum ('safe', 'not_safe');

-- ---------------------------------------------------------------- tables

create table devices (
  id               text primary key default gen_random_uuid()::text,
  name             text not null check (char_length(name) between 1 and 20),
  mode             device_mode not null,
  avatar_id        text not null check (avatar_id ~ '^avatar_(0[1-9]|1[0-2])$'),
  language         text not null default 'en' check (language in ('en', 'id')),
  apns_token       text,
  token_hash       bytea not null unique,          -- sha256(token); the token itself is never stored
  ext_last_seen_at timestamptz,                    -- PATCH /devices/me { extensionLastSeenAt }
  created_at       timestamptz not null default now(),
  last_seen_at     timestamptz not null default now()
);

create table family_links (
  protected_id text primary key references devices(id) on delete cascade,  -- one guardian per protected (I2)
  guardian_id  text not null references devices(id) on delete cascade,
  created_at   timestamptz not null default now(),
  check (protected_id <> guardian_id)
);
create index family_links_guardian on family_links(guardian_id);

create table family_codes (
  code        char(4) primary key check (code ~ '^[0-9]{4}$'),
  guardian_id text not null references devices(id) on delete cascade,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);
create index family_codes_guardian on family_codes(guardian_id);

create table join_attempts (
  id           bigint generated always as identity primary key,
  device_id    text references devices(id) on delete cascade,
  ip           inet,
  success      boolean not null,
  attempted_at timestamptz not null default now()
);
create index join_attempts_device_time on join_attempts(device_id, attempted_at desc);
create index join_attempts_ip_time on join_attempts(ip, attempted_at desc);

create table scans (
  id              text primary key default gen_random_uuid()::text,
  owner_id        text not null references devices(id) on delete cascade,
  url             text not null check (url ~* '^https?://'),
  domain          text not null check (domain = lower(domain) and domain !~ '^www\.'),
  page_title      text,
  favicon_url     text,
  score           int not null check (score between 30 and 100),
  status          scan_status not null,
  signals         jsonb not null default '[]'::jsonb check (jsonb_typeof(signals) = 'array'),
  screenshot_path text,                            -- '<owner_id>/<scan_id>.jpg' in bucket screenshots
  detected_at     timestamptz not null,
  created_at      timestamptz not null default now(),
  check ((status = 'blocked') = (score >= 80))
);
create index scans_owner_time on scans(owner_id, detected_at desc, id desc);
create index scans_owner_domain_time on scans(owner_id, domain, created_at desc);
create index scans_created on scans(created_at);

create table verdicts (
  owner_id     text not null references devices(id) on delete cascade,
  domain       text not null check (domain = lower(domain) and domain !~ '^www\.'),
  value        verdict_value not null,
  scan_id      text references scans(id) on delete set null,
  by_device_id text not null references devices(id) on delete cascade,
  by_name      text not null,                      -- name snapshot at decision time (DT-06)
  decided_at   timestamptz not null default now(),
  primary key (owner_id, domain)
);
create index verdicts_not_safe on verdicts(decided_at) where value = 'not_safe';
create index verdicts_by_device on verdicts(by_device_id);
create index verdicts_scan on verdicts(scan_id);

-- Global blocklist: review queue + published list (R2 §5, D-alief-25).
create table blocklist_entries (
  domain        text primary key check (domain = lower(domain) and domain !~ '^www\.'),
  families      int not null default 1 check (families >= 0),
  first_seen_at timestamptz not null default now(),
  approved_at   timestamptz,                       -- null = waiting for manual review; only approved rows are served
  approved_by   text,
  removed_at    timestamptz                        -- served through `removed[]`
);
create index blocklist_approved on blocklist_entries(approved_at)
  where approved_at is not null and removed_at is null;
create index blocklist_removed on blocklist_entries(removed_at)
  where approved_at is not null and removed_at is not null;

-- Written by /healthz/db and the retention cron so the Supabase Free project never pauses.
create table ops_heartbeat (
  source text primary key check (source in ('cron', 'healthz')),
  at     timestamptz not null default now()
);

create table push_log (
  id           bigint generated always as identity primary key,
  to_device_id text references devices(id) on delete cascade,
  scan_id      text references scans(id) on delete cascade,
  body         text not null,
  result       text not null,                      -- 'sent' | 'logged' | 'failed:<reason>'
  created_at   timestamptz not null default now()
);
create index push_log_created on push_log(created_at);
create index push_log_device on push_log(to_device_id);
create index push_log_scan on push_log(scan_id);

-- Generic rate-limit counters (R3 §5, D-alief-B02). key_hash = sha256('<bucket>:<ip or device>'),
-- so no raw IP address is stored. Rows older than 1 day are deleted by the retention cron (fase 12).
create table rate_limit_hits (
  id       bigint generated always as identity primary key,
  bucket   text not null,
  key_hash bytea not null,
  hit_at   timestamptz not null default now()
);
create index rate_limit_hits_lookup on rate_limit_hits(bucket, key_hash, hit_at desc);
create index rate_limit_hits_time on rate_limit_hits(hit_at);

-- ---------------------------------------------------------------- invariants

-- I1: a device's mode never changes after insert.
create function devices_mode_immutable() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.mode is distinct from old.mode then
    raise exception 'device mode is immutable' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger devices_mode_immutable
  before update of mode on devices
  for each row execute function devices_mode_immutable();

-- I3 + I4: guardian/protected modes match, max 3 protected per guardian.
create function family_links_check() returns trigger
language plpgsql set search_path = public as $$
declare
  g_mode device_mode;
  p_mode device_mode;
  n      int;
begin
  perform pg_advisory_xact_lock(hashtext(new.guardian_id));
  select mode into g_mode from devices where id = new.guardian_id;
  select mode into p_mode from devices where id = new.protected_id;
  if g_mode is distinct from 'guardian' then
    raise exception 'guardian_id must be a guardian device' using errcode = 'check_violation';
  end if;
  if p_mode is distinct from 'protected' then
    raise exception 'protected_id must be a protected device' using errcode = 'check_violation';
  end if;
  select count(*) into n from family_links
   where guardian_id = new.guardian_id and protected_id <> new.protected_id;
  if n >= 3 then
    raise exception 'family_full' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger family_links_check
  before insert or update on family_links
  for each row execute function family_links_check();

-- ---------------------------------------------------------------- roles and grants

-- No password here: local seed.sql sets a dev password, cloud sets it in the SQL editor (manual step).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'shoo_api') then
    create role shoo_api login noinherit nobypassrls;
  end if;
end $$;

grant usage on schema public to shoo_api;
grant select, insert, update, delete on
  devices, family_links, family_codes, join_attempts, scans, verdicts,
  blocklist_entries, push_log, ops_heartbeat, rate_limit_hits
to shoo_api;
grant usage on all sequences in schema public to shoo_api;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated, public;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated, public;

-- RLS on every table; the only policy is for shoo_api. Authorization lives in the Worker (R3 §3).
do $$
declare
  t text;
begin
  foreach t in array array[
    'devices', 'family_links', 'family_codes', 'join_attempts', 'scans', 'verdicts',
    'blocklist_entries', 'push_log', 'ops_heartbeat', 'rate_limit_hits'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy shoo_api_all on %I for all to shoo_api using (true) with check (true)', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- storage

-- Private bucket for evidence screenshots (fase 09 uploads through the Storage API).
insert into storage.buckets (id, name, public)
values ('screenshots', 'screenshots', false)
on conflict (id) do nothing;
