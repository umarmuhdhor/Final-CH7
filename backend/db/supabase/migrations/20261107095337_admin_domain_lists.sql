-- ADM-09 admin dashboard (shoo-dashboard plan phase 10a, D-dash-21/22/23, ref/R2 §2–§4): one list of
-- domains that must never be blocked, replacing seven hand-written ones (ai/ POPULAR, SHARED_HOSTS,
-- USER_CONTENT; backend ALLOWLIST, SHARED_ROOTS; the dashboard's copy; admin.shared_hosts).
--   * admin.domain_lists: one row per domain with three separate properties:
--       protect  subtree = never queued/published, subdomains included; apex = this exact name only
--       trusted  official site: layer 3 stays silent there (never on a public suffix or host_path row)
--       hosting  subdomains = anyone can get a subdomain (x.github.io); host_path = anyone can publish a
--                page under this host (docs.google.com/forms/...)
--     plus public_suffix (names under it belong to different owners: co.id, ac.id). The seed is what
--     the old lists did (proven by backend/api/test/domain-lists-golden.test.ts); every seed row is
--     locked, brand rows and the 18 bank/payment rows only the backend listed are hard_locked
--     (changed by migration only, D-dash-22 #4/#9).
--   * admin.domain_match(host): the one matching rule (K2). Backend verdicts (via
--     admin.v_domain_lists_public), admin.vote/add_domain and the dashboard all use it.
--   * admin.domain_set / admin.domain_remove: the dashboard's writes, audited, under advisory lock
--     (7, 1) like every blocklist write, so vote/add_domain cannot race a new row.
--   * admin.shared_hosts (never filled) is replaced by the view admin.v_shared_hosts; review_due()
--     and ai_dataset read it, so layer 5 no longer sends pages on shared hosts to the LLM.
-- New error codes (R2 §4): SA019 allowlisted, SA020 already_blocked (DETAIL = {"domains":[≤20],"total":N}),
-- SA021 domain_not_registrable, SA022 domain_list_full, SA023 brand_locked.
--
-- Rollback (one transaction): re-create admin.shared_hosts + admin.shared_hosts_set from
--   20261104133527_l5_review_data.sql (table, function, RLS, grants); re-run admin.review_due from that
--   file, admin.ai_dataset from 20261104145000_ai_dataset_scan_id.sql, admin.vote from
--   20261103020918_admin_domain_intel.sql and admin.add_domain from 20261102190630_admin_schema.sql; then
--   drop view admin.v_domain_lists, admin.v_domain_lists_public, admin.v_shared_hosts;
--   drop function admin.domain_set, admin.domain_remove, admin.domain_lists_version, admin.domain_match,
--     admin._suffixes, admin._check_list_note;
--   drop table admin.domain_lists, admin.domain_lists_meta; drop function admin._domain_lists_bump;
--   and git revert the backend change (src/data/allowlist.ts comes back).

set local lock_timeout = '1s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------- tables

create table admin.domain_lists (
  -- Same rule as DOMAIN in backend/api/src/http/validate.ts: lowercase, no www., at least one dot.
  domain        text primary key check (
                  char_length(domain) <= 253 and domain !~ '^www\.'
                  and domain ~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'),
  protect       text not null check (protect in ('subtree', 'apex', 'none')),
  trusted       boolean not null default false,
  hosting       text not null default 'none' check (hosting in ('none', 'subdomains', 'host_path')),
  public_suffix boolean not null default false,
  brand_id      text check (brand_id ~ '^[a-z0-9_-]{1,40}$'),
  locked        boolean not null default false,
  hard_locked   boolean not null default false,
  note          text check (char_length(note) <= 300),
  updated_by    text not null check (char_length(updated_by) between 1 and 320),
  updated_at    timestamptz not null default now(),
  check (not (hosting = 'host_path' and trusted)),
  check (not (public_suffix and trusted)),
  check (protect <> 'none' or trusted or hosting <> 'none'),
  check (locked or not hard_locked)
);

-- ETag of the list (dashboard 10b, GET /lists/domains 10c): + 1 per statement that changes rows.
create table admin.domain_lists_meta (
  id         boolean primary key default true check (id),
  version    bigint not null default 0,
  updated_at timestamptz not null default now()
);
insert into admin.domain_lists_meta (id) values (true);

-- Statement-level, so a 300-row seed or an upsert is one version. An upsert fires both the insert
-- and the update trigger; only the one whose transition table has rows counts.
create function admin._domain_lists_bump() returns trigger
language plpgsql set search_path = admin, pg_temp as $$
begin
  if exists (select 1 from changed) then
    update admin.domain_lists_meta set version = version + 1, updated_at = now();
  end if;
  return null;
end $$;

create trigger domain_lists_version_insert after insert on admin.domain_lists
  referencing new table as changed for each statement execute function admin._domain_lists_bump();
create trigger domain_lists_version_update after update on admin.domain_lists
  referencing new table as changed for each statement execute function admin._domain_lists_bump();
create trigger domain_lists_version_delete after delete on admin.domain_lists
  referencing old table as changed for each statement execute function admin._domain_lists_bump();

-- ---------------------------------------------------------------- matching (K2)

-- 'a.b.c.id' → {a.b.c.id, b.c.id, c.id, id}: the host first, then each parent.
create function admin._suffixes(p_host text) returns text[]
language sql immutable set search_path = admin, pg_temp as $$
  select coalesce(array_agg(array_to_string(l[i:], '.') order by i), '{}')
  from (select string_to_array(p_host, '.') as l) x cross join lateral generate_subscripts(x.l, 1) i
$$;

-- protected: a subtree row for the host or a parent, or an apex row for the host itself.
-- trusted:   false under any host_path row, or under a parent with hosting = subdomains (except
--            the parent's own www.); otherwise any trusted row on the host or a parent.
-- hosting:   of the nearest row that has one.
-- Always one row; a host over 253 characters matches nothing.
create function admin.domain_match(p_host text)
returns table (protected boolean, trusted boolean, hosting text)
language sql stable security definer set search_path = admin, pg_temp as $$
  with chain as (
    select s.depth - 1 as depth, r.protect, r.trusted, r.hosting
    from unnest(admin._suffixes(lower(p_host))) with ordinality s(d, depth)
    join admin.domain_lists r on r.domain = s.d
    where char_length(p_host) <= 253
  )
  select
    coalesce(bool_or(c.protect = 'subtree' or (c.protect = 'apex' and c.depth = 0)), false),
    case
      when coalesce(bool_or(c.hosting = 'host_path'), false) then false
      when coalesce(bool_or(c.hosting = 'subdomains' and c.depth > 0
                            and not (c.depth = 1 and lower(p_host) like 'www.%')), false) then false
      else coalesce(bool_or(c.trusted), false)
    end,
    coalesce((array_agg(c.hosting order by c.depth) filter (where c.hosting <> 'none'))[1], 'none')
  from chain c
$$;

-- ---------------------------------------------------------------- views (K8)

create view admin.v_domain_lists as
select domain, protect, trusted, hosting, public_suffix, brand_id, locked, hard_locked, note, updated_by, updated_at
from admin.domain_lists;

-- What the backend (and 10c's extension endpoint) may read: I2's second exception for shoo_api.
create view admin.v_domain_lists_public as
select domain, protect, trusted, hosting from admin.domain_lists;

-- Hosts where anyone can publish a page (was the admin.shared_hosts table).
create view admin.v_shared_hosts as
select domain as host from admin.domain_lists where hosting <> 'none';

-- ---------------------------------------------------------------- seed (K3)

-- Generated by backend/db/scripts/domain-lists-seed.mjs (276 rows). Do not edit by hand.
insert into admin.domain_lists (domain, protect, trusted, hosting, public_suffix, brand_id, locked, hard_locked, note, updated_by) values
  ('000webhostapp.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('1drv.ms', 'apex', false, 'host_path', false, null, true, false, 'seed: L3, multi-tenant', 'seed'),
  ('ac.id', 'apex', false, 'none', true, null, true, false, 'seed: L4, brands suffix', 'seed'),
  ('acrobat.adobe.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('adobe.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('agoda.co.id', 'subtree', true, 'none', false, 'agoda', true, true, 'seed: brands, L4', 'seed'),
  ('agoda.com', 'subtree', true, 'none', false, 'agoda', true, true, 'seed: brands, L4', 'seed'),
  ('airbnb.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('akamaihd.net', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('alodokter.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('amazon.com', 'subtree', true, 'none', false, 'amazon', true, true, 'seed: brands, L1, L4', 'seed'),
  ('amazonaws.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L1, L2', 'seed'),
  ('antaranews.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('anteraja.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('anthropic.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('apple.com', 'subtree', true, 'none', false, 'apple', true, true, 'seed: brands, L1, L4', 'seed'),
  ('appspot.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('azurewebsites.net', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('bankbsi.co.id', 'subtree', true, 'none', false, 'bsi', true, true, 'seed: brands, L4', 'seed'),
  ('bankjago.com', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('bankmandiri.co.id', 'subtree', true, 'none', false, 'mandiri', true, true, 'seed: brands, L4', 'seed'),
  ('bankmega.com', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('bbc.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('bca.co.id', 'subtree', true, 'none', false, 'bca', true, true, 'seed: brands, L1, L4', 'seed'),
  ('bi.go.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('bing.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('bit.ly', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('biz.id', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('blibli.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('blogger.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('blogspot.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('blubybcadigital.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('bni.co.id', 'subtree', true, 'none', false, 'bni', true, true, 'seed: brands, L1, L4', 'seed'),
  ('booking.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('bpjs-kesehatan.go.id', 'subtree', true, 'none', false, 'bpjs', true, true, 'seed: brands, L1', 'seed'),
  ('bpjsketenagakerjaan.go.id', 'subtree', true, 'none', false, 'bpjs', true, true, 'seed: brands, L1', 'seed'),
  ('bri.co.id', 'subtree', true, 'none', false, 'bri', true, true, 'seed: brands, L1, L4', 'seed'),
  ('btn.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('btpn.com', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('bukalapak.com', 'subtree', true, 'none', false, 'bukalapak', true, true, 'seed: brands, L1, L4', 'seed'),
  ('canva.site', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('carrd.co', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('cimbniaga.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('cloud.microsoft', 'apex', false, 'host_path', false, null, true, false, 'seed: multi-tenant', 'seed'),
  ('cloudflare.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('cloudfront.net', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('cnn.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('cnnindonesia.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('co.id', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('co.in', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('co.jp', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('co.kr', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('co.nz', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('co.th', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('co.uk', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('com.au', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('com.br', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('com.cn', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('com.hk', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('com.my', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('com.ph', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('com.sg', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('com.tw', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('com.vn', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('cutt.ly', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('dana.id', 'subtree', true, 'none', false, 'dana', true, true, 'seed: brands, L1, L4', 'seed'),
  ('danamon.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('desa.id', 'apex', false, 'none', true, null, true, false, 'seed: L4, brands suffix', 'seed'),
  ('detik.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('dhl.co.id', 'subtree', true, 'none', false, 'dhl', true, true, 'seed: brands, L4', 'seed'),
  ('dhl.com', 'subtree', true, 'none', false, 'dhl', true, true, 'seed: brands, L4', 'seed'),
  ('discord.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('docs.google.com', 'none', false, 'host_path', false, null, true, false, 'seed: L2, L3', 'seed'),
  ('doku.com', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('drive.google.com', 'none', false, 'host_path', false, null, true, false, 'seed: L2, L3', 'seed'),
  ('dropbox.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('duckdns.org', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('duckduckgo.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('ebay.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('express.adobe.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('facebook.com', 'subtree', true, 'none', false, 'meta', true, true, 'seed: brands, L1, L4', 'seed'),
  ('fastly.net', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('fb.com', 'subtree', true, 'none', false, 'meta', true, true, 'seed: brands, L4', 'seed'),
  ('fb.me', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('fbcdn.net', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('firebaseapp.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L3, L4 shared', 'seed'),
  ('firebasestorage.googleapis.com', 'apex', false, 'host_path', false, null, true, false, 'seed: multi-tenant', 'seed'),
  ('fly.dev', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('forms.cloud.microsoft', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('forms.gle', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('forms.microsoft.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('forms.office.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('framer.app', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('framer.website', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('gist.github.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('github.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('github.io', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('githubusercontent.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('gitlab.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('gitlab.io', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('glitch.me', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('gmail.com', 'subtree', true, 'none', false, 'google', true, true, 'seed: brands, L4', 'seed'),
  ('go.id', 'subtree', false, 'none', true, null, true, false, 'seed: L1, L4, brands suffix', 'seed'),
  ('godaddysites.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('gojek.com', 'subtree', true, 'none', false, 'gopay', true, true, 'seed: brands, L1, L4', 'seed'),
  ('goo.gl', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('google.co.id', 'subtree', true, 'none', false, 'google', true, true, 'seed: brands, L4', 'seed'),
  ('google.com', 'subtree', true, 'none', false, 'google', true, true, 'seed: brands, L1, L4', 'seed'),
  ('googleapis.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L1, L2', 'seed'),
  ('googleusercontent.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L1, L2', 'seed'),
  ('gopay.co.id', 'subtree', true, 'none', false, 'gopay', true, true, 'seed: brands, L1, L4', 'seed'),
  ('grab.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('gramedia.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('gstatic.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L1, L2', 'seed'),
  ('halodoc.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('herokuapp.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('icloud.com', 'subtree', true, 'none', false, 'apple', true, true, 'seed: brands, L1, L4', 'seed'),
  ('idntimes.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('in.th', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('indihome.co.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('indonesia.go.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('indosatooredoo.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('infinityfreeapp.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('instagram.com', 'subtree', true, 'none', false, 'meta', true, true, 'seed: brands, L1, L4', 'seed'),
  ('is.gd', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('jd.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('jenius.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('jet.co.id', 'subtree', true, 'none', false, 'jnt', true, true, 'seed: brands, L1, L4', 'seed'),
  ('jimdofree.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('jne.co.id', 'subtree', true, 'none', false, 'jne', true, true, 'seed: brands, L1, L4', 'seed'),
  ('jntexpress.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('kai.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('kaskus.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('kemdikbud.go.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('kemenkeu.go.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('kemensos.go.id', 'subtree', true, 'none', false, 'kemensos', true, true, 'seed: brands, L1', 'seed'),
  ('kemkes.go.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('klikbca.com', 'subtree', true, 'none', false, 'bca', true, true, 'seed: brands, L4', 'seed'),
  ('kominfo.go.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('kompas.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('kumparan.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('lazada.co.id', 'subtree', true, 'none', false, 'lazada', true, true, 'seed: brands, L1, L4', 'seed'),
  ('lazada.com', 'subtree', true, 'none', false, 'lazada', true, true, 'seed: brands, L4', 'seed'),
  ('linkaja.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('linkedin.cn', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('linkedin.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('linktr.ee', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('liputan6.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('live.com', 'subtree', true, 'none', false, 'microsoft', true, true, 'seed: brands, L1, L4', 'seed'),
  ('live.net', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('livin.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('lps.go.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('mandiri.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('maybank.co.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('mediafire.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('medium.com', 'subtree', true, 'subdomains', false, null, true, false, 'seed: L1', 'seed'),
  ('mega.nz', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('meta.com', 'subtree', true, 'none', false, 'meta', true, true, 'seed: brands, L4', 'seed'),
  ('microsoft.com', 'subtree', true, 'none', false, 'microsoft', true, true, 'seed: brands, L1, L4', 'seed'),
  ('microsoftonline.com', 'subtree', true, 'none', false, 'microsoft', true, true, 'seed: brands, L1, L4', 'seed'),
  ('midtrans.com', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('mil.id', 'apex', false, 'none', true, null, true, false, 'seed: L4, brands suffix', 'seed'),
  ('mozilla.org', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('my.id', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('myshopify.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('mystrikingly.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('mzstatic.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('net.id', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('netflix.com', 'subtree', true, 'none', false, 'netflix', true, true, 'seed: brands, L1, L4', 'seed'),
  ('netlify.app', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('ngrok-free.app', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('ngrok.io', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('notion.site', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('nytimes.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('ocbc.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('office.com', 'subtree', true, 'none', false, 'microsoft', true, true, 'seed: brands, L1, L4', 'seed'),
  ('office365.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('ojk.go.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('olx.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('onedrive.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('onedrive.live.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('onrender.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('openai.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('or.id', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('org.uk', 'apex', false, 'none', true, null, true, false, 'seed: brands suffix', 'seed'),
  ('outlook.com', 'subtree', true, 'none', false, 'microsoft', true, true, 'seed: brands, L1, L4', 'seed'),
  ('ovo.id', 'subtree', true, 'none', false, 'ovo', true, true, 'seed: brands, L1, L4', 'seed'),
  ('page.link', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('pages.dev', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('pajak.go.id', 'subtree', true, 'none', false, 'djp', true, true, 'seed: brands, L1', 'seed'),
  ('panin.co.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('paper.dropbox.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('paypal.com', 'subtree', true, 'none', false, 'paypal', true, true, 'seed: brands, L1, L4', 'seed'),
  ('permatabank.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('pertamina.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('pinterest.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('pln.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('polri.go.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('ponpes.id', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared', 'seed'),
  ('pos.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('posindonesia.co.id', 'subtree', true, 'none', false, 'posindonesia', true, true, 'seed: brands, L4', 'seed'),
  ('r2.dev', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('rebrand.ly', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('reddit.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('repl.co', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('replit.app', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('ruangguru.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('s.id', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('s3.amazonaws.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('sch.id', 'apex', false, 'none', true, null, true, false, 'seed: L4, brands suffix', 'seed'),
  ('script.google.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('seabank.co.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('sharepoint.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L3', 'seed'),
  ('shopee.co.id', 'subtree', true, 'none', false, 'shopee', true, true, 'seed: brands, L1, L4', 'seed'),
  ('shopee.com', 'subtree', true, 'none', false, 'shopee', true, true, 'seed: brands, L4', 'seed'),
  ('shopeepay.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('sicepat.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('sites.google.com', 'none', false, 'host_path', false, null, true, false, 'seed: L2, L3', 'seed'),
  ('sites.live.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('smartfren.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('sociolla.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('spark.adobe.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('spotify.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('square.site', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('squarespace.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('stackoverflow.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('storage.googleapis.com', 'apex', false, 'host_path', false, null, true, false, 'seed: L3, multi-tenant', 'seed'),
  ('sway.office.com', 'none', false, 'host_path', false, null, true, false, 'seed: L3', 'seed'),
  ('t.co', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('t.me', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('telegram.org', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('telkom.co.id', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('telkomsel.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('tempo.co', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('theguardian.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('tiket.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('tiki.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('tiktok.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('tinyurl.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('tokopedia.com', 'subtree', true, 'none', false, 'tokopedia', true, true, 'seed: brands, L1, L4', 'seed'),
  ('tokopedia.link', 'subtree', false, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('translate.goog', 'apex', false, 'subdomains', false, null, true, false, 'seed: L4 shared', 'seed'),
  ('traveloka.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('traveloka.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('tribunnews.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('tripadvisor.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('trycloudflare.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('tumblr.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('twitch.tv', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('twitter.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('typedream.app', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('uber.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('uob.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('vercel.app', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('wa.me', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('web.app', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L3, L4 shared', 'seed'),
  ('web.id', 'apex', false, 'none', true, null, true, false, 'seed: L4 shared, brands suffix', 'seed'),
  ('webflow.io', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('webwave.me', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('weebly.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('whatsapp.com', 'subtree', true, 'none', false, 'meta', true, true, 'seed: brands, L1, L4', 'seed'),
  ('wikipedia.org', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('windows.net', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('wix.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('wixsite.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('wordpress.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('workers.dev', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2, L4 shared', 'seed'),
  ('x.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('xendit.co', 'subtree', false, 'none', false, null, true, true, 'seed: L4', 'seed'),
  ('xl.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('yahoo.com', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed'),
  ('yolasite.com', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('youtu.be', 'apex', false, 'subdomains', false, null, true, false, 'seed: L2', 'seed'),
  ('youtube.com', 'subtree', true, 'none', false, 'google', true, true, 'seed: brands, L1, L4', 'seed'),
  ('zalora.co.id', 'subtree', true, 'none', false, null, true, false, 'seed: L1', 'seed'),
  ('zoom.us', 'subtree', true, 'none', false, null, true, false, 'seed: L1, L4', 'seed');

-- ---------------------------------------------------------------- dashboard writes (K5–K7)

-- At least 10 characters (as review_decisions), at most 300 (the column).
create function admin._check_list_note(p_note text) returns void
language plpgsql immutable set search_path = admin, pg_temp as $$
begin
  if p_note is null or char_length(btrim(p_note)) < 10 or char_length(p_note) > 300 then
    raise exception using errcode = 'SA003', message = 'note_required';
  end if;
end $$;

-- Upsert one row. brand_id, locked and hard_locked never change here (only by migration).
-- p_confirm = the domain typed again (checked here, not only in the Worker), needed to change a
-- locked row and to switch on trusted, subtree or public_suffix. The DB has no Public Suffix List:
-- trusted on a suffix that is not in the seed (com.ng) is stopped only by that confirmation.
-- A row that newly protects blocked domains (the domain, or its subdomains for subtree) fails with
-- already_blocked and their list in DETAIL until p_confirm_unblock = their total; then each one is
-- removed from the blocklist (admin.remove_domain, audited) in this transaction (D-dash-22 #8).
create function admin.domain_set(p_domain text, p_protect text, p_trusted boolean, p_hosting text,
  p_public_suffix boolean, p_note text, p_actor text, p_confirm text default null, p_confirm_unblock int default null)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_old     admin.domain_lists;
  v_new     admin.domain_lists;
  v_blocked text[] := '{}';
  v_total   int;
  d         text;
begin
  perform admin._check_actor(p_actor);
  perform admin._check_domain(p_domain, true);
  perform admin._check_list_note(p_note);
  if p_protect is null or p_protect not in ('subtree', 'apex', 'none')
     or p_hosting is null or p_hosting not in ('none', 'subdomains', 'host_path')
     or p_trusted is null or p_public_suffix is null
     or (p_protect = 'none' and not p_trusted and p_hosting = 'none') then
    raise exception using errcode = '22023', message = 'invalid_argument';
  end if;
  perform admin._require_read_committed();   -- K7 must see approvals committed while it waited
  perform pg_advisory_xact_lock(7, 1);
  select * into v_old from admin.domain_lists where domain = p_domain for update;
  if v_old.hard_locked then
    raise exception using errcode = 'SA023', message = 'brand_locked';
  end if;
  if v_old.domain is null and (select count(*) from admin.domain_lists) >= 5000 then
    raise exception using errcode = 'SA022', message = 'domain_list_full';
  end if;
  -- trusted = one official site: never a TLD, a public suffix or a host anyone publishes on.
  if p_trusted and (position('.' in p_domain) = 0 or p_public_suffix or p_hosting = 'host_path') then
    raise exception using errcode = 'SA021', message = 'domain_not_registrable';
  end if;
  -- A hosting row that protects nothing itself must sit under a subtree row (docs.google.com) or a
  -- protected multi-tenant host (forms.cloud.microsoft under cloud.microsoft, D-dash-24), so its
  -- registrable domain can never be queued whole.
  if p_hosting <> 'none' and p_protect = 'none' and not exists (
       select 1 from admin.domain_lists r
        where r.domain = any((admin._suffixes(p_domain))[2:])
          and (r.protect = 'subtree' or (r.protect <> 'none' and r.hosting = 'host_path'))) then
    raise exception using errcode = 'SA021', message = 'domain_not_registrable';
  end if;
  -- K7, before the confirm check, so the admin always sees the list first.
  if p_protect <> 'none' then
    select coalesce(array_agg(b.domain order by b.domain), '{}') into v_blocked
    from public.blocklist_entries b
    where b.approved_at is not null and b.removed_at is null
      and (b.domain = p_domain or (p_protect = 'subtree' and b.domain like '%.' || p_domain))
      and not (select m.protected from admin.domain_match(b.domain) m);
    v_total := cardinality(v_blocked);
    if v_total > 0 and p_confirm_unblock is distinct from v_total then
      raise exception using errcode = 'SA020', message = 'already_blocked',
        detail = jsonb_build_object('domains', to_jsonb(v_blocked[1:20]), 'total', v_total)::text;
    end if;
  end if;
  if (coalesce(v_old.locked, false)
      or (p_trusted and not coalesce(v_old.trusted, false))
      or (p_protect = 'subtree' and v_old.protect is distinct from 'subtree')
      or (p_public_suffix and not coalesce(v_old.public_suffix, false)))
     and p_confirm is distinct from p_domain then
    raise exception using errcode = 'SA011', message = 'confirm_required';
  end if;

  insert into admin.domain_lists as l (domain, protect, trusted, hosting, public_suffix, note, updated_by, updated_at)
  values (p_domain, p_protect, p_trusted, p_hosting, p_public_suffix, p_note, p_actor, now())
  on conflict (domain) do update
    set protect = excluded.protect, trusted = excluded.trusted, hosting = excluded.hosting,
        public_suffix = excluded.public_suffix, note = excluded.note, updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
  returning * into v_new;
  perform admin._audit(p_actor, 'domain_list.set', p_domain,
    case when v_old.domain is null then null else to_jsonb(v_old) end, to_jsonb(v_new), p_note);
  -- Last: remove_domain changes blocklist_entries timestamps (GET /blocklist?since= cursor).
  foreach d in array v_blocked loop
    perform admin.remove_domain(d, p_note, p_actor);
  end loop;
end $$;

-- Delete one row. Removing never blocks anything; a locked row needs the domain typed again.
create function admin.domain_remove(p_domain text, p_note text, p_actor text, p_confirm text default null)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_old admin.domain_lists;
begin
  perform admin._check_actor(p_actor);
  perform admin._check_domain(p_domain, false);
  perform admin._check_list_note(p_note);
  perform admin._require_read_committed();
  perform pg_advisory_xact_lock(7, 1);
  select * into v_old from admin.domain_lists where domain = p_domain for update;
  if not found then
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
  if v_old.hard_locked then
    raise exception using errcode = 'SA023', message = 'brand_locked';
  end if;
  if v_old.locked and p_confirm is distinct from p_domain then
    raise exception using errcode = 'SA011', message = 'confirm_required';
  end if;
  delete from admin.domain_lists where domain = p_domain;
  perform admin._audit(p_actor, 'domain_list.remove', p_domain, to_jsonb(v_old), null, p_note);
end $$;

create function admin.domain_lists_version()
returns table (version bigint, updated_at timestamptz)
language sql stable security definer set search_path = admin, pg_temp as $$
  select m.version, m.updated_at from admin.domain_lists_meta m
$$;

-- ---------------------------------------------------------------- vote / add_domain (K10)

-- True when p_domain must not be blocked: domain_match protects it, or it is a parent of a
-- hard_locked row (security review 10a: after an admin removes the co.id row, co.id still cannot
-- be approved above bca.co.id). Exact suffix comparison, no LIKE: vote's domain check is loose.
create function admin._refuses_block(p_domain text) returns boolean
language sql stable set search_path = admin, pg_temp as $$
  select (select m.protected from admin.domain_match(p_domain) m)
      or exists (select 1 from admin.domain_lists r
                  where r.hard_locked and p_domain = any((admin._suffixes(r.domain))[2:]))
$$;

-- 02a admin.vote (20261103020918_admin_domain_intel.sql) + the allowlisted check after the lock. Nothing
-- else changed. The Worker checks first (friendly message); this is the line that holds (SECURITY A5).
create or replace function admin.vote(p_domain text, p_action text, p_category text, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
declare
  v_category text;
begin
  if p_action is null or p_action not in ('approve', 'reject') then
    raise exception using errcode = '22023', message = 'invalid_action';
  end if;
  perform admin._check_domain(p_domain, false);
  perform admin._require_note(p_note);
  if p_action = 'approve' then
    perform admin._check_category(p_category);
    v_category := p_category;
    perform admin._require_read_committed();
  end if;
  perform pg_advisory_xact_lock(7, 1);
  if p_action = 'approve' then
    -- 10a K10: after the lock, which domain_set takes too, so a row added meanwhile is seen.
    if admin._refuses_block(p_domain) then
      raise exception using errcode = 'SA019', message = 'allowlisted';
    end if;
    perform admin._check_publish_cap();
  end if;

  insert into admin.review_decisions (domain, action, category, note, actor)
  values (p_domain, p_action, v_category, p_note, p_actor);
  perform admin._audit(p_actor, 'blocklist.' || p_action, p_domain, '{"status": "pending"}',
    jsonb_build_object('status', case p_action when 'approve' then 'approved' else 'rejected' end, 'category', v_category),
    p_note);
  insert into admin.domain_labels (domain, is_scam, note, category, source, connected, ai_score, ai_status, actor)
  select p_domain, p_action = 'approve', p_note, v_category, 'admin', true, s.score, s.status::text, p_actor
  from (select 1) one
  left join lateral (select score, status from public.scans
                      where domain = p_domain order by created_at desc, id desc limit 1) s on true;

  -- First vote wins (R4 §1, I4): only an undecided row changes. A concurrent vote waits on the
  -- advisory lock, then matches 0 rows here and rolls back its decision, audit and label rows.
  if p_action = 'approve' then
    update public.blocklist_entries set approved_at = now(), approved_by = p_actor   -- trigger: clock_timestamp()
     where domain = p_domain and approved_at is null and rejected_at is null and removed_at is null;
  else
    update public.blocklist_entries set rejected_at = now(), rejected_by = p_actor
     where domain = p_domain and approved_at is null and rejected_at is null and removed_at is null;
  end if;
  if not found then
    if exists (select 1 from public.blocklist_entries where domain = p_domain) then
      raise exception using errcode = 'SA001', message = 'already_decided';
    end if;
    raise exception using errcode = 'SA002', message = 'not_found';
  end if;
end $$;

-- 01a admin.add_domain (20261102190630_admin_schema.sql) + the same check. Nothing else changed.
create or replace function admin.add_domain(p_domain text, p_category text, p_note text, p_actor text)
returns void
language plpgsql security definer set search_path = admin, pg_temp as $$
begin
  perform admin._check_domain(p_domain, true);
  perform admin._require_note(p_note);
  perform admin._check_category(p_category);
  perform admin._require_read_committed();
  perform pg_advisory_xact_lock(7, 1);
  if admin._refuses_block(p_domain) then   -- 10a K10, as vote
    raise exception using errcode = 'SA019', message = 'allowlisted';
  end if;
  perform admin._check_publish_cap();
  insert into admin.review_decisions (domain, action, category, note, actor)
  values (p_domain, 'add', p_category, p_note, p_actor);
  perform admin._audit(p_actor, 'blocklist.add', p_domain,
    jsonb_build_object('status', admin._entry_status(p_domain)),
    jsonb_build_object('status', 'approved', 'category', p_category), p_note);
  insert into public.blocklist_entries as b (domain, families, approved_at, approved_by)
  values (p_domain, 0, clock_timestamp(), p_actor)
  on conflict (domain) do update
    set approved_at = clock_timestamp(), approved_by = excluded.approved_by,
        rejected_at = null, rejected_by = null, removed_at = null
    where b.approved_at is null or b.removed_at is not null;
  if not found then
    raise exception using errcode = 'SA005', message = 'already_approved';
  end if;
end $$;

-- ---------------------------------------------------------------- shared hosts (K11)

-- L5 review_due (20261104133527_l5_review_data.sql) reading v_shared_hosts by exact suffix (primary key
-- lookups instead of a LIKE join over up to 5000 rows; same result). Nothing else changed.
create or replace function admin.review_due(p_limit int)
returns table (domain text, input jsonb)
language sql stable security definer set search_path = admin, pg_temp as $$
  select b.domain,
         jsonb_build_object(
           'domain', b.domain,
           'signal_counts', coalesce(d.signal_counts, '{}'),
           'avg_score', case when d.scans > 0 then round(d.sum_score::numeric / d.scans)::int end,
           'max_score', d.max_score,
           'families_safe', coalesce(l.families_safe, 0),
           'families_not_safe', coalesce(l.families_not_safe, 0))
  from public.blocklist_entries b
  left join admin.domain_intel d on d.domain = b.domain
  left join admin.domain_intel_label l on l.domain = b.domain
  where b.approved_at is null and b.rejected_at is null and b.removed_at is null and b.families > 0
    and not exists (select 1 from admin.v_shared_hosts h where h.host = any(admin._suffixes(b.domain)))
    and not exists (select 1 from admin.domain_review r
                     where r.domain = b.domain
                       and r.reviewed_at >= coalesce((select max(x.created_at) from admin.domain_labels x
                                                       where x.domain = b.domain), '-infinity'))
  order by b.families desc, b.first_seen_at, b.domain
  limit least(greatest(coalesce(p_limit, 0), 0), 100)
$$;

-- ai_dataset (20261104145000_ai_dataset_scan_id.sql) reading v_shared_hosts. Same columns, same order;
-- create or replace keeps the grants (shoo_admin, shoo_ai). shoo_ai needs no grant on v_shared_hosts:
-- relations inside a view are read with the view owner's privileges.
create or replace view admin.ai_dataset with (security_barrier = true) as
select
  l.id,
  l.id as label_id,
  case when a.scan_id is not null
       then 'https://' || coalesce(a.host, a.domain) || admin.tokenize_path(a.url_path) end as url,
  l.domain,
  a.rdap_registered_at,
  (a.detected_at at time zone 'UTC')::date - a.rdap_registered_at as rdap_age_days,
  coalesce(p.layer1, '[]') as layer1,
  coalesce(p.layer2, '[]') as layer2,
  coalesce(p.layer3, '[]') as layer3,
  coalesce(p.layer4, '[]') as layer4,
  coalesce(p.layer1_score, 0) as layer1_score,
  coalesce(p.layer2_score, 0) as layer2_score,
  coalesce(p.layer3_score, 0) as layer3_score,
  coalesce(p.layer4_score, 0) as layer4_score,
  coalesce(a.score, l.ai_score) as score,
  coalesce(a.status, l.ai_status) as status,
  l.thresholds_version,
  a.detected_at as scanned_at,
  l.is_scam,
  admin.mask_note(l.note) as note,
  l.created_at as decided_at,
  l.owner_ref is null as anonymous,
  d.scans as domain_scans,
  case when d.scans > 0 then round(d.sum_score::numeric / d.scans)::int end as domain_avg_score,
  d.max_score as domain_max_score,
  dl.families_safe,
  dl.families_not_safe,
  dl.label as final_label,
  exists (select 1 from admin.v_shared_hosts h where l.domain = h.host or l.domain like '%.' || h.host) as shared_host,
  rv.result as review_result,
  rv.suggestion as review_suggestion,
  rv.decision as review_decision,
  a.scan_id,
  a.fragments_key is not null as has_fragments
from admin.domain_labels l
left join admin.scan_archive a on a.scan_id = l.scan_id
left join lateral (
  select
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '1') as layer1,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '2') as layer2,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '3') as layer3,
    jsonb_agg(e - 'layer') filter (where (e ->> 'layer') = '4') as layer4,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '1')::int as layer1_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '2')::int as layer2_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '3')::int as layer3_score,
    sum((e ->> 'weight')::int) filter (where (e ->> 'layer') = '4')::int as layer4_score
  from jsonb_array_elements(coalesce(a.signals, '[]')) e
  where (e ->> 'weight') ~ '^[0-9]{1,3}$'
) p on true
left join admin.domain_intel d on d.domain = l.domain
left join admin.domain_intel_label dl on dl.domain = l.domain
left join lateral (
  select r.result, r.suggestion, r.decision
  from admin.domain_review r where r.domain = l.domain
  order by r.reviewed_at desc, r.id desc limit 1
) rv on true
where l.source = 'guardian'
  and not (l.owner_ref is not null and exists (
    select 1 from admin.label_forget f
     where l.created_at <= f.at
       and ((f.by_ref is null and (f.owner_ref = l.owner_ref or f.owner_ref = l.by_ref))
            or (f.owner_ref = l.owner_ref and f.by_ref = l.by_ref))));

drop function admin.shared_hosts_set(text[], text, text);
drop table admin.shared_hosts;

-- ---------------------------------------------------------------- privileges (K13)

alter table admin.domain_lists enable row level security;
alter table admin.domain_lists_meta enable row level security;

revoke all on admin.domain_lists, admin.domain_lists_meta, admin.v_domain_lists, admin.v_domain_lists_public,
  admin.v_shared_hosts
  from public, anon, authenticated, service_role, shoo_api, shoo_admin, shoo_ai;
revoke all on function admin._domain_lists_bump(), admin._suffixes(text), admin._check_list_note(text),
  admin._refuses_block(text),
  admin.domain_match(text),
  admin.domain_set(text, text, boolean, text, boolean, text, text, text, int),
  admin.domain_remove(text, text, text, text),
  admin.domain_lists_version()
  from public, anon, authenticated, service_role, shoo_api, shoo_admin, shoo_ai;

grant select on admin.v_domain_lists, admin.v_domain_lists_public, admin.v_shared_hosts to shoo_admin;
-- I2's second exception (after public_config): POST /verdicts reads it in its transaction (W16).
grant select on admin.v_domain_lists_public to shoo_api;
grant execute on function
  admin.domain_match(text),
  admin.domain_set(text, text, boolean, text, boolean, text, text, text, int),
  admin.domain_remove(text, text, text, text),
  admin.domain_lists_version()
to shoo_admin;

revoke all on all functions in schema admin from public;
