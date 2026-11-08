-- ADM-11 (dashboard plan phase 11, D-dash-26, Alief 8 Nov 2026): secrets and LLM settings of the
-- shoo-ai, shoo-api and shoo-admin Workers are edited from the dashboard's Config page. The dashboard
-- Worker puts each value into the Worker through the Cloudflare secrets API and keeps an AES-256-GCM
-- copy here (key CONFIG_ENC_KEY lives only in the dashboard Worker; AAD = "<name>:<key_version>"), so
-- an admin can see the value again. This schema never sees a plaintext value.
--
-- Save protocol per entry (phase 11 K5), Cloudflare is never called inside a transaction:
--   tx 1: worker_secret_lock → worker_secret_begin   (marker needs_resave = true + save_token)
--   PUT to every Worker of the entry                  (outside any transaction)
--   tx 2: worker_secret_lock → worker_secret_set     (marker cleared only if the token is still ours)
-- A failed or timed-out PUT calls worker_secret_flag_resave instead of set. Two overlapping saves never
-- clear the marker: the second begin stores a null token, and set/flag_resave always empty it.

create table admin.worker_secrets (
  name text primary key check (name ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  -- One row per catalog entry; an entry shared by two Workers is one row.
  workers text[] not null check (cardinality(workers) between 1 and 3 and workers <@ '{shoo-ai,shoo-api,shoo-admin}'),
  ciphertext bytea check (octet_length(ciphertext) between 16 and 16384),
  iv bytea check (octet_length(iv) = 12),
  key_version smallint not null default 1 check (key_version between 1 and 1000),
  -- Last characters of a sensitive value ("••••1c0e"); never set on rows that are not sensitive.
  hint text check (char_length(hint) between 1 and 4),
  sensitive boolean not null,
  -- true = a save did not finish cleanly: the Workers may hold a different value than this row.
  needs_resave boolean not null default false,
  save_token uuid,
  updated_at timestamptz not null default now(),
  updated_by text not null check (char_length(updated_by) between 1 and 320),
  check ((ciphertext is null) = (iv is null)),
  -- A marker row (first save failed half way) has no value yet.
  check (ciphertext is not null or needs_resave),
  check (hint is null or sensitive)
);
alter table admin.worker_secrets enable row level security;
revoke all on admin.worker_secrets from public, anon, authenticated, service_role, shoo_api, shoo_admin;

create function admin._worker_secret_check(p_name text, p_workers text[], p_sensitive boolean) returns void
language plpgsql immutable set search_path = admin, pg_temp as $$
begin
  if p_name is null or p_name !~ '^[A-Z][A-Z0-9_]{1,63}$'
     or p_workers is null or cardinality(p_workers) not between 1 and 3
     or not (p_workers <@ '{shoo-ai,shoo-api,shoo-admin}'::text[]) or array_position(p_workers, null) is not null
     or p_sensitive is null then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
end $$;

-- The Config page's list. Ciphertext only for rows that are not sensitive (the page shows those values
-- without a reveal); sensitive rows only through worker_secret_read, which is audited.
create function admin.worker_secrets_list()
returns table (name text, workers text[], hint text, sensitive boolean, needs_resave boolean, key_version smallint,
               updated_at timestamptz, updated_by text, ciphertext bytea, iv bytea)
language sql stable security definer set search_path = admin, pg_temp as $$
  select s.name, s.workers, s.hint, s.sensitive, s.needs_resave, s.key_version, s.updated_at, s.updated_by,
         case when s.sensitive then null else s.ciphertext end,
         case when s.sensitive then null else s.iv end
  from admin.worker_secrets s
  order by s.name
$$;

-- First statement of both short save transactions (class 9; 7 = review, 8 = API keys).
create function admin.worker_secret_lock(p_name text) returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  if p_name is null or p_name !~ '^[A-Z][A-Z0-9_]{1,63}$' then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  perform pg_advisory_xact_lock(9, hashtext(p_name));
end $$;

-- K5 step 1: mark the row "needs a resave" before any Worker changes. A token still stored means
-- another save has not finished (or died): store null so neither set can clear the marker.
create function admin.worker_secret_begin(p_name text, p_workers text[], p_sensitive boolean, p_actor text)
returns uuid
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_token uuid := gen_random_uuid();
begin
  perform admin._check_actor(p_actor);
  perform admin._worker_secret_check(p_name, p_workers, p_sensitive);
  insert into admin.worker_secrets as s (name, workers, sensitive, needs_resave, save_token, updated_by)
  values (p_name, p_workers, p_sensitive, true, v_token, p_actor)
  on conflict (name) do update set
    workers = excluded.workers,
    sensitive = excluded.sensitive,
    hint = case when excluded.sensitive then s.hint end,
    needs_resave = true,
    save_token = case when s.save_token is null then excluded.save_token end;
  return v_token;
end $$;

-- K5 step 3: store the encrypted value. The marker is cleared only when the stored token is the
-- caller's; save_token is always emptied. Returns needs_resave after the write.
create function admin.worker_secret_set(p_name text, p_workers text[], p_ciphertext bytea, p_iv bytea, p_key_version int,
  p_hint text, p_sensitive boolean, p_save_token uuid, p_actor text, p_note text)
returns boolean
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_old_hint text;
  v_old_token uuid;
  v_found boolean;
  v_resave boolean;
begin
  perform admin._check_actor(p_actor);
  perform admin._worker_secret_check(p_name, p_workers, p_sensitive);
  perform admin._check_text(p_note, 1000, true);
  if p_save_token is null
     or p_ciphertext is null or octet_length(p_ciphertext) not between 16 and 16384
     or p_iv is null or octet_length(p_iv) <> 12
     or p_key_version is null or p_key_version not between 1 and 1000
     or (p_sensitive and (p_hint is null or char_length(p_hint) not between 1 and 4))
     or (not p_sensitive and p_hint is not null) then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  select s.hint, s.save_token, true into v_old_hint, v_old_token, v_found
    from admin.worker_secrets s where s.name = p_name for update;
  v_resave := v_found is not true or v_old_token is null or v_old_token <> p_save_token;
  insert into admin.worker_secrets as s
    (name, workers, ciphertext, iv, key_version, hint, sensitive, needs_resave, save_token, updated_at, updated_by)
  values (p_name, p_workers, p_ciphertext, p_iv, p_key_version, p_hint, p_sensitive, v_resave, null, now(), p_actor)
  on conflict (name) do update set
    workers = excluded.workers, ciphertext = excluded.ciphertext, iv = excluded.iv, key_version = excluded.key_version,
    hint = excluded.hint, sensitive = excluded.sensitive, needs_resave = excluded.needs_resave, save_token = null,
    updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  perform admin._audit(p_actor, 'secret.set', p_name,
    case when v_found then jsonb_build_object('hint', v_old_hint) end,
    jsonb_build_object('hint', p_hint, 'workers', to_jsonb(p_workers), 'needs_resave', v_resave), btrim(p_note));
  return v_resave;
end $$;

-- Reveal or a check of the stored value. Audited without the value. No row → nothing (no audit).
create function admin.worker_secret_read(p_name text, p_purpose text, p_actor text)
returns table (ciphertext bytea, iv bytea, key_version smallint, needs_resave boolean)
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  perform admin._check_actor(p_actor);
  if p_name is null or p_name !~ '^[A-Z][A-Z0-9_]{1,63}$' or p_purpose is null or p_purpose not in ('reveal', 'check') then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  return query
    select s.ciphertext, s.iv, s.key_version, s.needs_resave from admin.worker_secrets s where s.name = p_name;
  if found then
    perform admin._audit(p_actor, 'secret.' || p_purpose, p_name, null, null, null);
  end if;
end $$;

-- A PUT failed, timed out, or only reached some Workers: keep (or create) the marker.
create function admin.worker_secret_flag_resave(p_name text, p_workers text[], p_sensitive boolean, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  perform admin._check_actor(p_actor);
  perform admin._worker_secret_check(p_name, p_workers, p_sensitive);
  insert into admin.worker_secrets as s (name, workers, sensitive, needs_resave, save_token, updated_by)
  values (p_name, p_workers, p_sensitive, true, null, p_actor)
  on conflict (name) do update set needs_resave = true, save_token = null;
  perform admin._audit(p_actor, 'secret.partial', p_name, null, jsonb_build_object('workers', to_jsonb(p_workers)), null);
end $$;

-- Apple refuses a new provider token for the same key more than about once per 20 minutes
-- (TooManyProviderTokenUpdates): one APNs check per Key ID per 20 minutes, draft or stored value.
-- Returns the time of the last check when refused, null (and audits) when allowed.
create function admin.worker_secret_apns_gate(p_key_id text, p_actor text)
returns timestamptz
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_last timestamptz;
begin
  perform admin._check_actor(p_actor);
  if p_key_id is null or p_key_id !~ '^[A-Z0-9]{10}$' then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  perform pg_advisory_xact_lock(9, hashtext('apns:' || p_key_id));
  select max(a.at) into v_last from admin.admin_audit a
   where a.action = 'secret.apns_check' and a.target = p_key_id and a.at > now() - interval '20 minutes';
  if v_last is not null then
    return v_last;
  end if;
  perform admin._audit(p_actor, 'secret.apns_check', p_key_id, null, null, null);
  return null;
end $$;

revoke all on function admin._worker_secret_check(text, text[], boolean),
  admin.worker_secrets_list(), admin.worker_secret_lock(text),
  admin.worker_secret_begin(text, text[], boolean, text),
  admin.worker_secret_set(text, text[], bytea, bytea, int, text, boolean, uuid, text, text),
  admin.worker_secret_read(text, text, text),
  admin.worker_secret_flag_resave(text, text[], boolean, text),
  admin.worker_secret_apns_gate(text, text)
from public, anon, authenticated, service_role, shoo_api, shoo_admin;

grant execute on function
  admin.worker_secrets_list(), admin.worker_secret_lock(text),
  admin.worker_secret_begin(text, text[], boolean, text),
  admin.worker_secret_set(text, text[], bytea, bytea, int, text, boolean, uuid, text, text),
  admin.worker_secret_read(text, text, text),
  admin.worker_secret_flag_resave(text, text[], boolean, text),
  admin.worker_secret_apns_gate(text, text)
to shoo_admin;
