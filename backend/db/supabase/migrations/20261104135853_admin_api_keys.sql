-- ADM-08 (dashboard plan fase 08, Alief 4 Nov 2026): API keys for the AI team's training export.
-- An admin generates a key in the dashboard; the Worker keeps only its SHA-256 and the prefix. A key
-- reaches only /api/v1/training/* (scope ai:read: the anonymous scan export and the evidence fragments
-- of 07b), which Cloudflare Access bypasses; the Worker checks the key with admin.api_key_use.

create table admin.api_keys (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 60),
  -- Shown in the list and the audit trail ("shoo_ab12cd34"); the rest of the key is never stored.
  prefix text not null unique check (prefix ~ '^shoo_[0-9a-f]{8}$'),
  key_hash bytea not null unique check (octet_length(key_hash) = 32),
  scopes text[] not null default '{ai:read}' check (scopes <@ '{ai:read}' and cardinality(scopes) > 0),
  created_by text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz,
  uses bigint not null default 0,
  -- Fixed one-minute window per key (API_KEY_RATE).
  window_start timestamptz,
  window_count int not null default 0,
  revoked_at timestamptz,
  revoked_by text
);
alter table admin.api_keys enable row level security;
revoke all on admin.api_keys from public, anon, authenticated, service_role, shoo_api, shoo_admin;

-- Keys an admin may hold at once, and requests per key per minute (export paging + one call per fragment).
create function admin._api_key_max() returns int language sql immutable set search_path = admin, pg_temp as $$ select 5 $$;
create function admin._api_key_rate() returns int language sql immutable set search_path = admin, pg_temp as $$ select 300 $$;

-- The Worker makes the key (32 random bytes) and sends its prefix + SHA-256 (hex). 30, 90 or 365 days.
create function admin.api_key_create(p_name text, p_prefix text, p_hash text, p_days int, p_actor text)
returns bigint
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_id bigint;
begin
  perform admin._check_actor(p_actor);
  perform admin._check_text(p_name, 60, true);
  if p_prefix is null or p_prefix !~ '^shoo_[0-9a-f]{8}$' or p_hash is null or p_hash !~ '^[0-9a-f]{64}$'
     or p_days is null or p_days not in (30, 90, 365) then
    raise exception using errcode = 'SA009', message = 'config_invalid';
  end if;
  -- Serialise creates so two at once cannot both pass the limit (class 8; 7 is run_analysis).
  perform pg_advisory_xact_lock(8, 0);
  if (select count(*) from admin.api_keys where revoked_at is null and expires_at > now()) >= admin._api_key_max() then
    raise exception using errcode = 'SA018', message = 'api_key_limit';
  end if;
  insert into admin.api_keys (name, prefix, key_hash, created_by, expires_at)
  values (btrim(p_name), p_prefix, decode(p_hash, 'hex'), p_actor, now() + make_interval(days => p_days))
  returning id into v_id;
  perform admin._audit(p_actor, 'api_key.create', p_prefix, null,
    jsonb_build_object('id', v_id, 'name', btrim(p_name), 'days', p_days), null);
  return v_id;
end $$;

create function admin.api_key_revoke(p_id bigint, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_prefix text;
begin
  perform admin._check_actor(p_actor);
  update admin.api_keys set revoked_at = now(), revoked_by = p_actor
   where id = p_id and revoked_at is null returning prefix into v_prefix;
  if not found then
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
  perform admin._audit(p_actor, 'api_key.revoke', v_prefix, null, jsonb_build_object('id', p_id), null);
end $$;

-- One request with a key: no row = unknown, revoked or expired (401); `limited` = over the rate (429).
create function admin.api_key_use(p_hash text)
returns table (id bigint, prefix text, scopes text[], limited boolean)
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    return;
  end if;
  return query
  update admin.api_keys k set
    window_start = case when k.window_start is null or k.window_start <= now() - interval '1 minute' then now() else k.window_start end,
    window_count = case when k.window_start is null or k.window_start <= now() - interval '1 minute' then 1 else k.window_count + 1 end,
    last_used_at = now(),
    uses = k.uses + 1
  where k.key_hash = decode(p_hash, 'hex') and k.revoked_at is null and k.expires_at > now()
  returning k.id, k.prefix, k.scopes, k.window_count > admin._api_key_rate();
end $$;

-- The dashboard's list: never the hash.
create view admin.v_api_keys as
  select id, name, prefix, scopes, created_by, created_at, expires_at, last_used_at, uses, revoked_at, revoked_by,
         revoked_at is null and expires_at > now() as active
  from admin.api_keys;
revoke all on admin.v_api_keys from public, anon, authenticated, service_role, shoo_api, shoo_admin;

revoke all on function admin._api_key_max(), admin._api_key_rate(),
  admin.api_key_create(text, text, text, int, text), admin.api_key_revoke(bigint, text), admin.api_key_use(text)
from public, anon, authenticated, service_role, shoo_api, shoo_admin;

grant select on admin.v_api_keys to shoo_admin;
grant execute on function
  admin.api_key_create(text, text, text, int, text),
  admin.api_key_revoke(bigint, text),
  admin.api_key_use(text)
to shoo_admin;
