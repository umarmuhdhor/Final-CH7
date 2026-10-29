-- Retention walks (PR #20 security review, MEDIUM) and the page replica indexes (fase 18, EX-07).
create extension if not exists pgtap with schema extensions;

begin;

select plan(8);

select has_index('public', 'scans', 'scans_plain_created', array['created_at', 'id'], 'plain-scan retention walk');
select has_index('public', 'scans', 'scans_shot_created', array['created_at', 'id'], 'screenshot-scan retention walk');

-- has_index does not look at predicates; Postgres normalizes them, so the regexes stay loose.
select ok((select indexdef from pg_indexes where indexname = 'scans_plain_created')
  ~ 'screenshot_path IS NULL.*favicon_path IS NULL.*replica_path IS NULL', 'plain walk excludes scans with a replica');
select ok((select indexdef from pg_indexes where indexname = 'scans_shot_created')
  ~ 'screenshot_path IS NOT NULL.*favicon_path IS NOT NULL.*replica_path IS NOT NULL', 'stored-files walk includes scans with only a replica');
select has_index('public', 'scans', 'scans_replica_path', array['owner_id', 'replica_path'], 'replica path lookups per owner');
select ok((select indexdef from pg_indexes where indexname = 'scans_replica_path') ~ 'WHERE \(?replica_path IS NOT NULL', 'scans_replica_path is partial');
select ok((select indexdef from pg_indexes where indexname = 'scans_original_replica')
  ~ '\(created_at\) INCLUDE \(owner_id, replica_bytes\) WHERE \(?replica_bytes IS NOT NULL', 'quota index: original uploads, index-only');
select is((select count(*)::int from pg_indexes where tablename = 'scans' and indexname like 'scans\_%\_v2'), 0, 'no leftover index from the swap');

select * from finish();
rollback;
