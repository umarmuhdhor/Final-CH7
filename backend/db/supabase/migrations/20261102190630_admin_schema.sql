-- ADM-01 admin dashboard (shoo-dashboard plan, ref/R2 §1–§5, objects labelled 01a): schema `admin`
-- for reviewing the global blocklist. The dashboard Worker logs in as `shoo_admin` through its own
-- Hyperdrive and sees only masked views and validating functions; it has no privilege on any object
-- in `public`. shoo-api behaviour does not change: no backend table, grant, policy or trigger is
-- altered. The one backend-side addition is an index on scans(domain, created_at) for the queue view.
--
-- Publishing: the dashboard re-opens the path that hardening (T5) closed for the Worker, but only
-- through admin.vote/admin.add_domain, as a named admin with a note, at most `max_publish_per_day`
-- (default 50) approvals + manual adds per 24 h across all admins (K7).
--
-- Rollback (before dashboard phase 02a): `drop schema admin cascade; drop index scans_domain_created;`
-- The role stays; the dashboard then fails closed because its views are gone.

-- `set local`: only this migration's transaction (see 20261029100000_page_replicas.sql).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- role

-- The role may already exist (created by hand in the cloud before this migration). Attributes are
-- forced either way so local, CI and cloud match. No password here: seed.sql sets the local one; the
-- cloud one is set in the SQL editor and kept in the password manager (manual step).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'shoo_admin') then
    create role shoo_admin login;
  end if;
  -- PG 16+: the creating role gets ADMIN but not SET (createrole_self_grant is empty on Supabase).
  -- SET lets postgres `set role shoo_admin` in the SQL editor and in pgTAP. INHERIT stays off, so
  -- postgres never picks up shoo_admin's privileges implicitly.
  if not pg_has_role('postgres', 'shoo_admin', 'SET') then
    grant shoo_admin to postgres with inherit false, set true;
  end if;
end $$;

alter role shoo_admin login noinherit nobypassrls connection limit 5;
-- Same idea as shoo_api (hardening): a stuck dashboard query never holds a backend lock or a
-- pooled connection for long. 5 s keeps admin reads away from POST /scans latency (A9).
alter role shoo_admin set statement_timeout = '5s';
alter role shoo_admin set lock_timeout = '5s';
alter role shoo_admin set idle_in_transaction_session_timeout = '15s';
alter role shoo_admin set search_path = admin;

create schema admin;
revoke all on schema admin from public;
grant usage on schema admin to shoo_admin;
-- Functions are executable by PUBLIC by default. Close that before any function exists; each API
-- function is granted to shoo_admin alone below. A later `grant usage on schema admin to shoo_api`
-- must not let the backend call admin.vote.
alter default privileges in schema admin revoke execute on functions from public;

-- ---------------------------------------------------------------- tables

-- Server-side secrets for later phases (owner_ref hashing, 02a). postgres only.
create table admin.secrets (
  key   text primary key,
  value text not null
);
insert into admin.secrets (key, value) values ('owner_ref_salt', encode(extensions.gen_random_bytes(32), 'hex'));

-- Dashboard settings. Changed only through admin.set_config(), which validates against the rule
-- columns of the row itself; later phases add rows with their own rules.
create table admin.admin_config (
  key          text primary key,
  value        jsonb not null,
  kind         text not null check (kind in ('bool', 'int')),
  min_value    int,
  max_value    int,
  internal     boolean not null default false,   -- hidden from v_config, refused by set_config
  confirm_when text check (confirm_when in ('true', 'lower')),  -- loosening privacy needs confirm
  updated_at   timestamptz not null default now(),
  updated_by   text not null default 'migration',
  check ((kind = 'int') = (min_value is not null and max_value is not null)),
  check (jsonb_typeof(value) = case kind when 'bool' then 'boolean' else 'number' end)
);
insert into admin.admin_config (key, value, kind, min_value, max_value, internal, confirm_when) values
  ('replica_enabled',           'false', 'bool', null, null, false, 'true'),
  ('replica_min_families',      '2',     'int',  2,    10,   false, 'lower'),
  ('max_publish_per_day',       '50',    'int',  1,    200,  false, null),
  ('require_admin_note_locked', 'true',  'bool', null, null, true,  null),
  ('require_admin_note',        'true',  'bool', null, null, false, null);

-- Append-only: no role but postgres can update or delete rows (I3).
create table admin.admin_audit (
  id     bigint generated always as identity primary key,
  at     timestamptz not null default clock_timestamp(),
  actor  text not null check (char_length(actor) between 1 and 320),
  action text not null check (action ~ '^[a-z_]{1,30}\.[a-z_]{1,30}$'),
  target text check (char_length(target) <= 300),
  before jsonb,
  after  jsonb,
  note   text check (char_length(note) <= 1000)
);
create index admin_audit_at on admin.admin_audit (at desc, id desc);

create table admin.categories (
  id       text primary key check (id ~ '^[a-z_]{1,40}$'),
  label_id text not null,
  label_en text not null,
  active   boolean not null default true
);
insert into admin.categories (id, label_id, label_en) values
  ('phishing_bank',     'Phishing bank',           'Bank phishing'),
  ('phishing_ewallet',  'Phishing e-wallet',       'E-wallet phishing'),
  ('marketplace_palsu', 'Marketplace palsu',       'Fake marketplace'),
  ('undian_palsu',      'Undian/hadiah palsu',     'Fake prize'),
  ('investasi_bodong',  'Investasi bodong',        'Investment scam'),
  ('judi',              'Judi online',             'Online gambling'),
  ('pinjol_ilegal',     'Pinjol ilegal',           'Illegal online loan'),
  ('lainnya',           'Lainnya',                 'Other');

-- One row per admin action on the blocklist. "First vote wins" is enforced by the state of
-- public.blocklist_entries, not here (R4 §1); this is the history shown next to a domain.
create table admin.review_decisions (
  id       bigint generated always as identity primary key,
  domain   text not null check (domain = lower(domain) and domain !~ '^www\.'),
  action   text not null check (action in ('approve', 'reject', 'unreject', 'remove', 'add')),
  category text references admin.categories (id),
  note     text check (char_length(note) between 10 and 1000),
  actor    text not null check (char_length(actor) between 1 and 320),
  at       timestamptz not null default clock_timestamp(),
  check ((action in ('approve', 'add')) = (category is not null))
);
create index review_decisions_domain_at on admin.review_decisions (domain, at desc, id desc);
-- The publish cap counts approvals + adds of the last 24 h.
create index review_decisions_published on admin.review_decisions (at) where action in ('approve', 'add');

-- The queue view and the per-domain scan list look scans up by domain; the existing indexes all
-- lead with owner_id. scans is small (14-day retention), so the build takes seconds under the
-- SHARE lock this transaction holds (inserts wait; lock_timeout above bounds the wait to acquire it).
create index scans_domain_created on public.scans (domain, created_at desc);

-- ---------------------------------------------------------------- internal helpers
-- Owned by postgres, no grant: called only from the security definer functions below.

create function admin._cfg(p_key text) returns jsonb
language sql stable set search_path = admin, pg_temp
as $$ select value from admin.admin_config where key = p_key $$;

-- Every action needs a note of at least 10 characters while require_admin_note is on (Q29).
create function admin._require_note(p_note text) returns void
language plpgsql stable set search_path = admin, pg_temp as $$
begin
  if p_note is not null and char_length(btrim(p_note)) >= 10 then
    return;
  end if;
  if p_note is not null or coalesce((admin._cfg('require_admin_note'))::boolean, true) then
    raise exception using errcode = 'SA003', message = 'note_required';
  end if;
end $$;

-- p_strict (add_domain): a hostname the admin typed. Otherwise only the backend's own check
-- (domain = lower(domain), no www.), so any domain the backend queued can still be decided.
create function admin._check_domain(p_domain text, p_strict boolean) returns void
language plpgsql immutable set search_path = admin, pg_temp as $$
begin
  if p_domain is null or p_domain <> lower(p_domain) or p_domain ~ '^www\.' or char_length(p_domain) > 253
     or (p_strict and p_domain !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$') then
    raise exception using errcode = 'SA014', message = 'invalid_domain';
  end if;
end $$;

-- K7: approvals + manual adds of the last 24 h, all admins. Caller holds advisory lock (7, 1), so
-- two approvals cannot both pass at count 49.
create function admin._check_publish_cap() returns void
language plpgsql stable set search_path = admin, pg_temp as $$
begin
  if (select count(*) from admin.review_decisions
       where action in ('approve', 'add') and at > now() - interval '24 hours')
     >= (admin._cfg('max_publish_per_day'))::int then
    raise exception using errcode = 'SA013', message = 'publish_cap';
  end if;
end $$;

create function admin._check_category(p_category text) returns void
language plpgsql stable set search_path = admin, pg_temp as $$
begin
  if p_category is null or not exists (select 1 from admin.categories where id = p_category and active) then
    raise exception using errcode = 'SA004', message = 'category_unknown';
  end if;
end $$;

create function admin._entry_status(p_domain text) returns text
language sql stable set search_path = admin, public, pg_temp as $$
  select case
           when removed_at is not null then 'removed'
           when approved_at is not null then 'approved'
           when rejected_at is not null then 'rejected'
           else 'pending'
         end
  from public.blocklist_entries where domain = p_domain
$$;

create function admin._audit(p_actor text, p_action text, p_target text, p_before jsonb, p_after jsonb, p_note text)
returns void
language sql set search_path = admin, pg_temp as $$
  insert into admin.admin_audit (actor, action, target, before, after, note)
  values (p_actor, p_action, p_target, p_before, p_after, p_note)
$$;

-- ---------------------------------------------------------------- API functions (shoo_admin)
-- Errors use SQLSTATE class SA (R2 §4); the Worker maps each code to an HTTP status (R3 §3).
-- vote/unreject/remove_domain/add_domain serialize on advisory lock (7, 1) (classes 1–6 are the
-- backend's) and change blocklist_entries as their last statement: GET /blocklist?since= pages by
-- approved_at/removed_at, so nothing slow may run between that write and commit.
-- p_actor is the admin's email from the verified Access JWT. It is the audit trail, not
-- authorization: only the dashboard Worker can log in as shoo_admin.

create function admin.vote(p_domain text, p_action text, p_category text, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, public, pg_temp as $$
declare
  v_category text;
begin
  perform pg_advisory_xact_lock(7, 1);
  if p_action is null or p_action not in ('approve', 'reject') then
    raise exception using errcode = '22023', message = 'invalid_action';
  end if;
  perform admin._check_domain(p_domain, false);
  perform admin._require_note(p_note);
  if p_action = 'approve' then
    perform admin._check_category(p_category);
    v_category := p_category;
    perform admin._check_publish_cap();
  end if;

  insert into admin.review_decisions (domain, action, category, note, actor)
  values (p_domain, p_action, v_category, p_note, p_actor);
  perform admin._audit(p_actor, 'blocklist.' || p_action, p_domain, '{"status": "pending"}',
    jsonb_build_object('status', case p_action when 'approve' then 'approved' else 'rejected' end, 'category', v_category),
    p_note);

  -- First vote wins (R4 §1, I4): only an undecided row changes. A concurrent vote waits on the
  -- advisory lock, then matches 0 rows here and rolls back its decision + audit rows.
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

-- rejected → pending. If no family supports the domain any more, recountFamilies has already
-- deleted the row, so there is nothing to unreject.
create function admin.unreject(p_domain text, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(7, 1);
  perform admin._check_domain(p_domain, false);
  perform admin._require_note(p_note);
  insert into admin.review_decisions (domain, action, note, actor) values (p_domain, 'unreject', p_note, p_actor);
  perform admin._audit(p_actor, 'blocklist.unreject', p_domain, '{"status": "rejected"}', '{"status": "pending"}', p_note);
  update public.blocklist_entries set rejected_at = null, rejected_by = null
   where domain = p_domain and rejected_at is not null;
  if not found then
    raise exception using errcode = 'SA006', message = 'not_rejected';
  end if;
end $$;

-- approved → removed: extensions drop it through `removed[]` of GET /blocklist.
create function admin.remove_domain(p_domain text, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(7, 1);
  perform admin._check_domain(p_domain, false);
  perform admin._require_note(p_note);
  insert into admin.review_decisions (domain, action, note, actor) values (p_domain, 'remove', p_note, p_actor);
  perform admin._audit(p_actor, 'blocklist.remove', p_domain, '{"status": "approved"}', '{"status": "removed"}', p_note);
  update public.blocklist_entries set removed_at = now()   -- trigger: clock_timestamp()
   where domain = p_domain and approved_at is not null and removed_at is null;
  if not found then
    raise exception using errcode = 'SA007', message = 'not_approved';
  end if;
end $$;

-- Manual add (Q43): new domain, queued/rejected domain, or a removed one → approved. The insert
-- path sets clock_timestamp() itself: blocklist_entries_times only runs BEFORE UPDATE, and now()
-- (transaction start) could fall behind a cursor of GET /blocklist?since=.
create function admin.add_domain(p_domain text, p_category text, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(7, 1);
  perform admin._check_domain(p_domain, true);
  perform admin._require_note(p_note);
  perform admin._check_category(p_category);
  perform admin._check_publish_cap();
  insert into admin.review_decisions (domain, action, category, note, actor)
  values (p_domain, 'add', p_category, p_note, p_actor);
  perform admin._audit(p_actor, 'blocklist.add', p_domain,
    jsonb_build_object('status', admin._entry_status(p_domain)),
    jsonb_build_object('status', 'approved', 'category', p_category), p_note);
  insert into public.blocklist_entries as b (domain, families, approved_at, approved_by)
  values (p_domain, 0, clock_timestamp(), p_actor)
  on conflict (domain) do update
    set approved_at = clock_timestamp(), approved_by = excluded.approved_by,
        rejected_at = null, rejected_by = null, removed_at = null
    where b.approved_at is null or b.removed_at is not null;
  if not found then
    raise exception using errcode = 'SA005', message = 'already_approved';
  end if;
end $$;

-- The R2 object path of the newest replica of a queued domain whose owner is still in a family
-- (same reach as the backend's replicaPathForViewer: after a disconnect the copy is unreachable,
-- P13). Only the domain is an argument, so an admin cannot pick a scan or an owner; at least
-- replica_min_families families must have reported it, so a copy cannot be tied to one family
-- (D-dash-07). The path names the owner: the Worker uses it to read R2 and never returns it.
create function admin.replica_for(p_domain text)
returns text
language plpgsql stable security definer set search_path = admin, public, pg_temp as $$
declare
  v_families int;
  v_path     text;
begin
  if not coalesce((admin._cfg('replica_enabled'))::boolean, false) then
    raise exception using errcode = 'SA016', message = 'replica_disabled';
  end if;
  if not exists (select 1 from public.blocklist_entries
                  where domain = p_domain and approved_at is null and rejected_at is null
                    and removed_at is null and families > 0) then
    raise exception using errcode = 'SA008', message = 'not_in_queue';
  end if;
  select count(distinct by_device_id) into v_families from public.verdicts
   where domain = p_domain and value = 'not_safe' and global_eligible;
  if v_families < (admin._cfg('replica_min_families'))::int then
    raise exception using errcode = 'SA015', message = 'replica_locked';
  end if;
  select s.replica_path into v_path from public.scans s
   where s.domain = p_domain and s.replica_path is not null
     and exists (select 1 from public.family_links f where f.protected_id = s.owner_id or f.guardian_id = s.owner_id)
   order by s.detected_at desc, s.created_at desc, s.id desc
   limit 1;
  if v_path is null then
    raise exception using errcode = 'SA008', message = 'not_in_queue';
  end if;
  return v_path;
end $$;

-- p_value / p_confirm are text as typed in the UI. Loosening a privacy setting (confirm_when)
-- needs p_confirm equal to the new value (I7, D-dash-07/08).
create function admin.set_config(p_key text, p_value text, p_actor text, p_note text, p_confirm text default null)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  r     admin.admin_config;
  v_new jsonb;
  v_int int;
begin
  select * into r from admin.admin_config where key = p_key for update;
  if not found or r.internal then
    raise exception using errcode = 'SA010', message = 'config_unknown';
  end if;
  perform admin._require_note(p_note);

  if r.kind = 'bool' then
    if p_value is null or lower(btrim(p_value)) not in ('true', 'false') then
      raise exception using errcode = 'SA009', message = 'config_invalid';
    end if;
    v_new := to_jsonb(lower(btrim(p_value))::boolean);
  else
    if p_value is null or btrim(p_value) !~ '^-?[0-9]{1,9}$' then
      raise exception using errcode = 'SA009', message = 'config_invalid';
    end if;
    v_int := btrim(p_value)::int;
    if v_int < r.min_value or v_int > r.max_value then
      raise exception using errcode = 'SA009', message = 'config_invalid';
    end if;
    v_new := to_jsonb(v_int);
  end if;

  if p_key = 'require_admin_note' and v_new = 'false'::jsonb
     and coalesce((admin._cfg('require_admin_note_locked'))::boolean, true) then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;

  if (r.confirm_when = 'true' and v_new = 'true'::jsonb and r.value <> v_new)
     or (r.confirm_when = 'lower' and (v_new)::int < (r.value)::int) then
    if p_confirm is null or lower(btrim(p_confirm)) <> v_new::text then
      raise exception using errcode = 'SA011', message = 'confirm_required';
    end if;
  end if;

  update admin.admin_config set value = v_new, updated_at = now(), updated_by = p_actor where key = p_key;
  perform admin._audit(p_actor, 'config.set', p_key, jsonb_build_object('value', r.value),
    jsonb_build_object('value', v_new), p_note);
end $$;

-- Worker actions without a DB change (opening a replica, an export). Decision and config entries
-- come only from the functions above, so the feed cannot be forged through this one.
create function admin.log_audit(p_actor text, p_action text, p_target text, p_note text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  if p_action is null or p_action !~ '^[a-z_]{1,30}\.[a-z_]{1,30}$' or split_part(p_action, '.', 1) in ('blocklist', 'config') then
    raise exception using errcode = '22023', message = 'invalid_action';
  end if;
  perform admin._audit(p_actor, p_action, p_target, null, null, p_note);
end $$;

-- ---------------------------------------------------------------- views (shoo_admin, select only)
-- Owned by postgres without security_invoker: they read backend tables with the owner's rights,
-- so shoo_admin needs no grant in public. security_barrier keeps caller predicates from running
-- before the view's own filters. Never exposed: url, page_title, owner_id, by_device_id, by_name,
-- signal evidence, replica_path (SECURITY D1, D-dash-07, I13).

-- Queue (R4 §1 pending). families_* count distinct guardians, as recountFamilies does.
-- has_replica is true exactly when admin.replica_for would succeed.
create view admin.v_review_queue with (security_barrier = true) as
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
                               where f.protected_id = r.owner_id or f.guardian_id = r.owner_id))) as has_replica
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
where b.approved_at is null and b.rejected_at is null and b.removed_at is null and b.families > 0;

create view admin.v_blocklist with (security_barrier = true) as
select
  b.domain,
  b.families,
  b.first_seen_at,
  b.approved_at,
  b.approved_by,
  b.rejected_at,
  b.rejected_by,
  b.removed_at,
  case
    when b.removed_at is not null then 'removed'
    when b.approved_at is not null then 'approved'
    when b.rejected_at is not null then 'rejected'
    else 'pending'
  end as status,
  d.action as last_action,
  d.category as last_category,
  d.note as last_note,
  d.actor as last_actor,
  d.at as last_at
from public.blocklist_entries b
left join lateral (
  select action, category, note, actor, at from admin.review_decisions r
   where r.domain = b.domain order by r.at desc, r.id desc limit 1
) d on true;

-- Scans of the last 14 days, masked: no userinfo/query/fragment, signal ids without evidence text,
-- the verdict value without who decided, no owner at all.
create view admin.v_scans with (security_barrier = true) as
select
  s.id,
  s.domain,
  regexp_replace(regexp_replace(s.url, '[?#].*$', ''), '^(https?://)[^/@]*@', '\1') as url_masked,
  s.score,
  s.status::text as status,
  coalesce((select array_agg(e ->> 'id' order by o)
              from jsonb_array_elements(s.signals) with ordinality as x(e, o)
             where e ->> 'id' is not null), '{}') as signal_ids,
  s.detected_at,
  s.replica_path is not null as has_replica,
  v.value::text as verdict
from public.scans s
left join public.verdicts v on v.owner_id = s.owner_id and v.domain = s.domain
where s.created_at > now() - interval '14 days';

-- One row of operational counts (dashboard phase 03 reads it; no per-device data).
create view admin.v_ops_snapshot with (security_barrier = true) as
select
  (select coalesce(jsonb_object_agg(mode, n), '{}') from
     (select mode::text, count(*)::int as n from public.devices group by mode) x) as devices_by_mode,
  (select count(distinct guardian_id)::int from public.family_links) as families,
  (select round(100.0 * count(*) filter (where ext_last_seen_at > now() - interval '24 hours') / nullif(count(*), 0), 1)
     from public.devices where mode = 'protected') as ext_active_pct_24h,
  (select coalesce(jsonb_object_agg(value, n), '{}') from
     (select value::text, count(*)::int as n from public.verdicts
       where decided_at > now() - interval '24 hours' group by value) x) as verdicts_24h,
  (select coalesce(jsonb_object_agg(result, n), '{}') from
     (select result, count(*)::int as n from public.push_log
       where created_at > now() - interval '24 hours' group by result) x) as push_24h,
  (select coalesce(jsonb_object_agg(bucket, n), '{}') from
     (select bucket, count(*)::int as n from public.rate_limit_hits
       where hit_at > now() - interval '24 hours' group by bucket) x) as rate_limit_24h,
  (select coalesce(jsonb_agg(jsonb_build_object('job', job, 'started_at', started_at, 'ok_at', ok_at,
            'failed', failed, 'backlog', backlog, 'finished_at', finished_at) order by job), '[]')
     from public.ops_jobs) as jobs,
  pg_database_size(current_database()) as db_bytes,
  (select coalesce(jsonb_agg(jsonb_build_object('table', name, 'bytes', bytes) order by bytes desc), '[]') from
     (select c.oid::regclass::text as name, pg_total_relation_size(c.oid) as bytes
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where c.relkind in ('r', 'p') and n.nspname in ('public', 'admin', 'storage')
       order by 2 desc limit 10) x) as top_tables;

create view admin.v_audit with (security_barrier = true) as
select id, at, actor, action, target, before, after, note from admin.admin_audit;

create view admin.v_config with (security_barrier = true) as
select key, value, kind, min_value, max_value, confirm_when, updated_at, updated_by
from admin.admin_config where not internal;

create view admin.v_categories with (security_barrier = true) as
select id, label_id, label_en, active from admin.categories;

-- Activity feed: each decision once (from review_decisions) plus audit entries that are not
-- decisions (config, replica, export). Phase 02a adds labels and analysis runs.
create view admin.v_feed with (security_barrier = true) as
select 'decision'::text as kind, r.id, r.at, r.actor, 'blocklist.' || r.action as action,
       r.domain as target, r.category, r.note
from admin.review_decisions r
union all
select 'audit', a.id, a.at, a.actor, a.action, a.target, null, a.note
from admin.admin_audit a
where a.action not like 'blocklist.%';

-- ---------------------------------------------------------------- privileges

do $$
declare
  t text;
begin
  foreach t in array array['secrets', 'admin_config', 'admin_audit', 'categories', 'review_decisions'] loop
    -- Second layer: RLS with no policy at all. Only the owner (postgres) reads or writes.
    execute format('alter table admin.%I enable row level security', t);
  end loop;
end $$;

-- After every object exists: drop whatever default privileges handed out, then grant the API.
revoke all on all tables in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all sequences in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;
revoke all on all functions in schema admin from public, anon, authenticated, service_role, shoo_api, shoo_admin;

grant select on
  admin.v_review_queue, admin.v_blocklist, admin.v_scans, admin.v_ops_snapshot,
  admin.v_audit, admin.v_config, admin.v_categories, admin.v_feed
to shoo_admin;

grant execute on function
  admin.vote(text, text, text, text, text),
  admin.unreject(text, text, text),
  admin.remove_domain(text, text, text),
  admin.add_domain(text, text, text, text),
  admin.replica_for(text),
  admin.set_config(text, text, text, text, text),
  admin.log_audit(text, text, text, text)
to shoo_admin;
