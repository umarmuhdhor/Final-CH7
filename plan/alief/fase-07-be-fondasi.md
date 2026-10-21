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

Backend bisa dijalankan lokal dan di cloud: Supabase (Postgres + Storage) untuk data, Cloudflare Worker `shoo-api` (Hono) sebagai satu-satunya pintu, auth token per device, dan `GET /blocklist` sudah hidup supaya Imelda bisa memakai bentuk aslinya. Spike singkat memutuskan jalur push APNs.

## Bacaan wajib

- `contracts/api.md` (Devices, Blocklist, bentuk error, auth), `backend/CLAUDE.md`
- `ref/R1` §1, `ref/R2` (seluruhnya), `ref/R3` §1–§5, §7, `SECURITY.md` T3, T7, T8
- Docs resmi (lewat `ecc:documentation-lookup`): Cloudflare Hyperdrive + postgres.js, Workers `nodejs_compat`, `@cloudflare/vitest-plugin`, Supabase CLI (`init`, `start`, `migration new`, `test db`), Supabase Storage REST

## Output

- `backend/.gitignore`, `backend/.env.example`, `backend/README.md` (setup lokal + deploy manual)
- `backend/db/supabase/`: `config.toml`, migrasi `…_init.sql` (enum, tabel R2 §2, trigger I1–I4, role `shoo_api`, grant, RLS), `seed.sql`, `tests/schema.test.sql`, `tests/grants.test.sql`
- `backend/api/`: `package.json`, `wrangler.jsonc` (Hyperdrive binding `DB` + `localConnectionString`, `compatibility_flags: ["nodejs_compat"]`, `triggers.crons` kosong dulu), `src/{index,app,env}.ts`, `src/db/client.ts`, `src/db/repo/devices.ts`, `src/http/{auth,errors,validate,rateLimit}.ts`, `src/routes/{health,devices,blocklist}.ts`, test
- `backend/ci/backend.yml` + `backend/ci/README.md` (draf workflow, inert)
- Log spike APNs di `log/fase-07.md` + keputusan D-alief-16

## Langkah kerja

1. **Supabase lokal.** `cd backend/db && supabase init` (folder `supabase/` di bawah `backend/db`). `supabase start`. Bucket `screenshots` private dibuat lewat migrasi (`insert into storage.buckets (id, name, public) values ('screenshots','screenshots', false)`).
2. **Migrasi awal** sesuai R2 (TDD: tulis `tests/*.test.sql` pgTAP dulu untuk I1–I8, lalu migrasi). Password `shoo_api` lokal diset di `seed.sql` (nilai dev, bukan rahasia). `supabase db reset && supabase test db` hijau.
3. **Worker.** `backend/api`: Hono, zod, postgres; dev: wrangler, typescript, vitest@^4, @cloudflare/vitest-plugin. `db/client.ts` membuat koneksi per request dari `env.DB.connectionString` (`prepare: false` bila memakai pooler transaksi).
4. **Error + auth.** `ApiError` → bentuk kontrak; middleware auth (R3 §2); `x-request-id`.
5. **`POST /devices`** `{ name, mode, apnsToken? }` → buat token `shoo_` + 32 byte, simpan hash, avatar acak → `201 { deviceId, token, avatarId }`. Rate limit per IP.
6. **`PATCH /devices/me`** `{ name?, apnsToken?, language? }` → `{ ok: true }`.
7. **`GET /blocklist?since=`** (R2 §5) → `{ domains: [{ domain, addedAt }], nextSince }`. Data dari `verdicts` (masih kosong sampai fase 10; seed lokal punya 1 domain contoh).
8. **`GET /healthz`**, **`GET /healthz/db`**.
9. **Spike APNs (≤ 30 menit, BELUM DIVERIFIKASI).** Di Worker lokal (`wrangler dev --remote` tidak perlu): tulis `scripts/apns-spike.ts` yang mengirim request HTTP/2 ke `https://api.sandbox.push.apple.com/3/device/<dummy>` dengan JWT dari kunci dummy. Hasil yang diharapkan kalau `fetch` bisa HTTP/2: respons APNs `403 InvalidProviderToken` atau `400 BadDeviceToken` (artinya protokol tembus). Kalau error koneksi/protokol → fallback Edge Function Supabase `push` (Deno) di fase 11. Catat D-alief-16 + bukti. Kalau belum punya kunci asli, ulangi cek dengan `wrangler deploy` saat LANGKAH MANUAL dan catat.
10. **Test** (vitest + vitest-plugin melawan Supabase lokal): 201 device + token hanya dikembalikan sekali, hash di DB ≠ token, 401 tanpa/ salah token, 422 nama 0/21 karakter, mode invalid, `PATCH` hanya diri sendiri, blocklist kosong/berisi + `since`, error JSON rusak → 400 `bad_json`, grant: koneksi role `anon` tidak bisa `select` (pgTAP).
11. **Draf CI** `backend/ci/backend.yml`: job `test` (PR, paths `backend/**`): setup Node 24 + pnpm, `supabase/setup-cli`, `supabase start` di `backend/db`, `supabase test db`, `pnpm -C backend/api test`; job `deploy` (push ke main, `needs: test`): `supabase link` + `supabase db push`, `wrangler deploy` dengan secret repo. `backend/ci/README.md` = langkah C2.
12. **LANGKAH MANUAL deploy pertama** (tulis di log, berhenti): B1–B4 TODO, `supabase db push`, set password `shoo_api` di SQL editor, `wrangler hyperdrive create`, isi `id` Hyperdrive di `wrangler.jsonc` (bukan rahasia), `wrangler deploy`, `curl /healthz`, `curl /healthz/db`, `curl -H "Authorization: Bearer …" /blocklist`. Lalu kirim C7 ke Imelda. Monitor uptime B9.

## Verifikasi

```bash
cd backend/db && supabase start && supabase db reset && supabase test db
cd ../api && pnpm install && pnpm typecheck && pnpm test
pnpm dev &   # wrangler dev :8787
curl -s localhost:8787/healthz
curl -s -X POST localhost:8787/devices -H 'content-type: application/json' -d '{"name":"Adhella","mode":"guardian"}'
```

## Kriteria selesai (DoD)

- [ ] Semua test pgTAP + vitest hijau; angka di log.
- [ ] Token hanya tersimpan sebagai hash; grep log test tidak memuat token.
- [ ] `anon`/`authenticated` tidak punya akses tabel (pgTAP).
- [ ] Keputusan jalur push tercatat (D-alief-16) dengan bukti.
- [ ] LANGKAH MANUAL deploy pertama tertulis; setelah Alief menjalankan: `/healthz` dan `/blocklist` cloud hijau (G3).

## Risiko & fallback

| Risiko | Fallback |
|---|---|
| Hyperdrive tidak tersedia/kuota Free kecil | postgres.js langsung ke pooler Supabase via `connect()` TCP (`nodejs_compat`); catat DECISIONS |
| vitest-plugin tidak bisa menjangkau Postgres lokal | Test integrasi memakai `unstable_dev`/`wrangler dev` + `fetch` dari Node vitest biasa; unit service diuji dengan `postgres` langsung |
| Docker berat di Mac | `supabase start -x studio,imgproxy,edge-runtime,logflare,vector` |

## Catatan handoff

- Fase 08–12 memakai `auth`, `ApiError`, repo pattern, `resetDb()`.
- Bagikan URL Worker ke Imelda (C7) dan simpan di `backend/README.md`.
