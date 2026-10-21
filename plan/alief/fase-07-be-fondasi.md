# Fase 07 — Fondasi backend: Supabase lokal, skema, Worker Hono, auth device, blocklist awal, spike APNs

| Field | Nilai |
|---|---|
| Track | be · worktree `../Final-CH7-be` |
| Branch | `feat/BE-devices` |
| Prasyarat | 00 |
| Requirement | Mandat Fase B: Devices (`POST /devices`, `PATCH /devices/me`, auth token per perangkat), Blocklist (awal, "kerjakan lebih awal") |
| Model | Opus 5.5 · `ecc:api-design`, `ecc:postgres-patterns`, `ecc:database-migrations`, `ecc:backend-patterns`, `ecc:documentation-lookup` |
| Fase berikutnya | 08 |

## Tujuan

Backend bisa dijalankan lokal dan di cloud: Supabase (Postgres + Storage) untuk data, Cloudflare Worker `shoo-api` (Hono) sebagai satu-satunya pintu, auth token per device, dan `GET /blocklist` sudah hidup supaya Imelda bisa memakai bentuk aslinya. Spike di Worker cloud memutuskan apakah push bisa langsung dari Worker atau tetap lewat relay (D-alief-16).

## Bacaan wajib

- `contracts/api.md` (Devices, Blocklist, bentuk error, auth), `backend/CLAUDE.md`
- `ref/R1` §1, `ref/R2` (seluruhnya), `ref/R3` §1–§5, §7, `SECURITY.md` T3, T7, T8, T14, `log/DECISIONS.md` D-alief-16, D-alief-17
- Docs resmi (lewat `ecc:documentation-lookup`): Hyperdrive + Supabase (Direct connection, `--caching-disabled`), postgres.js di Workers (≥ 3.4.5, `nodejs_compat`), Hyperdrive local development (`localConnectionString`, env `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_DB`), `@cloudflare/vitest-plugin` (vitest ≥ 4.1, `cloudflareTest()`, `miniflare.hyperdrives`), Supabase CLI (`init`, `start`, `migration new`, `test db`, pgTAP)

## Output

- `backend/.gitignore`, `backend/.env.example`, `backend/README.md` (setup lokal, deploy manual, **ringkasan skema** — `backend/CLAUDE.md` meminta skema didokumentasikan di `backend/`)
- `backend/db/supabase/`: `config.toml`, migrasi `…_init.sql` (enum, tabel R2 §2 termasuk `ops_heartbeat`, trigger I1–I4, role `shoo_api` **tanpa password**, grant, RLS, bucket `screenshots` private), `seed.sql` (password lokal `shoo_api`, data contoh), `tests/schema.test.sql`, `tests/grants.test.sql` (masing-masing diawali `create extension if not exists pgtap with schema extensions;`)
- `backend/api/`: `package.json` (`postgres@^3.4.5`, `vitest@^4.1.0`, devDependency `wait-on`, scripts `dev`, `test`, `typecheck` = `tsc --noEmit`, `deploy`), `wrangler.jsonc` (Hyperdrive binding `DB` + `localConnectionString`, `id` placeholder sampai LANGKAH MANUAL langkah 3 mengisi id asli — BELUM DIVERIFIKASI apakah `wrangler dev`/vitest menerima placeholder; kalau tidak, pakai env `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_DB` dan catat di log, `compatibility_flags: ["nodejs_compat"]`, `triggers.crons` kosong dulu), `vitest.config.ts` (`cloudflareTest({ wrangler: { configPath: "./wrangler.jsonc" }, miniflare: { hyperdrives: { DB: <URL Postgres lokal> } } })` — bentuk persis dicek di recipe Hyperdrive docs), `src/{index,app,env}.ts`, `src/db/client.ts`, `src/db/repo/devices.ts`, `src/http/{auth,errors,validate,rateLimit}.ts`, `src/routes/{health,devices,blocklist,debug-apns}.ts`, `src/services/push/jwt.ts`, `test/helpers/{resetDb,seed,schema}.ts`, test
- `backend/ci/backend.yml` + `backend/ci/README.md` (draf workflow, inert)
- Hasil spike APNs → entri `D-alief-B01` + bukti di `log/fase-07.md`

## Langkah kerja

1. **Supabase lokal.** `(cd backend/db && supabase init && supabase start)`. Kalau Docker berat: `supabase start -x studio,imgproxy,edge-runtime,logflare,vector` (jangan exclude `edge-runtime` saat fase 11).
2. **Migrasi awal** sesuai R2 (TDD: pgTAP dulu untuk I1–I9, lalu migrasi). Role `shoo_api` dibuat tanpa password; `seed.sql` menjalankan `alter role shoo_api password 'shoo_api_local';`. `(cd backend/db && supabase db reset && supabase test db)` hijau.
3. **Worker.** `backend/api`: hono, zod, `postgres@^3.4.5`; dev: wrangler, typescript, `vitest@^4.1.0`, `@cloudflare/vitest-plugin`, ajv. `db/client.ts` membuat client per request: `postgres(env.DB.connectionString, { max: 5, fetch_types: false })` — **tanpa** `prepare: false` (D-alief-17). Lokal: `localConnectionString = postgres://shoo_api:shoo_api_local@127.0.0.1:54322/postgres` (bukan rahasia; nilai cloud tidak pernah di file).
4. **Error + auth.** `ApiError` → bentuk kontrak (R3 §1); middleware auth (R3 §2); `x-request-id`.
5. **`POST /devices`** `{ name, mode, apnsToken? }` → token `shoo_` + 32 byte, simpan hash, avatar acak → `201 { deviceId, token, avatarId }`. Rate limit per IP.
6. **`PATCH /devices/me`** `{ name?, apnsToken?, language?, extensionLastSeenAt? }` → `{ ok: true }` (kontrak). `extensionLastSeenAt` (ISO) disimpan ke `ext_last_seen_at` (ditolak kalau > 5 menit di masa depan; nilai lebih lama dari yang tersimpan diabaikan). Field tak dikenal diabaikan.
7. **`GET /blocklist?since=`** (R2 §5 butir 5) → `{ domains: [{ domain, addedAt }], nextSince }`. Tabel `blocklist_entries` dibuat di migrasi awal fase ini, lengkap dengan grant `shoo_api` + policy RLS (R2 §3) dan pgTAP `table_privs_are('blocklist_entries', 'shoo_api', …)`; pengisian dari verdict di fase 10. Seed lokal punya 1 domain contoh yang sudah disetujui.
8. **`GET /healthz`**, **`GET /healthz/db`** (upsert `ops_heartbeat`, R3 §4).
9. **Spike APNs (BELUM DIVERIFIKASI, hasil hanya sah dari Worker cloud).** `src/services/push/jwt.ts` (JWT ES256 dari PEM PKCS#8, test vitest dengan kunci uji yang dibuat di test). Spike **tidak butuh `.p8` asli**: endpoint membuat kunci P-256 sekali pakai (`crypto.subtle.generateKey`) dan Key ID/Team ID palsu; respons `403 InvalidProviderToken` dari APNs sudah membuktikan HTTP/2 tembus. `src/routes/debug-apns.ts`: `POST /debug/apns-spike` aktif hanya kalau `APNS_SPIKE=1` dan header `x-spike-key` cocok dengan secret `SPIKE_KEY`; mengirim satu request ke `https://api.sandbox.push.apple.com/3/device/<token dummy 64 hex>` dan mengembalikan status + body + `cf` info. Lulus = respons APNs JSON (`400 BadDeviceToken` atau `403 InvalidProviderToken`/`ExpiredProviderToken`), artinya HTTP/2 tembus. Gagal = error koneksi/protokol atau respons non-APNs. Uji ini dijalankan di LANGKAH MANUAL langkah 12; sampai ada hasil, jalur push = relay (D-alief-16).
10. **Test** (vitest + `cloudflareTest()` melawan Supabase lokal): 201 device + token hanya dikembalikan sekali, hash di DB ≠ token, 401 tanpa/salah token, 422 nama 0/21 karakter, mode invalid, `PATCH` hanya diri sendiri, blocklist kosong/berisi + `since`, JSON rusak → 400 `bad_json`, `/healthz/db` menulis `ops_heartbeat`, `/debug/apns-spike` 404 tanpa flag; pgTAP: `anon`/`authenticated` tidak bisa `select`, `has_role('shoo_api')`. Fallback kalau `miniflare.hyperdrives` tidak bisa menjangkau Postgres lokal: `wrangler dev` + vitest Node biasa yang memanggil `http://localhost:8787` (catat `D-alief-B…`).
11. **Draf CI** `backend/ci/backend.yml`: job `test` (PR, paths `backend/**`): Node 24 + pnpm, `supabase/setup-cli`, `supabase start` di `backend/db`, `supabase test db`, `pnpm -C backend/api test`; job `deploy` (push ke main, `needs: test`): `supabase link` + `supabase db push`, `wrangler deploy` dengan secret repo. `backend/ci/README.md` = langkah C2.
12. **LANGKAH MANUAL deploy pertama** (tulis di log, berhenti):
    1. B1–B3 (proyek Supabase, `supabase link`, `wrangler login`).
    2. `(cd backend/db && supabase db push)`; set password `shoo_api` di SQL editor.
    3. B4: `npx wrangler hyperdrive create shoo-db --connection-string="…Direct connection…" --caching-disabled`; kalau gagal (IPv6), ulangi dengan session pooler 5432 (`shoo_api.<ref>`). Isi `id` Hyperdrive di `wrangler.jsonc` (bukan rahasia).
    4. `npx wrangler secret put SPIKE_KEY`; var `APNS_SPIKE="1"` dan `INVITE_BASE_URL` di `vars` `wrangler.jsonc` (R3 §7); `pnpm -C backend/api run deploy`.
    5. `curl https://shoo-api.<akun>.workers.dev/healthz`, `/healthz/db`, `POST /devices` lalu `GET /blocklist` dengan token itu.
    6. Spike: `curl -X POST …/debug/apns-spike -H "x-spike-key: …"` → tempel hasil ke log, tulis `D-alief-B01` (langsung vs relay). Lalu set `APNS_SPIKE=0` dan deploy ulang.
    7. Kirim C7 ke Imelda. Pasang monitor B9.

## Verifikasi

```bash
(cd backend/db && supabase start && supabase db reset && supabase test db)
pnpm -C backend/api install && pnpm -C backend/api typecheck && pnpm -C backend/api test
(pnpm -C backend/api dev > /tmp/shoo-dev.log 2>&1 &) && pnpm -C backend/api exec wait-on tcp:8787
curl -s localhost:8787/healthz
curl -s -X POST localhost:8787/devices -H 'content-type: application/json' -d '{"name":"Adhella","mode":"guardian"}'
pkill -f "wrangler dev" || true
```

## Kriteria selesai (DoD)

- [ ] Semua test pgTAP + vitest hijau; angka di log.
- [ ] Token hanya tersimpan sebagai hash; grep log test tidak memuat token.
- [ ] `anon`/`authenticated` tidak punya akses tabel (pgTAP).
- [ ] Hyperdrive cloud dibuat dengan `--caching-disabled` (output `wrangler hyperdrive get shoo-db` di log, tanpa password).
- [ ] Hasil spike dari Worker cloud tercatat (`D-alief-B01`) dengan bukti; endpoint debug dimatikan.
- [ ] Setelah Alief menjalankan LANGKAH MANUAL: `/healthz`, `/healthz/db`, `/blocklist` cloud hijau (G3).

## Risiko & fallback

| Risiko | Fallback |
|---|---|
| Direct connection Supabase hanya IPv6 dan Hyperdrive tidak bisa menjangkau | Session pooler port 5432 (`shoo_api.<ref>`), bukan transaction pooler 6543 |
| Hyperdrive bermasalah | postgres.js langsung ke pooler via `connect()` TCP (`nodejs_compat`); catat `D-alief-B…` |
| `cloudflareTest()` tidak bisa menjangkau Postgres lokal | `wrangler dev` + vitest Node biasa (langkah 10) |
| Spike: Worker tidak bisa HTTP/2 ke APNs | Sudah jadi rencana utama: relay Edge Function (fase 11) |
| Docker berat di Mac | `supabase start -x …` (langkah 1) |

## Catatan handoff

- Fase 08–12 memakai `auth`, `ApiError`, repo pattern, `test/helpers/resetDb.ts`, `test/helpers/schema.ts`.
- Bagikan URL Worker ke Imelda (C7) dan simpan di `backend/README.md`.
