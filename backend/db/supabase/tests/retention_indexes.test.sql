-- Retention walks (PR #20 security review, MEDIUM).
create extension if not exists pgtap with schema extensions;

begin;

select plan(2);

select has_index('public', 'scans', 'scans_plain_created', array['created_at', 'id'], 'plain-scan retention walk');
select has_index('public', 'scans', 'scans_shot_created', array['created_at', 'id'], 'screenshot-scan retention walk');

select * from finish();
rollback;
