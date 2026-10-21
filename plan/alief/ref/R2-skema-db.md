# R2 — Skema database (Supabase Postgres)

> Sumber kebenaran bentuk JSON tetap `contracts/`. Skema ini hanya cara kita menyimpannya.
> Migrasi di `backend/db/supabase/migrations/`, test di `backend/db/supabase/tests/` (pgTAP). Semua akses dari Worker lewat role `shoo_api`.

## 1. Prinsip

- Postgres tidak diekspos ke klien. PostgREST tidak dipakai: `anon` dan `authenticated` tidak punya grant apa pun di schema `public` (penting juga untuk perubahan grant Supabase 30 Okt 2026).
- RLS **aktif** di semua tabel tanpa policy untuk `anon`/`authenticated` (lapis kedua). Role `shoo_api` diberi `BYPASSRLS = false` tapi punya policy `USING (true)` khusus role itu, sehingga otorisasi tetap di Worker (R3 §3).
- ID: `uuid` (`gen_random_uuid()`), dikirim ke klien sebagai string. Fixture memakai `dev_mom`, jadi kolom ID bertipe `text` supaya seed lokal bisa memakai ID fixture.
- Waktu: `timestamptz`, dikirim ISO 8601 UTC.
- Semua invariant penting ditegakkan di DB (constraint/trigger), bukan hanya di Worker.

## 2. Tabel

```sql
create type device_mode as enum ('guardian', 'protected');
create type scan_status as enum ('warning', 'blocked');
create type verdict_value as enum ('safe', 'not_safe');

create table devices (
  id            text primary key default gen_random_uuid()::text,
  name          text not null check (char_length(name) between 1 and 20),
  mode          device_mode not null,                     -- tidak bisa diubah (trigger devices_mode_immutable)
  avatar_id     text not null check (avatar_id ~ '^avatar_(0[1-9]|1[0-2])$'),
  language      text not null default 'en' check (language in ('en', 'id')),
  apns_token    text,
  token_hash    bytea not null unique,                    -- sha256(token)
  ext_last_seen_at timestamptz,                           -- diisi lewat heartbeat (P1, kalau kontrak ditambah)
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);

create table family_links (
  protected_id  text primary key references devices(id) on delete cascade,  -- satu Protected = satu Guardian
  guardian_id   text not null references devices(id) on delete cascade,
  created_at    timestamptz not null default now(),
  check (protected_id <> guardian_id)
);
create index family_links_guardian on family_links(guardian_id);
-- trigger family_links_check: guardian_id harus mode guardian, protected_id harus mode protected,
-- dan count(*) per guardian_id < 3 sebelum insert (dikunci dengan pg_advisory_xact_lock(hashtext(guardian_id))).

create table family_codes (
  code          char(4) primary key check (code ~ '^[0-9]{4}$'),
  guardian_id   text not null references devices(id) on delete cascade,
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now()
);
create index family_codes_guardian on family_codes(guardian_id);

create table join_attempts (
  id            bigint generated always as identity primary key,
  device_id     text references devices(id) on delete cascade,
  ip            inet,
  success       boolean not null,
  attempted_at  timestamptz not null default now()
);
create index join_attempts_device_time on join_attempts(device_id, attempted_at desc);
create index join_attempts_ip_time on join_attempts(ip, attempted_at desc);

create table scans (
  id              text primary key default gen_random_uuid()::text,
  owner_id        text not null references devices(id) on delete cascade,
  url             text not null check (url ~* '^https?://'),
  domain          text not null check (domain = lower(domain) and domain !~ '^www\.'),
  page_title      text,
  favicon_url     text,
  score           int not null check (score between 30 and 100),
  status          scan_status not null,
  signals         jsonb not null default '[]'::jsonb check (jsonb_typeof(signals) = 'array'),
  screenshot_path text,                                   -- '<owner_id>/<scan_id>.jpg' di bucket screenshots
  detected_at     timestamptz not null,
  created_at      timestamptz not null default now(),
  check ((status = 'blocked') = (score >= 80))
);
create index scans_owner_time on scans(owner_id, detected_at desc, id desc);
create index scans_owner_domain_time on scans(owner_id, domain, created_at desc);
create index scans_created on scans(created_at);

create table verdicts (
  owner_id      text not null references devices(id) on delete cascade,   -- pemilik halaman (Protected atau Guardian sendiri)
  domain        text not null,
  value         verdict_value not null,
  scan_id       text references scans(id) on delete set null,
  by_device_id  text references devices(id) on delete set null,
  by_name       text not null,                            -- snapshot nama saat memutuskan (DT-06)
  decided_at    timestamptz not null default now(),
  primary key (owner_id, domain)
);
create index verdicts_not_safe on verdicts(decided_at) where value = 'not_safe';

create table push_log (                                   -- untuk LogSender, debugging, dan QA
  id            bigint generated always as identity primary key,
  to_device_id  text references devices(id) on delete cascade,
  scan_id       text references scans(id) on delete cascade,
  body          text not null,
  result        text not null,                            -- 'sent' | 'logged' | 'failed:<reason>'
  created_at    timestamptz not null default now()
);
```

## 3. Role dan grant

```sql
create role shoo_api login password :'shoo_api_password' noinherit;   -- password diisi saat migrasi lewat psql var, bukan di file
grant usage on schema public to shoo_api;
grant select, insert, update, delete on devices, family_links, family_codes, join_attempts, scans, verdicts, push_log to shoo_api;
grant usage on all sequences in schema public to shoo_api;
revoke all on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
-- RLS
alter table devices enable row level security;   -- … sama untuk semua tabel
create policy shoo_api_all on devices for all to shoo_api using (true) with check (true);   -- … sama untuk semua tabel
```

Password role `shoo_api` tidak pernah ada di file migrasi. Lokal: diset di `seed.sql` dengan nilai dev `shoo_api_local` (tidak rahasia). Cloud: `alter role shoo_api password '...'` dijalankan Alief lewat SQL editor (LANGKAH MANUAL fase 07).

## 4. Invariant (diuji pgTAP)

| # | Invariant | Penegak |
|---|---|---|
| I1 | `devices.mode` tidak bisa berubah setelah insert | trigger `devices_mode_immutable` |
| I2 | Satu Protected punya paling banyak satu Guardian | PK `family_links.protected_id` |
| I3 | Satu Guardian paling banyak 3 Protected | trigger + advisory lock |
| I4 | Guardian di link = device mode guardian; Protected = mode protected | trigger |
| I5 | Scan selalu skor ≥ 30 dan status konsisten dengan skor | check constraint |
| I6 | Satu verdict per (pemilik, domain), keputusan terakhir menang | PK + `on conflict do update` |
| I7 | `anon`/`authenticated` tidak bisa membaca tabel mana pun | grant + test `has_table_privilege` |
| I8 | `domain` lowercase tanpa `www.` | check constraint |

## 5. Blocklist

`GET /blocklist?since=` = `select domain, max(decided_at) as added_at from verdicts where value = 'not_safe' and decided_at > $since group by domain order by added_at limit 1000`. `nextSince` = `added_at` terakhir. Lihat risiko peracunan (SECURITY T5, D-alief-06).

## 6. Retensi

Cron Worker harian (R4 §4):
```sql
delete from scans where created_at < now() - interval '14 days' returning screenshot_path;  -- lalu hapus objek Storage
delete from family_codes where expires_at < now() - interval '1 hour';
delete from join_attempts where attempted_at < now() - interval '1 day';
delete from push_log where created_at < now() - interval '14 days';
```
Verdict tidak dihapus (D-alief-14).
