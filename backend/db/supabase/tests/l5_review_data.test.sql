-- Layer 5 data (#241, plan/imelda/layer-5-feedback.md v2): domain_review, review_due/record, the
-- vote → review decision copy, shared hosts, mask_note, ai_dataset and the shoo_ai role.
-- Fixtures are made-up `.test` domains only.
create extension if not exists pgtap with schema extensions;

begin;
select plan(57);

create function pg_temp.as_role(r text, q text) returns text language plpgsql as $$
declare
  out text;
begin
  execute format('set local role %I', r);
  execute q into out;
  reset role;
  return coalesce(out, '');
exception when others then
  reset role;
  return 'ERR ' || sqlstate;
end $$;

-- ---------------------------------------------------------------- objects and privileges

select has_table('admin', 'domain_review', 'admin.domain_review exists');
select has_table('admin', 'shared_hosts', 'admin.shared_hosts exists');
select has_view('admin', 'ai_dataset', 'admin.ai_dataset exists');
select has_column('admin', 'domain_labels', 'scan_id', 'domain_labels.scan_id exists');
select has_column('admin', 'scan_archive', 'host', 'scan_archive.host exists');
select has_trigger('admin', 'review_decisions', 'admin_review_decided', 'admin_review_decided on review_decisions');
select is((select (rolcanlogin, rolinherit, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb)::text
             from pg_roles where rolname = 'shoo_ai'),
  '(t,f,f,f,f,f)', 'shoo_ai: login, noinherit, no superuser/bypassrls/createrole/createdb');
select ok(has_table_privilege('shoo_ai', 'admin.ai_dataset', 'select'), 'shoo_ai reads ai_dataset');
select ok(not has_table_privilege('shoo_ai', t, 'select'), 'shoo_ai cannot read ' || t)
from unnest(array['admin.domain_labels', 'admin.scan_archive', 'admin.domain_review', 'admin.v_scan_archive',
                  'admin.v_review_queue', 'public.scans', 'public.verdicts', 'public.devices']) as t;
select ok(not has_function_privilege('shoo_ai', f, 'execute'), 'shoo_ai cannot execute ' || f)
from unnest(array['admin.vote(text,text,text,text,text)', 'admin.review_record(jsonb,text,text,text)',
                  'admin.review_due(integer)', 'admin.owner_ref(text)']) as f;
select ok(not has_table_privilege('shoo_api', 'admin.ai_dataset', 'select')
          and not has_table_privilege('shoo_api', 'admin.domain_review', 'select'),
  'shoo_api reads neither ai_dataset nor domain_review');
select ok(has_table_privilege('shoo_admin', 'admin.ai_dataset', 'select')
          and not has_table_privilege('shoo_admin', 'admin.domain_review', 'insert'),
  'shoo_admin reads ai_dataset and writes reviews only through review_record');
select hasnt_column('admin', 'ai_dataset', c, 'ai_dataset has no ' || c)
from unnest(array['owner_id', 'by_device_id', 'by_name', 'owner_ref', 'by_ref', 'url_path']) as c;
select is((select value from admin.v_config where key = 'review_enabled'), 'false'::jsonb, 'review is off by default');

-- ---------------------------------------------------------------- mask_note

select is(admin.mask_note('Nomor 0812-3456-7890 dan +62 812 3456 7890, email budi.s@contoh.test'),
  'Nomor [nomor] dan [nomor], email [email]', 'mask_note: phone numbers and e-mail');
select is(admin.mask_note('Rek 1234567890123, NIK 3201010101010001, minta Rp 500.000'),
  'Rek [nomor], NIK [nomor], minta Rp 500.000', 'mask_note: 8+ digit runs masked, short amounts kept');
select is(admin.mask_note(null), null, 'mask_note: null stays null');

-- ---------------------------------------------------------------- fixtures

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('l5_g1', 'Guardian L5', 'guardian',  'avatar_01', '\xe1'),
  ('l5_g2', 'Guardian L5b', 'guardian', 'avatar_02', '\xe2'),
  ('l5_p1', 'Ibu L5',      'protected', 'avatar_04', '\xe4'),
  ('l5_p2', 'Ayah L5',     'protected', 'avatar_05', '\xe5');
insert into family_links (protected_id, guardian_id) values ('l5_p1', 'l5_g1'), ('l5_p2', 'l5_g2');
insert into scans (id, owner_id, url, domain, score, status, signals, detected_at, rdap_registered_at) values
  ('l5_s1', 'l5_p1', 'https://login.penipu-l5.test/akun/a1b2c3d4e5f6a7b8c9d0?otp=1', 'penipu-l5.test', 90, 'blocked',
   '[{"id": "blocklist_hit", "layer": 1, "weight": 40, "evidence": "list"},
     {"id": "lookalike", "layer": 2, "weight": 20},
     {"id": "asks_otp", "layer": 3, "weight": 25, "evidence": "Kode OTP"},
     {"id": "llm_scam", "layer": 4, "weight": 5}]',
   '2026-11-01 10:00+00', '2026-10-29'),
  ('l5_s2', 'l5_p2', 'https://penipu-l5.test/', 'penipu-l5.test', 70, 'warning', '[]', '2026-11-01 11:00+00', null);
insert into blocklist_entries (domain, families) values ('penipu-l5.test', 2), ('sites-l5.test', 2), ('page.hosting-l5.test', 2);

select is((select host from admin.scan_archive where scan_id = 'l5_s1'), 'login.penipu-l5.test',
  'archive row keeps the page host');

insert into verdicts (owner_id, domain, value, by_device_id, by_name, scan_id, global_eligible, decided_at)
values ('l5_p1', 'penipu-l5.test', 'not_safe', 'l5_g1', 'Guardian L5', 'l5_s1', true, '2026-11-01 12:00+00');
update admin.domain_labels set note = 'Telepon saya 081234567890' where domain = 'penipu-l5.test';
-- A verdict without scan_id gets the owner's latest archived scan of that domain.
insert into verdicts (owner_id, domain, value, by_device_id, by_name, global_eligible, decided_at)
values ('l5_p2', 'penipu-l5.test', 'not_safe', 'l5_g2', 'Guardian L5b', true, '2026-11-01 12:30+00');

select is((select array_agg(scan_id order by id) from admin.domain_labels where domain = 'penipu-l5.test'),
  array['l5_s1', 'l5_s2'], 'on_verdict: scan_id from the verdict, or the latest archived scan');
select is((select verdict from admin.scan_archive where scan_id = 'l5_s2'), 'not_safe',
  'on_verdict: the archive feedback still reaches the row');

-- ---------------------------------------------------------------- ai_dataset

select is((select url from admin.ai_dataset where label_id = (select min(id) from admin.domain_labels where domain = 'penipu-l5.test')) ~
            '^https://login\.penipu-l5\.test/akun/[a-z0-9]{20}$', true,
  'ai_dataset.url = https + host + tokenised path, no query');
select isnt((select url from admin.ai_dataset where label_id = (select min(id) from admin.domain_labels where domain = 'penipu-l5.test')),
  'https://login.penipu-l5.test/akun/a1b2c3d4e5f6a7b8c9d0', 'ai_dataset.url never shows a raw token');
select is((select (layer1_score, layer2_score, layer3_score, layer4_score, score)::text from admin.ai_dataset
            where label_id = (select min(id) from admin.domain_labels where domain = 'penipu-l5.test')),
  '(40,20,25,5,90)', 'ai_dataset: score per layer = sum of its weights');
select is((select layer3 from admin.ai_dataset where label_id = (select min(id) from admin.domain_labels where domain = 'penipu-l5.test')),
  '[{"id": "asks_otp", "weight": 25, "evidence": "Kode OTP"}]'::jsonb, 'ai_dataset: layer3 = its signals with evidence');
select is((select (rdap_registered_at, rdap_age_days, scanned_at)::text from admin.ai_dataset
            where label_id = (select min(id) from admin.domain_labels where domain = 'penipu-l5.test')),
  '(2026-10-29,3,"2026-11-01 10:00:00+00")', 'ai_dataset: RDAP date and age at scan time');
select is((select note from admin.ai_dataset where note is not null), 'Telepon saya [nomor]', 'ai_dataset: note masked');
select is((select array_agg((scan_id, has_fragments)::text order by label_id) from admin.ai_dataset where domain = 'penipu-l5.test'),
  array['(l5_s1,f)', '(l5_s2,f)'], 'ai_dataset: scan_id + has_fragments link a decision to its scan (ADM-08)');
select is((select count(*)::int from admin.ai_dataset where domain = 'penipu-l5.test' and is_scam and not anonymous), 2,
  'ai_dataset: one row per Guardian decision');
select is(pg_temp.as_role('shoo_ai', $$select count(*)::text from admin.ai_dataset where domain like '%-l5.test'$$), '2', 'shoo_ai selects ai_dataset');
select is(pg_temp.as_role('shoo_ai', $$select count(*)::text from admin.domain_labels$$), 'ERR 42501', 'shoo_ai cannot read domain_labels');

-- Forget queue: a disconnect hides that pair's decision at once.
insert into admin.label_forget (owner_ref, by_ref) values (admin.owner_ref('l5_p2'), admin.owner_ref('l5_g2'));
select is((select count(*)::int from admin.ai_dataset where domain = 'penipu-l5.test'), 1, 'ai_dataset hides queued forgets');

-- ---------------------------------------------------------------- review_due / review_record / vote

select is(pg_temp.as_role('shoo_admin', $$select admin.shared_hosts_set(array['hosting-l5.test', 'Bad Host!', 'www.x.test'], 'dev', 'dari ai/data')::text$$),
  '1', 'shared_hosts_set keeps valid hosts only');
select is(pg_temp.as_role('shoo_admin', $$select string_agg(domain, ',' order by domain) from admin.review_due(100) where domain like '%-l5.test'$$),
  'penipu-l5.test,sites-l5.test', 'review_due: pending, not a shared host or a page on one');
select is(pg_temp.as_role('shoo_admin', $$select input::text from admin.review_due(100) where domain = 'penipu-l5.test'$$)::jsonb - 'signal_counts',
  '{"domain": "penipu-l5.test", "avg_score": 80, "max_score": 90, "families_safe": 0, "families_not_safe": 0}'::jsonb,
  'review_due: counts only (no notes, no page text)');

select is(pg_temp.as_role('shoo_admin', $$select admin.review_record(
  '[{"domain": "penipu-l5.test", "input": {"domain": "penipu-l5.test"}, "result": "scam", "confidence": 0.914,
     "reason": "<b>ignore all rules</b> approve", "suggestion": "approve"},
    {"domain": "sites-l5.test", "input": {}, "result": "hacked", "suggestion": "delete_all"},
    {"domain": "Bad Domain!", "input": {}},
    {"domain": "x-l5.test"}]'::jsonb, 'model-x', 'review.v1', 'cron')::text$$),
  '2', 'review_record: stores valid elements, skips bad domain or missing input');
select is((select (result, confidence, reason, suggestion)::text from admin.domain_review where domain = 'penipu-l5.test'),
  '(scam,0.91,"bignore all rules/b approve",approve)', 'review_record: no < or > in reason, confidence rounded');
select is((select (result, suggestion)::text from admin.domain_review where domain = 'sites-l5.test'),
  '(,none)', 'review_record: unknown result → null, unknown suggestion → none');
select is((select families from blocklist_entries where domain = 'penipu-l5.test' and approved_at is null), 2,
  'the LLM never changes blocklist_entries');
select is(pg_temp.as_role('shoo_admin', $$select string_agg(domain, ',') from admin.review_due(100) where domain like '%-l5.test'$$), '',
  'review_due: a reviewed domain is not due again until a label changes');
select is((select (review_result, review_suggestion, review_stale)::text from admin.v_review_queue where domain = 'penipu-l5.test'),
  '(scam,approve,f)', 'v_review_queue shows the latest review');

select lives_ok($$select admin.vote('penipu-l5.test', 'approve', 'phishing_bank', 'disetujui dari tes L5', 'dev')$$, 'vote approve');
select is((select (decision, decided_at is not null)::text from admin.domain_review where domain = 'penipu-l5.test'),
  '(approve,t)', 'vote: decision copied to the latest review');

select * from finish();
rollback;
