-- Fase 27c (F-B7, K5): a domain a reviewer rejected stays rejected when it is queued again.
--
-- recountFamilies deletes a queued row nobody supports any more, rejected or not (D-alief-40: no
-- browsing domain kept without a purpose). The next eligible not_safe then inserted a fresh row
-- with rejected_at null, so the domain was back in the review queue. The reviewer's decision is
-- still in admin.review_decisions, but shoo_api may neither read that table nor write
-- rejected_at/rejected_by (hardening.sql: insert (domain, families) only). This function reads the
-- domain's last decision itself and inserts the row already rejected when that decision is
-- `reject`. Only a later decision ends it: in practice `add` (or `unreject` once the row is back),
-- since approve/remove need an existing row. It never returns the actor.
--
-- Limits: a reject made by hand in the SQL editor, without a review_decisions row, is not known.
-- While no row exists (no support), admin.unreject has nothing to clear (SA006 not_rejected):
-- the reject stands until the domain is queued again, then the reviewer can unreject it.
-- No admin lock (7, 1) is taken: the lock order admin vs. domain verdict lock stays as it is. A
-- reviewer acting between this read and commit acts on the row it then sees (first vote wins).
--
-- Deploy order: this migration before the Worker that calls it (backend.yml runs `supabase db push`
-- before `wrangler deploy`); a Worker without the function fails every eligible not_safe (42883).
-- Rollback: deploy the Worker back to the plain insert first, then drop this function in a later
-- migration (the insert (domain, families) grant is kept for that).

create or replace function public.queue_blocklist_domain(p_domain text, p_families int) returns void
language plpgsql security definer set search_path = pg_catalog, pg_temp as $$
declare
  v_action text;
  v_actor  text;
begin
  if p_families is null or p_families < 1 then
    raise exception using errcode = '22023', message = 'invalid_families';
  end if;
  select r.action, r.actor into v_action, v_actor
    from admin.review_decisions r
   where r.domain = p_domain
   order by r.at desc, r.id desc
   limit 1;
  insert into public.blocklist_entries as b (domain, families, rejected_at, rejected_by)
  values (p_domain, p_families,
          case when v_action = 'reject' then pg_catalog.now() end,
          case when v_action = 'reject' then v_actor end)
  on conflict (domain) do update set families = excluded.families
   where b.families is distinct from excluded.families;
end $$;

revoke all on function public.queue_blocklist_domain(text, int) from public, anon, authenticated, service_role;
grant execute on function public.queue_blocklist_domain(text, int) to shoo_api;

-- The Worker could now make a reviewer's email reappear in rejected_by for any domain ever rejected
-- (security review): it reads every column it needs but not the reviewers' names. The Worker never
-- selects approved_by or rejected_by (backend/api/src).
revoke select on public.blocklist_entries from shoo_api;
grant select (domain, families, first_seen_at, approved_at, removed_at, rejected_at) on public.blocklist_entries to shoo_api;
