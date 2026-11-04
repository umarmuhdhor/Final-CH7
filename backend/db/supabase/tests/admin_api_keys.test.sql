-- ADM-08 admin dashboard: API keys for the training export (migration admin_api_keys). Hashes are
-- made-up hex; the Worker computes the real SHA-256.
create extension if not exists pgtap with schema extensions;

begin;
select plan(22);

create function pg_temp.as_admin(q text) returns text language plpgsql as $$
declare
  out text;
begin
  set local role shoo_admin;
  execute q into out;
  reset role;
  return coalesce(out, '');
exception when others then
  reset role;
  return 'ERR ' || sqlstate;
end $$;

create function pg_temp.h(n int) returns text language sql as $$ select lpad(to_hex(n), 64, '0') $$;
create function pg_temp.p(n int) returns text language sql as $$ select 'shoo_' || lpad(to_hex(n), 8, '0') $$;

delete from admin.api_keys;

-- create
select isnt(pg_temp.as_admin(format($q$select admin.api_key_create('Imelda', %L, %L, 90, 'dev@local.test')$q$, pg_temp.p(1), pg_temp.h(1))), '',
  'shoo_admin creates a key');
select is((select (expires_at - created_at) from admin.api_keys where prefix = pg_temp.p(1)), interval '90 days', 'expires after the chosen days');
select is((select scopes from admin.api_keys where prefix = pg_temp.p(1)), '{ai:read}'::text[], 'default scope ai:read');
select is((select encode(key_hash, 'hex') from admin.api_keys where prefix = pg_temp.p(1)), pg_temp.h(1), 'stores the hash as sent');
select is((select count(*)::int from admin.admin_audit where action = 'api_key.create' and target = pg_temp.p(1)), 1, 'create is audited');

select is(pg_temp.as_admin(format($q$select admin.api_key_create('x', %L, %L, 7, 'dev@local.test')$q$, pg_temp.p(2), pg_temp.h(2))), 'ERR SA009', 'days other than 30/90/365 → SA009');
select is(pg_temp.as_admin(format($q$select admin.api_key_create('x', 'shoo_XYZ', %L, 30, 'dev@local.test')$q$, pg_temp.h(2))), 'ERR SA009', 'bad prefix → SA009');
select is(pg_temp.as_admin(format($q$select admin.api_key_create('x', %L, 'abc', 30, 'dev@local.test')$q$, pg_temp.p(2))), 'ERR SA009', 'bad hash → SA009');
select is(pg_temp.as_admin(format($q$select admin.api_key_create('', %L, %L, 30, 'dev@local.test')$q$, pg_temp.p(2), pg_temp.h(2))), 'ERR SA009', 'empty name → SA009');
select is(pg_temp.as_admin(format($q$select admin.api_key_create('dup', %L, %L, 30, 'dev@local.test')$q$, pg_temp.p(2), pg_temp.h(1))), 'ERR 23505', 'same hash twice → unique violation');

-- limit: 5 active
select pg_temp.as_admin(format($q$select admin.api_key_create('k', %L, %L, 30, 'dev@local.test')$q$, pg_temp.p(n), pg_temp.h(n))) from generate_series(2, 5) n;
select is(pg_temp.as_admin(format($q$select admin.api_key_create('k6', %L, %L, 30, 'dev@local.test')$q$, pg_temp.p(6), pg_temp.h(6))), 'ERR SA018', 'a sixth active key → SA018');

-- use
select is(pg_temp.as_admin(format($q$select prefix || ' ' || limited from admin.api_key_use(%L)$q$, pg_temp.h(1))), pg_temp.p(1) || ' false', 'a valid key is accepted');
select is((select uses from admin.api_keys where prefix = pg_temp.p(1)), 1::bigint, 'use counts');
select isnt((select last_used_at from admin.api_keys where prefix = pg_temp.p(1)), null, 'use sets last_used_at');
select is(pg_temp.as_admin(format($q$select count(*)::text from admin.api_key_use(%L)$q$, pg_temp.h(99))), '0', 'unknown key → no row');
select is(pg_temp.as_admin($q$select count(*)::text from admin.api_key_use('nothex')$q$), '0', 'malformed hash → no row');

-- rate: the 301st request in the window is limited
update admin.api_keys set window_start = now(), window_count = 300 where prefix = pg_temp.p(1);
select is(pg_temp.as_admin(format($q$select limited::text from admin.api_key_use(%L)$q$, pg_temp.h(1))), 'true', 'over 300 per minute → limited');
update admin.api_keys set window_start = now() - interval '2 minutes' where prefix = pg_temp.p(1);
select is(pg_temp.as_admin(format($q$select limited::text from admin.api_key_use(%L)$q$, pg_temp.h(1))), 'false', 'a new window starts over');

-- expiry and revoke
update admin.api_keys set expires_at = now() - interval '1 second' where prefix = pg_temp.p(2);
select is(pg_temp.as_admin(format($q$select count(*)::text from admin.api_key_use(%L)$q$, pg_temp.h(2))), '0', 'expired key → no row');
select lives_ok(format($q$select pg_temp.as_admin('select admin.api_key_revoke(%s, ''dev@local.test'')')$q$, (select id from admin.api_keys where prefix = pg_temp.p(3))), 'revoke');
select is(pg_temp.as_admin(format($q$select count(*)::text from admin.api_key_use(%L)$q$, pg_temp.h(3))), '0', 'revoked key → no row');

-- the view never has the hash; shoo_admin cannot read the table
select is((select count(*)::int from information_schema.columns where table_schema = 'admin' and table_name = 'v_api_keys' and column_name = 'key_hash'), 0,
  'v_api_keys has no key_hash');

select * from finish();
rollback;
