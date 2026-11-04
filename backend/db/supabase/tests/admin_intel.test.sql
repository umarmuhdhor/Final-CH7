-- ADM-02 admin dashboard: long-term domain data and learning labels (dashboard plan R2 objects 02a,
-- R4 §2; invariants I5, I6, I8, I9, I11 (single-session part), I13; backfill K7). The two-session
-- parts of I10/I11 are in backend/db/scripts/admin_intel_concurrency.sh.
create extension if not exists pgtap with schema extensions;

begin;
select plan(85);

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

create function pg_temp.labels(p_domain text) returns int language sql as $$
  select count(*)::int from admin.domain_labels where domain = p_domain
$$;

-- ---------------------------------------------------------------- objects

select has_table('admin', t, 'admin.' || t || ' exists')
from unnest(array['domain_intel', 'domain_intel_label', 'domain_labels', 'label_forget', 'domain_dirty',
                  'stats_daily', 'analysis_runs', 'intel_state']) as t;
select has_trigger('public', t, g, g || ' on public.' || t)
from (values ('scans', 'admin_scan_intel'), ('verdicts', 'admin_verdict_label'),
             ('devices', 'admin_device_forget'), ('family_links', 'admin_family_unlink')) as x(t, g);
-- C3 / Q18: nothing of ours fires when scans or verdicts are deleted (retention, cascades).
select is((select count(*)::int from pg_trigger
            where tgrelid in ('public.scans'::regclass, 'public.verdicts'::regclass)
              and tgname like 'admin\_%' and (tgtype & 8) <> 0),
  0, 'C3: no admin trigger on delete of scans or verdicts');
-- Every trigger function carries its own lock wait bound (K1).
select is((select count(*)::int from pg_proc
            where pronamespace = 'admin'::regnamespace
              and proname in ('on_scan_insert', 'on_verdict', 'on_device_delete', 'on_family_unlink')
              and proconfig @> array['lock_timeout=200ms'] and prosecdef),
  4, 'K1: four trigger functions, security definer, lock_timeout 200ms');
-- D1 / I13: no identity or page content in the long-term data or its views.
select hasnt_column('admin', t, c, 'admin.' || t || ' has no ' || c)
from unnest(array['domain_intel', 'v_domain_intel', 'v_labels']) as t
cross join unnest(array['url', 'page_title', 'owner_id', 'owner_ref', 'by_ref', 'by_device_id']) as c;
select is((select jsonb_object_agg(key, value) from admin.admin_config
            where key in ('analysis_interval_days', 'label_min_families_scam', 'label_min_families_safe',
                          'ignore_unconnected_guardian', 'export_min_families', 'export_enabled',
                          'uptime_check_minutes', 'ops_metrics_retention_days')),
  '{"analysis_interval_days": 3, "label_min_families_scam": 2, "label_min_families_safe": 2,
    "ignore_unconnected_guardian": true, "export_min_families": 2, "export_enabled": true,
    "uptime_check_minutes": 5, "ops_metrics_retention_days": 90}'::jsonb,
  '02a config defaults (R2 §5)');
select is((select backfilled_at is not null from admin.intel_state), true, 'K7: the migration ran the backfill');

-- ---------------------------------------------------------------- fixtures

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('t_g1', 'Guardian Satu', 'guardian',  'avatar_01', '\xb1'),
  ('t_g2', 'Guardian Dua',  'guardian',  'avatar_02', '\xb2'),
  ('t_gx', 'Guardian Lepas','guardian',  'avatar_03', '\xb3'),
  ('t_p1', 'Ibu',           'protected', 'avatar_04', '\xb4'),
  ('t_p2', 'Ayah',          'protected', 'avatar_05', '\xb5'),
  ('t_p3', 'Kakak',         'protected', 'avatar_06', '\xb6'),
  ('t_p4', 'Sendiri',       'protected', 'avatar_07', '\xb7');
insert into family_links (protected_id, guardian_id) values ('t_p1', 't_g1'), ('t_p2', 't_g1'), ('t_p3', 't_g2');

-- ---------------------------------------------------------------- K7 backfill (before the triggers saw anything)

alter table public.scans disable trigger admin_scan_intel;
alter table public.verdicts disable trigger admin_verdict_label;
insert into scans (id, owner_id, url, domain, score, status, signals, detected_at) values
  ('t_bf1', 't_p1', 'https://lama.test/a', 'lama.test', 85, 'blocked', '[{"id": "brand_mismatch"}, {"id": "new_domain"}]', now()),
  ('t_bf2', 't_p3', 'https://lama.test/b', 'lama.test', 40, 'warning', '[{"id": "new_domain"}]', now());
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p1', 'lama.test', 'not_safe', 't_bf1', 't_g1', 'Guardian Satu');
alter table public.scans enable trigger admin_scan_intel;
alter table public.verdicts enable trigger admin_verdict_label;
update admin.intel_state set intel_since = clock_timestamp(), backfilled_at = null;
select admin._backfill();
select admin._backfill();   -- idempotent
select is((select (scans, blocked, warning, max_score, sum_score, signal_counts)::text from admin.domain_intel where domain = 'lama.test'),
  '(2,1,1,85,125,"{""new_domain"": 2, ""brand_mismatch"": 1}")', 'K7: backfill counts old scans once, run twice');
select is((select (is_scam, connected, ai_score, ai_status, analyzed_at is null)::text from admin.domain_labels where domain = 'lama.test'),
  '(t,t,85,blocked,t)', 'K7: backfill adds a locked label for an old verdict');

-- ---------------------------------------------------------------- scan trigger

insert into scans (id, owner_id, url, domain, page_title, score, status, signals, detected_at) values
  ('t_s1', 't_p1', 'https://penipu.test/login?u=ibu', 'penipu.test', 'Login Ibu', 92, 'blocked',
   '[{"id": "brand_mismatch", "evidence": "BCA"}, {"id": "otp_form"}]', now());
select is((select (scans, blocked, warning, max_score, sum_score, signal_counts)::text from admin.domain_intel where domain = 'penipu.test'),
  '(1,1,0,92,92,"{""otp_form"": 1, ""brand_mismatch"": 1}")', 'scan insert creates domain_intel');
insert into scans (id, owner_id, url, domain, score, status, signals, detected_at) values
  ('t_s2', 't_p3', 'https://penipu.test/x', 'penipu.test', 60, 'warning', '[{"id": "otp_form"}, "not-an-object"]', now()),
  ('t_s3', 't_p2', 'https://penipu.test/y', 'penipu.test', 95, 'blocked', '[]', now());
select is((select (scans, blocked, warning, max_score, sum_score, signal_counts)::text from admin.domain_intel where domain = 'penipu.test'),
  '(3,2,1,95,247,"{""otp_form"": 2, ""brand_mismatch"": 1}")', 'second and third scan: counters, max and signals merged');
select is((select avg_score from admin.v_domain_intel where domain = 'penipu.test'), 82, 'v_domain_intel avg_score = sum / scans');
select is((select signal_counts::text from admin.domain_intel where domain = 'penipu.test') like '%BCA%', false,
  'D1: signal evidence never reaches domain_intel');

-- Signal ids come from the client: only contract-style ids are counted, and a domain takes new ids
-- only while it has fewer than 64.
insert into scans (id, owner_id, url, domain, score, status, signals, detected_at) values
  ('t_sj', 't_p2', 'https://sampah.test/', 'sampah.test', 50, 'warning',
   '[{"id": "Bad Id"}, {"id": "x;drop"}, {"id": "asks_otp"}]', now());
select is((select signal_counts::text from admin.domain_intel where domain = 'sampah.test'), '{"asks_otp": 1}',
  'only snake_case signal ids are counted');
update admin.domain_intel set signal_counts = (select jsonb_object_agg('s' || g, 1) from generate_series(1, 64) g)
 where domain = 'sampah.test';
insert into scans (id, owner_id, url, domain, score, status, signals, detected_at) values
  ('t_sk', 't_p2', 'https://sampah.test/', 'sampah.test', 50, 'warning', '[{"id": "s1"}, {"id": "baru"}]', now());
select is((select (signal_counts ->> 's1', signal_counts ? 'baru', (select count(*) from jsonb_object_keys(signal_counts)))::text
             from admin.domain_intel where domain = 'sampah.test'),
  '(2,f,64)', 'a domain with 64 ids keeps counting them but takes no new one');

-- Retention (Q18): deleting scans changes nothing in domain_intel.
delete from scans where id = 't_s3';
select is((select scans from admin.domain_intel where domain = 'penipu.test'), 3::bigint, 'Q18: retention delete keeps domain_intel');

-- ---------------------------------------------------------------- verdict trigger (R4 §2)

insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p1', 'penipu.test', 'not_safe', 't_s1', 't_g1', 'Guardian Satu');
select is((select (is_scam, source, connected, ai_score, ai_status, analyzed_at is null, owner_ref ~ '^[0-9a-f]{16}$', by_ref <> owner_ref)::text
             from admin.domain_labels where domain = 'penipu.test'),
  '(t,guardian,t,92,blocked,t,t,t)', 'new not_safe verdict: one locked label with keyed refs and AI snapshot');
select is((select owner_ref from admin.domain_labels where domain = 'penipu.test'), admin.owner_ref('t_p1'),
  'K2: owner_ref = keyed hash of the device id');

-- I6: locked label does not follow the live verdict; the verdict itself changes.
update verdicts set value = 'safe' where owner_id = 't_p1' and domain = 'penipu.test';
select is(pg_temp.labels('penipu.test'), 1, 'I6: change before analysis adds no row');
select is((select is_scam from admin.domain_labels where domain = 'penipu.test'), true, 'I6: the locked label keeps its value');
select is((select value::text from verdicts where owner_id = 't_p1' and domain = 'penipu.test'), 'safe', 'the live verdict did change');
update verdicts set value = 'not_safe' where owner_id = 't_p1' and domain = 'penipu.test';

-- After analysis: a different value is a revision, the same value (upsert) is nothing (C2).
select admin.run_analysis('manual', 'test@local');
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p1', 'penipu.test', 'not_safe', 't_s1', 't_g1', 'Guardian Satu')
  on conflict (owner_id, domain) do update set value = excluded.value, decided_at = clock_timestamp();
select is(pg_temp.labels('penipu.test'), 1, 'C2: upsert with the same value adds no row');
update verdicts set value = 'safe' where owner_id = 't_p1' and domain = 'penipu.test';
select is((select (is_scam, analyzed_at is null, revision_of is not null)::text from admin.domain_labels
            where domain = 'penipu.test' order by id desc limit 1),
  '(f,t,t)', 'after analysis a changed decision is a new locked row with revision_of');
select is(pg_temp.labels('penipu.test'), 2, 'two rows for one slot');

-- connected (R4 §2 rule 7, D-dash-06): unlinked guardian false, own decision true.
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('t_s4', 't_p4', 'https://lepas.test/', 'lepas.test', 70, 'warning', now()),
  ('t_s5', 't_p4', 'https://sendiri.test/', 'sendiri.test', 70, 'warning', now());
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p4', 'lepas.test', 'not_safe', 't_s4', 't_gx', 'Guardian Lepas'),
  ('t_p4', 'sendiri.test', 'not_safe', 't_s5', 't_p4', 'Sendiri');
select is((select connected from admin.domain_labels where domain = 'lepas.test'), false, 'unlinked guardian: connected = false');
select is((select connected from admin.domain_labels where domain = 'sendiri.test'), true, 'own decision: connected = true');

-- A verdict whose scan is already gone: label without AI snapshot.
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p2', 'tanpa-scan.test', 'not_safe', null, 't_g1', 'Guardian Satu');
select is((select (ai_score is null and ai_status is null)::text from admin.domain_labels where domain = 'tanpa-scan.test'),
  'true', 'scan gone: label kept without AI snapshot');

-- ---------------------------------------------------------------- I9 disconnect, I8 device delete

insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('t_s6', 't_p3', 'https://dua.test/', 'dua.test', 88, 'blocked', now()),
  ('t_s7', 't_p1', 'https://dua.test/', 'dua.test', 88, 'blocked', now());
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p3', 'dua.test', 'not_safe', 't_s6', 't_g2', 'Guardian Dua'),
  ('t_p1', 'dua.test', 'not_safe', 't_s7', 't_g1', 'Guardian Satu');
delete from family_links where protected_id = 't_p3';
select is((select count(*)::int from admin.domain_labels where owner_ref = admin.owner_ref('t_p3')), 0,
  'I9: disconnect deletes the labels of that pair');
select is((select count(*)::int from admin.domain_labels where domain = 'dua.test'), 1, 'I9: labels of other families stay');
select ok(exists (select 1 from admin.domain_dirty where domain = 'dua.test'), 'a deleted label marks its domain for the next analysis');

select is((select scans from admin.domain_intel where domain = 'penipu.test'), 3::bigint, 'domain_intel before device delete');
delete from devices where id = 't_p1';
select is((select count(*)::int from admin.domain_labels where owner_ref = admin.owner_ref('t_p1')), 0,
  'I8: device delete removes its labels as owner');
select is((select scans from admin.domain_intel where domain = 'penipu.test'), 3::bigint, 'I8: domain_intel unchanged after device delete (scans cascaded)');
delete from devices where id = 't_g1';
select is((select count(*)::int from admin.domain_labels where by_ref = admin.owner_ref('t_g1')), 0,
  'I8: device delete removes labels it decided as Guardian');

-- ---------------------------------------------------------------- I11 (single session): label_forget

insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('t_s8', 't_p4', 'https://lupa.test/', 'lupa.test', 81, 'blocked', now());
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p4', 'lupa.test', 'not_safe', 't_s8', 't_gx', 'Guardian Lepas');
insert into admin.label_forget (owner_ref, by_ref) values (admin.owner_ref('t_p4'), admin.owner_ref('t_gx'));
select is(pg_temp.as_admin($$select count(*)::text from admin.v_labels where domain = 'lupa.test'$$), '0',
  'I11: a label in label_forget is hidden from v_labels at once');
select is(pg_temp.as_admin($$select count(*)::text from admin.v_feed where kind = 'label' and target = 'lupa.test'$$), '0',
  'I11: and from v_feed');
select is(pg_temp.labels('lupa.test'), 1, 'I11: still physically there before snapshot_daily');
select is(pg_temp.as_admin($$select (admin.snapshot_daily() ->> 'ok')$$), 'true', 'snapshot_daily runs as shoo_admin');
select is(pg_temp.labels('lupa.test'), 0, 'I11: snapshot_daily deletes it');
select is((select count(*)::int from admin.label_forget), 0, 'I11: forget queue emptied');
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p4', 'lupa-lagi.test', 'safe', null, 't_gx', 'Guardian Lepas');
select is(pg_temp.labels('lupa-lagi.test'), 1, 'I11: a label made after the forget entry stays');

-- ---------------------------------------------------------------- stats_daily

select is(pg_temp.as_admin($$select string_agg(metric || ':' || key || '=' || value, ',' order by metric, key) from admin.v_stats_daily$$),
          (select string_agg(metric || ':' || key || '=' || value, ',' order by metric, key) from admin.stats_daily where metric not like '%\_total'),
  'v_stats_daily = stats_daily without running totals');
create temp table snap1 as select metric, key, value from admin.stats_daily;
select admin.snapshot_daily();
select is((select count(*)::int from (select * from snap1 except select metric, key, value from admin.stats_daily) x), 0,
  'snapshot_daily twice on one day gives the same numbers');
select ok((select value > 0 from admin.stats_daily where metric = 'scans_total' and key = 'blocked'), 'stats: running total of blocked scans');

-- ---------------------------------------------------------------- v_domain_intel blocklist status (read, not stored)

insert into blocklist_entries (domain, families, approved_at, approved_by) values ('penipu.test', 1, now(), 'a@test');
select is((select blocklist_status from admin.v_domain_intel where domain = 'penipu.test'), 'approved', 'blocklist status read live');
select admin.remove_domain('penipu.test', 'uji status hapus', 'a@test');
select is((select blocklist_status from admin.v_domain_intel where domain = 'penipu.test'), 'removed',
  'blocklist status follows remove_domain without an analysis');

-- ---------------------------------------------------------------- I5: a failing trigger never fails the backend

-- Real failures inside the real functions (a constraint the trigger's write cannot meet).
alter table admin.domain_intel add constraint t_fail check (scans < 0) not valid;
select lives_ok($$insert into scans (id, owner_id, url, domain, score, status, detected_at)
                  values ('t_s9', 't_p4', 'https://gagal.test/', 'gagal.test', 50, 'warning', now())$$,
  'I5: scan insert succeeds when the scan trigger fails');
select is((select count(*)::int from admin.domain_intel where domain = 'gagal.test'), 0, 'I5: the failed count is lost, not the scan');
alter table admin.domain_intel drop constraint t_fail;

alter table admin.domain_labels add constraint t_fail check (false) not valid;
select lives_ok($$insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
                  values ('t_p4', 'gagal.test', 'not_safe', 't_s9', 't_gx', 'Guardian Lepas')$$,
  'I5: verdict insert succeeds when the verdict trigger fails');
select lives_ok($$update verdicts set value = 'safe' where owner_id = 't_p4' and domain = 'gagal.test'$$,
  'I5: verdict update succeeds when the verdict trigger fails');
alter table admin.domain_labels drop constraint t_fail;

create function pg_temp.boom() returns trigger language plpgsql as $$ begin raise exception 'boom'; end $$;
create trigger t_boom before delete on admin.domain_labels for each row execute function pg_temp.boom();
insert into family_links (protected_id, guardian_id) values ('t_p2', 't_g2');
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_p2', 'hapus.test', 'not_safe', null, 't_g2', 'Guardian Dua'),
  ('t_p2', 'hapus-2.test', 'not_safe', null, 't_p2', 'Ayah');
select lives_ok($$delete from family_links where protected_id = 't_p2'$$, 'I5: disconnect succeeds when the unlink trigger fails');
select lives_ok($$delete from devices where id = 't_p2'$$, 'I5: device delete succeeds when the forget trigger fails');
drop trigger t_boom on admin.domain_labels;

-- ---------------------------------------------------------------- shoo_admin reads the views, not the tables

select unalike(pg_temp.as_admin(format('select count(*)::text from admin.%I', v)), 'ERR%', 'shoo_admin can read admin.' || v)
from unnest(array['v_domain_intel', 'v_labels', 'v_analysis_runs', 'v_stats_daily']) as v;
select is(pg_temp.as_admin('select count(*)::text from admin.domain_labels'),
  'ERR 42501 permission denied for table domain_labels', 'shoo_admin cannot read domain_labels directly');
select is(pg_temp.as_admin($$select admin.owner_ref('x')$$),
  'ERR 42501 permission denied for function owner_ref', 'shoo_admin cannot compute owner_ref');

select * from finish();
rollback;
