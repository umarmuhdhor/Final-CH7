-- Family-wide "Mark as safe" (plan/alief/family-safe.md): a verdict on a link counts for every phone
-- in the family, not only for the member whose scan it was made on. A family is one Guardian and its
-- linked Protected members (family_links); a device without a link is a family of one.
--
-- public.verdict_family(device) gives that device's family as it is now. The Worker reads it in the
-- verdict lookup (findVerdict, selectScans, recordScan) and in the weekly-review lock check
-- (decideVerdict), so nothing is copied: a member who leaves stops seeing the family's verdicts at
-- once, and the admin learning still counts one decision per family. No table changes.
--
-- Rollback: drop function public.verdict_family(text); (deploy the Worker without it first).

set local lock_timeout = '1s';
set local statement_timeout = '60s';

create function public.verdict_family(p_device text) returns text[]
language sql stable strict parallel safe set search_path = pg_catalog, pg_temp as $$
  with g as (
    select coalesce((select l.guardian_id from public.family_links l where l.protected_id = p_device), p_device) as id
  )
  select array(
    select g.id from g
    union
    select l.protected_id from public.family_links l join g on l.guardian_id = g.id
  )
$$;

revoke all on function public.verdict_family(text) from public, anon, authenticated;
grant execute on function public.verdict_family(text) to shoo_api;
