-- ADM-01 admin dashboard: role, tables, views and functions of schema `admin` (01a objects of the
-- dashboard plan R2 §1–§5; invariants I1, I3, I4, I7, I13). Error codes: SA0xx (R2 §4).
create extension if not exists pgtap with schema extensions;

begin;
select plan(97);

-- Runs one SELECT as shoo_admin and returns its first column, or 'ERR <sqlstate> <message>'.
-- pgTAP's own temp tables belong to postgres, so the role switch stays inside this function; the
-- exception block rolls the failed statement and the role change back together.
create function pg_temp.as_admin(q text) returns text language plpgsql as $$
declare
  out text;
begin
  set local role shoo_admin;
  execute q into out;
  reset role;
  return coalesce(out, '');
exception when others then
  return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $$;

-- ---------------------------------------------------------------- role

select has_role('shoo_admin', 'role shoo_admin exists');
select ok(rolcanlogin and not rolinherit and not rolbypassrls and not rolsuper and not rolcreaterole and rolconnlimit = 5,
  'shoo_admin: login, noinherit, nobypassrls, connection limit 5')
from pg_roles where rolname = 'shoo_admin';
select ok((select setconfig @> array['statement_timeout=5s', 'search_path=admin']
           from pg_db_role_setting where setrole = 'shoo_admin'::regrole and setdatabase = 0),
  'shoo_admin: statement_timeout 5s, search_path admin');
select ok(pg_has_role('postgres', 'shoo_admin', 'SET'), 'C8: postgres can set role shoo_admin');
select ok(not rolcreatedb and not rolreplication, 'shoo_admin: nocreatedb, noreplication')
from pg_roles where rolname = 'shoo_admin';
select is((select count(*)::int from pg_auth_members where member = 'shoo_admin'::regrole), 0,
  'shoo_admin is a member of no role');

-- ---------------------------------------------------------------- tables (01a; 02a objects in admin_intel.test.sql)

select has_table('admin', t, 'admin.' || t || ' exists')
from unnest(array['secrets', 'admin_config', 'admin_audit', 'categories', 'review_decisions']) as t;
select is((select count(*)::int from admin.categories where active), 8, 'eight active categories');
select ok((select value ~ '^[0-9a-f]{64}$' from admin.secrets where key = 'owner_ref_salt'), 'owner_ref_salt is 32 random bytes');
select is((select jsonb_object_agg(key, value) from admin.admin_config
            where key in ('replica_enabled', 'replica_min_families', 'max_publish_per_day',
                          'require_admin_note_locked', 'require_admin_note')),
  '{"replica_enabled": false, "replica_min_families": 2, "max_publish_per_day": 50,
    "require_admin_note_locked": true, "require_admin_note": true}'::jsonb,
  '01a config defaults (R2 §5)');

-- ---------------------------------------------------------------- fixtures

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('t_g1', 'Guardian Satu', 'guardian',  'avatar_01', '\xa1'),
  ('t_g2', 'Guardian Dua',  'guardian',  'avatar_02', '\xa2'),
  ('t_p1', 'Ibu',           'protected', 'avatar_03', '\xa3'),
  ('t_p2', 'Ayah',          'protected', 'avatar_04', '\xa4'),
  ('t_p3', 'Lepas',         'protected', 'avatar_05', '\xa5');
insert into family_links (protected_id, guardian_id) values ('t_p1', 't_g1'), ('t_p2', 't_g2');

insert into scans (id, owner_id, url, domain, page_title, score, status, signals, detected_at, replica_path, replica_bytes) values
  ('t_s1', 't_p1', 'https://u:pw@x-two.test/login?token=abc#frag', 'x-two.test', 'Judul rahasia', 85, 'blocked',
   '[{"id":"new_domain","evidence":"teks halaman rahasia"},{"id":"asks_password"}]', now() - interval '1 hour',
   't_p1/t_s1-replica.html.gz', 100),
  ('t_s2', 't_p2', 'https://x-two.test/b', 'x-two.test', null, 60, 'warning', '[{"id":"new_domain"}]',
   now() - interval '30 minutes', 't_p2/t_s2-replica.html.gz', 100),
  ('t_s5', 't_p1', 'https://u:p?w@x-two.test/', 'x-two.test', null, 40, 'warning', '[]', now() - interval '2 hours', null, null),
  ('t_s6', 't_p1', 'HTTPS://user:pw@x-two.test/a', 'x-two.test', null, 40, 'warning', '[]', now() - interval '2 hours', null, null),
  ('t_s7', 't_p1', 'https://a:b@c@x-two.test/x', 'x-two.test', null, 40, 'warning', '[]', now() - interval '2 hours', null, null),
  ('t_s8', 't_p1', 'https://a-very-long-subdomain-name.x-two.test/reset/AbCdEf0123456789xyz/order/12345678/u/ibu@mail.test/ok',
   'x-two.test', null, 40, 'warning', '[]', now() - interval '2 hours', null, null),
  ('t_s3', 't_p1', 'https://x-solo.test/', 'x-solo.test', null, 50, 'warning', '[]', now(), 't_p1/t_s3-replica.html.gz', 100),
  ('t_s4', 't_p3', 'https://x-gone.test/', 'x-gone.test', null, 50, 'warning', '[]', now(), 't_p3/t_s4-replica.html.gz', 100);
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name, global_eligible) values
  ('t_p1', 'x-two.test',  'not_safe', 't_s1', 't_g1', 'Guardian Satu', true),
  ('t_p2', 'x-two.test',  'not_safe', 't_s2', 't_g2', 'Guardian Dua',  true),
  ('t_p1', 'x-solo.test', 'not_safe', 't_s3', 't_g1', 'Guardian Satu', true),
  ('t_p1', 'x-gone.test', 'not_safe', null,   't_g1', 'Guardian Satu', true),
  ('t_p2', 'x-gone.test', 'not_safe', null,   't_g2', 'Guardian Dua',  true);
insert into blocklist_entries (domain, families) values
  ('x-two.test', 2), ('x-solo.test', 1), ('x-gone.test', 2), ('x-one.test', 1), ('x-rej.test', 1), ('x-cap.test', 1);
insert into blocklist_entries (domain, families, approved_at, approved_by) values ('x-app.test', 1, now(), 'seed');

-- ---------------------------------------------------------------- views (I13, D1)

select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'admin' and column_name in ('owner_id', 'owner_ref', 'by_ref', 'by_device_id', 'by_name', 'page_title', 'url', 'signals', 'replica_path')
      and table_name in (select table_name from information_schema.views where table_schema = 'admin')),
  0, 'I13: no admin view exposes owner, guardian name, title, raw URL, signals or replica path');
select columns_are('admin', 'v_scans',
  array['id', 'domain', 'url_masked', 'score', 'status', 'signal_ids', 'detected_at', 'has_replica', 'verdict'],
  'v_scans columns (D-dash-07)');
select is((select url_masked from admin.v_scans where id = 't_s1'), 'https://x-two.test/login',
  'v_scans.url_masked drops userinfo, query and fragment');
select is((select url_masked from admin.v_scans where id = 't_s5'), 'https://x-two.test/',
  'userinfo containing ? is removed before the query');
select is((select url_masked from admin.v_scans where id = 't_s6'), 'HTTPS://x-two.test/a', 'userinfo removed in any case');
select is((select url_masked from admin.v_scans where id = 't_s7'), 'https://x-two.test/x', 'userinfo with two @ removed');
select is((select url_masked from admin.v_scans where id = 't_s8'),
  'https://a-very-long-subdomain-name.x-two.test/reset/…/order/…/u/…/ok',
  'path segments with tokens, long numbers or emails are masked; the host is kept');
select is((select signal_ids from admin.v_scans where id = 't_s1'), array['new_domain', 'asks_password'],
  'v_scans.signal_ids holds ids only');
select ok(not exists (select 1 from admin.v_scans v where v::text like '%rahasia%'),
  'v_scans carries no evidence or page title text');
select is((select verdict from admin.v_scans where id = 't_s1'), 'not_safe', 'v_scans.verdict is the value only');

select is((select families_not_safe from admin.v_review_queue where domain = 'x-two.test'),
  (select families from blocklist_entries where domain = 'x-two.test'),
  'C5: families_not_safe matches blocklist_entries.families (recountFamilies)');
select is((select scans_14d from admin.v_review_queue where domain = 'x-two.test'), 6, 'v_review_queue.scans_14d');
select is((select top_signals from admin.v_review_queue where domain = 'x-two.test'), array['new_domain', 'asks_password'],
  'v_review_queue.top_signals ordered by frequency');
select ok(not exists (select 1 from admin.v_review_queue where domain = 'x-app.test'), 'approved domains are not queued');
select ok(not (select has_replica from admin.v_review_queue where domain = 'x-two.test'),
  'has_replica false while replica_enabled = false');
select is((select status from admin.v_blocklist where domain = 'x-app.test'), 'approved', 'v_blocklist status');
select is((select count(*)::int from admin.v_config where key = 'require_admin_note_locked'), 0, 'v_config hides internal keys');
select ok((select db_bytes > 0 and jsonb_array_length(top_tables) > 0 from admin.v_ops_snapshot),
  'C7: v_ops_snapshot reads database and table sizes');

-- Every view is readable by shoo_admin; backend tables are not (I1).
select unalike(pg_temp.as_admin(format('select count(*)::text from admin.%I', v)), 'ERR%', 'shoo_admin can read admin.' || v)
from unnest(array['v_review_queue', 'v_blocklist', 'v_scans', 'v_ops_snapshot',
                  'v_audit', 'v_config', 'v_categories', 'v_feed']) as v;
select is(pg_temp.as_admin('select count(*)::text from public.scans'), 'ERR 42501 permission denied for table scans',
  'I1: shoo_admin cannot read public.scans');
select is(pg_temp.as_admin('select count(*)::text from admin.admin_audit'), 'ERR 42501 permission denied for table admin_audit',
  'shoo_admin cannot read admin tables directly');

-- ---------------------------------------------------------------- vote (I4)

select is(pg_temp.as_admin($$select admin.vote('x-one.test', 'approve', 'judi', 'catatan sepuluh+', 'a@test')$$), '',
  'vote approve');
select ok((select approved_at is not null and approved_by = 'a@test' from blocklist_entries where domain = 'x-one.test'),
  'approve sets approved_at/by');
select is(pg_temp.as_admin($$select admin.vote('x-one.test', 'reject', null, 'catatan sepuluh+', 'b@test')$$),
  'ERR SA001 already_decided', 'I4: a second vote on the same domain fails');
select is((select count(*)::int from admin.review_decisions where domain = 'x-one.test'), 1, 'one decision row per accepted vote');
select ok(exists (select 1 from admin.admin_audit where action = 'blocklist.approve' and target = 'x-one.test' and actor = 'a@test'),
  'vote writes admin_audit');
select is(pg_temp.as_admin($$select admin.vote('x-none.test', 'approve', 'judi', 'catatan sepuluh+', 'a@test')$$),
  'ERR SA002 not_found', 'vote on an unknown domain');
select is(pg_temp.as_admin($$select admin.vote('x-two.test', 'approve', 'judi', 'pendek', 'a@test')$$),
  'ERR SA003 note_required', 'note shorter than 10 characters');
select is(pg_temp.as_admin($$select admin.vote('x-two.test', 'approve', null, 'catatan sepuluh+', 'a@test')$$),
  'ERR SA004 category_unknown', 'approve needs a category');
select is(pg_temp.as_admin($$select admin.vote('x-two.test', 'approve', 'bukan_kategori', 'catatan sepuluh+', 'a@test')$$),
  'ERR SA004 category_unknown', 'unknown category');
select is(pg_temp.as_admin($$select admin.vote('www.x-two.test', 'approve', 'judi', 'catatan sepuluh+', 'a@test')$$),
  'ERR SA014 invalid_domain', 'www. domain refused');
select is(pg_temp.as_admin($$select admin.vote('x-rej.test', 'reject', null, 'bukan penipuan', 'a@test')$$), '', 'vote reject');
select is((select status from admin.v_blocklist where domain = 'x-rej.test'), 'rejected', 'reject sets rejected state');
select is((select last_action from admin.v_blocklist where domain = 'x-rej.test'), 'reject', 'v_blocklist shows the last decision');

-- ---------------------------------------------------------------- unreject, remove_domain

select is(pg_temp.as_admin($$select admin.unreject('x-rej.test', 'ternyata perlu dicek', 'a@test')$$), '', 'unreject');
select is((select status from admin.v_blocklist where domain = 'x-rej.test'), 'pending', 'unreject returns the domain to the queue');
select is(pg_temp.as_admin($$select admin.unreject('x-two.test', 'ternyata perlu dicek', 'a@test')$$),
  'ERR SA006 not_rejected', 'unreject needs a rejected domain');
select is(pg_temp.as_admin($$select admin.remove_domain('x-app.test', 'salah blokir domain', 'a@test')$$), '', 'remove_domain');
select ok((select removed_at is not null from blocklist_entries where domain = 'x-app.test'), 'remove sets removed_at');
select is(pg_temp.as_admin($$select admin.remove_domain('x-two.test', 'salah blokir domain', 'a@test')$$),
  'ERR SA007 not_approved', 'remove needs an approved domain');

-- ---------------------------------------------------------------- add_domain

select is(pg_temp.as_admin($$select admin.add_domain('x-new.test', 'judi', 'laporan langsung', 'a@test')$$), '', 'add_domain');
select ok((select approved_at > now() and families = 0 from blocklist_entries where domain = 'x-new.test'),
  'add_domain uses clock_timestamp(), not the transaction start');
create temp table t_before as select approved_at from blocklist_entries where domain = 'x-new.test';
select is(pg_temp.as_admin($$select admin.add_domain('x-new.test', 'judi', 'laporan langsung', 'a@test')$$),
  'ERR SA005 already_approved', 'add_domain on an approved domain');
select is((select approved_at from blocklist_entries where domain = 'x-new.test'), (select approved_at from t_before),
  'already_approved leaves approved_at unchanged');
select is(pg_temp.as_admin($$select admin.add_domain('x-app.test', 'judi', 'ternyata memang scam', 'a@test')$$), '',
  'add_domain re-approves a removed domain');
select ok((select removed_at is null and approved_at > now() from blocklist_entries where domain = 'x-app.test'),
  're-approval clears removed_at with a fresh approved_at');
select is(pg_temp.as_admin($$select admin.add_domain('bad..domain', 'judi', 'laporan langsung', 'a@test')$$),
  'ERR SA014 invalid_domain', 'add_domain validates the domain');

-- ---------------------------------------------------------------- replica_for (D-dash-07/08)

select is(pg_temp.as_admin($$select admin.replica_for('x-two.test')$$), 'ERR SA016 replica_disabled',
  'replica_for refused while replica_enabled = false');
select is(pg_temp.as_admin($$select admin.set_config('replica_enabled', 'true', 'a@test', 'privasi sudah siap')$$),
  'ERR SA011 confirm_required', 'enabling replicas needs confirm');
select is(pg_temp.as_admin($$select admin.set_config('replica_enabled', 'true', 'a@test', 'privasi sudah siap', 'true')$$), '',
  'enabling replicas with confirm');
select is(pg_temp.as_admin($$select admin.replica_for('x-solo.test')$$), 'ERR SA015 replica_locked',
  'I13: one reporting family is not enough');
select is(pg_temp.as_admin($$select admin.replica_for('x-two.test')$$), 't_p2/t_s2-replica.html.gz',
  'replica_for returns the newest connected replica');
select is(pg_temp.as_admin($$select admin.replica_for('x-gone.test')$$), 'ERR SA008 not_in_queue',
  'replica of a disconnected owner is not reachable');
select is(pg_temp.as_admin($$select admin.replica_for('x-one.test')$$), 'ERR SA008 not_in_queue',
  'replica_for only serves queued domains');
select ok((select has_replica from admin.v_review_queue where domain = 'x-two.test')
  and not (select has_replica from admin.v_review_queue where domain = 'x-solo.test')
  and not (select has_replica from admin.v_review_queue where domain = 'x-gone.test'),
  'has_replica is true exactly when replica_for succeeds');

-- ---------------------------------------------------------------- set_config (I7)

select is(pg_temp.as_admin($$select admin.set_config('replica_min_families', '1', 'a@test', 'coba satu keluarga')$$),
  'ERR SA009 config_invalid', 'replica_min_families cannot be 1');
select is(pg_temp.as_admin($$select admin.set_config('replica_min_families', '3', 'a@test', 'lebih ketat dulu')$$), '',
  'raising replica_min_families needs no confirm');
select is(pg_temp.as_admin($$select admin.set_config('replica_min_families', '2', 'a@test', 'kembali ke dua')$$),
  'ERR SA011 confirm_required', 'lowering replica_min_families needs confirm');
select is(pg_temp.as_admin($$select admin.set_config('replica_min_families', '2', 'a@test', 'kembali ke dua', '2')$$), '',
  'lowering with confirm');
select ok(exists (select 1 from admin.admin_audit where action = 'config.set' and target = 'replica_min_families'
                    and before = '{"value": 3}' and after = '{"value": 2}'),
  'set_config writes before/after to admin_audit');
select is(pg_temp.as_admin($$select admin.set_config('require_admin_note', 'false', 'a@test', 'catatan tidak wajib')$$),
  'ERR SA009 config_invalid', 'I7: require_admin_note stays true while locked');
select is(pg_temp.as_admin($$select admin.set_config('require_admin_note_locked', 'false', 'a@test', 'buka kunci catatan')$$),
  'ERR SA010 config_unknown', 'internal keys cannot be set');
select is(pg_temp.as_admin($$select admin.set_config('tidak_ada', '1', 'a@test', 'key tidak dikenal')$$),
  'ERR SA010 config_unknown', 'unknown key');
select is(pg_temp.as_admin($$select admin.set_config('max_publish_per_day', '201', 'a@test', 'batas terlalu tinggi')$$),
  'ERR SA009 config_invalid', 'max_publish_per_day above 200');
select is(pg_temp.as_admin($$select admin.set_config('max_publish_per_day', 'lima', 'a@test', 'bukan angka sama sekali')$$),
  'ERR SA009 config_invalid', 'non-numeric value');
select is(pg_temp.as_admin($$select admin.set_config('max_publish_per_day', '60', 'a@test', 'butuh lebih banyak')$$),
  'ERR SA011 confirm_required', 'raising the publish cap needs confirm');
select is(pg_temp.as_admin($$select admin.set_config('max_publish_per_day', '40', 'a@test', 'lebih ketat saja')$$), '',
  'lowering the publish cap needs no confirm');
select is(pg_temp.as_admin(format($f$select admin.vote('x-two.test', 'reject', null, %L, 'a@test')$f$, repeat('x', 1001))),
  'ERR SA003 note_required', 'a note over 1000 characters is refused with SA003');

-- ---------------------------------------------------------------- log_audit, feed, I3

select is(pg_temp.as_admin($$select admin.log_audit('a@test', 'replica.open', 'x-two.test', null)$$), '', 'log_audit');
select is(pg_temp.as_admin($$select admin.log_audit('a@test', 'blocklist.approve', 'x-two.test', null)$$),
  'ERR 22023 invalid_action', 'log_audit cannot forge decision or config entries');
select ok((select count(*) from admin.v_feed where kind = 'decision') = (select count(*) from admin.review_decisions)
  and exists (select 1 from admin.v_feed where kind = 'audit' and action = 'replica.open')
  and not exists (select 1 from admin.v_feed where kind = 'audit' and action like 'blocklist.%'),
  'v_feed: every decision once plus the non-decision audit entries');
select is(pg_temp.as_admin('with d as (update admin.admin_audit set note = null returning 1) select count(*)::text from d'),
  'ERR 42501 permission denied for table admin_audit', 'I3: shoo_admin cannot update admin_audit');
select is(pg_temp.as_admin('with d as (delete from admin.admin_audit returning 1) select count(*)::text from d'),
  'ERR 42501 permission denied for table admin_audit', 'I3: shoo_admin cannot delete admin_audit');

-- ---------------------------------------------------------------- publish cap (K7)

insert into admin.review_decisions (domain, action, category, note, actor)
select 'x-filler-' || g || '.test', 'approve', 'judi', 'pengisi batas harian', 'seed'
from generate_series(1, 40 - (select count(*)::int from admin.review_decisions
                              where action in ('approve', 'add') and at > now() - interval '24 hours')) g;
select is(pg_temp.as_admin($$select admin.vote('x-cap.test', 'approve', 'judi', 'catatan sepuluh+', 'a@test')$$),
  'ERR SA013 publish_cap', 'K7: the approval past max_publish_per_day within 24 h is refused');
select is(pg_temp.as_admin($$select admin.add_domain('x-cap2.test', 'judi', 'laporan langsung', 'a@test')$$),
  'ERR SA013 publish_cap', 'K7: manual adds count toward the cap');
select is(pg_temp.as_admin($$select admin.vote('x-cap.test', 'reject', null, 'bukan penipuan', 'a@test')$$), '',
  'rejects are not capped');

select * from finish();
rollback;
