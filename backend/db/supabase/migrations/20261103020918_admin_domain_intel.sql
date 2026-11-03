-- ADM-02 admin dashboard (shoo-dashboard plan, ref/R2 objects labelled 02a, ref/R4 §2–§3): long-term
-- domain data, learning labels and the analysis run. Scans are deleted after 14 days; this keeps,
-- per domain and for good, how often Shoo flagged it, with which signals and score (no owner, URL,
-- path or page title: Q12a, SECURITY D1), plus a copy of each Guardian decision for learning that
-- carries only keyed refs (owner_ref) and is deleted on disconnect or device delete (D4, P13).
--
-- This is the first dashboard migration that touches backend tables: four AFTER triggers on
-- public.scans, public.verdicts, public.devices and public.family_links. Each trigger function
-- catches every error and only raises a WARNING, and waits at most 200 ms for a lock, so no
-- dashboard problem can fail POST /scans, POST /verdicts, DELETE /devices/me or a disconnect
-- (SECURITY A8, invariant I5). Each one does O(1) work: one upsert, one insert or one indexed delete.
--
-- Emergency off switch (TODO D5), any trigger on its own, data already kept stays:
--   alter table public.scans disable trigger admin_scan_intel;
--   alter table public.verdicts disable trigger admin_verdict_label;
-- Rollback (before dashboard phase 04a):
--   drop trigger admin_scan_intel on public.scans; drop trigger admin_verdict_label on public.verdicts;
--   drop trigger admin_device_forget on public.devices; drop trigger admin_family_unlink on public.family_links;
--   drop table admin.domain_labels, admin.label_forget, admin.domain_intel, admin.domain_intel_label,
--              admin.stats_daily, admin.analysis_runs, admin.intel_state, admin.domain_dirty cascade;
--   then re-run the 01a admin.vote and admin.v_feed definitions.
-- The backfill of scans and verdicts older than this migration is the next migration.

-- 1 s, not 5 s: the trigger section locks four live backend tables; a short wait keeps POST /scans
-- from queueing behind it and stays at deadlock_timeout, so a deploy that cannot get the locks
-- fails (and is re-run) instead of a backend transaction being chosen as the deadlock victim.
set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- tables

-- One row per domain, for good (Q40). Counters only, written only by the scan trigger and the
-- backfill. avg score = sum_score / scans. signal_counts = {"<signal id>": n}.
create table admin.domain_intel (
  domain        text primary key check (domain = lower(domain) and domain !~ '^www\.'),
  first_seen_at timestamptz not null,
  last_seen_at  timestamptz not null,
  scans         bigint not null default 0 check (scans >= 0),
  blocked       bigint not null default 0 check (blocked >= 0),
  warning       bigint not null default 0 check (warning >= 0),
  max_score     int not null check (max_score between 0 and 100),
  sum_score     bigint not null default 0 check (sum_score >= 0),
  signal_counts jsonb not null default '{}' check (jsonb_typeof(signal_counts) = 'object'),
  updated_at    timestamptz not null default now()
);

-- The result of the last analysis per domain, apart from the counters so that run_analysis never
-- locks a row the scan trigger upserts (A8, I10). The blocklist status is not stored here: views
-- read it from public.blocklist_entries so it is never stale.
create table admin.domain_intel_label (
  domain            text primary key check (domain = lower(domain) and domain !~ '^www\.'),
  families_not_safe int not null default 0,
  families_safe     int not null default 0,
  label             text check (label in ('scam_strong', 'scam_weak', 'safe')),
  label_source      text check (label_source in ('admin', 'families')),
  label_at          timestamptz,
  category          text references admin.categories (id),
  updated_at        timestamptz not null default now()
);

-- Learning labels (R4 §2). analyzed_at null = locked until the next analysis (Q33); a changed
-- decision after that is a new row (revision_of). owner_ref/by_ref are keyed hashes of device ids
-- (admin.owner_ref): never shown, used only to count families and to delete on disconnect/delete.
create table admin.domain_labels (
  id                 bigint generated always as identity primary key,
  domain             text not null check (domain = lower(domain) and domain !~ '^www\.'),
  is_scam            boolean not null,
  note               text check (char_length(note) <= 1000),
  category           text references admin.categories (id),
  source             text not null check (source in ('guardian', 'admin')),
  connected          boolean not null,
  ai_score           int check (ai_score between 0 and 100),
  ai_status          text check (ai_status in ('warning', 'blocked')),
  thresholds_version int,
  owner_ref          text check (owner_ref ~ '^[0-9a-f]{16}$'),
  by_ref             text check (by_ref ~ '^[0-9a-f]{16}$'),
  actor              text check (char_length(actor) between 1 and 320),
  created_at         timestamptz not null default clock_timestamp(),
  analyzed_at        timestamptz,
  revision_of        bigint references admin.domain_labels (id) on delete set null,
  check ((source = 'guardian') = (owner_ref is not null and by_ref is not null and actor is null)),
  check ((source = 'admin') = (actor is not null))
);
-- Slot lookup in the verdict trigger (latest row of owner + domain) and delete by device.
create index domain_labels_owner_domain on admin.domain_labels (owner_ref, domain, id desc);
create index domain_labels_by on admin.domain_labels (by_ref);
create index domain_labels_domain on admin.domain_labels (domain, id desc);
create index domain_labels_locked on admin.domain_labels (id) where analyzed_at is null;

-- Deletes the label triggers could not do at once because run_analysis held the rows (55P03).
-- Views hide matching labels right away; snapshot_daily() deletes them for real (D4, I11).
-- by_ref null = every label that names owner_ref on either side (device deleted).
create table admin.label_forget (
  id       bigint generated always as identity primary key,
  owner_ref text not null check (owner_ref ~ '^[0-9a-f]{16}$'),
  by_ref    text check (by_ref ~ '^[0-9a-f]{16}$'),
  at        timestamptz not null default clock_timestamp()
);
create index label_forget_owner on admin.label_forget (owner_ref);

-- Domains that lost labels since the last analysis (device delete, disconnect, forget queue), so
-- the next run_analysis recomputes their families and label even with no new label there.
create table admin.domain_dirty (
  domain text primary key
);

-- Daily numbers (R2 §2). *_total rows are running totals at snapshot time, so the next day's
-- delta needs no per-insert hot row (K11).
create table admin.stats_daily (
  day    date not null,
  metric text not null check (metric ~ '^[a-z_]{1,30}$'),
  key    text not null default '' check (char_length(key) <= 100),
  value  bigint not null,
  primary key (day, metric, key)
);

create table admin.analysis_runs (
  id               bigint generated always as identity primary key,
  trigger          text not null check (trigger in ('cron', 'manual')),
  actor            text check (char_length(actor) between 1 and 320),
  started_at       timestamptz not null default clock_timestamp(),
  finished_at      timestamptz,
  labels_processed int not null default 0,
  domains_updated  int not null default 0,
  backlog          int not null default 0,
  ok               boolean,
  error_code       text
);
create index analysis_runs_started on admin.analysis_runs (started_at desc);

-- Boundary between the backfill and the triggers (K7). One row, set again right before the triggers
-- are created (under their table locks). A table rather than admin_config because a timestamp is
-- neither of its kinds.
create table admin.intel_state (
  id            boolean primary key default true check (id),
  intel_since   timestamptz not null,
  backfilled_at timestamptz
);
insert into admin.intel_state (intel_since) values (now());

insert into admin.admin_config (key, value, kind, min_value, max_value, internal, confirm_when) values
  ('analysis_interval_days',      '3',    'int',  1,    30,   false, null),
  ('label_min_families_scam',     '2',    'int',  1,    10,   false, null),
  ('label_min_families_safe',     '2',    'int',  1,    10,   false, null),
  ('ignore_unconnected_guardian', 'true', 'bool', null, null, false, null),
  ('export_min_families',         '2',    'int',  2,    10,   false, 'lower'),
  ('export_enabled',              'true', 'bool', null, null, false, null),
  ('uptime_check_minutes',        '5',    'int',  5,    30,   false, null),
  ('ops_metrics_retention_days',  '90',   'int',  7,    90,   false, null);

-- ---------------------------------------------------------------- internal helpers

-- K2: a device id → 16 hex chars, keyed with the salt from 01a. Not reversible without the salt,
-- which never leaves the database. No grant: called only from the functions below.
create function admin.owner_ref(p_id text) returns text
language sql stable security definer set search_path = admin, pg_temp as $$
  select left(encode(extensions.hmac(p_id, (select value from admin.secrets where key = 'owner_ref_salt'), 'sha256'), 'hex'), 16)
$$;

-- {"id": n} of one scan's signals (ids only; evidence never leaves public.scans). Ids come from the
-- client (any string ≤ 64, routes/scans.ts): only snake_case ids like the contract's
-- (scan-result.schema.json) are counted, so junk cannot grow the row.
create function admin._signal_counts(p_signals jsonb) returns jsonb
language sql immutable set search_path = admin, pg_temp as $$
  select coalesce(jsonb_object_agg(id, n), '{}')
  from (select e ->> 'id' as id, count(*) as n
          from jsonb_array_elements(case jsonb_typeof(p_signals) when 'array' then p_signals else '[]' end) e
         where e ->> 'id' ~ '^[a-z0-9_]{1,40}$' group by 1) x
$$;

-- Adds b's counts to a. New ids are taken only while a has fewer than 64, so a domain's
-- signal_counts stays bounded (≤ 64 + one scan's ids) and the scan trigger stays O(1).
create function admin._merge_counts(a jsonb, b jsonb) returns jsonb
language sql immutable set search_path = admin, pg_temp as $$
  select coalesce(jsonb_object_agg(k, n), '{}')
  from (select k, sum(v::bigint) as n, bool_or(src) as in_a
          from (select key as k, value as v, true as src from jsonb_each_text(a)
                union all
                select key, value, false from jsonb_each_text(b)) x
         group by k) y
  where in_a or (select count(*) from jsonb_object_keys(a)) < 64
$$;

-- A label row the forget queue has already claimed (hidden in views, deleted daily).
create function admin._forgotten(p_owner text, p_by text, p_created timestamptz) returns boolean
language sql stable set search_path = admin, pg_temp as $$
  select p_owner is not null and exists (
    select 1 from admin.label_forget f
     where p_created <= f.at
       and ((f.by_ref is null and (f.owner_ref = p_owner or f.owner_ref = p_by))
            or (f.owner_ref = p_owner and f.by_ref = p_by)))
$$;

-- ---------------------------------------------------------------- triggers (A8)
-- security definer: the backend role has no privilege in schema admin. lock_timeout 200 ms: a
-- held lock loses one count instead of slowing the backend. statement_timeout of the caller
-- (shoo_api 10 s) still applies and query_canceled is not caught, hence O(1) bodies.

create function admin.on_scan_insert() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
begin
  begin
    insert into admin.domain_intel as d
      (domain, first_seen_at, last_seen_at, scans, blocked, warning, max_score, sum_score, signal_counts)
    values (new.domain, new.created_at, new.created_at, 1, (new.status = 'blocked')::int,
            (new.status = 'warning')::int, new.score, new.score, admin._signal_counts(new.signals))
    on conflict (domain) do update set
      first_seen_at = least(d.first_seen_at, excluded.first_seen_at),
      last_seen_at  = greatest(d.last_seen_at, excluded.last_seen_at),
      scans         = d.scans + 1,
      blocked       = d.blocked + excluded.blocked,
      warning       = d.warning + excluded.warning,
      max_score     = greatest(d.max_score, excluded.max_score),
      sum_score     = d.sum_score + excluded.sum_score,
      signal_counts = admin._merge_counts(d.signal_counts, excluded.signal_counts),
      updated_at    = now();
  exception when others then
    raise warning 'admin_trigger_failed on_scan_insert % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- R4 §2. The live verdict always changes (protection is never locked); only the learning copy is.
create function admin.on_verdict() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_ref  text;
  v_by   text;
  v_scam boolean;
  v_last admin.domain_labels;
begin
  begin
    v_ref  := admin.owner_ref(new.owner_id);
    v_by   := admin.owner_ref(new.by_device_id);
    v_scam := new.value = 'not_safe';
    select * into v_last from admin.domain_labels l
     where l.owner_ref = v_ref and l.domain = new.domain and l.source = 'guardian'
       and not admin._forgotten(l.owner_ref, l.by_ref, l.created_at)
     order by l.id desc limit 1;
    if found and (v_last.analyzed_at is null or v_last.is_scam = v_scam) then
      return null;   -- locked (Q33), or the same decision again (upsert with the same value)
    end if;
    insert into admin.domain_labels (domain, is_scam, source, connected, ai_score, ai_status,
                                     owner_ref, by_ref, revision_of)
    select new.domain, v_scam, 'guardian',
           new.owner_id = new.by_device_id
             or exists (select 1 from public.family_links f
                         where f.protected_id = new.owner_id and f.guardian_id = new.by_device_id),
           s.score, s.status::text, v_ref, v_by, v_last.id
    from (select 1) one
    left join public.scans s on s.id = new.scan_id;
  exception when others then
    raise warning 'admin_trigger_failed on_verdict % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- D4 / I8: a deleted device takes every label that names it, as owner or as deciding Guardian.
create function admin.on_device_delete() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_ref text;
begin
  begin
    v_ref := admin.owner_ref(old.id);
    begin
      -- SKIP LOCKED: rows a running analysis holds are left for the forget queue instead of waiting.
      with gone as (
        delete from admin.domain_labels where id in (
          select id from admin.domain_labels where owner_ref = v_ref or by_ref = v_ref for update skip locked)
        returning domain)
      insert into admin.domain_dirty (domain) select distinct domain from gone on conflict do nothing;
      if exists (select 1 from admin.domain_labels where owner_ref = v_ref or by_ref = v_ref) then
        insert into admin.label_forget (owner_ref, by_ref) values (v_ref, null);
      end if;
    exception when lock_not_available then
      insert into admin.label_forget (owner_ref, by_ref) values (v_ref, null);
    end;
  exception when others then
    raise warning 'admin_trigger_failed on_device_delete % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- D4 / P13 / I9: a disconnect takes the labels of that pair only (as dropVerdicts does).
create function admin.on_family_unlink() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_owner text;
  v_by    text;
begin
  begin
    v_owner := admin.owner_ref(old.protected_id);
    v_by    := admin.owner_ref(old.guardian_id);
    begin
      with gone as (
        delete from admin.domain_labels where id in (
          select id from admin.domain_labels where owner_ref = v_owner and by_ref = v_by for update skip locked)
        returning domain)
      insert into admin.domain_dirty (domain) select distinct domain from gone on conflict do nothing;
      if exists (select 1 from admin.domain_labels where owner_ref = v_owner and by_ref = v_by) then
        insert into admin.label_forget (owner_ref, by_ref) values (v_owner, v_by);
      end if;
    exception when lock_not_available then
      insert into admin.label_forget (owner_ref, by_ref) values (v_owner, v_by);
    end;
  exception when others then
    raise warning 'admin_trigger_failed on_family_unlink % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- All four locks at once (one wait, bounded by lock_timeout above), then the backfill boundary:
-- a row committed before this point has no trigger and is counted by the backfill (created_at <
-- intel_since); a row after it fires the trigger.
lock table public.scans, public.verdicts, public.devices, public.family_links in share row exclusive mode;
update admin.intel_state set intel_since = clock_timestamp();

-- No trigger on delete of scans or verdicts: retention and cascades never reduce long-term data (Q18).
create trigger admin_scan_intel after insert on public.scans
  for each row execute function admin.on_scan_insert();
create trigger admin_verdict_label after insert or update of value on public.verdicts
  for each row execute function admin.on_verdict();
create trigger admin_device_forget after delete on public.devices
  for each row execute function admin.on_device_delete();
create trigger admin_family_unlink after delete on public.family_links
  for each row execute function admin.on_family_unlink();

-- ---------------------------------------------------------------- API functions (shoo_admin)

-- 01a vote + one learning label per decision (K6): approve = scam, reject = safe, processed by the
-- next analysis. AI snapshot from the newest scan of the domain (R4 §2 rule 8).
create or replace function admin.vote(p_domain text, p_action text, p_category text, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_category text;
begin
  if p_action is null or p_action not in ('approve', 'reject') then
    raise exception using errcode = '22023', message = 'invalid_action';
  end if;
  perform admin._check_domain(p_domain, false);
  perform admin._require_note(p_note);
  if p_action = 'approve' then
    perform admin._check_category(p_category);
    v_category := p_category;
    perform admin._require_read_committed();
  end if;
  perform pg_advisory_xact_lock(7, 1);
  if p_action = 'approve' then
    perform admin._check_publish_cap();
  end if;

  insert into admin.review_decisions (domain, action, category, note, actor)
  values (p_domain, p_action, v_category, p_note, p_actor);
  perform admin._audit(p_actor, 'blocklist.' || p_action, p_domain, '{"status": "pending"}',
    jsonb_build_object('status', case p_action when 'approve' then 'approved' else 'rejected' end, 'category', v_category),
    p_note);
  insert into admin.domain_labels (domain, is_scam, note, category, source, connected, ai_score, ai_status, actor)
  select p_domain, p_action = 'approve', p_note, v_category, 'admin', true, s.score, s.status::text, p_actor
  from (select 1) one
  left join lateral (select score, status from public.scans
                      where domain = p_domain order by created_at desc, id desc limit 1) s on true;

  -- First vote wins (R4 §1, I4): only an undecided row changes. A concurrent vote waits on the
  -- advisory lock, then matches 0 rows here and rolls back its decision, audit and label rows.
  if p_action = 'approve' then
    update public.blocklist_entries set approved_at = now(), approved_by = p_actor   -- trigger: clock_timestamp()
     where domain = p_domain and approved_at is null and rejected_at is null and removed_at is null;
  else
    update public.blocklist_entries set rejected_at = now(), rejected_by = p_actor
     where domain = p_domain and approved_at is null and rejected_at is null and removed_at is null;
  end if;
  if not found then
    if exists (select 1 from public.blocklist_entries where domain = p_domain) then
      raise exception using errcode = 'SA001', message = 'already_decided';
    end if;
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
end $$;

-- R4 §3. Unlocks at most 5000 locked labels (oldest first), then recomputes the label of every
-- domain they touch (plus every domain in domain_dirty) from the newest analyzed row of each slot: admin approve > admin reject >
-- families reporting scam ≥ label_min_families_scam > families saying safe ≥ label_min_families_safe.
-- A family = one deciding device (count(distinct by_ref)), as recountFamilies counts guardians.
-- Advisory lock (7, 0) makes runs exclusive (classes 1–6 are the backend's). The caller sets
-- statement_timeout for the transaction (role default 5 s, R4 §3; 02b uses 50 s). A statement
-- timeout (57014) is not caught here and rolls back the run row too, so 02b must log it itself. A failure inside the work is
-- recorded on the run row (ok = false, error_code) and the labels stay locked.
create function admin.run_analysis(p_trigger text, p_actor text)
returns jsonb
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_run      bigint;
  v_labels   int := 0;
  v_domains  int := 0;
  v_backlog  int := 0;
  v_now      timestamptz := clock_timestamp();
  v_min_scam int := (admin._cfg('label_min_families_scam'))::int;
  v_min_safe int := (admin._cfg('label_min_families_safe'))::int;
  v_ignore   boolean := coalesce((admin._cfg('ignore_unconnected_guardian'))::boolean, true);
  v_err      text;
  v_ids      bigint[];
  v_dirty    text[];
begin
  if p_trigger is null or p_trigger not in ('cron', 'manual') then
    raise exception using errcode = '22023', message = 'invalid_trigger';
  end if;
  if not pg_try_advisory_xact_lock(7, 0) then
    raise exception using errcode = 'SA012', message = 'analysis_running';
  end if;
  insert into admin.analysis_runs (trigger, actor) values (p_trigger, p_actor) returning id into v_run;

  begin
    -- Locks the batch: a device delete meanwhile goes to label_forget instead of waiting (I11).
    select coalesce(array_agg(id), '{}') into v_ids
      from (select id from admin.domain_labels
             where analyzed_at is null order by id limit 5000 for update) x;
    v_labels := cardinality(v_ids);

    update admin.domain_labels set analyzed_at = v_now where id = any (v_ids);
    with d as (delete from admin.domain_dirty returning domain)
    select coalesce(array_agg(domain), '{}') into v_dirty from d;

    with doms as (select domain from admin.domain_labels where id = any (v_ids)
                  union
                  select unnest(v_dirty)),
    slots as (   -- newest analyzed, not forgotten row per slot
      select distinct on (l.domain, l.source, coalesce(l.owner_ref, ''))
             l.domain, l.source, l.is_scam, l.connected, l.by_ref, l.category, l.id
        from admin.domain_labels l join doms d on d.domain = l.domain
       where l.analyzed_at is not null and not admin._forgotten(l.owner_ref, l.by_ref, l.created_at)
       order by l.domain, l.source, coalesce(l.owner_ref, ''), l.id desc
    ),
    per as (
      select d.domain,
             count(distinct s.by_ref) filter (where s.source = 'guardian' and s.is_scam and (s.connected or not v_ignore))::int as fam_scam,
             count(distinct s.by_ref) filter (where s.source = 'guardian' and not s.is_scam and (s.connected or not v_ignore))::int as fam_safe,
             (array_agg(s.is_scam order by s.id desc) filter (where s.source = 'admin'))[1] as admin_scam,
             (array_agg(s.category order by s.id desc) filter (where s.source = 'admin'))[1] as admin_category
        from doms d left join slots s on s.domain = d.domain
       group by d.domain
    ),
    lab as (
      select domain, fam_scam, fam_safe,
             case when admin_scam then 'scam_strong'
                  when admin_scam = false then 'safe'
                  when fam_scam >= v_min_scam then 'scam_weak'
                  when fam_safe >= v_min_safe then 'safe' end as label,
             case when admin_scam is not null then 'admin'
                  when fam_scam >= v_min_scam or fam_safe >= v_min_safe then 'families' end as source,
             admin_category as category
        from per
    ),
    up as (
      insert into admin.domain_intel_label as t
        (domain, families_not_safe, families_safe, label, label_source, label_at, category, updated_at)
      select domain, fam_scam, fam_safe, label, source, case when label is not null then v_now end, category, v_now
        from lab
      on conflict (domain) do update set
        families_not_safe = excluded.families_not_safe,
        families_safe     = excluded.families_safe,
        label             = excluded.label,
        label_source      = excluded.label_source,
        label_at          = case when t.label is distinct from excluded.label then excluded.label_at else t.label_at end,
        category          = excluded.category,
        updated_at        = excluded.updated_at
      where (t.families_not_safe, t.families_safe, t.label, t.label_source, t.category)
            is distinct from (excluded.families_not_safe, excluded.families_safe, excluded.label, excluded.label_source, excluded.category)
      returning 1
    )
    select count(*) into v_domains from up;

    select count(*) into v_backlog from admin.domain_labels where analyzed_at is null;
    update admin.analysis_runs
       set finished_at = clock_timestamp(), labels_processed = v_labels, domains_updated = v_domains,
           backlog = v_backlog, ok = true
     where id = v_run;
  exception when others then
    v_err := sqlstate;
    raise warning 'admin_analysis_failed %', v_err;
    update admin.analysis_runs set finished_at = clock_timestamp(), ok = false, error_code = v_err where id = v_run;
    v_labels := 0; v_domains := 0;
  end;
  if p_trigger = 'manual' then
    perform admin._audit(coalesce(p_actor, 'unknown'), 'analysis.run', null, null,
      jsonb_build_object('run', v_run, 'labels', v_labels, 'domains', v_domains), null);
  end if;
  return jsonb_build_object('run', v_run, 'ok', v_err is null, 'labels_processed', v_labels,
                            'domains_updated', v_domains, 'backlog', v_backlog, 'error_code', v_err);
end $$;

-- Daily, from the cron of dashboard phase 02b (R4 §3): numbers of the previous WITA day into
-- stats_daily, then the real delete of labels in label_forget. Running it twice on one day gives
-- the same rows (each delta is against the totals stored for an earlier day). Skipped while an
-- analysis holds (7, 0); the next day retries.
create function admin.snapshot_daily()
returns jsonb
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '2s' as $$
declare
  v_day      date := (now() at time zone 'Asia/Makassar')::date - 1;
  v_from     timestamptz := (v_day::timestamp) at time zone 'Asia/Makassar';
  v_to       timestamptz := ((v_day + 1)::timestamp) at time zone 'Asia/Makassar';
  v_prev     date;
  v_forgot   int := 0;
  v_maxf     bigint;
begin
  if not pg_try_advisory_xact_lock(7, 0) then
    return jsonb_build_object('ok', false, 'error_code', 'analysis_running', 'day', v_day);
  end if;
  select max(day) into v_prev from admin.stats_daily where metric = 'scans_total' and day < v_day;

  delete from admin.stats_daily where day = v_day;
  -- Running totals (scans by status, signals by id) from domain_intel; the day is the difference.
  insert into admin.stats_daily (day, metric, key, value)
  select v_day, 'scans_total', k, n from (
    select 'blocked' as k, coalesce(sum(blocked), 0) as n from admin.domain_intel
    union all select 'warning', coalesce(sum(warning), 0) from admin.domain_intel) x;
  insert into admin.stats_daily (day, metric, key, value)
  select v_day, 'signal_total', s.key, sum(s.value::bigint)
    from admin.domain_intel d cross join lateral jsonb_each_text(d.signal_counts) s
   group by s.key;
  insert into admin.stats_daily (day, metric, key, value)
  select v_day, replace(t.metric, '_total', ''), t.key,
         t.value - coalesce((select p.value from admin.stats_daily p
                              where p.day = v_prev and p.metric = t.metric and p.key = t.key), 0)
    from admin.stats_daily t
   where t.day = v_day and t.metric in ('scans_total', 'signal_total');

  insert into admin.stats_daily (day, metric, key, value)
  select v_day, 'verdicts', value::text, count(*) from public.verdicts
   where decided_at >= v_from and decided_at < v_to group by value
  union all
  select v_day, 'devices', mode::text, count(*) from public.devices group by mode
  union all
  select v_day, 'families', '', count(distinct guardian_id) from public.family_links
  union all
  select v_day, 'ext_active', '', count(*) from public.devices
   where mode = 'protected' and ext_last_seen_at >= v_from and ext_last_seen_at < v_to
  union all
  select v_day, 'push', result, count(*) from public.push_log
   where created_at >= v_from and created_at < v_to group by result;

  -- I11: the real delete of what the triggers could not delete at once.
  -- Bounded by the queue's max id read first: a forget row committed after the label delete must
  -- stay, or its label would show again (I11).
  select max(id) into v_maxf from admin.label_forget;
  with gone as (
    delete from admin.domain_labels l
     where exists (select 1 from admin.label_forget f
                    where f.id <= v_maxf and l.created_at <= f.at
                      and ((f.by_ref is null and (f.owner_ref = l.owner_ref or f.owner_ref = l.by_ref))
                           or (f.owner_ref = l.owner_ref and f.by_ref = l.by_ref)))
    returning domain),
  dirty as (
    insert into admin.domain_dirty (domain) select distinct domain from gone on conflict do nothing)
  select count(*) into v_forgot from gone;
  delete from admin.label_forget where id <= v_maxf;

  return jsonb_build_object('ok', true, 'day', v_day, 'labels_forgotten', v_forgot);
end $$;

-- ---------------------------------------------------------------- views (shoo_admin, select only)
-- Families are counts only; owner_ref/by_ref never leave the database (D-dash-07, I13).

create view admin.v_domain_intel as
select
  coalesce(i.domain, l.domain) as domain,
  i.first_seen_at,
  i.last_seen_at,
  coalesce(i.scans, 0) as scans,
  coalesce(i.blocked, 0) as blocked,
  coalesce(i.warning, 0) as warning,
  i.max_score,
  case when i.scans > 0 then round(i.sum_score::numeric / i.scans)::int end as avg_score,
  coalesce(i.signal_counts, '{}') as signal_counts,
  coalesce(l.families_not_safe, 0) as families_not_safe,
  coalesce(l.families_safe, 0) as families_safe,
  l.label,
  l.label_source,
  l.label_at,
  l.category,
  case
    when b.domain is null then null
    when b.removed_at is not null then 'removed'
    when b.approved_at is not null then 'approved'
    when b.rejected_at is not null then 'rejected'
    else 'pending'
  end as blocklist_status
from admin.domain_intel i
full join admin.domain_intel_label l on l.domain = i.domain
left join public.blocklist_entries b on b.domain = coalesce(i.domain, l.domain);

-- Labels without refs, hidden as soon as they are in label_forget (I11). The forget check is
-- inline: a function called from a view runs with the caller's EXECUTE privilege (see 01a v_scans).
create view admin.v_labels with (security_barrier = true) as
select l.id, l.domain, l.is_scam, l.note, l.category, l.source, l.connected, l.ai_score, l.ai_status,
       l.thresholds_version, l.actor, l.created_at, l.analyzed_at, l.revision_of
from admin.domain_labels l
where not exists (select 1 from admin.label_forget f
                   where l.created_at <= f.at
                     and ((f.by_ref is null and (f.owner_ref = l.owner_ref or f.owner_ref = l.by_ref))
                          or (f.owner_ref = l.owner_ref and f.by_ref = l.by_ref)));

create view admin.v_analysis_runs as
select id, trigger, actor, started_at, finished_at, labels_processed, domains_updated, backlog, ok, error_code
from admin.analysis_runs;

create view admin.v_stats_daily as
select day, metric, key, value from admin.stats_daily where metric not like '%\_total';

-- 01a feed + Guardian labels (no device, actor 'guardian') + analysis runs.
create or replace view admin.v_feed as
select 'decision'::text as kind, r.id, r.at, r.actor, 'blocklist.' || r.action as action,
       r.domain as target, r.category, r.note
from admin.review_decisions r
union all
select 'audit', a.id, a.at, a.actor, a.action, a.target, null, a.note
from admin.admin_audit a
where a.action not like 'blocklist.%' and a.action <> 'analysis.run'
union all
select 'label', l.id, l.created_at, 'guardian', 'label.' || case when l.is_scam then 'not_safe' else 'safe' end,
       l.domain, null, null
from admin.domain_labels l
where l.source = 'guardian'
  and not exists (select 1 from admin.label_forget f
                   where l.created_at <= f.at
                     and ((f.by_ref is null and (f.owner_ref = l.owner_ref or f.owner_ref = l.by_ref))
                          or (f.owner_ref = l.owner_ref and f.by_ref = l.by_ref)))
union all
select 'analysis', r.id, r.started_at, coalesce(r.actor, 'cron'), 'analysis.' || r.trigger, null, null,
       case when r.ok then format('%s label, %s domain', r.labels_processed, r.domains_updated)
            else 'gagal ' || coalesce(r.error_code, '') end
from admin.analysis_runs r;

-- ---------------------------------------------------------------- privileges

do $$
declare
  t text;
begin
  foreach t in array array['domain_intel', 'domain_intel_label', 'domain_labels', 'label_forget',
                           'domain_dirty', 'stats_daily', 'analysis_runs', 'intel_state'] loop
    execute format('alter table admin.%I enable row level security', t);
  end loop;
end $$;

revoke all on all tables in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all sequences in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all functions in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;

grant select on
  admin.v_review_queue, admin.v_blocklist, admin.v_scans, admin.v_ops_snapshot,
  admin.v_audit, admin.v_config, admin.v_categories, admin.v_feed,
  admin.v_domain_intel, admin.v_labels, admin.v_analysis_runs, admin.v_stats_daily
to shoo_admin;

grant execute on function
  admin.vote(text, text, text, text, text),
  admin.unreject(text, text, text),
  admin.remove_domain(text, text, text),
  admin.add_domain(text, text, text, text),
  admin.replica_for(text),
  admin.set_config(text, text, text, text, text),
  admin.log_audit(text, text, text, text),
  admin.run_analysis(text, text),
  admin.snapshot_daily()
to shoo_admin;
