-- ADM-02 admin dashboard: admin.run_analysis and admin.vote v2 (dashboard plan R4 §2–§3, K5, K6).
-- The "another session holds the run lock" case needs two sessions: backend/db/scripts/admin_intel_concurrency.sh.
create extension if not exists pgtap with schema extensions;

begin;
select plan(27);

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

create function pg_temp.label(p_domain text) returns text language sql as $$
  select coalesce(label, '-') || '/' || coalesce(label_source, '-') || '/' || families_not_safe || '/' || families_safe
  from admin.domain_intel_label where domain = p_domain
$$;

-- Labels written straight into the table, as the triggers would (refs from admin.owner_ref).
create function pg_temp.guardian(p_domain text, p_owner text, p_by text, p_scam boolean, p_connected boolean default true)
returns void language sql as $$
  insert into admin.domain_labels (domain, is_scam, source, connected, owner_ref, by_ref)
  values (p_domain, p_scam, 'guardian', p_connected, admin.owner_ref(p_owner), admin.owner_ref(p_by))
$$;

-- Start from nothing locked: seed labels belong to other tests.
update admin.domain_labels set analyzed_at = now() where analyzed_at is null;

-- ---------------------------------------------------------------- families → scam_weak / safe

-- One Guardian with two Protected members = one family (count(distinct by_ref)).
select pg_temp.guardian('satu.test', 'p1', 'g1', true);
select pg_temp.guardian('satu.test', 'p2', 'g1', true);
-- Two different Guardians = two families.
select pg_temp.guardian('dua.test', 'p1', 'g1', true);
select pg_temp.guardian('dua.test', 'p3', 'g2', true);
-- Two families say safe.
select pg_temp.guardian('aman.test', 'p1', 'g1', false);
select pg_temp.guardian('aman.test', 'p3', 'g2', false);
-- One connected + one unconnected Guardian.
select pg_temp.guardian('lepas.test', 'p1', 'g1', true);
select pg_temp.guardian('lepas.test', 'p4', 'gx', true, false);

select is(pg_temp.as_admin($$select admin.run_analysis('manual', 'a@test') ->> 'labels_processed'$$), '8',
  'run as shoo_admin processes the 8 locked labels');
select is(pg_temp.label('satu.test'), '-/-/1/0', 'one Guardian with two members counts as one family: no label');
select is(pg_temp.label('dua.test'), 'scam_weak/families/2/0', 'two families reporting scam: scam_weak');
select is(pg_temp.label('aman.test'), 'safe/families/0/2', 'two families saying safe: safe');
select is(pg_temp.label('lepas.test'), '-/-/1/0', 'ignore_unconnected_guardian: the unconnected guardian is not counted');
select is((select count(*)::int from admin.domain_labels where analyzed_at is null), 0, 'all labels unlocked');
select is((select (ok, labels_processed, domains_updated, backlog, trigger, actor)::text from admin.analysis_runs order by id desc limit 1),
  '(t,8,4,0,manual,a@test)', 'analysis_runs row');
select is((select count(*)::int from admin.admin_audit where action = 'analysis.run' and actor = 'a@test'), 1, 'manual run is audited');
select is(pg_temp.as_admin($$select count(*)::text from admin.v_feed where kind = 'analysis' and actor = 'a@test'$$), '1', 'run appears in v_feed');

-- Second run with nothing new.
select is((admin.run_analysis('cron', null) ->> 'labels_processed'), '0', 'second run without new labels: labels_processed = 0');
select is((select (domains_updated, actor is null)::text from admin.analysis_runs order by id desc limit 1), '(0,t)', 'nothing changed, cron has no actor');

-- Setting off: unconnected guardians count.
update admin.admin_config set value = 'false' where key = 'ignore_unconnected_guardian';
select pg_temp.guardian('lepas.test', 'p5', 'gy', true, false);
select admin.run_analysis('cron', null);
select is(pg_temp.label('lepas.test'), 'scam_weak/families/3/0', 'ignore_unconnected_guardian = false: all three count');
update admin.admin_config set value = 'true' where key = 'ignore_unconnected_guardian';

-- A revision replaces the slot's earlier answer instead of adding to it.
select pg_temp.guardian('dua.test', 'p3', 'g2', false);
select admin.run_analysis('cron', null);
select is(pg_temp.label('dua.test'), '-/-/1/1', 'revision: the slot counts once, with its newest answer');

-- A family that goes away (device delete) lowers the label at the next run with no new label.
insert into devices (id, name, mode, avatar_id, token_hash) values
  ('t_d1', 'D1', 'guardian', 'avatar_01', '\xd1'), ('t_d2', 'D2', 'guardian', 'avatar_02', '\xd2');
select pg_temp.guardian('pergi.test', 'p1', 't_d1', true);
select pg_temp.guardian('pergi.test', 'p3', 't_d2', true);
select admin.run_analysis('cron', null);
select is(pg_temp.label('pergi.test'), 'scam_weak/families/2/0', 'two families: scam_weak');
delete from devices where id = 't_d2';
select admin.run_analysis('cron', null);
select is(pg_temp.label('pergi.test'), '-/-/1/0', 'after one family is deleted the next run lowers the label (domain_dirty)');

-- ---------------------------------------------------------------- admin vote → scam_strong / safe (K6)

insert into devices (id, name, mode, avatar_id, token_hash) values
  ('t_a1', 'A', 'protected', 'avatar_01', '\xc1');
insert into scans (id, owner_id, url, domain, score, status, detected_at, created_at) values
  ('t_v1', 't_a1', 'https://antre.test/1', 'antre.test', 70, 'warning', now(), now() - interval '1 hour'),
  ('t_v2', 't_a1', 'https://antre.test/2', 'antre.test', 88, 'blocked', now(), now());
insert into blocklist_entries (domain, families) values ('antre.test', 1), ('tolak.test', 1);

select is(pg_temp.as_admin($$select admin.vote('antre.test', 'approve', 'judi', 'catatan sepuluh+', 'a@test')$$), '', 'vote approve');
select is((select (source, is_scam, category, actor, connected, ai_score, ai_status, analyzed_at is null, owner_ref is null)::text
             from admin.domain_labels where domain = 'antre.test'),
  '(admin,t,judi,a@test,t,88,blocked,t,t)', 'K6: approve adds a locked admin label with the newest scan as AI snapshot');
select is(pg_temp.as_admin($$select admin.vote('tolak.test', 'reject', null, 'bukan penipuan ini', 'b@test')$$), '', 'vote reject');
select is((select (is_scam, ai_score is null)::text from admin.domain_labels where domain = 'tolak.test'), '(f,t)',
  'K6: reject adds a safe label; no scan → no snapshot');
select is(pg_temp.as_admin($$select admin.vote('antre.test', 'reject', null, 'terlambat sekali', 'b@test')$$),
  'ERR SA001 already_decided', 'second vote still already_decided (01a behaviour kept)');
select is((select count(*)::int from admin.domain_labels where domain = 'antre.test'), 1, 'a refused vote leaves no label');

-- Admin outranks families.
select pg_temp.guardian('tolak.test', 'p1', 'g1', true);
select pg_temp.guardian('tolak.test', 'p3', 'g2', true);
select admin.run_analysis('cron', null);
select is(pg_temp.label('antre.test'), 'scam_strong/admin/0/0', 'approve → scam_strong');
select is(pg_temp.label('tolak.test'), 'safe/admin/2/0', 'reject → safe, even against two families');
select is((select category from admin.domain_intel_label where domain = 'antre.test'), 'judi', 'category from the approve');
select is(pg_temp.as_admin($$select label || '/' || blocklist_status from admin.v_domain_intel where domain = 'antre.test'$$),
  'scam_strong/approved', 'v_domain_intel joins label and live blocklist status');

-- ---------------------------------------------------------------- K5: 5000 per run, the rest is backlog

insert into admin.domain_labels (domain, is_scam, source, connected, actor)
select 'banyak-' || g || '.test', true, 'admin', true, 'bulk@test' from generate_series(1, 5001) g;
select is((admin.run_analysis('cron', null) ->> 'labels_processed'), '5000', 'K5: one run processes at most 5000 labels');
select is((select backlog from admin.analysis_runs order by id desc limit 1), 1, 'K5: the rest is backlog');

select * from finish();
rollback;
