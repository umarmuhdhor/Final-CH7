-- ADM-11 admin dashboard (plan phase 11, D-dash-26): encrypted copies of Worker secrets
-- (migration admin_worker_secrets). The Worker encrypts with AES-256-GCM; here the bytes are made up.
-- Save protocol (K5): tx 1 lock + begin (marker + token) → Cloudflare PUT outside any tx → tx 2 lock + set.
create extension if not exists pgtap with schema extensions;

begin;
select plan(48);

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

-- Tokens returned by begin, kept outside shoo_admin's reach (the temp table belongs to postgres).
create temp table tok (k text primary key, v text);

create function pg_temp.begin_(p_name text, p_sensitive boolean default true) returns text language sql as $$
  select pg_temp.as_admin(format(
    $q$select admin.worker_secret_begin(%L, '{shoo-ai}', %L, 'dev@local.test')::text$q$, p_name, p_sensitive))
$$;
create function pg_temp.set_(p_name text, p_token text, p_hint text default 'ab12', p_sensitive boolean default true) returns text language sql as $$
  select pg_temp.as_admin(format(
    $q$select admin.worker_secret_set(%L, '{shoo-ai}', '\x0102030405060708090a0b0c0d0e0f1011'::bytea,
       '\x0102030405060708090a0b0c'::bytea, 1, %L, %L, %L::uuid, 'dev@local.test', 'rotate')::text$q$,
    p_name, p_hint, p_sensitive, p_token))
$$;
create function pg_temp.flag_(p_name text) returns text language sql as $$
  select pg_temp.as_admin(format(
    $q$select admin.worker_secret_flag_resave(%L, '{shoo-ai,shoo-api}', true, 'dev@local.test')::text$q$, p_name))
$$;
create function pg_temp.resave(p_name text) returns boolean language sql as $$
  select needs_resave from admin.worker_secrets where name = p_name
$$;

delete from admin.worker_secrets;

-- privileges
select is(pg_temp.as_admin('select count(*)::text from admin.worker_secrets'), 'ERR 42501', 'shoo_admin cannot read the table');
select is(pg_temp.as_admin($q$update admin.worker_secrets set needs_resave = false$q$), 'ERR 42501', 'shoo_admin cannot write the table');

-- begin on a new name → marker row with a token
insert into tok select 'k1', pg_temp.begin_('LLM_API_KEY');
select ok((select v from tok where k = 'k1') ~ '^[0-9a-f-]{36}$', 'begin returns a token');
select is((select ciphertext from admin.worker_secrets where name = 'LLM_API_KEY'), null, 'first begin leaves a marker row without ciphertext');
select is(pg_temp.resave('LLM_API_KEY'), true, 'the marker row needs a resave');
select is((select save_token::text from admin.worker_secrets where name = 'LLM_API_KEY'), (select v from tok where k = 'k1'), 'begin stores its token');

-- set with the same token → clean
select is(pg_temp.set_('LLM_API_KEY', (select v from tok where k = 'k1')), 'false', 'set with the matching token returns needs_resave = false');
select is(pg_temp.resave('LLM_API_KEY'), false, 'matching set clears the marker');
select is((select save_token from admin.worker_secrets where name = 'LLM_API_KEY'), null, 'set empties save_token');
select is((select updated_by from admin.worker_secrets where name = 'LLM_API_KEY'), 'dev@local.test', 'set records the actor');

-- list: hint + updated_by; ciphertext only for rows that are not sensitive
select is(pg_temp.as_admin($q$select hint || ' ' || updated_by || ' ' || (ciphertext is null)::text from admin.worker_secrets_list() where name = 'LLM_API_KEY'$q$),
  'ab12 dev@local.test true', 'list shows hint + actor, never the ciphertext of a sensitive row');
insert into tok select 'm1', pg_temp.begin_('LLM_MODEL', false);
select is(pg_temp.set_('LLM_MODEL', (select v from tok where k = 'm1'), null, false), 'false', 'set a row that is not sensitive');
select is(pg_temp.as_admin($q$select (ciphertext is not null and iv is not null)::text from admin.worker_secrets_list() where name = 'LLM_MODEL'$q$),
  'true', 'list returns ciphertext + iv of a row that is not sensitive');
select is(pg_temp.as_admin($q$select string_agg(name, ',' order by name) from admin.worker_secrets_list()$q$),
  'LLM_API_KEY,LLM_MODEL', 'list returns every row');

-- set twice → still one row; audited with hints only
insert into tok select 'k2', pg_temp.begin_('LLM_API_KEY');
select is(pg_temp.set_('LLM_API_KEY', (select v from tok where k = 'k2'), 'cd34'), 'false', 'second save');
select is((select count(*)::int from admin.worker_secrets where name = 'LLM_API_KEY'), 1, 'one row per name');
select is((select before->>'hint' || ' ' || (after->>'hint') || ' ' || (after->'workers'->>0) from admin.admin_audit
            where action = 'secret.set' and target = 'LLM_API_KEY' order by id desc limit 1),
  'ab12 cd34 shoo-ai', 'secret.set audits the old and new hint and the workers');
select is((select count(*)::int from admin.admin_audit where action like 'secret.%'
            and (coalesce(before, '{}') ?| array['ciphertext', 'iv', 'value'] or coalesce(after, '{}') ?| array['ciphertext', 'iv', 'value'])),
  0, 'no audit row carries ciphertext, iv or a value');
select is((select note from admin.admin_audit where action = 'secret.set' order by id desc limit 1), 'rotate', 'set keeps the admin note');

-- flag_resave without a row → marker row
select is(pg_temp.flag_('APNS_KEY_P8_B64'), '', 'flag_resave on a new name');
select is((select (ciphertext is null)::text || ' ' || needs_resave::text from admin.worker_secrets where name = 'APNS_KEY_P8_B64'),
  'true true', 'flag_resave without a row leaves a marker row');
select is((select count(*)::int from admin.admin_audit where action = 'secret.partial' and target = 'APNS_KEY_P8_B64'), 1, 'flag_resave is audited');
select throws_ok($q$insert into admin.worker_secrets (name, workers, sensitive, needs_resave, updated_by)
                    values ('X_NO_VALUE', '{shoo-ai}', true, false, 'dev@local.test')$q$,
  '23514', null, 'a row without ciphertext must need a resave');

-- flag_resave then a full save clears the marker
insert into tok select 'p1', pg_temp.begin_('APNS_KEY_P8_B64');
select is(pg_temp.set_('APNS_KEY_P8_B64', (select v from tok where k = 'p1')), 'false', 'flag_resave → begin → set clears the marker');

-- flag_resave and set always empty save_token
insert into tok select 'k3', pg_temp.begin_('LLM_API_KEY');
select pg_temp.flag_('LLM_API_KEY');
select is((select save_token from admin.worker_secrets where name = 'LLM_API_KEY'), null, 'flag_resave empties save_token');
select is(pg_temp.set_('LLM_API_KEY', (select v from tok where k = 'k3')), 'true', 'set after flag_resave keeps the marker');
select is((select save_token from admin.worker_secrets where name = 'LLM_API_KEY'), null, 'set empties save_token even on a mismatch');

-- a second begin while a token is still stored → stored token null
insert into tok select 'a0', pg_temp.begin_('RATE_KEY_SECRET');
insert into tok select 'b0', pg_temp.begin_('RATE_KEY_SECRET');
select is((select save_token from admin.worker_secrets where name = 'RATE_KEY_SECRET'), null, 'second begin while the first is open stores null');
select isnt((select v from tok where k = 'b0'), (select v from tok where k = 'a0'), 'each begin returns its own token');

-- (a) A begin, B begin, A PUT, B PUT, B set, A set → marker stays
select is(pg_temp.set_('RATE_KEY_SECRET', (select v from tok where k = 'b0')), 'true', '(a) B set after overlapping begins keeps the marker');
select is(pg_temp.set_('RATE_KEY_SECRET', (select v from tok where k = 'a0')), 'true', '(a) A set after B keeps the marker');
select is(pg_temp.resave('RATE_KEY_SECRET'), true, '(a) still needs a resave');

-- (b) B PUT, A PUT, A set, B set → marker stays
insert into tok select 'a1', pg_temp.begin_('SCREENSHOT_URL_SECRET');
insert into tok select 'b1', pg_temp.begin_('SCREENSHOT_URL_SECRET');
select is(pg_temp.set_('SCREENSHOT_URL_SECRET', (select v from tok where k = 'a1')), 'true', '(b) A set first keeps the marker');
select is(pg_temp.set_('SCREENSHOT_URL_SECRET', (select v from tok where k = 'b1')), 'true', '(b) B set second keeps the marker');

-- (c) A begin, B begin, B PUT w1, A PUT w1, A PUT w2 fails → flag_resave, B PUT w2, B set → marker stays
insert into tok select 'a2', pg_temp.begin_('OPS_STATUS_TOKEN');
insert into tok select 'b2', pg_temp.begin_('OPS_STATUS_TOKEN');
select pg_temp.flag_('OPS_STATUS_TOKEN');
select is(pg_temp.set_('OPS_STATUS_TOKEN', (select v from tok where k = 'b2')), 'true', '(c) B set after A flag_resave keeps the marker');
select is(pg_temp.resave('OPS_STATUS_TOKEN'), true, '(c) still needs a resave');

-- one clean save afterwards clears it
insert into tok select 'c3', pg_temp.begin_('OPS_STATUS_TOKEN');
select is(pg_temp.set_('OPS_STATUS_TOKEN', (select v from tok where k = 'c3')), 'false', 'a single resave after (c) clears the marker');

-- read: audited per purpose, no ciphertext in the audit
select is(pg_temp.as_admin($q$select (ciphertext is not null)::text || ' ' || key_version || ' ' || needs_resave::text
                                from admin.worker_secret_read('OPS_STATUS_TOKEN', 'reveal', 'dev@local.test')$q$),
  'true 1 false', 'read returns ciphertext, key_version and needs_resave');
select is((select count(*)::int from admin.admin_audit where action = 'secret.reveal' and target = 'OPS_STATUS_TOKEN'
            and before is null and after is null), 1, 'reveal is audited without the value');
select pg_temp.as_admin($q$select count(*)::text from admin.worker_secret_read('OPS_STATUS_TOKEN', 'check', 'dev@local.test')$q$);
select is((select count(*)::int from admin.admin_audit where action = 'secret.check' and target = 'OPS_STATUS_TOKEN'), 1, 'check is audited');
select is(pg_temp.as_admin($q$select count(*)::text from admin.worker_secret_read('NOT_SAVED_YET', 'reveal', 'dev@local.test')$q$),
  '0', 'read of a name without a row returns nothing');

-- APNs gate: once per 20 minutes per key id
select is(pg_temp.as_admin($q$select coalesce(admin.worker_secret_apns_gate('ABC123DEFG', 'dev@local.test')::text, 'null')$q$),
  'null', 'first APNs check is allowed');
select is((select count(*)::int from admin.admin_audit where action = 'secret.apns_check' and target = 'ABC123DEFG'), 1, 'allowed APNs check is audited');
select isnt(pg_temp.as_admin($q$select coalesce(admin.worker_secret_apns_gate('ABC123DEFG', 'dev@local.test')::text, 'null')$q$),
  'null', 'a second APNs check within 20 minutes returns the last time');
update admin.admin_audit set at = now() - interval '21 minutes' where action = 'secret.apns_check' and target = 'ABC123DEFG';
select is(pg_temp.as_admin($q$select coalesce(admin.worker_secret_apns_gate('ABC123DEFG', 'dev@local.test')::text, 'null')$q$),
  'null', 'after 20 minutes the check is allowed again');

-- bad input → SA009
select is(
  array[
    pg_temp.as_admin($q$select admin.worker_secret_apns_gate('abc', 'dev@local.test')::text$q$),
    pg_temp.as_admin($q$select count(*)::text from admin.worker_secret_read('LLM_API_KEY', 'dump', 'dev@local.test')$q$),
    pg_temp.as_admin($q$select admin.worker_secret_begin('LLM_API_KEY', '{shoo-xyz}', true, 'dev@local.test')::text$q$),
    pg_temp.as_admin($q$select admin.worker_secret_begin('LLM_API_KEY', '{}', true, 'dev@local.test')::text$q$),
    pg_temp.as_admin($q$select admin.worker_secret_begin('llm_api_key', '{shoo-ai}', true, 'dev@local.test')::text$q$),
    pg_temp.as_admin($q$select admin.worker_secret_begin('LLM_API_KEY', '{shoo-ai}', true, '')::text$q$),
    pg_temp.set_('LLM_API_KEY', (select v from tok where k = 'k3'), 'abcde'),
    pg_temp.set_('LLM_MODEL', (select v from tok where k = 'm1'), 'ab12', false),
    pg_temp.as_admin($q$select admin.worker_secret_set('LLM_API_KEY', '{shoo-ai}', '\x01'::bytea, '\x01'::bytea, 1, 'ab12', true,
                        gen_random_uuid(), 'dev@local.test', 'rotate')::text$q$),
    pg_temp.as_admin($q$select admin.worker_secret_set('LLM_API_KEY', '{shoo-ai}', '\x0102030405060708090a0b0c0d0e0f1011'::bytea,
                        '\x0102030405060708090a0b0c'::bytea, 1, 'ab12', true, null, 'dev@local.test', 'rotate')::text$q$),
    pg_temp.as_admin($q$select admin.worker_secret_set('LLM_API_KEY', '{shoo-ai}', '\x0102030405060708090a0b0c0d0e0f1011'::bytea,
                        '\x0102030405060708090a0b0c'::bytea, 1, 'ab12', true, gen_random_uuid(), 'dev@local.test', '')::text$q$)
  ],
  array_fill('ERR SA009'::text, array[11]),
  'bad key id, purpose, worker, empty workers, name, actor, hint > 4, hint on a plain row, iv length, null token, empty note → SA009');

select lives_ok($q$select pg_temp.as_admin('select admin.worker_secret_lock(''LLM_API_KEY'')')$q$, 'lock runs for shoo_admin');
select is(pg_temp.as_admin($q$select admin.worker_secret_lock('LLM_API_KEY')::text$q$), '', 'lock returns nothing');

select * from finish();
rollback;
