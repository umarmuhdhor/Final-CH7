-- Layer 5 data (#241, spec plan/imelda/layer-5-feedback.md v2 on #245, D-imelda-52/53), the parts
-- that need no contract change. Nothing here changes what the backend, the extension or the app do.
--   * admin.domain_review: one row per LLM review of a queued domain (POST /review in ai/, Imelda).
--     The dashboard cron asks admin.review_due() which domains are due and stores the answers with
--     admin.review_record(). It stays off until review_enabled is switched on. The LLM only
--     suggests: nothing here writes public.blocklist_entries. admin.vote's decision is copied to
--     the domain's latest review (trigger on admin.review_decisions), so suggestion vs decision
--     gives the LLM's precision.
--   * admin.v_review_queue: the latest review of each queued domain (columns appended).
--   * admin.shared_hosts: hosts where anyone can publish a page. Never reviewed by the LLM. Filled
--     from ai/data/shared-hosts.json by admin.shared_hosts_set() (the backend keeps no list of its own).
--   * admin.domain_labels.scan_id: the scan each Guardian decision was about, so a decision row can
--     be joined to its archive row. admin.scan_archive.host: the page's host (subdomains matter
--     for layers 1–2); a URL is rebuilt as https:// + host + tokenised path.
--   * admin.mask_note(): masks e-mail addresses and digit runs of 8 or more (phone, account, NIK,
--     card) in a Guardian note. Used by admin.ai_dataset now, and by on_verdict once verdicts carry
--     notes (contract change, Umar, #241 Q11).
--   * admin.ai_dataset: a view for Team AI, one row per Guardian decision with the detector result
--     per layer at scan time, the RDAP age, the domain summary and the latest LLM review. Paths are
--     tokenised (admin.tokenize_path), notes masked, no owner_id/by_device_id/name/owner_ref/by_ref.
--     Read by the new login role shoo_ai (select on this view only) and by shoo_admin.
-- Not here (they wait for answers in #241): verdicts per link + notes, and anonymising instead of
-- deleting labels on device delete / disconnect (SECURITY D4/P13, Umar Q12).
--
-- Rollback (reviews are lost):
--   drop trigger admin_review_decided on admin.review_decisions;
--   drop view admin.ai_dataset; drop function admin.review_due, admin.review_record,
--     admin.shared_hosts_set, admin.mask_note, admin.on_review_decided;
--   drop table admin.domain_review, admin.shared_hosts;
--   alter table admin.domain_labels drop column scan_id; alter table admin.scan_archive drop column host;
--   delete from admin.admin_config where key in ('review_enabled', 'review_batch_size', 'review_max_batches');
--   drop owned by shoo_ai; drop role shoo_ai;
--   then re-run the L3 admin.on_scan_insert(), the 07a admin.on_verdict() and the 01a
--   admin.v_review_queue definitions.

-- 1 s (as 07a): create or replace of the scan trigger function locks nothing on public.scans,
-- but altering admin tables the triggers write does; a short wait keeps POST /scans moving.
set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- role

-- Team AI's read-only login (D-imelda-53). Same shape as shoo_admin (01a H2). No password here:
-- the cloud one is set in the SQL editor and kept in the password manager (manual step).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'shoo_ai') then
    create role shoo_ai login;
  end if;
  if not pg_has_role('postgres', 'shoo_ai', 'SET') then
    grant shoo_ai to postgres with inherit false, set true;
  end if;
end $$;
alter role shoo_ai login noinherit nobypassrls nocreatedb nocreaterole noreplication connection limit 3;
do $$
begin
  if (select rolsuper from pg_roles where rolname = 'shoo_ai') then
    raise exception 'shoo_ai must not be a superuser';
  end if;
  if exists (select 1 from pg_auth_members where member = 'shoo_ai'::regrole) then
    raise exception 'shoo_ai must not be a member of any role';
  end if;
end $$;
revoke all on all tables in schema public from shoo_ai;
revoke all on all sequences in schema public from shoo_ai;
revoke all on all functions in schema public from shoo_ai;
alter role shoo_ai set statement_timeout = '15s';
alter role shoo_ai set lock_timeout = '1s';
alter role shoo_ai set idle_in_transaction_session_timeout = '15s';
alter role shoo_ai set default_transaction_read_only = on;
alter role shoo_ai set search_path = admin;
grant usage on schema admin to shoo_ai;

-- ---------------------------------------------------------------- config

-- Off until the PM agrees and POST /review exists. Batch limits keep one cron run far under the
-- 50 subrequests of Workers Free (one request per batch).
insert into admin.admin_config (key, value, kind, min_value, max_value, internal, confirm_when) values
  ('review_enabled',     'false', 'bool', null, null, false, 'true'),
  ('review_batch_size',  '25',    'int',  1,    50,   false, null),
  ('review_max_batches', '2',     'int',  1,    10,   false, null);

-- ---------------------------------------------------------------- tables

create table admin.shared_hosts (
  host     text primary key check (host = lower(host) and host ~ '^[a-z0-9.-]{1,253}$' and host !~ '^www\.'),
  added_at timestamptz not null default now()
);

create table admin.domain_review (
  id          bigint generated always as identity primary key,
  domain      text not null check (domain = lower(domain) and domain !~ '^www\.'),
  result      text check (result in ('scam', 'legit', 'unsure')),   -- null = failed after retries
  confidence  numeric(3,2) check (confidence between 0 and 1),
  reason      text check (char_length(reason) <= 500 and position('<' in reason) = 0),
  suggestion  text not null check (suggestion in ('approve', 'reject', 'none')),
  input       jsonb not null check (jsonb_typeof(input) = 'object'),  -- what the LLM saw
  model       text not null check (char_length(model) between 1 and 100),
  prompt      text not null check (prompt ~ '^[a-z0-9_.-]{1,40}$'),   -- prompt version, e.g. review.v1
  reviewed_at timestamptz not null default clock_timestamp(),
  decision    text check (decision in ('approve', 'reject')),          -- admin.vote, via trigger
  decided_at  timestamptz,
  check ((decision is null) = (decided_at is null))
);
create index domain_review_domain on admin.domain_review (domain, reviewed_at desc, id desc);

alter table admin.domain_labels add column scan_id text check (char_length(scan_id) between 1 and 64);
alter table admin.scan_archive add column host text check (char_length(host) between 1 and 253);

-- ---------------------------------------------------------------- functions

-- E-mail first (its digits are then gone), then digit runs of 8+ with optional space, dot or dash
-- between digits and an optional leading +. "Rp 500.000" (6 digits) stays readable.
create function admin.mask_note(p_note text) returns text
language sql immutable set search_path = admin, pg_temp as $$
  select regexp_replace(
           regexp_replace(p_note, '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}', '[email]', 'g'),
           '\+?[0-9]([ .-]?[0-9]){7,}', '[nomor]', 'g')
$$;

-- Queued domains the LLM should look at: pending blocklist entry, not a shared host (or a page on
-- one), and no review since the domain's last label change. Most-reported first, then oldest.
-- input = exactly what POST /review gets: counts only, no notes, no page text (D-imelda-27/36).
create function admin.review_due(p_limit int)
returns table (domain text, input jsonb)
language sql stable security definer set search_path = admin, pg_temp as $$
  select b.domain,
         jsonb_build_object(
           'domain', b.domain,
           'signal_counts', coalesce(d.signal_counts, '{}'),
           'avg_score', case when d.scans > 0 then round(d.sum_score::numeric / d.scans)::int end,
           'max_score', d.max_score,
           'families_safe', coalesce(l.families_safe, 0),
           'families_not_safe', coalesce(l.families_not_safe, 0))
  from public.blocklist_entries b
  left join admin.domain_intel d on d.domain = b.domain
  left join admin.domain_intel_label l on l.domain = b.domain
  where b.approved_at is null and b.rejected_at is null and b.removed_at is null and b.families > 0
    and not exists (select 1 from admin.shared_hosts h
                     where b.domain = h.host or b.domain like '%.' || h.host)
    and not exists (select 1 from admin.domain_review r
                     where r.domain = b.domain
                       and r.reviewed_at >= coalesce((select max(x.created_at) from admin.domain_labels x
                                                       where x.domain = b.domain), '-infinity'))
  order by b.families desc, b.first_seen_at, b.domain
  limit least(greatest(coalesce(p_limit, 0), 0), 100)
$$;

-- Stores one batch of POST /review answers. p_results = [{domain, input, result, confidence,
-- reason, suggestion}]. Answers are model output, so they are cleaned, not trusted: an unknown
-- result becomes null, an unknown suggestion 'none', '<' never reaches reason (prompt injection
-- shown in the dashboard). An element without a valid domain or input is skipped. Returns the
-- number of rows stored.
create function admin.review_record(p_results jsonb, p_model text, p_prompt text, p_actor text)
returns int
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_n int;
begin
  perform admin._check_actor(p_actor);
  if jsonb_typeof(p_results) is distinct from 'array' or jsonb_array_length(p_results) > 100 then
    raise exception using errcode = '22023', message = 'invalid_results';
  end if;
  with rows as (
    select lower(e ->> 'domain') as domain, e -> 'input' as input,
           case when e ->> 'result' in ('scam', 'legit', 'unsure') then e ->> 'result' end as result,
           case when jsonb_typeof(e -> 'confidence') = 'number' and (e ->> 'confidence')::numeric between 0 and 1
                then round((e ->> 'confidence')::numeric, 2) end as confidence,
           nullif(left(btrim(replace(replace(e ->> 'reason', '<', ''), '>', '')), 500), '') as reason,
           case when e ->> 'suggestion' in ('approve', 'reject') then e ->> 'suggestion' else 'none' end as suggestion
    from jsonb_array_elements(p_results) e
    where jsonb_typeof(e) = 'object'
  ), ins as (
    insert into admin.domain_review (domain, result, confidence, reason, suggestion, input, model, prompt)
    select r.domain, r.result, r.confidence, r.reason, r.suggestion, r.input, left(p_model, 100), p_prompt
    from rows r
    where r.domain ~ '^[a-z0-9.-]{1,253}$' and r.domain !~ '^www\.' and jsonb_typeof(r.input) = 'object'
    returning 1
  )
  select count(*)::int into v_n from ins;
  return v_n;
end $$;

-- Replaces the shared host list (from ai/data/shared-hosts.json). Audited with before/after counts.
create function admin.shared_hosts_set(p_hosts text[], p_actor text, p_note text)
returns int
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_before int;
  v_after  int;
begin
  perform admin._check_actor(p_actor);
  if p_hosts is null or cardinality(p_hosts) > 5000 then
    raise exception using errcode = '22023', message = 'invalid_hosts';
  end if;
  select count(*)::int into v_before from admin.shared_hosts;
  delete from admin.shared_hosts;
  insert into admin.shared_hosts (host)
  select distinct lower(btrim(h)) from unnest(p_hosts) h
  where lower(btrim(h)) ~ '^[a-z0-9.-]{1,253}$' and lower(btrim(h)) !~ '^www\.';
  select count(*)::int into v_after from admin.shared_hosts;
  perform admin._audit(p_actor, 'shared_hosts.set', null, jsonb_build_object('hosts', v_before),
                       jsonb_build_object('hosts', v_after), left(p_note, 1000));
  return v_after;
end $$;

-- admin.vote's decision on the domain's latest undecided review. Runs inside vote's transaction:
-- a vote that rolls back (already_decided) takes this update with it.
create function admin.on_review_decided() returns trigger
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  if new.action in ('approve', 'reject') then
    update admin.domain_review set decision = new.action, decided_at = new.at
     where id = (select id from admin.domain_review
                  where domain = new.domain and decision is null
                  order by reviewed_at desc, id desc limit 1);
  end if;
  return null;
end $$;

create trigger admin_review_decided after insert on admin.review_decisions
  for each row execute function admin.on_review_decided();

-- L3 on_scan_insert + the page's host in the archive row. Nothing else changed.
create or replace function admin.on_scan_insert() returns trigger
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
  begin
    insert into admin.scan_archive
      (scan_id, domain, url_path, page_title, score, status, signals, signal_ids, layers,
       detected_at, created_at, owner_ref, rdap_registered_at, host)
    select new.id, new.domain, admin._url_path(new.url), new.page_title, new.score, new.status::text,
           s.signals,
           coalesce((select array_agg(distinct e ->> 'id') from jsonb_array_elements(s.signals) e), '{}'),
           coalesce((select array_agg(distinct (e ->> 'layer')::smallint) from jsonb_array_elements(s.signals) e
                      where e ->> 'layer' ~ '^[1-5]$'), '{}'),
           new.detected_at, new.created_at, admin.owner_ref(new.owner_id), new.rdap_registered_at,
           nullif(lower(substring(new.url from '^[A-Za-z]+://(?:[^/?#@]*@)?([^/?#:]+)')), '')
    from (select admin._archive_signals(new.signals) as signals) s
    on conflict (scan_id) do nothing;
  exception when others then
    raise warning 'admin_trigger_failed on_scan_archive % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- 07a on_verdict + scan_id on the label row: the verdict's scan, or the owner's latest archived
-- scan of that domain (the same row the archive feedback goes to).
create or replace function admin.on_verdict() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_ref  text;
  v_by   text;
  v_scam boolean;
  v_last admin.domain_labels;
  v_scan text;
begin
  begin
    v_ref := admin.owner_ref(new.owner_id);
    v_by  := admin.owner_ref(new.by_device_id);
  exception when others then
    raise warning 'admin_trigger_failed on_verdict % %', sqlstate, sqlerrm;
    return null;
  end;
  -- Its own block: a failed archive lookup leaves scan_id null, never loses the label.
  begin
    v_scan := coalesce(new.scan_id,
                (select l.scan_id from admin.scan_archive l
                  where l.owner_ref = v_ref and l.domain = new.domain and l.detected_at <= new.decided_at
                  order by l.detected_at desc limit 1));
  exception when others then
    raise warning 'admin_trigger_failed on_verdict_scan % %', sqlstate, sqlerrm;
    v_scan := new.scan_id;
  end;
  <<label>>
  begin
    v_scam := new.value = 'not_safe';
    select * into v_last from admin.domain_labels l
     where l.owner_ref = v_ref and l.domain = new.domain and l.source = 'guardian'
       and not admin._forgotten(l.owner_ref, l.by_ref, l.created_at)
     order by l.id desc limit 1;
    if found and (v_last.analyzed_at is null or v_last.is_scam = v_scam) then
      exit label;   -- locked (Q33), or the same decision again (upsert with the same value)
    end if;
    insert into admin.domain_labels (domain, is_scam, source, connected, ai_score, ai_status,
                                     thresholds_version, owner_ref, by_ref, revision_of, scan_id)
    select new.domain, v_scam, 'guardian',
           new.owner_id = new.by_device_id
             or exists (select 1 from public.family_links f
                         where f.protected_id = new.owner_id and f.guardian_id = new.by_device_id),
           s.score, s.status::text, (select version from admin.public_config), v_ref, v_by, v_last.id, v_scan
    from (select 1) one
    left join public.scans s on s.id = new.scan_id;
  exception when others then
    raise warning 'admin_trigger_failed on_verdict % %', sqlstate, sqlerrm;
  end;
  begin
    update admin.scan_archive a set verdict = new.value::text, verdict_at = new.decided_at, by_ref = v_by
     where a.scan_id = v_scan;
  exception when others then
    raise warning 'admin_trigger_failed on_verdict_archive % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- Host of the archive rows whose scan still exists (older rows keep host null; url falls back to
-- the registrable domain).
update admin.scan_archive a
   set host = nullif(lower(substring(s.url from '^[A-Za-z]+://(?:[^/?#@]*@)?([^/?#:]+)')), '')
  from public.scans s
 where s.id = a.scan_id and a.host is null;

-- ---------------------------------------------------------------- views

-- 01a v_review_queue + the latest LLM review (columns appended; create or replace keeps grants).
-- review_stale = a label changed after that review, so its input is out of date.
create or replace view admin.v_review_queue as
select
  b.domain,
  v.families_not_safe,
  v.families_safe,
  s.scans_14d,
  s.max_score,
  s.avg_score,
  b.first_seen_at,
  t.top_signals,
  (cfg.replica_enabled
   and v.families_not_safe >= cfg.replica_min_families
   and exists (select 1 from public.scans r
                where r.domain = b.domain and r.replica_path is not null
                  and exists (select 1 from public.family_links f
                               where f.protected_id = r.owner_id or f.guardian_id = r.owner_id))) as has_replica,
  rv.result as review_result,
  rv.confidence as review_confidence,
  rv.reason as review_reason,
  rv.suggestion as review_suggestion,
  rv.reviewed_at,
  (rv.reviewed_at is not null
   and exists (select 1 from admin.domain_labels x where x.domain = b.domain and x.created_at > rv.reviewed_at)) as review_stale
from public.blocklist_entries b
cross join (
  select (select value from admin.admin_config where key = 'replica_enabled')::boolean as replica_enabled,
         (select value from admin.admin_config where key = 'replica_min_families')::int as replica_min_families
) cfg
cross join lateral (
  select count(distinct by_device_id) filter (where value = 'not_safe' and global_eligible)::int as families_not_safe,
         count(distinct by_device_id) filter (where value = 'safe')::int as families_safe
  from public.verdicts where domain = b.domain
) v
cross join lateral (
  select count(*)::int as scans_14d, max(score) as max_score, round(avg(score))::int as avg_score
  from public.scans where domain = b.domain and created_at > now() - interval '14 days'
) s
cross join lateral (
  select coalesce(array_agg(id order by n desc, id), '{}') as top_signals
  from (select e ->> 'id' as id, count(*) as n
          from public.scans sc cross join lateral jsonb_array_elements(sc.signals) e
         where sc.domain = b.domain and sc.created_at > now() - interval '14 days' and e ->> 'id' is not null
         group by 1 order by 2 desc, 1 limit 3) x
) t
left join lateral (
  select r.result, r.confidence, r.reason, r.suggestion, r.reviewed_at
  from admin.domain_review r where r.domain = b.domain
  order by r.reviewed_at desc, r.id desc limit 1
) rv on true
where b.approved_at is null and b.rejected_at is null and b.removed_at is null and b.families > 0;

-- D-imelda-53: one row per Guardian decision, ready for Team AI (no join needed). The forget queue
-- hides a decision at once (inline, as v_scan_archive: functions in a view run with the caller's
-- privileges, and shoo_ai executes only tokenize_path and mask_note). Layers 1–2 can be re-run
-- from url + rdap_*; layers 3–4 only from their stored result (no page text is kept).
create view admin.ai_dataset with (security_barrier = true) as
select
  l.id,
  l.id as label_id,
  case when a.scan_id is not null
       then 'https://' || coalesce(a.host, a.domain) || admin.tokenize_path(a.url_path) end as url,
  l.domain,
  a.rdap_registered_at,
  (a.detected_at at time zone 'UTC')::date - a.rdap_registered_at as rdap_age_days,
  coalesce(p.layer1, '[]') as layer1,
  coalesce(p.layer2, '[]') as layer2,
  coalesce(p.layer3, '[]') as layer3,
  coalesce(p.layer4, '[]') as layer4,
  coalesce(p.layer1_score, 0) as layer1_score,
  coalesce(p.layer2_score, 0) as layer2_score,
  coalesce(p.layer3_score, 0) as layer3_score,
  coalesce(p.layer4_score, 0) as layer4_score,
  coalesce(a.score, l.ai_score) as score,
  coalesce(a.status, l.ai_status) as status,
  l.thresholds_version,
  a.detected_at as scanned_at,
  l.is_scam,
  admin.mask_note(l.note) as note,
  l.created_at as decided_at,
  l.owner_ref is null as anonymous,
  d.scans as domain_scans,
  case when d.scans > 0 then round(d.sum_score::numeric / d.scans)::int end as domain_avg_score,
  d.max_score as domain_max_score,
  dl.families_safe,
  dl.families_not_safe,
  dl.label as final_label,
  exists (select 1 from admin.shared_hosts h where l.domain = h.host or l.domain like '%.' || h.host) as shared_host,
  rv.result as review_result,
  rv.suggestion as review_suggestion,
  rv.decision as review_decision
from admin.domain_labels l
left join admin.scan_archive a on a.scan_id = l.scan_id
left join lateral (
  select
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '1') as layer1,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '2') as layer2,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '3') as layer3,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '4') as layer4,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '1')::int as layer1_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '2')::int as layer2_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '3')::int as layer3_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '4')::int as layer4_score
  from jsonb_array_elements(coalesce(a.signals, '[]')) e
  where (e ->> 'weight') ~ '^[0-9]{1,3}$'
) p on true
left join admin.domain_intel d on d.domain = l.domain
left join admin.domain_intel_label dl on dl.domain = l.domain
left join lateral (
  select r.result, r.suggestion, r.decision
  from admin.domain_review r where r.domain = l.domain
  order by r.reviewed_at desc, r.id desc limit 1
) rv on true
where l.source = 'guardian'
  and not (l.owner_ref is not null and exists (
    select 1 from admin.label_forget f
     where l.created_at <= f.at
       and ((f.by_ref is null and (f.owner_ref = l.owner_ref or f.owner_ref = l.by_ref))
            or (f.owner_ref = l.owner_ref and f.by_ref = l.by_ref))));

-- ---------------------------------------------------------------- privileges

alter table admin.domain_review enable row level security;
alter table admin.shared_hosts enable row level security;

revoke all on admin.domain_review, admin.shared_hosts, admin.ai_dataset
  from public, anon, authenticated, service_role, shoo_api, shoo_admin, shoo_ai;
revoke all on sequence admin.domain_review_id_seq
  from public, anon, authenticated, service_role, shoo_api, shoo_admin, shoo_ai;
revoke all on function admin.mask_note(text), admin.review_due(int),
  admin.review_record(jsonb, text, text, text), admin.shared_hosts_set(text[], text, text),
  admin.on_review_decided()
  from public, anon, authenticated, service_role, shoo_api, shoo_admin, shoo_ai;

grant select on admin.ai_dataset to shoo_admin, shoo_ai;
grant execute on function admin.review_due(int), admin.review_record(jsonb, text, text, text),
  admin.shared_hosts_set(text[], text, text), admin.mask_note(text)
  to shoo_admin;
-- Called by ai_dataset with the caller's privileges; pure functions of their argument.
grant execute on function admin.tokenize_path(text), admin.mask_note(text) to shoo_ai;
