-- ADM-04 admin dashboard (shoo-dashboard plan fase 04a, ref/R2 objects labelled 04a, ref/R4 §3 step 6
-- and §4): how often the AI is right, which signals mislead, which score threshold fits best, and
-- the case library + lessons the AI team curates with the admins.
--
-- Nothing here changes what the backend or the extension does. The score thresholds are only
-- stored: admin.public_config publishes 30/80 version 0 until thresholds_live is switched on in
-- dashboard phase 05 (G6), and no role can read that view before 05 grants it to shoo_api.
-- The only backend-facing change is admin.on_verdict, which now also records the published
-- thresholds version on each label (R4 §2 rule 8): still one O(1) read, still error-proof (A8).
--
-- Evaluation limits (K1): a verdict exists only for a stored scan, and only scans scoring ≥ 30
-- (warning/blocked) are stored, so every label is a page the AI already flagged. "Recall" is recall
-- among flagged pages (FN = warning judged scam); misses below 30 cannot be measured.
--
-- Rollback (before dashboard phase 04b):
--   drop view admin.v_eval_summary, admin.v_eval_curve, admin.v_eval_labels, admin.v_eval_signals,
--             admin.v_eval_targets, admin.v_cases, admin.v_lessons, admin.v_thresholds,
--             admin.public_config, admin._eval_counted, admin._case_eligible;
--   drop function admin.set_thresholds, admin.reset_thresholds, admin.case_add, admin.case_pin,
--                 admin.case_delete, admin.lesson_add, admin.lesson_pin, admin.lesson_delete,
--                 admin.usage_record, admin._refresh_cases, admin._store_thresholds,
--                 admin._check_text, admin._check_json, admin._check_signals, admin._check_actor;
--   drop table admin.case_library, admin.ai_lessons;
--   delete from admin.admin_config where key in ('require_guardian_note', 'case_library_size',
--     'threshold_warn_at', 'threshold_block_at', 'thresholds_version', 'thresholds_live');
--   then re-run the 02a admin.on_verdict and admin.run_analysis definitions.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- tables

-- Example cases for the AI (layer 4). One case per domain for good: a case an admin deleted stays
-- as a 'deleted' row so the analysis never brings it back (K3). signals = the domain's
-- signal_counts at the time ({"<signal id>": n}, ids only).
create table admin.case_library (
  id         bigint generated always as identity primary key,
  domain     text not null unique check (domain = lower(domain) and domain !~ '^www\.'),
  signals    jsonb not null default '{}' check (jsonb_typeof(signals) = 'object'),
  label      text not null check (label in ('scam_strong', 'scam_weak', 'safe')),
  category   text references admin.categories (id),
  note       text check (char_length(note) <= 500 and position('<' in note) = 0),
  pinned     boolean not null default false,
  status     text not null default 'active' check (status in ('active', 'deleted')),
  uses       bigint not null default 0 check (uses >= 0),
  correct    bigint not null default 0 check (correct >= 0),
  wrong      bigint not null default 0 check (wrong >= 0),
  source     text not null check (source in ('analysis', 'ai', 'admin')),
  created_by text check (char_length(created_by) between 1 and 320 and position('<' in created_by) = 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- A category's active cases (K3 limit). Safe and uncategorised scam cases group by their label.
create index case_library_group on admin.case_library ((coalesce(category, label))) where status = 'active';

-- REPEAT/AVOID lessons the AI team writes (Q45); admins pin or delete them.
create table admin.ai_lessons (
  id            bigint generated always as identity primary key,
  kind          text not null check (kind in ('avoid', 'repeat')),
  text          text not null check (char_length(text) between 1 and 500 and position('<' in text) = 0),
  conditions    jsonb not null default '{}' check (jsonb_typeof(conditions) = 'object' and octet_length(conditions::text) <= 2048),
  from_label_id bigint references admin.domain_labels (id) on delete set null,
  pinned        boolean not null default false,
  status        text not null default 'active' check (status in ('active', 'deleted')),
  uses          bigint not null default 0 check (uses >= 0),
  correct       bigint not null default 0 check (correct >= 0),
  wrong         bigint not null default 0 check (wrong >= 0),
  created_by    text not null check (char_length(created_by) between 1 and 320 and position('<' in created_by) = 0),
  created_at    timestamptz not null default now()
);
-- A label delete (device delete, disconnect) sets from_label_id null without a scan of this table.
create index ai_lessons_from_label on admin.ai_lessons (from_label_id) where from_label_id is not null;

-- Threshold keys are internal: set_config refuses them (config_unknown, I7) and v_config hides
-- them. They change only through set_thresholds/reset_thresholds, both at once, one version each.
insert into admin.admin_config (key, value, kind, min_value, max_value, internal, confirm_when) values
  ('require_guardian_note', 'false', 'bool', null, null,      false, null),
  ('case_library_size',     '5',     'int',  1,    10,        false, null),
  ('threshold_warn_at',     '30',    'int',  30,   60,        true,  null),
  ('threshold_block_at',    '80',    'int',  50,   95,        true,  null),
  ('thresholds_version',    '1',     'int',  1,    999999999, true,  null),
  ('thresholds_live',       'false', 'bool', null, null,      false, 'true');

-- ---------------------------------------------------------------- published thresholds (I12)

-- What the backend serves on /config/public from phase 05 (R2 §3). While thresholds_live is off it
-- is the default the extension already has built in (30/80) with version 0, so a stored change is
-- never published by accident (A6). No grant in 04a; on_verdict (postgres) reads it.
create view admin.public_config with (security_barrier = true) as
select case when c.live then c.warn else 30 end as warn_at,
       case when c.live then c.block else 80 end as block_at,
       case when c.live then c.version else 0 end as version,
       c.updated_at
from (select (select (value)::boolean from admin.admin_config where key = 'thresholds_live') as live,
             (select (value)::int from admin.admin_config where key = 'threshold_warn_at') as warn,
             (select (value)::int from admin.admin_config where key = 'threshold_block_at') as block,
             (select (value)::int from admin.admin_config where key = 'thresholds_version') as version,
             (select max(updated_at) from admin.admin_config
               where key in ('thresholds_live', 'thresholds_version')) as updated_at) c;

-- Stored values for the Config page, published or not.
create view admin.v_thresholds as
select (w.value)::int as warn_at, (b.value)::int as block_at, (v.value)::int as version,
       (l.value)::boolean as live, v.updated_at, v.updated_by
from admin.admin_config w, admin.admin_config b, admin.admin_config v, admin.admin_config l
where w.key = 'threshold_warn_at' and b.key = 'threshold_block_at'
  and v.key = 'thresholds_version' and l.key = 'thresholds_live';

-- ---------------------------------------------------------------- internal helpers

-- K5: text the AI team or an admin writes: ≤ p_max characters, no HTML (refused on any '<').
create function admin._check_text(p_text text, p_max int, p_required boolean) returns void
language plpgsql immutable set search_path = admin, pg_temp as $$
begin
  if (p_text is null or btrim(p_text) = '') then
    if p_required then
      raise exception using errcode = 'SA009', message = 'config_invalid';
    end if;
    return;
  end if;
  if char_length(p_text) > p_max or position('<' in p_text) > 0 then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
end $$;

-- K5: a JSON object of at most 2 KB, no '<' anywhere in it.
create function admin._check_json(p_json jsonb) returns void
language plpgsql immutable set search_path = admin, pg_temp as $$
begin
  if p_json is null or jsonb_typeof(p_json) <> 'object' or octet_length(p_json::text) > 2048
     or position('<' in p_json::text) > 0 then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
end $$;

-- Case signals have the domain_intel shape: {"<signal id>": n}, at most 64 ids.
create function admin._check_signals(p_signals jsonb) returns void
language plpgsql immutable set search_path = admin, pg_temp as $$
begin
  perform admin._check_json(p_signals);
  if (select count(*) from jsonb_object_keys(p_signals)) > 64
     or exists (select 1 from jsonb_each(p_signals) e
                 where e.key !~ '^[a-z0-9_]{1,40}$' or jsonb_typeof(e.value) <> 'number'
                    or (e.value #>> '{}') !~ '^[0-9]{1,9}$') then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
end $$;

-- The actor lands in created_by, admin_audit and updated_by, which the dashboard renders: K5 rule.
create function admin._check_actor(p_actor text) returns void
language plpgsql immutable set search_path = admin, pg_temp as $$
begin
  if p_actor is null or btrim(p_actor) = '' or char_length(p_actor) > 320 or position('<' in p_actor) > 0 then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
end $$;

-- One threshold change: both values, version + 1, audit before/after. Caller holds the row locks.
create function admin._store_thresholds(p_warn int, p_block int, p_actor text, p_note text, p_action text)
returns int
language plpgsql set search_path = admin, pg_temp as $$
declare
  v_before jsonb;
  v_version int;
begin
  select jsonb_build_object('warn_at', warn_at, 'block_at', block_at, 'version', version), version + 1
    into v_before, v_version from admin.v_thresholds;
  update admin.admin_config
     set value = case key when 'threshold_warn_at' then to_jsonb(p_warn)
                          when 'threshold_block_at' then to_jsonb(p_block)
                          else to_jsonb(v_version) end,
         updated_at = now(), updated_by = p_actor
   where key in ('threshold_warn_at', 'threshold_block_at', 'thresholds_version');
  perform admin._audit(p_actor, p_action, 'thresholds', v_before,
    jsonb_build_object('warn_at', p_warn, 'block_at', p_block, 'version', v_version), p_note);
  return v_version;
end $$;

-- Final labels the family majority does not contradict (K3, R3 "tanpa konflik"): a scam label with
-- more families saying safe, or a safe label with more families reporting scam, is a conflict
-- (shown in Evaluasi AI, never a teaching example). grp = the category, or the label when none.
create view admin._case_eligible as
select l.domain, l.label, l.category, coalesce(l.category, l.label) as grp, l.label_at,
       coalesce(i.signal_counts, '{}') as signal_counts
from admin.domain_intel_label l
left join admin.domain_intel i on i.domain = l.domain
where l.label is not null
  and not (l.label in ('scam_strong', 'scam_weak') and l.families_safe > l.families_not_safe)
  and not (l.label = 'safe' and l.families_not_safe > l.families_safe);

-- R4 §3 step 6, over the whole library (each run, so a slot an admin frees is refilled):
-- 1. an analysis case whose label is no longer eligible goes (unless pinned);
-- 2. the rest follow their domain's current label and signals;
-- 3. a group over case_library_size drops its oldest unpinned analysis cases (pinned always stay);
-- 4. free slots take the newest eligible domains that never had a case (a deleted one never returns).
-- AI and admin cases count toward the limit but are never changed or dropped here.
create function admin._refresh_cases(p_size int) returns int
language plpgsql set search_path = admin, pg_temp as $$
declare
  v_added int;
begin
  delete from admin.case_library c
   where c.source = 'analysis' and c.status = 'active' and not c.pinned
     and not exists (select 1 from admin._case_eligible e where e.domain = c.domain);

  update admin.case_library c
     set label = e.label, category = e.category, signals = e.signal_counts, updated_at = now()
    from admin._case_eligible e
   where e.domain = c.domain and c.source = 'analysis' and c.status = 'active'
     and (c.label, c.category, c.signals) is distinct from (e.label, e.category, e.signal_counts);

  delete from admin.case_library where id in (
    select id from (
      select id, source, pinned,
             row_number() over (partition by coalesce(category, label) order by pinned desc, created_at desc, id desc) as rn
        from admin.case_library where status = 'active') x
     where x.rn > p_size and not x.pinned and x.source = 'analysis');

  with active as (
    select coalesce(category, label) as grp, count(*) as n
      from admin.case_library where status = 'active' group by 1
  ),
  cand as (
    select e.*, row_number() over (partition by e.grp order by e.label_at desc nulls last, e.domain) as rn
      from admin._case_eligible e
     where not exists (select 1 from admin.case_library c where c.domain = e.domain)
  ),
  ins as (
    insert into admin.case_library (domain, signals, label, category, source)
    select c.domain, c.signal_counts, c.label, c.category, 'analysis'
      from cand c left join active a on a.grp = c.grp
     where c.rn <= p_size - coalesce(a.n, 0)
    on conflict (domain) do nothing   -- case_add of the same domain committed meanwhile
    returning 1
  )
  select count(*) into v_added from ins;
  return v_added;
end $$;

-- ---------------------------------------------------------------- triggers (A8)

-- 02a on_verdict + thresholds_version from public_config (R4 §2 rule 8): the version that was
-- really published when the Guardian decided (0 before G6). Four primary-key reads, still O(1).
create or replace function admin.on_verdict() returns trigger
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
                                     thresholds_version, owner_ref, by_ref, revision_of)
    select new.domain, v_scam, 'guardian',
           new.owner_id = new.by_device_id
             or exists (select 1 from public.family_links f
                         where f.protected_id = new.owner_id and f.guardian_id = new.by_device_id),
           s.score, s.status::text, (select version from admin.public_config), v_ref, v_by, v_last.id
    from (select 1) one
    left join public.scans s on s.id = new.scan_id;
  exception when others then
    raise warning 'admin_trigger_failed on_verdict % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- ---------------------------------------------------------------- API functions (shoo_admin)

-- 02a run_analysis + require_guardian_note (R4 §3 step 2: a Guardian answer without a note is kept
-- but not counted while the setting is on) + step 6 (case library). The rest is unchanged.
create or replace function admin.run_analysis(p_trigger text, p_actor text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_run      bigint;
  v_labels   int := 0;
  v_domains  int := 0;
  v_backlog  int := 0;
  v_cases    int;
  v_now      timestamptz := clock_timestamp();
  v_min_scam int := (admin._cfg('label_min_families_scam'))::int;
  v_min_safe int := (admin._cfg('label_min_families_safe'))::int;
  v_ignore   boolean := coalesce((admin._cfg('ignore_unconnected_guardian'))::boolean, true);
  v_req_note boolean := coalesce((admin._cfg('require_guardian_note'))::boolean, false);
  v_size     int := coalesce((admin._cfg('case_library_size'))::int, 5);
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
             l.domain, l.source, l.is_scam, l.connected, l.by_ref, l.category, l.id,
             nullif(btrim(l.note), '') is not null as has_note
        from admin.domain_labels l join doms d on d.domain = l.domain
       where l.analyzed_at is not null and not admin._forgotten(l.owner_ref, l.by_ref, l.created_at)
       order by l.domain, l.source, coalesce(l.owner_ref, ''), l.id desc
    ),
    per as (
      select d.domain,
             count(distinct s.by_ref) filter (where s.source = 'guardian' and s.is_scam and (s.connected or not v_ignore)
                                                and (s.has_note or not v_req_note))::int as fam_scam,
             count(distinct s.by_ref) filter (where s.source = 'guardian' and not s.is_scam and (s.connected or not v_ignore)
                                                and (s.has_note or not v_req_note))::int as fam_safe,
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

    -- Step 6 must never cost the labels: a failure here is logged and the next run retries.
    begin
      v_cases := admin._refresh_cases(v_size);
    exception when others then
      raise warning 'admin_cases_failed % %', sqlstate, sqlerrm;
      v_cases := null;
    end;

    select count(*) into v_backlog from admin.domain_labels where analyzed_at is null;
    update admin.analysis_runs
       set finished_at = clock_timestamp(), labels_processed = v_labels, domains_updated = v_domains,
           backlog = v_backlog, ok = true
     where id = v_run;
  exception when others then
    v_err := sqlstate;
    raise warning 'admin_analysis_failed %', v_err;
    update admin.analysis_runs set finished_at = clock_timestamp(), ok = false, error_code = v_err where id = v_run;
    v_labels := 0; v_domains := 0; v_cases := null;
  end;
  if p_trigger = 'manual' then
    perform admin._audit(coalesce(p_actor, 'unknown'), 'analysis.run', null, null,
      jsonb_build_object('run', v_run, 'labels', v_labels, 'domains', v_domains), left(p_note, 1000));
  end if;
  return jsonb_build_object('run', v_run, 'ok', v_err is null, 'labels_processed', v_labels,
                            'domains_updated', v_domains, 'backlog', v_backlog, 'cases_added', v_cases,
                            'error_code', v_err);
end $$;

-- K4 / R4 §4: both thresholds in one change, one version. Guard (Q47, D-dash-05): warn 30–60 (below
-- 30 is safe: not stored, not warned), block 50–95, block − warn ≥ 15. Raising block (looser) needs
-- confirm = the new value. Values and confirm are checked before the note, so the dialog shows the
-- real problem first (W3). Unchanged values return the current version without a new one.
create function admin.set_thresholds(p_warn int, p_block int, p_actor text, p_note text, p_confirm text default null)
returns int
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  w admin.admin_config;
  b admin.admin_config;
begin
  perform admin._check_actor(p_actor);
  -- Key order, as reset_thresholds: two concurrent changes serialize and each adds one version.
  perform 1 from admin.admin_config
   where key in ('threshold_block_at', 'threshold_warn_at', 'thresholds_version') order by key for update;
  select * into w from admin.admin_config where key = 'threshold_warn_at';
  select * into b from admin.admin_config where key = 'threshold_block_at';
  if p_warn is null or p_block is null
     or p_warn < w.min_value or p_warn > w.max_value
     or p_block < b.min_value or p_block > b.max_value
     or p_block - p_warn < 15 then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  if p_block > (b.value)::int and (p_confirm is null or btrim(p_confirm) <> p_block::text) then
    raise exception using errcode = 'SA011', message = 'confirm_required';
  end if;
  perform admin._require_note(p_note);
  if p_warn = (w.value)::int and p_block = (b.value)::int then
    return (admin._cfg('thresholds_version'))::int;
  end if;
  return admin._store_thresholds(p_warn, p_block, p_actor, p_note, 'thresholds.set');
end $$;

-- "Kembalikan ke default": 30/80, version + 1, no confirm (it can only be the shipped default).
create function admin.reset_thresholds(p_actor text, p_note text)
returns int
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  perform admin._check_actor(p_actor);
  perform 1 from admin.admin_config
   where key in ('threshold_block_at', 'threshold_warn_at', 'thresholds_version') order by key for update;
  perform admin._require_note(p_note);
  if (admin._cfg('threshold_warn_at'))::int = 30 and (admin._cfg('threshold_block_at'))::int = 80 then
    return (admin._cfg('thresholds_version'))::int;
  end if;
  return admin._store_thresholds(30, 80, p_actor, p_note, 'thresholds.reset');
end $$;

-- K5 / W13: the AI team adds a case (Worker scope ai:write, 04b). One case per domain: a domain
-- that already has one, deleted or not, is refused.
create function admin.case_add(p_domain text, p_label text, p_category text, p_note text, p_signals jsonb, p_actor text)
returns bigint
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_id bigint;
begin
  perform admin._check_domain(p_domain, true);
  if p_label is null or p_label not in ('scam_strong', 'scam_weak', 'safe') then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  if p_category is not null then
    perform admin._check_category(p_category);
  end if;
  perform admin._check_text(p_note, 500, false);
  perform admin._check_signals(coalesce(p_signals, '{}'));
  perform admin._check_actor(p_actor);
  insert into admin.case_library (domain, signals, label, category, note, source, created_by)
  values (p_domain, coalesce(p_signals, '{}'), p_label, p_category, nullif(btrim(p_note), ''), 'ai', p_actor)
  on conflict (domain) do nothing
  returning id into v_id;
  if v_id is null then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  perform admin._audit(p_actor, 'case.add', p_domain, null,
    jsonb_build_object('id', v_id, 'label', p_label, 'category', p_category), null);
  return v_id;
end $$;

-- 04b K5: pin and delete need the admin's note and are audited.
create function admin.case_pin(p_id bigint, p_pinned boolean, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_domain text;
begin
  perform admin._check_actor(p_actor);
  perform admin._require_note(p_note);
  if p_pinned is null then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  update admin.case_library set pinned = p_pinned, updated_at = now()
   where id = p_id and status = 'active' returning domain into v_domain;
  if not found then
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
  perform admin._audit(p_actor, 'case.pin', v_domain, null, jsonb_build_object('id', p_id, 'pinned', p_pinned), p_note);
end $$;

create function admin.case_delete(p_id bigint, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_domain text;
begin
  perform admin._check_actor(p_actor);
  perform admin._require_note(p_note);
  update admin.case_library set status = 'deleted', pinned = false, updated_at = now()
   where id = p_id and status = 'active' returning domain into v_domain;
  if not found then
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
  perform admin._audit(p_actor, 'case.delete', v_domain, null, jsonb_build_object('id', p_id), p_note);
end $$;

-- K5 / W13: a REPEAT or AVOID lesson, optionally tied to the label it came from.
create function admin.lesson_add(p_kind text, p_text text, p_conditions jsonb, p_from_label_id bigint, p_actor text)
returns bigint
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_id bigint;
begin
  if p_kind is null or p_kind not in ('avoid', 'repeat') then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  perform admin._check_text(p_text, 500, true);
  perform admin._check_json(coalesce(p_conditions, '{}'));
  perform admin._check_actor(p_actor);
  if p_from_label_id is not null and not exists (select 1 from admin.domain_labels where id = p_from_label_id) then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  insert into admin.ai_lessons (kind, text, conditions, from_label_id, created_by)
  values (p_kind, btrim(p_text), coalesce(p_conditions, '{}'), p_from_label_id, p_actor)
  returning id into v_id;
  perform admin._audit(p_actor, 'lesson.add', v_id::text, null, jsonb_build_object('kind', p_kind), null);
  return v_id;
end $$;

create function admin.lesson_pin(p_id bigint, p_pinned boolean, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  perform admin._check_actor(p_actor);
  perform admin._require_note(p_note);
  if p_pinned is null then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  update admin.ai_lessons set pinned = p_pinned where id = p_id and status = 'active';
  if not found then
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
  perform admin._audit(p_actor, 'lesson.pin', p_id::text, null, jsonb_build_object('pinned', p_pinned), p_note);
end $$;

create function admin.lesson_delete(p_id bigint, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  perform admin._check_actor(p_actor);
  perform admin._require_note(p_note);
  update admin.ai_lessons set status = 'deleted', pinned = false where id = p_id and status = 'active';
  if not found then
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
  perform admin._audit(p_actor, 'lesson.delete', p_id::text, null, null, p_note);
end $$;

-- R3 / 05b K5: calibration-report.mjs reports, per case or lesson, how often it was used and how
-- often the result was right or wrong since its last report. Not audited (a batch per report run);
-- a deleted item still counts, the pipeline may hold an old copy.
create function admin.usage_record(p_kind text, p_id bigint, p_uses int, p_correct int, p_wrong int)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  if p_kind is null or p_kind not in ('case', 'lesson')
     or p_uses is null or p_correct is null or p_wrong is null
     or p_uses < 1 or p_uses > 1000000 or p_correct < 0 or p_wrong < 0 or p_correct + p_wrong > p_uses then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  if p_kind = 'case' then
    update admin.case_library set uses = uses + p_uses, correct = correct + p_correct, wrong = wrong + p_wrong
     where id = p_id;
  else
    update admin.ai_lessons set uses = uses + p_uses, correct = correct + p_correct, wrong = wrong + p_wrong
     where id = p_id;
  end if;
  if not found then
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
end $$;

-- ---------------------------------------------------------------- views (shoo_admin, select only)

-- K1: the labels evaluation counts. Analyzed rows only, the newest answer per family per domain
-- (admin rows: the newest per domain), forgotten labels hidden (I11). outcome among flagged pages:
-- blocked = AI positive, warning = AI negative; no AI snapshot (scan gone before the verdict) = null.
create view admin._eval_counted with (security_barrier = true) as
select distinct on (l.domain, l.source, coalesce(l.by_ref, ''))
       l.id, l.domain, l.note, l.is_scam, l.source, l.category, l.ai_score, l.ai_status,
       l.thresholds_version, l.created_at, l.analyzed_at,
       case when l.ai_status = 'blocked' then case when l.is_scam then 'tp' else 'fp' end
            when l.ai_status = 'warning' then case when l.is_scam then 'fn' else 'tn' end end as outcome
from admin.domain_labels l
where l.analyzed_at is not null
  and not exists (select 1 from admin.label_forget f
                   where l.created_at <= f.at
                     and ((f.by_ref is null and (f.owner_ref = l.owner_ref or f.owner_ref = l.by_ref))
                          or (f.owner_ref = l.owner_ref and f.by_ref = l.by_ref)))
order by l.domain, l.source, coalesce(l.by_ref, ''), l.id desc;

-- Evaluasi AI per period (decision time). Ratios are counts the UI hides while n < 30. Recall is
-- null when no label falls in the warning band: a miss cannot be seen then, and 100 % would lie.
create view admin.v_eval_summary as
select period, n, tp, fp, fn, tn, no_ai,
       case when tp + fp > 0 then round(tp::numeric / (tp + fp), 3) end as precision,
       case when fn + tn > 0 and tp + fn > 0 then round(tp::numeric / (tp + fn), 3) end as recall
from (
  select w.period,
         count(c.outcome)::int as n,
         count(*) filter (where c.outcome = 'tp')::int as tp,
         count(*) filter (where c.outcome = 'fp')::int as fp,
         count(*) filter (where c.outcome = 'fn')::int as fn,
         count(*) filter (where c.outcome = 'tn')::int as tn,
         count(*) filter (where c.id is not null and c.outcome is null)::int as no_ai
    from (values ('7d', interval '7 days'), ('30d', interval '30 days'), ('90d', interval '90 days'),
                 ('all', null::interval)) w(period, span)
    left join admin._eval_counted c on w.span is null or c.created_at >= now() - w.span
   group by w.period) x;

-- K2: precision and recall-among-flagged if the block threshold were t (30, 35, …, 95). Information
-- only: nothing changes the thresholds from here (Q25).
create view admin.v_eval_curve as
with c as materialized (   -- the counted labels once, not once per period × threshold
  select is_scam, ai_score, created_at from admin._eval_counted where ai_score is not null
)
select period, threshold, tp, fp, fn, tn,
       case when tp + fp > 0 then round(tp::numeric / (tp + fp), 3) end as precision,
       case when tp + fn > 0 then round(tp::numeric / (tp + fn), 3) end as recall
from (
  select w.period, t.threshold,
         count(*) filter (where c.is_scam and c.ai_score >= t.threshold)::int as tp,
         count(*) filter (where not c.is_scam and c.ai_score >= t.threshold)::int as fp,
         count(*) filter (where c.is_scam and c.ai_score < t.threshold)::int as fn,
         count(*) filter (where not c.is_scam and c.ai_score < t.threshold)::int as tn
    from (values ('7d', interval '7 days'), ('30d', interval '30 days'), ('90d', interval '90 days'),
                 ('all', null::interval)) w(period, span)
   cross join generate_series(30, 95, 5) t(threshold)
    left join c on w.span is null or c.created_at >= now() - w.span
   group by w.period, t.threshold) x;

-- Q30 table "domain | catatan | T/F": one row per counted label.
create view admin.v_eval_labels as
select id, domain, note, is_scam, source, category, ai_score, ai_status, thresholds_version,
       outcome, outcome in ('tp', 'tn') as ai_correct, created_at, analyzed_at
from admin._eval_counted;

-- Spektrum sinyal (C2): per signal id, labeled domains that carry it and its scan hits, by label.
create view admin.v_eval_signals as
select s.key as signal,
       count(*) filter (where l.label in ('scam_strong', 'scam_weak'))::int as domains_scam,
       count(*) filter (where l.label = 'safe')::int as domains_safe,
       coalesce(sum(s.value::bigint) filter (where l.label in ('scam_strong', 'scam_weak')), 0) as hits_scam,
       coalesce(sum(s.value::bigint) filter (where l.label = 'safe'), 0) as hits_safe
from admin.domain_intel i
join admin.domain_intel_label l on l.domain = i.domain and l.label is not null
cross join lateral jsonb_each_text(i.signal_counts) s
where s.value ~ '^[0-9]{1,18}$'
group by s.key;

-- K1b: Team AI mandate targets (docs/mandates/imelda.md) approximated on labeled domains, with
-- the newest AI score any label of the domain carries. Percent null while n < 30. The mandate's
-- own eval set (official + popular sites) is not what users label safe here; the Panduan says so.
create view admin.v_eval_targets with (security_barrier = true) as
select scam_domains, scam_ge50, scam_ge80, scam_no_ai,
       case when scam_domains >= 30 then round(scam_ge50::numeric / scam_domains, 3) end as pct_ge50,
       case when scam_domains >= 30 then round(scam_ge80::numeric / scam_domains, 3) end as pct_ge80,
       0.90 as target_ge50, 0.70 as target_ge80,
       safe_domains, safe_flagged
from (
  select count(*) filter (where d.scam and d.score is not null)::int as scam_domains,
         count(*) filter (where d.scam and d.score >= 50)::int as scam_ge50,
         count(*) filter (where d.scam and d.score >= 80)::int as scam_ge80,
         count(*) filter (where d.scam and d.score is null)::int as scam_no_ai,
         count(*) filter (where not d.scam)::int as safe_domains,
         count(*) filter (where not d.scam and d.score >= 30)::int as safe_flagged
    from (
      select l.label in ('scam_strong', 'scam_weak') as scam,
             (select x.ai_score from admin.domain_labels x
               where x.domain = l.domain and x.ai_score is not null
                 and not exists (select 1 from admin.label_forget f
                                  where x.created_at <= f.at
                                    and ((f.by_ref is null and (f.owner_ref = x.owner_ref or f.owner_ref = x.by_ref))
                                         or (f.owner_ref = x.owner_ref and f.by_ref = x.by_ref)))
               order by x.id desc limit 1) as score
        from admin.domain_intel_label l
       where l.label is not null) d) t;

-- Active cases and lessons (deleted ones stay only to block re-creation).
create view admin.v_cases as
select id, domain, signals as signal_counts, label, category, note, pinned, uses, correct, wrong,
       source, created_by, created_at, updated_at
from admin.case_library where status = 'active';

create view admin.v_lessons as
select id, kind, text, conditions, from_label_id, pinned, uses, correct, wrong, created_by, created_at
from admin.ai_lessons where status = 'active';

-- ---------------------------------------------------------------- privileges

alter table admin.case_library enable row level security;
alter table admin.ai_lessons enable row level security;

revoke all on all tables in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all sequences in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all functions in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;

-- public_config, _eval_counted and _case_eligible: no grant (05 grants public_config to shoo_api).
grant select on
  admin.v_review_queue, admin.v_blocklist, admin.v_scans, admin.v_ops_snapshot,
  admin.v_audit, admin.v_config, admin.v_categories, admin.v_feed,
  admin.v_domain_intel, admin.v_labels, admin.v_analysis_runs, admin.v_stats_daily,
  admin.v_eval_summary, admin.v_eval_curve, admin.v_eval_labels, admin.v_eval_signals,
  admin.v_eval_targets, admin.v_cases, admin.v_lessons, admin.v_thresholds
to shoo_admin;

grant execute on function
  admin.vote(text, text, text, text, text),
  admin.unreject(text, text, text),
  admin.remove_domain(text, text, text),
  admin.add_domain(text, text, text, text),
  admin.replica_for(text),
  admin.set_config(text, text, text, text, text),
  admin.log_audit(text, text, text, text),
  admin.run_analysis(text, text, text),
  admin.snapshot_daily(),
  admin.set_thresholds(int, int, text, text, text),
  admin.reset_thresholds(text, text),
  admin.case_add(text, text, text, text, jsonb, text),
  admin.case_pin(bigint, boolean, text, text),
  admin.case_delete(bigint, text, text),
  admin.lesson_add(text, text, jsonb, bigint, text),
  admin.lesson_pin(bigint, boolean, text, text),
  admin.lesson_delete(bigint, text, text),
  admin.usage_record(text, bigint, int, int, int)
to shoo_admin;
