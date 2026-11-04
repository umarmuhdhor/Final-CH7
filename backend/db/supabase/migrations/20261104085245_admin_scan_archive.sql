-- ADM-07 admin dashboard (shoo-dashboard plan fase 07a K5, K8–K12, K15; D-dash-17): every scan is
-- kept for good in admin.scan_archive, linked to its owner by owner_ref while the account exists.
-- public.scans still goes after 14 days; the archive row stays.
--   * insert of a scan: the 02a scan trigger now writes domain_intel and the archive row, each in its
--     own safety block (a failed archive write never loses the domain_intel count, and neither ever
--     fails POST /scans, A8 / I5).
--   * Guardian decision: verdict, verdict_at and by_ref on the scan's row (or the owner's latest row
--     of that domain when the verdict has no scan_id).
--   * DELETE /devices/me: the owner's rows are stripped, not deleted (owner_ref, by_ref, page_title
--     null, times rounded to the hour), and their evidence fragments are tombstoned unless the domain
--     is shown to be a scam (approved blocklist entry, label scam_strong/scam_weak, or a not_safe
--     decision). Rows the device decided as Guardian lose by_ref.
--   * disconnect: the pair's feedback (verdict, verdict_at, by_ref, note) is cleared.
--   * evidence fragments (contracts/api.md "Evidence fragments"): the API stores the object in the
--     R2 bucket shoo-replica-archive as '<scan_id>.fragments.html.gz' and sets scans.fragments_bytes;
--     a trigger copies the key to the archive row. shoo_api still executes no admin function and
--     reads nothing in admin but public_config (20261103080245).
-- A strip or clear that cannot get its rows within 200 ms goes through the 02a forget queue
-- (admin.label_forget, I11): v_scan_archive hides the fields at once, and a BEFORE DELETE trigger on
-- the queue applies the change when snapshot_daily() drains it (a row it still cannot lock stays in
-- the queue for the next day).
--
-- Paths are stored without query string or fragment and shown only through admin.tokenize_path(),
-- which replaces token-like segments with random characters of the same shape on every read
-- (D-dash-17 #6). The view has owner_ref/by_ref (pseudonyms, D-dash-17 #1; I13 as amended by 07a K15),
-- never owner_id, by_device_id or a name.
--
-- Emergency off switch for the new trigger (the archive write inside on_scan_insert has its own):
--   alter table public.scans disable trigger admin_scan_fragments;
-- Rollback (rows are lost; objects in shoo-replica-archive stay until removed by hand):
--   drop trigger admin_scan_fragments on public.scans; drop trigger admin_archive_forget on admin.label_forget;
--   drop view admin.v_scan_archive, admin.v_archive_size; drop table admin.scan_archive;
--   drop index scans_fragments; alter table public.scans drop column fragments_bytes;
--   then re-run the 02a admin.on_scan_insert(), on_device_delete(), on_family_unlink() and the
--   admin_learning admin.on_verdict() definitions.
-- The backfill of the scans and verdicts that exist now is the next migration.

-- 1 s (as 02a): add column and create trigger lock public.scans; a short wait keeps POST /scans
-- from queueing behind the deploy. On lock timeout (55P03) the whole file rolls back; re-run it.
set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- tables

-- K8. No foreign key to public.scans: the row outlives the scan. signals keep only id, layer,
-- weight and evidence of each signal (no labels). signal_ids / layers are for the GIN filters.
create table admin.scan_archive (
  scan_id         text primary key check (char_length(scan_id) between 1 and 64),
  domain          text not null check (domain = lower(domain) and domain !~ '^www\.'),
  url_path        text not null check (char_length(url_path) between 1 and 2048 and url_path !~ '[?#]'),
  page_title      text check (char_length(page_title) <= 300),
  score           int not null check (score between 0 and 100),
  status          text not null check (status in ('warning', 'blocked')),
  signals         jsonb not null default '[]' check (jsonb_typeof(signals) = 'array'),
  signal_ids      text[] not null default '{}',
  layers          smallint[] not null default '{}',
  detected_at     timestamptz not null,
  created_at      timestamptz not null,
  owner_ref       text check (owner_ref ~ '^[0-9a-f]{16}$'),
  verdict         text check (verdict in ('not_safe', 'safe')),
  verdict_at      timestamptz,
  by_ref          text check (by_ref ~ '^[0-9a-f]{16}$'),
  -- The Guardian's reason, once verdicts carry one (dashboard plan X7). Null until then.
  note            text check (char_length(note) <= 1000),
  fragments_key   text check (fragments_key = scan_id || '.fragments.html.gz'),
  fragments_bytes int check (fragments_bytes between 1 and 307200),
  stripped_at     timestamptz,
  check ((fragments_key is null) = (fragments_bytes is null)),
  check ((verdict is null) = (verdict_at is null)),
  check (stripped_at is null or owner_ref is null)
);
create index scan_archive_time on admin.scan_archive (detected_at desc, scan_id desc);
-- The verdict trigger's "latest row of owner + domain" and the strip by owner.
create index scan_archive_owner on admin.scan_archive (owner_ref, domain, detected_at desc) where owner_ref is not null;
create index scan_archive_by on admin.scan_archive (by_ref) where by_ref is not null;
create index scan_archive_domain on admin.scan_archive (domain, detected_at desc);
create index scan_archive_signals on admin.scan_archive using gin (signal_ids);
create index scan_archive_layers on admin.scan_archive using gin (layers);

-- K5: set by the API on the scan that uploaded its evidence fragments (one object per scan, no
-- reuse). Same bound as replica_bytes (gzip of 400 KB base64). The 24-hour quotas read this index.
alter table public.scans add column fragments_bytes int check (fragments_bytes between 1 and 307200);
create index scans_fragments on public.scans (created_at) include (owner_id, fragments_bytes)
  where fragments_bytes is not null;

-- ---------------------------------------------------------------- internal helpers

-- {"id", "layer", "weight", "evidence"} of each signal, nothing else (labels are text the dashboard
-- has in its own catalog). Same id rule as _signal_counts.
create function admin._archive_signals(p_signals jsonb) returns jsonb
language sql immutable set search_path = admin, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', e -> 'id', 'layer', e -> 'layer', 'weight', e -> 'weight', 'evidence', e -> 'evidence'))
           order by o), '[]')
  from jsonb_array_elements(case jsonb_typeof(p_signals) when 'array' then p_signals else '[]' end)
       with ordinality as x(e, o)
  where e ->> 'id' ~ '^[a-z0-9_]{1,40}$'
$$;

-- Path of an http(s) URL without query string and fragment ('/' for none).
create function admin._url_path(p_url text) returns text
language sql immutable set search_path = admin, pg_temp as $$
  select coalesce(nullif(substring(p_url from '^[A-Za-z]+://[^/?#]*([^?#]*)'), ''), '/')
$$;

-- D-dash-17 #6 (07a K13): a path segment that looks like a token (≥ 16 hex digits, or ≥ 16
-- characters of [A-Za-z0-9_.-] with a digit, a lower- and an upper-case letter) becomes random
-- characters of the same class at each position, new on every call; the real value is never kept
-- next to it. Words like /verify-account-now stay readable.
create function admin.tokenize_path(p_path text) returns text
language plpgsql volatile set search_path = admin, pg_temp as $$
declare
  v_seg  text;
  v_out  text[] := '{}';
  v_tok  text;
  v_ch   text;
begin
  if p_path is null then
    return null;
  end if;
  foreach v_seg in array string_to_array(p_path, '/') loop
    if (v_seg ~ '^[0-9A-Fa-f-]{16,}$' and length(regexp_replace(v_seg, '[^0-9A-Fa-f]', '', 'g')) >= 16)
       or (v_seg ~ '^[A-Za-z0-9_.-]{16,}$' and v_seg ~ '[0-9]' and v_seg ~ '[a-z]' and v_seg ~ '[A-Z]') then
      v_tok := '';
      foreach v_ch in array regexp_split_to_array(v_seg, '') loop
        v_tok := v_tok || case
          when v_ch ~ '[0-9]' then chr(48 + floor(random() * 10)::int)
          when v_ch ~ '[a-z]' then chr(97 + floor(random() * 26)::int)
          when v_ch ~ '[A-Z]' then chr(65 + floor(random() * 26)::int)
          else v_ch end;
      end loop;
      v_out := v_out || v_tok;
    else
      v_out := v_out || v_seg;
    end if;
  end loop;
  return array_to_string(v_out, '/');
end $$;

-- K12: a domain whose evidence stays after the account is deleted.
create function admin._scam_evidence(p_domain text) returns boolean
language sql stable set search_path = admin, pg_temp as $$
  select exists (select 1 from public.blocklist_entries b
                  where b.domain = p_domain and b.approved_at is not null and b.removed_at is null)
      or exists (select 1 from admin.domain_intel_label l
                  where l.domain = p_domain and l.label in ('scam_strong', 'scam_weak'))
      or exists (select 1 from admin.scan_archive a where a.domain = p_domain and a.verdict = 'not_safe')
$$;

-- K11 + K12 for one forget entry (the shape of admin.label_forget): by_ref null = device p_owner
-- was deleted; else the pair p_owner (protected) / p_by (Guardian) disconnected at p_at (a pair that
-- linked again later keeps its newer feedback). Raises
-- lock_not_available when a row is held longer than the caller's lock_timeout; callers queue or retry.
create function admin._archive_forget(p_owner text, p_by text, p_at timestamptz) returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  if p_by is null then
    -- Fragments of domains without scam evidence go; the API cron removes the objects (tombstones,
    -- D-alief-B12, store "archive" in services/screenshots.ts).
    with gone as (
      update admin.scan_archive a set fragments_key = null, fragments_bytes = null
       where a.owner_ref = p_owner and a.fragments_key is not null and not admin._scam_evidence(a.domain)
      returning a.scan_id || '.fragments.html.gz' as path)
    insert into public.storage_tombstones (path) select path from gone
    on conflict (path) do nothing;
    update admin.scan_archive set
        owner_ref   = null,
        by_ref      = null,
        page_title  = null,
        detected_at = date_trunc('hour', detected_at),
        created_at  = date_trunc('hour', created_at),
        verdict_at  = date_trunc('hour', verdict_at),
        stripped_at = now()
     where owner_ref = p_owner;
    update admin.scan_archive set by_ref = null where by_ref = p_owner;
  else
    update admin.scan_archive set verdict = null, verdict_at = null, by_ref = null, note = null
     where owner_ref = p_owner and by_ref = p_by and verdict_at <= p_at;
  end if;
end $$;

-- ---------------------------------------------------------------- triggers (A8)

-- 02a on_scan_insert + the archive row (K9, D-dash-17 #12e). One trigger, two safety blocks.
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
       detected_at, created_at, owner_ref)
    select new.id, new.domain, admin._url_path(new.url), new.page_title, new.score, new.status::text,
           s.signals,
           coalesce((select array_agg(distinct e ->> 'id') from jsonb_array_elements(s.signals) e), '{}'),
           coalesce((select array_agg(distinct (e ->> 'layer')::smallint) from jsonb_array_elements(s.signals) e
                      where e ->> 'layer' ~ '^[1-5]$'), '{}'),
           new.detected_at, new.created_at, admin.owner_ref(new.owner_id)
    from (select admin._archive_signals(new.signals) as signals) s
    on conflict (scan_id) do nothing;
  exception when others then
    raise warning 'admin_trigger_failed on_scan_archive % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- K5: the key of the evidence fragments the API stored (or cleared after a failed upload).
create function admin.on_scan_fragments() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
begin
  begin
    update admin.scan_archive set
        fragments_key   = case when new.fragments_bytes is null then null else scan_id || '.fragments.html.gz' end,
        fragments_bytes = new.fragments_bytes
     where scan_id = new.id;
  exception when others then
    raise warning 'admin_trigger_failed on_scan_fragments % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- admin_learning on_verdict + the archive feedback (K10), in its own safety block after the label
-- part. Its early returns (locked label, same decision) now skip only the label, never the archive.
create or replace function admin.on_verdict() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_ref  text;
  v_by   text;
  v_scam boolean;
  v_last admin.domain_labels;
begin
  begin
    v_ref := admin.owner_ref(new.owner_id);
    v_by  := admin.owner_ref(new.by_device_id);
  exception when others then
    raise warning 'admin_trigger_failed on_verdict % %', sqlstate, sqlerrm;
    return null;
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
  begin
    update admin.scan_archive a set verdict = new.value::text, verdict_at = new.decided_at, by_ref = v_by
     where a.scan_id = coalesce(new.scan_id,
             (select l.scan_id from admin.scan_archive l
               where l.owner_ref = v_ref and l.domain = new.domain and l.detected_at <= new.decided_at
               order by l.detected_at desc limit 1));
  exception when others then
    raise warning 'admin_trigger_failed on_verdict_archive % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- 02a on_device_delete + the archive strip (K11, K12). A held row queues the device (I11).
create or replace function admin.on_device_delete() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_ref    text;
  v_queued boolean := false;
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
        v_queued := true;
      end if;
    exception when lock_not_available then
      insert into admin.label_forget (owner_ref, by_ref) values (v_ref, null);
      v_queued := true;
    end;
    begin
      perform admin._archive_forget(v_ref, null, clock_timestamp());
    exception when lock_not_available then
      if not v_queued then
        insert into admin.label_forget (owner_ref, by_ref) values (v_ref, null);
      end if;
    end;
  exception when others then
    raise warning 'admin_trigger_failed on_device_delete % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- 02a on_family_unlink + the pair's archive feedback (K11).
create or replace function admin.on_family_unlink() returns trigger
language plpgsql security definer set search_path = admin, pg_temp set lock_timeout = '200ms' as $$
declare
  v_owner  text;
  v_by     text;
  v_queued boolean := false;
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
        v_queued := true;
      end if;
    exception when lock_not_available then
      insert into admin.label_forget (owner_ref, by_ref) values (v_owner, v_by);
      v_queued := true;
    end;
    begin
      perform admin._archive_forget(v_owner, v_by, clock_timestamp());
    exception when lock_not_available then
      if not v_queued then
        insert into admin.label_forget (owner_ref, by_ref) values (v_owner, v_by);
      end if;
    end;
  exception when others then
    raise warning 'admin_trigger_failed on_family_unlink % %', sqlstate, sqlerrm;
  end;
  return null;
end $$;

-- I11 for the archive: snapshot_daily() deletes drained queue rows; each one first applies its
-- archive change. A row that still cannot be locked keeps its queue entry (return null skips the
-- delete of that entry only), so the view keeps hiding it and the next day retries.
create function admin.on_forget_drain() returns trigger
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  perform admin._archive_forget(old.owner_ref, old.by_ref, old.at);
  return old;
exception when lock_not_available then
  return null;
end $$;

create trigger admin_scan_fragments after update of fragments_bytes on public.scans
  for each row when (old.fragments_bytes is distinct from new.fragments_bytes)
  execute function admin.on_scan_fragments();
create trigger admin_archive_forget before delete on admin.label_forget
  for each row execute function admin.on_forget_drain();

-- ---------------------------------------------------------------- views (shoo_admin, select only)

-- K15. Raw url_path never leaves: only tokenize_path() of it. Entries of the forget queue hide what
-- they will remove (inline, as v_labels: functions in a view run with the caller's privileges).
create view admin.v_scan_archive with (security_barrier = true) as
select a.scan_id, a.domain, admin.tokenize_path(a.url_path) as path,
       case when f.owner_gone then null else a.page_title end as page_title,
       a.score, a.status, a.signals, a.signal_ids, a.layers, a.detected_at, a.created_at,
       case when f.owner_gone then null else a.owner_ref end as owner_ref,
       case when f.pair_gone then null else a.verdict end as verdict,
       case when f.pair_gone then null else a.verdict_at end as verdict_at,
       case when f.owner_gone or f.pair_gone or f.by_gone then null else a.by_ref end as by_ref,
       case when f.pair_gone then null else a.note end as note,
       a.fragments_key, a.fragments_bytes,
       coalesce(a.stripped_at, case when f.owner_gone then now() end) as stripped_at
from admin.scan_archive a
cross join lateral (
  select
    a.owner_ref is not null and exists (select 1 from admin.label_forget q
      where q.by_ref is null and q.owner_ref = a.owner_ref) as owner_gone,
    a.by_ref is not null and exists (select 1 from admin.label_forget q
      where q.by_ref is null and q.owner_ref = a.by_ref) as by_gone,
    a.owner_ref is not null and a.by_ref is not null and exists (select 1 from admin.label_forget q
      where q.owner_ref = a.owner_ref and q.by_ref = a.by_ref and a.verdict_at <= q.at) as pair_gone
) f;

-- 07b K9: archive size for the Sistem page (aggregates only).
create view admin.v_archive_size as
select (select count(*) from admin.scan_archive) as rows,
       pg_total_relation_size('admin.scan_archive') as table_bytes,
       (select coalesce(sum(fragments_bytes), 0) from admin.scan_archive)::bigint as fragment_bytes;

-- ---------------------------------------------------------------- privileges

alter table admin.scan_archive enable row level security;

revoke all on all tables in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all sequences in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all functions in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;

-- The admin_learning and 05 grants again (the revokes above take every grant in admin), plus 07a's.
grant select on
  admin.v_review_queue, admin.v_blocklist, admin.v_scans, admin.v_ops_snapshot,
  admin.v_audit, admin.v_config, admin.v_categories, admin.v_feed,
  admin.v_domain_intel, admin.v_labels, admin.v_analysis_runs, admin.v_stats_daily,
  admin.v_eval_summary, admin.v_eval_curve, admin.v_eval_labels, admin.v_eval_signals,
  admin.v_eval_targets, admin.v_cases, admin.v_lessons, admin.v_thresholds,
  admin.v_scan_archive, admin.v_archive_size
to shoo_admin;
grant select on admin.public_config to shoo_api;

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
  admin.usage_record(text, bigint, int, int, int),
  -- Called by v_scan_archive with the caller's privileges; a pure function of its argument.
  admin.tokenize_path(text)
to shoo_admin;
