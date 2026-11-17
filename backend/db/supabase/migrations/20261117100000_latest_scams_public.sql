-- Home "Scam terbaru di pengguna Shoo" (GET /scams/latest): which kinds of scam Shoo users met lately.
--
-- The feed must not become a spam channel: anyone can make devices and send scans, so nothing a client
-- sends may decide what the card says. This view is the gate. It lists only domains a named admin
-- approved onto the blocklist (admin.vote / admin.add_domain: a note, `max_publish_per_day`), with the
-- category the admin chose then. The card's words come from admin.categories, never from a page title,
-- URL or domain. "lainnya" (Other) says nothing about the scam and is left out; so is a domain the
-- admin later removed, and a domain on the trusted/protected lists (an official brand site).
--
-- The Worker counts scans against it (routes/scams.ts): blocked only, the last 7 days by server time,
-- devices older than a day, at least 3 different devices per category. Scans are deleted after 14
-- days and with their device, so the count follows a deletion right away; nothing new is stored here.
--
-- shoo_api gets SELECT on this view only (I2's third exception, admin_grants.test.sql). It shows
-- what GET /blocklist already serves, plus the category.
--
-- Rollback: drop view admin.v_scam_categories_public;

set local lock_timeout = '1s';
set local statement_timeout = '60s';

create view admin.v_scam_categories_public as
select b.domain, c.id as category, c.label_en, c.label_id
from public.blocklist_entries b
cross join lateral (
  select r.category
  from admin.review_decisions r
  where r.domain = b.domain and r.action in ('approve', 'add')
  order by r.at desc, r.id desc
  limit 1
) d
join admin.categories c on c.id = d.category
where b.approved_at is not null
  and b.removed_at is null
  and c.active
  and c.id <> 'lainnya'
  and not exists (
    select 1 from admin.domain_lists l
    where l.domain = b.domain and (l.trusted or l.protect <> 'none')
  );

comment on view admin.v_scam_categories_public is
  'Approved blocklist domains with the admin''s category, for GET /scams/latest. SELECT for shoo_api.';

revoke all on admin.v_scam_categories_public from public;
grant select on admin.v_scam_categories_public to shoo_admin;
grant select on admin.v_scam_categories_public to shoo_api;
