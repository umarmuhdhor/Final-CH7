-- Local development data only (supabase db reset). Never run against the cloud project.
-- Dev password for the Worker role: not a secret, local Postgres only (R2 §3).
alter role shoo_api password 'shoo_api_local';
-- Admin dashboard role (ADM-01, migration 20261102190630_admin_schema.sql), local only like the one above.
alter role shoo_admin password 'shoo_admin_local';

-- Devices use the fixture IDs from contracts/fixtures. Local bearer values are
-- 'shoo_local_<id>' (e.g. shoo_local_dev_me); only their sha256 is stored.
insert into devices (id, name, mode, avatar_id, language, token_hash, ext_last_seen_at) values
  ('dev_me',  'Adhella', 'guardian',  'avatar_01', 'id', extensions.digest('shoo_local_dev_me',  'sha256'), null),
  ('dev_mom', 'Mom',     'protected', 'avatar_03', 'id', extensions.digest('shoo_local_dev_mom', 'sha256'), now()),
  ('dev_dad', 'Dad',     'protected', 'avatar_07', 'en', extensions.digest('shoo_local_dev_dad', 'sha256'), now() - interval '3 days');

insert into family_links (protected_id, guardian_id) values
  ('dev_mom', 'dev_me'),
  ('dev_dad', 'dev_me');

-- From contracts/fixtures/blocked-92.json (signals trimmed to one).
insert into scans (id, owner_id, url, domain, page_title, score, status, signals, detected_at) values
  ('6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03', 'dev_mom', 'https://bca-verifikasi.site/login?ref=wa',
   'bca-verifikasi.site', 'KlikBCA - Verifikasi Akun', 92, 'blocked',
   '[{"id":"new_domain","layer":2,"weight":30,"label":{"en":"Domain age 3 days","id":"Umur domain 3 hari"},"labelSimple":{"en":"This site was made 3 days ago","id":"Situs ini baru dibuat 3 hari lalu"}}]'::jsonb,
   '2026-10-21T04:05:00Z');

-- One approved global blocklist domain, one still waiting for review.
insert into blocklist_entries (domain, families, approved_at, approved_by) values
  ('bca-verifikasi.site', 1, '2026-10-21T05:00:00Z', 'seed'),
  ('pending-review.example', 1, null, null);

-- Admin dashboard review queue (ADM-01): three undecided domains, each supported by dev_me's verdict.
-- `select admin.vote('contoh-a.test', 'approve', 'judi', '<note>', 'dev@local')` then serves it on GET /blocklist.
insert into scans (id, owner_id, url, domain, score, status, signals, detected_at) values
  ('6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e11', 'dev_mom', 'https://contoh-a.test/masuk?ref=wa', 'contoh-a.test', 88, 'blocked',
   '[{"id":"new_domain","layer":2,"weight":30,"label":{"en":"Domain age 3 days","id":"Umur domain 3 hari"},"labelSimple":{"en":"This site was made 3 days ago","id":"Situs ini baru dibuat 3 hari lalu"}}]'::jsonb,
   now() - interval '2 hours'),
  ('6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e12', 'dev_dad', 'https://contoh-b.test/hadiah', 'contoh-b.test', 65, 'warning', '[]'::jsonb,
   now() - interval '5 hours'),
  ('6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e13', 'dev_mom', 'https://contoh-c.test/', 'contoh-c.test', 45, 'warning', '[]'::jsonb,
   now() - interval '1 day');

insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name, global_eligible) values
  ('dev_mom', 'contoh-a.test', 'not_safe', '6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e11', 'dev_me', 'Adhella', true),
  ('dev_dad', 'contoh-b.test', 'not_safe', '6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e12', 'dev_me', 'Adhella', true),
  ('dev_mom', 'contoh-c.test', 'not_safe', '6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e13', 'dev_me', 'Adhella', true);

insert into blocklist_entries (domain, families) values
  ('contoh-a.test', 1), ('contoh-b.test', 1), ('contoh-c.test', 1);
