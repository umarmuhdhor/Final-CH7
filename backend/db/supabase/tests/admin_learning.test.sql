-- ADM-04 admin dashboard: learning tables, evaluation views and stored thresholds (dashboard plan
-- fase 04a K1–K5, R2 objects labelled 04a, R4 §3 step 6 and §4; invariants I7, I12).
create extension if not exists pgtap with schema extensions;

begin;
select plan(97);

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

-- A Guardian label as the trigger writes it; analyzed unless p_locked. p_age backdates it.
create function pg_temp.lab(p_domain text, p_owner text, p_by text, p_scam boolean, p_score int, p_status text,
                            p_locked boolean default false, p_age interval default '0')
returns void language sql as $$
  insert into admin.domain_labels (domain, is_scam, source, connected, ai_score, ai_status, owner_ref, by_ref, created_at, analyzed_at)
  values (p_domain, p_scam, 'guardian', true, p_score, p_status, admin.owner_ref(p_owner), admin.owner_ref(p_by),
          clock_timestamp() - p_age, case when not p_locked then now() end)
$$;

create function pg_temp.admin_lab(p_domain text, p_scam boolean, p_category text, p_score int default null, p_status text default null)
returns void language sql as $$
  insert into admin.domain_labels (domain, is_scam, category, source, connected, ai_score, ai_status, actor)
  values (p_domain, p_scam, p_category, 'admin', true, p_score, p_status, 'a@test')
$$;

create function pg_temp.cases(p_group text) returns text language sql as $$
  select coalesce(string_agg(domain, ',' order by domain), '-') from admin.case_library
   where status = 'active' and coalesce(category, label) = p_group
$$;

-- Labels, cases and lessons from the seed and the backfill belong to other tests.
delete from admin.domain_labels;
delete from admin.domain_intel_label;
delete from admin.domain_intel;
delete from admin.case_library;
delete from admin.ai_lessons;

-- ---------------------------------------------------------------- tables, defaults

select has_table('admin', t, 'admin.' || t || ' exists') from unnest(array['case_library', 'ai_lessons']) as t;
select is((select jsonb_object_agg(key, value) from admin.admin_config
            where key in ('require_guardian_note', 'case_library_size', 'threshold_warn_at', 'threshold_block_at',
                          'thresholds_version', 'thresholds_live')),
  '{"require_guardian_note": false, "case_library_size": 5, "threshold_warn_at": 30, "threshold_block_at": 80,
    "thresholds_version": 1, "thresholds_live": false}'::jsonb,
  '04a config defaults (R2 §5)');
select is(pg_temp.as_admin($$select string_agg(key, ',' order by key) from admin.v_config
                              where key like 'threshold%' or key in ('case_library_size', 'require_guardian_note')$$),
  'case_library_size,require_guardian_note,thresholds_live', 'v_config shows thresholds_live but not the threshold keys');

-- ---------------------------------------------------------------- K4 / I7 / I12: thresholds

select is(pg_temp.as_admin($$select warn_at || '/' || block_at || '/' || version || '/' || live from admin.v_thresholds$$),
  '30/80/1/false', 'v_thresholds: stored defaults');
select is((select warn_at || '/' || block_at || '/' || version from admin.public_config), '30/80/0',
  'I12: public_config is 30/80 version 0 while thresholds_live = false');
select is(pg_temp.as_admin('select count(*)::text from admin.public_config'), 'ERR 42501 permission denied for view public_config',
  'public_config has no grant in 04a (05 grants it to shoo_api)');

-- on_verdict v2: the label records the published version (0 before G6).
insert into devices (id, name, mode, avatar_id, token_hash) values
  ('t_o', 'O', 'protected', 'avatar_01', '\xa1'), ('t_g', 'G', 'guardian', 'avatar_02', '\xa2');
insert into scans (id, owner_id, url, domain, score, status, detected_at) values
  ('t_s1', 't_o', 'https://versi.test/', 'versi.test', 85, 'blocked', now());
insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name) values
  ('t_o', 'versi.test', 'not_safe', 't_s1', 't_g', 'G');
select is((select (ai_score, ai_status, thresholds_version)::text from admin.domain_labels where domain = 'versi.test'),
  '(85,blocked,0)', 'on_verdict v2: AI snapshot + thresholds_version 0 before thresholds go live');

select is(pg_temp.as_admin($$select admin.set_config('threshold_block_at', '90', 'dev', 'catatan sepuluh+')$$),
  'ERR SA010 config_unknown', 'I7: set_config refuses threshold_block_at');
select is(pg_temp.as_admin($$select admin.set_config('threshold_warn_at', '40', 'dev', 'catatan sepuluh+')$$),
  'ERR SA010 config_unknown', 'I7: set_config refuses threshold_warn_at');
select is(pg_temp.as_admin($$select admin.set_config('thresholds_version', '9', 'dev', 'catatan sepuluh+')$$),
  'ERR SA010 config_unknown', 'I7: set_config refuses thresholds_version');

select is(pg_temp.as_admin($$select admin.set_thresholds(29, 80, 'a@test', 'catatan sepuluh+', null)$$),
  'ERR SA009 config_invalid', 'I7: warn 29 → config_invalid');
select is(pg_temp.as_admin($$select admin.set_thresholds(61, 90, 'a@test', 'catatan sepuluh+', '90')$$),
  'ERR SA009 config_invalid', 'I7: warn 61 → config_invalid');
select is(pg_temp.as_admin($$select admin.set_thresholds(30, 96, 'a@test', 'catatan sepuluh+', '96')$$),
  'ERR SA009 config_invalid', 'I7: block 96 → config_invalid');
select is(pg_temp.as_admin($$select admin.set_thresholds(40, 49, 'a@test', 'catatan sepuluh+', null)$$),
  'ERR SA009 config_invalid', 'I7: block 49 → config_invalid');
select is(pg_temp.as_admin($$select admin.set_thresholds(50, 60, 'a@test', 'catatan sepuluh+', null)$$),
  'ERR SA009 config_invalid', 'I7: gap 10 → config_invalid');
select is(pg_temp.as_admin($$select admin.set_thresholds(null, 80, 'a@test', 'catatan sepuluh+', null)$$),
  'ERR SA009 config_invalid', 'I7: null → config_invalid');
select is(pg_temp.as_admin($$select admin.set_thresholds(30, 90, 'dev', 'uji', null)$$),
  'ERR SA011 confirm_required', 'I7 / W3: raising block without confirm → confirm_required');
select is(pg_temp.as_admin($$select admin.set_thresholds(30, 90, 'a@test', 'catatan sepuluh+', '85')$$),
  'ERR SA011 confirm_required', 'confirm must equal the new block value');
select is(pg_temp.as_admin($$select admin.set_thresholds(35, 90, 'a@test', 'pendek', '90')$$),
  'ERR SA003 note_required', 'a valid change still needs the note');
select is((select count(*)::int from admin.admin_audit where action like 'thresholds.%'), 0, 'refused changes leave no audit');

select is(pg_temp.as_admin($$select admin.set_thresholds(35, 90, 'a@test', 'naikkan ambang uji', ' 90 ')$$), '2',
  'set_thresholds with confirm → version 2');
select is(pg_temp.as_admin($$select warn_at || '/' || block_at || '/' || version || '/' || updated_by from admin.v_thresholds$$),
  '35/90/2/a@test', 'both values stored, version + 1 once');
select is((select (before ->> 'warn_at') || '/' || (before ->> 'block_at') || '/' || (before ->> 'version') || '>' ||
                  (after ->> 'warn_at') || '/' || (after ->> 'block_at') || '/' || (after ->> 'version') || ' ' || note
             from admin.admin_audit where action = 'thresholds.set'),
  '30/80/1>35/90/2 naikkan ambang uji', 'audit before/after + note');
select is(pg_temp.as_admin($$select admin.set_thresholds(35, 85, 'a@test', 'turunkan ambang uji', null)$$), '3',
  'lowering block (stricter) needs no confirm');
select is(pg_temp.as_admin($$select admin.set_thresholds(35, 85, 'a@test', 'sama seperti tadi', null)$$), '3',
  'the same values again: no new version');
select is((select count(*)::int from admin.admin_audit where action = 'thresholds.set'), 2, 'and no audit row');
select is((select warn_at || '/' || block_at || '/' || version from admin.public_config), '30/80/0',
  'I12: still 30/80 version 0 while not live');

select is(pg_temp.as_admin($$select admin.set_config('thresholds_live', 'true', 'a@test', 'terbitkan ambang uji')$$),
  'ERR SA011 confirm_required', 'thresholds_live → true needs confirm');
select is(pg_temp.as_admin($$select admin.set_config('thresholds_live', 'true', 'a@test', 'terbitkan ambang uji', 'true')$$), '',
  'thresholds_live → true with confirm');
select is((select warn_at || '/' || block_at || '/' || version from admin.public_config), '35/85/3',
  'public_config publishes the stored values once live');

select is(pg_temp.as_admin($$select admin.reset_thresholds('a@test', 'kembali ke bawaan')$$), '4',
  'reset_thresholds → 30/80, version + 1, no confirm');
select is(pg_temp.as_admin($$select warn_at || '/' || block_at || '/' || version || '/' || live from admin.v_thresholds$$),
  '30/80/4/true', 'reset stored');
select is((select count(*)::int from admin.admin_audit where action = 'thresholds.reset' and note = 'kembali ke bawaan'), 1,
  'reset audited');
select is(pg_temp.as_admin($$select admin.reset_thresholds('a@test', 'kembali ke bawaan')$$), '4', 'reset at the defaults: no new version');

insert into verdicts (owner_id, domain, value, by_device_id, by_name) values ('t_o', 'versi2.test', 'safe', 't_g', 'G');
select is((select (ai_score is null, thresholds_version)::text from admin.domain_labels where domain = 'versi2.test'),
  '(t,4)', 'on_verdict v2: the published version after go-live');

update admin.admin_config set value = 'false' where key = 'thresholds_live';
delete from admin.domain_labels;

-- ---------------------------------------------------------------- K1: evaluation (hand-computed)

select pg_temp.lab('e1.test', 'p1', 'g1', false, 90, 'blocked', p_age => '1 minute');   -- older answer of the same family: not counted
select pg_temp.lab('e1.test', 'p1', 'g1', true, 90, 'blocked');    -- TP
select pg_temp.lab('e2.test', 'p1', 'g1', false, 85, 'blocked');   -- FP
select pg_temp.lab('e3.test', 'p1', 'g1', true, 60, 'warning');    -- FN
select pg_temp.lab('e4.test', 'p1', 'g1', false, 40, 'warning');   -- TN
select pg_temp.admin_lab('e5.test', true, 'judi', 95, 'blocked');  -- TP (admin)
update admin.domain_labels set analyzed_at = now() where domain = 'e5.test';
select pg_temp.lab('e6.test', 'p1', 'g1', true, null, null);       -- no AI data
select pg_temp.lab('e8.test', 'p1', 'g1', true, 92, 'blocked', p_locked => true);   -- locked: not counted
select pg_temp.lab('e9.test', 'p1', 'g1', true, 88, 'blocked', p_age => '40 days'); -- TP, outside 7d/30d

select is(pg_temp.as_admin($$select string_agg(period, ',' order by period) from admin.v_eval_summary$$),
  '30d,7d,90d,all', 'v_eval_summary: one row per window');
select is(pg_temp.as_admin($$select n || '/' || tp || '/' || fp || '/' || fn || '/' || tn || '/' || no_ai || '/' || precision || '/' || recall
                              from admin.v_eval_summary where period = 'all'$$),
  '6/3/1/1/1/1/0.750/0.750', 'K1 all: newest answer per family, analyzed only, warning band = FN/TN');
select is(pg_temp.as_admin($$select n || '/' || tp || '/' || precision || '/' || recall from admin.v_eval_summary where period = '7d'$$),
  '5/2/0.667/0.667', 'K1 7d: the 40-day-old label is outside');
select is(pg_temp.as_admin($$select outcome || '/' || ai_correct from admin.v_eval_labels where domain = 'e3.test'$$),
  'fn/false', 'v_eval_labels: FN row, AI wrong');
select is(pg_temp.as_admin($$select coalesce(outcome, 'null') || '/' || coalesce(ai_correct::text, 'null') from admin.v_eval_labels where domain = 'e6.test'$$),
  'null/null', 'v_eval_labels: no AI data → no outcome (C1)');
select is(pg_temp.as_admin($$select count(*)::text from admin.v_eval_labels where domain in ('e1.test', 'e8.test')$$),
  '1', 'v_eval_labels: one row per family, locked labels left out');

-- K2: curve 30..95, counts at 85 = scam ≥ 85 {e1 90, e5 95, e9 88}, safe ≥ 85 {e2}, scam < 85 {e3}, safe < 85 {e4}.
select is(pg_temp.as_admin($$select count(*)::text || '/' || min(threshold) || '/' || max(threshold) from admin.v_eval_curve where period = 'all'$$),
  '14/30/95', 'K2: 14 thresholds, 30 to 95');
select is(pg_temp.as_admin($$select tp || '/' || fp || '/' || fn || '/' || tn || '/' || precision || '/' || recall
                              from admin.v_eval_curve where period = 'all' and threshold = 85$$),
  '3/1/1/1/0.750/0.750', 'K2: counts at 85');
select is(pg_temp.as_admin($$select tp || '/' || fp || '/' || fn || '/' || tn from admin.v_eval_curve where period = 'all' and threshold = 95$$),
  '1/0/3/2', 'K2: counts at 95');

-- No warning-band label at all: a miss cannot be seen, so recall is null, never 100 %.
delete from admin.domain_labels where domain in ('e3.test', 'e4.test');
select is(pg_temp.as_admin($$select fn || '/' || tn || '/' || precision || '/' || coalesce(recall::text, 'null') from admin.v_eval_summary where period = 'all'$$),
  '0/0/0.750/null', 'K1: FN = 0 without any warning-band label → recall null, not 100 %');

-- K1b targets + signal spectrum, from domain labels.
insert into admin.domain_intel_label (domain, label, label_source) values
  ('ta.test', 'scam_strong', 'admin'), ('tb.test', 'scam_weak', 'families'),
  ('tc.test', 'safe', 'families'), ('td.test', 'safe', 'families'), ('te.test', 'scam_weak', 'families');
select pg_temp.lab('ta.test', 'p1', 'g1', true, 70, 'warning', p_age => '1 minute');
select pg_temp.lab('ta.test', 'p2', 'g2', true, 90, 'blocked');   -- newest score of ta: 90
select pg_temp.lab('tb.test', 'p1', 'g1', true, 60, 'warning');
select pg_temp.lab('tc.test', 'p1', 'g1', false, 40, 'warning');
select pg_temp.lab('td.test', 'p1', 'g1', false, null, null);
select is(pg_temp.as_admin($$select scam_domains || '/' || scam_ge50 || '/' || scam_ge80 || '/' || scam_no_ai || '/' ||
                                     coalesce(pct_ge50::text, 'null') || '/' || safe_domains || '/' || safe_flagged
                              from admin.v_eval_targets$$),
  '2/2/1/1/null/2/1', 'K1b: newest score per domain, no percent while n < 30');
insert into admin.domain_intel_label (domain, label, label_source)
select 'tt' || g || '.test', 'scam_weak', 'families' from generate_series(1, 30) g;
select pg_temp.lab('tt' || g || '.test', 'p1', 'g1', true, case when g = 1 then 60 else 90 end, 'blocked') from generate_series(1, 30) g;
select is(pg_temp.as_admin($$select scam_domains || '/' || pct_ge50 || '/' || pct_ge80 || '/' || target_ge50 || '/' || target_ge80 from admin.v_eval_targets$$),
  '32/1.000/0.938/0.90/0.70', 'K1b: 30/32 ≥ 80 once n ≥ 30, targets from the Team AI mandate');

insert into admin.domain_intel (domain, first_seen_at, last_seen_at, scans, max_score, sum_score, signal_counts) values
  ('ta.test', now(), now(), 4, 90, 300, '{"new_domain": 3, "brand_bank": 1}'),
  ('tc.test', now(), now(), 2, 40, 80, '{"new_domain": 2}'),
  ('tx.test', now(), now(), 9, 90, 800, '{"new_domain": 9}');   -- unlabeled: not in the spectrum
select is(pg_temp.as_admin($$select domains_scam || '/' || domains_safe || '/' || hits_scam || '/' || hits_safe
                              from admin.v_eval_signals where signal = 'new_domain'$$),
  '1/1/3/2', 'v_eval_signals: per signal, labeled domains only (C2)');

delete from admin.domain_labels;
delete from admin.domain_intel_label;
delete from admin.domain_intel;

-- ---------------------------------------------------------------- K5: AI team writes

select ok(pg_temp.as_admin($$select admin.lesson_add('avoid', 'Jangan percaya domain baru berlogo bank', '{"signal": "new_domain"}', null, 'ai:pipeline')$$) ~ '^[0-9]+$',
  'W13: lesson_add returns the new id');
select is(pg_temp.as_admin($$select admin.lesson_add('avoid', 'awas <script>alert(1)</script>', '{}', null, 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'K5: text with < refused');
select is(pg_temp.as_admin($$select admin.lesson_add('maybe', 'teks pelajaran', '{}', null, 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'K5: unknown kind refused');
select is(pg_temp.as_admin(format('select admin.lesson_add(%L, %L, %L, null, %L)', 'repeat', repeat('a', 501), '{}', 'ai:pipeline')),
  'ERR SA009 config_invalid', 'K5: 501 characters refused');
select ok(pg_temp.as_admin(format('select admin.lesson_add(%L, %L, %L, null, %L)', 'repeat', repeat('a', 500), '{}', 'ai:pipeline')) ~ '^[0-9]+$',
  'K5: 500 characters accepted');
select is(pg_temp.as_admin($$select admin.lesson_add('avoid', '   ', '{}', null, 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'K5: blank text refused');
select is(pg_temp.as_admin($$select admin.lesson_add('avoid', 'teks pelajaran', '[1]', null, 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'K5: conditions must be an object');
select is(pg_temp.as_admin(format('select admin.lesson_add(%L, %L, %L, null, %L)', 'avoid', 'teks pelajaran',
                                  jsonb_build_object('k', repeat('a', 2100)), 'ai:pipeline')),
  'ERR SA009 config_invalid', 'K5: conditions over 2 KB refused');
select is(pg_temp.as_admin($$select admin.lesson_add('avoid', 'teks pelajaran', '{"k": "<b>"}', null, 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'K5: conditions with < refused');
select is(pg_temp.as_admin($$select admin.lesson_add('avoid', 'teks pelajaran', '{}', 999999999, 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'K5: unknown from_label_id refused');
select is(pg_temp.as_admin($$select admin.lesson_add('avoid', 'teks pelajaran', '{}', null, '')$$),
  'ERR SA009 config_invalid', 'K5: empty actor refused');
select is(pg_temp.as_admin($$select count(*)::text from admin.v_lessons$$), '2', 'v_lessons: the two accepted lessons');

select is(pg_temp.as_admin(format('select admin.lesson_pin(%s, true, %L)', (select min(id) from admin.ai_lessons), 'a@test')), '',
  'lesson_pin');
select is(pg_temp.as_admin($$select string_agg(pinned::text, ',' order by id) from admin.v_lessons$$), 'true,false', 'pinned shows in v_lessons');
select is(pg_temp.as_admin(format('select admin.lesson_delete(%s, %L, %L)', (select min(id) from admin.ai_lessons), 'pendek', 'a@test')),
  'ERR SA003 note_required', 'lesson_delete needs a note');
select is(pg_temp.as_admin(format('select admin.lesson_delete(%s, %L, %L)', (select min(id) from admin.ai_lessons), 'tidak berlaku lagi', 'a@test')), '',
  'lesson_delete');
select is(pg_temp.as_admin($$select count(*)::text from admin.v_lessons$$), '1', 'a deleted lesson leaves v_lessons');
select is(pg_temp.as_admin(format('select admin.lesson_delete(%s, %L, %L)', (select min(id) from admin.ai_lessons), 'tidak berlaku lagi', 'a@test')),
  'ERR SA002 not_found', 'deleting twice → not_found');
select is((select count(*)::int from admin.admin_audit where action in ('lesson.add', 'lesson.pin', 'lesson.delete') and actor <> 'ai:seed'), 4,
  'lesson writes are audited');

select is(pg_temp.as_admin(format('select admin.usage_record(%L, %s, %L)', 'lesson', (select max(id) from admin.ai_lessons), 'correct')), '', 'usage_record correct');
select is(pg_temp.as_admin(format('select admin.usage_record(%L, %s, null)', 'lesson', (select max(id) from admin.ai_lessons))), '', 'usage_record without outcome');
select is(pg_temp.as_admin($$select uses || '/' || correct || '/' || wrong from admin.v_lessons$$), '2/1/0', 'uses and outcomes counted');
select is(pg_temp.as_admin(format('select admin.usage_record(%L, %s, %L)', 'lesson', (select max(id) from admin.ai_lessons), 'maybe')),
  'ERR SA009 config_invalid', 'usage_record: unknown outcome refused');
select is(pg_temp.as_admin($$select admin.usage_record('case', 999999999, null)$$), 'ERR SA002 not_found', 'usage_record: unknown case');

select ok(pg_temp.as_admin($$select admin.case_add('kasus-ai.test', 'scam_weak', 'pinjol_ilegal', 'pola pinjol klasik', '{"new_domain": 1}', 'ai:pipeline')$$) ~ '^[0-9]+$',
  'W13: case_add returns the new id');
select is(pg_temp.as_admin($$select source || '/' || label || '/' || signal_counts::text from admin.v_cases where domain = 'kasus-ai.test'$$),
  'ai/scam_weak/{"new_domain": 1}', 'v_cases: AI case');
select is(pg_temp.as_admin($$select admin.case_add('kasus-ai.test', 'scam_weak', null, null, '{}', 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'one case per domain');
select is(pg_temp.as_admin($$select admin.case_add('lain.test', 'maybe', null, null, '{}', 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'case_add: unknown label');
select is(pg_temp.as_admin($$select admin.case_add('lain.test', 'scam_weak', 'tidak_ada', null, '{}', 'ai:pipeline')$$),
  'ERR SA004 category_unknown', 'case_add: unknown category');
select is(pg_temp.as_admin($$select admin.case_add('WWW.Lain.test', 'scam_weak', null, null, '{}', 'ai:pipeline')$$),
  'ERR SA014 invalid_domain', 'case_add: domain checked');
select is(pg_temp.as_admin($$select admin.case_add('lain.test', 'safe', null, '<i>aman</i>', '{}', 'ai:pipeline')$$),
  'ERR SA009 config_invalid', 'case_add: note with < refused');

-- ---------------------------------------------------------------- K3: case library from analysis (R4 §3 step 6)

update admin.admin_config set value = '2' where key = 'case_library_size';
select pg_temp.admin_lab('k' || g || '.test', true, 'judi') from generate_series(1, 4) g;
insert into admin.domain_intel (domain, first_seen_at, last_seen_at, scans, max_score, sum_score, signal_counts) values
  ('k1.test', now(), now(), 2, 90, 180, '{"new_domain": 2}');
select pg_temp.admin_lab('konflik.test', false, null);                      -- admin safe against two families: conflict
select pg_temp.lab('konflik.test', 'p1', 'g1', true, null, null, p_locked => true);
select pg_temp.lab('konflik.test', 'p2', 'g2', true, null, null, p_locked => true);
select pg_temp.lab('aman2.test', 'p1', 'g1', false, null, null, p_locked => true);
select pg_temp.lab('aman2.test', 'p2', 'g2', false, null, null, p_locked => true);
select pg_temp.lab('balik.test', 'p1', 'g1', false, null, null, p_locked => true);
select pg_temp.lab('balik.test', 'p2', 'g2', false, null, null, p_locked => true);

select is((admin.run_analysis('cron', null) ->> 'ok'), 'true', 'run with step 6');
select is(pg_temp.cases('judi'), 'k1.test,k2.test', 'K3: at most case_library_size per category');
select is(pg_temp.cases('safe'), 'aman2.test,balik.test', 'K3: safe cases from families');
select is((select count(*)::int from admin.case_library where domain = 'konflik.test'), 0, 'K3: a conflicting label gives no case');
select is(pg_temp.cases('pinjol_ilegal'), 'kasus-ai.test', 'the AI case stays in its own category');
select is(pg_temp.as_admin($$select source || '/' || label || '/' || signal_counts::text from admin.v_cases where domain = 'k1.test'$$),
  'analysis/scam_strong/{"new_domain": 2}', 'v_cases: analysis case with the domain signal counts');

select is(pg_temp.as_admin(format('select admin.case_pin(%s, true, %L)', (select id from admin.case_library where domain = 'k1.test'), 'a@test')), '', 'case_pin');
select is(pg_temp.as_admin(format('select admin.case_delete(%s, %L, %L)', (select id from admin.case_library where domain = 'k2.test'), 'contoh kurang bagus', 'a@test')), '',
  'case_delete');
select is(pg_temp.as_admin($$select admin.case_pin(999999999, true, 'a@test')$$), 'ERR SA002 not_found', 'case_pin: unknown id');
select pg_temp.admin_lab('balik.test', true, 'judi');                        -- admin now says scam against two safe families

select admin.run_analysis('cron', null);
select is(pg_temp.cases('judi'), 'k1.test,k3.test', 'K3: pinned stays, deleted is not recreated, the free slot is refilled');
select is((select status from admin.case_library where domain = 'k2.test'), 'deleted', 'the deleted case stays deleted');
select is((select count(*)::int from admin.case_library where domain = 'balik.test'), 0, 'K3: a case whose label turned conflicting is dropped');
select is(pg_temp.cases('safe'), 'aman2.test', 'safe group after balik left');

update admin.admin_config set value = '1' where key = 'case_library_size';
select admin.run_analysis('cron', null);
select is(pg_temp.cases('judi'), 'k1.test', 'K3: a smaller size trims unpinned analysis cases, the pinned one stays');

-- ---------------------------------------------------------------- require_guardian_note (R4 §3 step 2)

update admin.admin_config set value = '2' where key = 'case_library_size';
update admin.admin_config set value = 'true' where key = 'require_guardian_note';
select pg_temp.lab('catat.test', 'p1', 'g1', true, null, null, p_locked => true);
select pg_temp.lab('catat.test', 'p2', 'g2', true, null, null, p_locked => true);
update admin.domain_labels set note = 'situs ini minta OTP' where domain = 'catat.test' and by_ref = admin.owner_ref('g1');
select admin.run_analysis('cron', null);
select is((select families_not_safe from admin.domain_intel_label where domain = 'catat.test'), 1,
  'require_guardian_note: a Guardian label without a note is not counted');

-- ---------------------------------------------------------------- grants

select is(pg_temp.as_admin('select count(*)::text from admin.case_library'), 'ERR 42501 permission denied for table case_library',
  'shoo_admin cannot read case_library directly');
select is(pg_temp.as_admin($$update admin.admin_config set value = '95' where key = 'threshold_block_at'$$),
  'ERR 42501 permission denied for table admin_config', 'shoo_admin cannot write thresholds directly');

select * from finish();
rollback;
