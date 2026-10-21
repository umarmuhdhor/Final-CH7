# Log fase 07 — Fondasi backend + auth + blocklist awal

| Field | Nilai |
|---|---|
| Status | `[m]` berhenti di LANGKAH MANUAL (deploy cloud pertama). Belum ada PR |
| Track / branch | be · `feat/BE-devices` (worktree sesi `track-be-776b81`, menggantikan `../Final-CH7-be`) |
| Basis | ditumpuk di atas `docs/alief-plan-sync` (PR #7, belum di-merge) → PR nanti menulis "Stacked on #7", rebase ke `main` setelah #7 merge |
| Mulai | 21 Okt 2026 21:04 WITA |
| Model | Opus 5.5 |

## Ringkasan rencana

Rencana lengkap: [`fase-07-plan.md`](fase-07-plan.md). Supabase lokal + migrasi R2 (pgTAP dulu), Worker Hono dengan error/auth/validasi sesuai kontrak, `POST /devices`, `PATCH /devices/me` (termasuk `extensionLastSeenAt`), `GET /blocklist?since=` (hanya entri disetujui, `removed[]`), `/healthz` + `/healthz/db`, JWT ES256 APNs + endpoint spike, draf CI. Cloud = LANGKAH MANUAL. `GET /devices/me` tetap di fase 08 (D-alief-38).

## Checklist langkah kerja

- [x] 1. Supabase lokal (`supabase init`, `project_id = "shoo"`, `supabase start -x studio,imgproxy,edge-runtime,logflare,vector,mailpit,realtime,postgres-meta,supavisor`)
- [x] 2. Migrasi awal + pgTAP (I1–I9, RLS, bucket private), seed lokal
- [x] 3. Worker `backend/api` (hono 4.13, zod 4.6, postgres 3.4.9; vitest 4.1.12 + `@cloudflare/vitest-plugin` 1.4.6)
- [x] 4. Error + auth + `x-request-id`
- [x] 5. `POST /devices` + rate limit 10/jam per IP
- [x] 6. `PATCH /devices/me` (`extensionLastSeenAt` → `ext_last_seen_at`, maju saja, tolak > 5 menit di depan)
- [x] 7. `GET /blocklist?since=` + `blocklist_entries` (grant, RLS, pgTAP), seed 1 domain disetujui
- [x] 8. `/healthz`, `/healthz/db` (upsert `ops_heartbeat`, 1/menit per IP)
- [x] 9. Spike APNs: kode `jwt.ts` + `POST /debug/apns-spike` siap; **uji di Worker cloud = LANGKAH MANUAL 6**
- [x] 10. Test vitest + pgTAP
- [x] 11. Draf CI `backend/ci/backend.yml` + `backend/ci/README.md`
- [ ] 12. LANGKAH MANUAL deploy pertama (di bawah) — menunggu Alief
- [ ] Setelah 12: `D-alief-B01`, review (langkah 8 PROMPT), verifikasi ulang, PR

## File dibuat / diubah

- `backend/.gitignore`, `backend/.env.example`, `backend/README.md` (setup, endpoint, ringkasan skema, deploy)
- `backend/db/supabase/config.toml`, `.gitignore`, `migrations/20261021130000_init.sql`, `seed.sql`, `tests/schema.test.sql`, `tests/grants.test.sql`
- `backend/api/package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml` (`allowBuilds` esbuild + workerd untuk pnpm 12), `tsconfig.json`, `wrangler.jsonc`, `vitest.config.ts`, `.dev.vars.example`
- `backend/api/src/{index,app,env}.ts`, `db/client.ts`, `db/repo/{devices,blocklist}.ts`, `http/{auth,errors,validate,rateLimit,crypto}.ts`, `routes/{health,devices,blocklist,debug-apns}.ts`, `services/push/jwt.ts`
- `backend/api/test/{devices,blocklist,health,apns}.test.ts`, `test/helpers/{resetDb,seed}.ts`, `test/env.d.ts`
- `backend/ci/backend.yml`, `backend/ci/README.md`
- `plan/alief/log/{fase-07,fase-07-plan}.md`, `log/DECISIONS.md` (B02–B04), `PROGRESS.md` (baris 07)

## Hasil verifikasi (lokal, 21 Okt 2026 ±21:18 WITA)

| Perintah | Hasil |
|---|---|
| `(cd backend/db && supabase db reset && supabase test db)` | `Files=2, Tests=58` · `Result: PASS` |
| `pnpm -C backend/api typecheck` | bersih (0 error) |
| `pnpm -C backend/api test` | `Test Files 4 passed (4)` · `Tests 34 passed (34)` · 3,2 s · 0 error |
| `pnpm -C backend/api dev` + curl | `/healthz` → `{"ok":true}`; `/healthz/db` → `{"ok":true}`; `POST /devices` → `{"deviceId":"c001b7a6-…","token":"<redacted>","avatarId":"avatar_11"}`; `GET /blocklist` (token itu) → `{"domains":[],"nextSince":null}`; `PATCH /devices/me {"language":"id"}` → `{"ok":true}`; `POST /debug/apns-spike` → `404` |
| grep token di log | `grep -cE "shoo_[A-Za-z0-9_-]{43}"` di log vitest = 0; token curl di log `wrangler dev` = 0 |

Placeholder Hyperdrive `id` (`000…0`) diterima `wrangler dev` dan vitest (`localConnectionString` / `miniflare.hyperdrives`), jadi env `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_DB` tidak dibutuhkan (butir BELUM DIVERIFIKASI di file fase terjawab).

Catatan TDD: pgTAP dan vitest ditulis sebelum/bersama kode; satu bug nyata ditemukan test (`since` kehilangan mikrodetik, D-alief-B03).

## DoD

- [x] Semua test pgTAP + vitest hijau; angka di atas.
- [x] Token hanya tersimpan sebagai hash (`devices.test.ts` "creates a device and returns the token once"); grep log test tidak memuat token.
- [x] `anon`/`authenticated` tidak punya akses tabel (`grants.test.sql`, 20 assert `table_privs_are … array[]`).
- [ ] Hyperdrive cloud dibuat dengan `--caching-disabled` — LANGKAH MANUAL 3.
- [ ] Hasil spike dari Worker cloud tercatat (`D-alief-B01`); endpoint debug dimatikan — LANGKAH MANUAL 6.
- [ ] `/healthz`, `/healthz/db`, `/blocklist` cloud hijau (G3) — LANGKAH MANUAL 5.

## Deviasi

- D-alief-B02 tabel `rate_limit_hits` (hash, tanpa IP mentah).
- D-alief-B03 tanpa `sql.end()`; `since` lewat `::text`.
- D-alief-B04 detail kecil API; `test/helpers/schema.ts` (ajv) ditunda ke fase 09.
- `vitest.config.ts` memakai `fileParallelism: false` (semua file test berbagi satu Postgres lokal).

## Placeholder aktif

- `backend/api/wrangler.jsonc` Hyperdrive `id` = `00000000000000000000000000000000` → diisi di LANGKAH MANUAL 3.
- `backend/api/wrangler.jsonc` `INVITE_BASE_URL` = `http://localhost:8787` → URL Worker di LANGKAH MANUAL 4.
- `POST /debug/apns-spike` + `APNS_SPIKE` + `SPIKE_KEY` → dihapus di fase 11.

## LANGKAH MANUAL (Alief) — deploy cloud pertama

Semua dijalankan dari root worktree, di branch `feat/BE-devices` (D-alief-27). Password dan secret **diketik di terminal / SQL editor**, tidak pernah di file atau chat. Centang tiap butir dan tempel hasilnya (tanpa password/token) di bawah butir itu.

- [x] 1. **B1–B3.** Buat proyek Supabase `shoo-demo` (region Singapore, plan Free; simpan password DB di password manager). Lalu:
  ```bash
  (cd backend/db && supabase login && supabase link --project-ref <ref>)
  pnpm -C backend/api exec wrangler login
  ```
- [x] 2. **Migrasi cloud** + password role Worker:
  ```bash
  (cd backend/db && supabase db push)
  ```
  Di Supabase Dashboard → SQL editor (password baru yang kuat, simpan di password manager):
  ```sql
  alter role shoo_api password '<password kuat>';
  ```
  Cek cepat di SQL editor: `select count(*) from blocklist_entries;` → `0`, dan `select public from storage.buckets where id = 'screenshots';` → `false`.
- [x] 3. **B4 Hyperdrive (cache mati).** Ambil host Direct connection di Dashboard → Connect:
  ```bash
  pnpm -C backend/api exec wrangler hyperdrive create shoo-db --connection-string="postgres://shoo_api:<password>@db.<ref>.supabase.co:5432/postgres" --caching-disabled
  ```
  Kalau gagal karena IPv6: ulangi dengan **session pooler port 5432** (`postgres://shoo_api.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`), bukan port 6543. Salin `id` yang dicetak ke `backend/api/wrangler.jsonc` (`hyperdrive[0].id`, bukan rahasia). Tempel output (tanpa password):
  ```bash
  pnpm -C backend/api exec wrangler hyperdrive get shoo-db
  ```
  → pastikan caching `disabled`.
- [x] 4. **Secret spike + var + deploy.**
  ```bash
  pnpm -C backend/api exec wrangler secret put SPIKE_KEY     # ketik nilai acak, simpan sementara untuk butir 6
  ```
  Edit `backend/api/wrangler.jsonc` → `vars`: `"APNS_SPIKE": "1"`, `"INVITE_BASE_URL": "https://shoo-api.<akun>.workers.dev"`. Lalu:
  ```bash
  pnpm -C backend/api run deploy
  ```
- [x] 5. **Uji asap cloud** (`U=https://shoo-api.<akun>.workers.dev`):
  ```bash
  curl -s $U/healthz
  curl -s $U/healthz/db
  T=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke","mode":"guardian"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
  curl -s $U/blocklist -H "authorization: Bearer $T"
  ```
  Harapan: `{"ok":true}`, `{"ok":true}`, `{"domains":[],"nextSince":null}`. Tempel ketiga hasil (jangan tempel `$T`).
- [x] 6. **Spike APNs dari Worker cloud** (D-alief-16):
  ```bash
  curl -s -X POST $U/debug/apns-spike -H "x-spike-key: <SPIKE_KEY>"
  ```
  Tempel JSON hasilnya. Lulus = `"reached":true` dengan `status` 403 + body `InvalidProviderToken`/`ExpiredProviderToken` atau 400 `BadDeviceToken`. Gagal = `"reached":false` (error koneksi/protokol) atau respons bukan JSON APNs. Setelah itu matikan: `"APNS_SPIKE": "0"` di `wrangler.jsonc`, lalu `pnpm -C backend/api run deploy` lagi, dan cek `curl -s -o /dev/null -w "%{http_code}" -X POST $U/debug/apns-spike -H "x-spike-key: <SPIKE_KEY>"` → `404`.
- [x] 7. **DITUNDA oleh Alief (21 Okt 2026), bukan blocker (PROMPT 6h); tetap terbuka di TODO C7/B9.** **C7 + B9.** Kirim ke Imelda (teks TODO C7) URL `$U/blocklist`. Pasang monitor uptime: `$U/healthz` tiap 5 menit, `$U/healthz/db` tiap 1 hari.
- [x] 8. Commit perubahan `wrangler.jsonc` (`id` Hyperdrive, `INVITE_BASE_URL`, `APNS_SPIKE: "0"`), lalu ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent akan menulis `D-alief-B01` dari hasil butir 6, menjalankan review keamanan, dan membuka PR.

### Hasil LANGKAH MANUAL (21 Okt 2026 ±21:35 WITA, dijalankan agent coordinator atas permintaan Alief; password diketik Alief sendiri)

- 1: org Supabase baru `Shoo` (`oxsfyebspuymhtegwizi`), proyek `shoo-demo` ref `nmekxihgjszgcibqytyj`, `ap-southeast-1`, Free. `supabase link` OK; CLI dan wrangler sudah login.
- 2: `supabase db push` → `Applying migration 20261021130000_init.sql... Finished supabase db push.` Password `shoo_api` di-set lewat `supabase db query --linked` (Management API, file SQL sementara mode 600 lalu dihapus) — bukan SQL editor. Cek: `blocklist_rows 0`, `screenshots_public false`, `shoo_api_login true`. Catatan: password `postgres` dibuat acak oleh Supabase dan tidak disimpan siapa pun; reset di Dashboard → Settings → Database kalau dibutuhkan.
- 3: Hyperdrive `shoo-db` id `f6c9b58d147c457ab5691d47d85f8309`, host direct `db.<ref>.supabase.co:5432` (tidak perlu pooler), user `shoo_api`, `caching.disabled: true`.
- 4: `SPIKE_KEY` (acak, tidak pernah dicetak) di-set; `INVITE_BASE_URL = https://shoo-api.afindo-mi01.workers.dev`; deploy OK.
- 5: `/healthz` → `{"ok":true}`; `/healthz/db` → `{"ok":true}`; `/blocklist` → `{"domains":[],"nextSince":null}`. Satu device uji `Smoke` (guardian) tertinggal di DB cloud.
- 6: `{"reached":true,"status":403,"body":"{\"reason\":\"InvalidProviderToken\"}","ms":1242,"colo":"CDG"}` → **lulus** (Worker fetch mencapai APNs sandbox lewat HTTP/2). Lalu `APNS_SPIKE: "0"`, deploy ulang, `POST /debug/apns-spike` → `404`. Secret `SPIKE_KEY` masih ada di Worker sampai fase 11.
- 7: **ditunda** — Alief kirim C7 ke Imelda dan pasang monitor uptime B9 nanti. Agent tidak berhenti karena butir ini. Selama itu, semua input dari Imelda (ScanResult: `score`, `signals`, label EN/ID) dimock dari `contracts/fixtures/*.json` (aturan 3 CLAUDE.md) — fase 08–10 seed dan test memakai fixture itu, bukan data detector/AI asli.
- 8: `wrangler.jsonc` di-commit (id Hyperdrive, `INVITE_BASE_URL`, `APNS_SPIKE: "0"`).

## Catatan handoff

- Fase 08–12 memakai `requireDevice` (`src/http/auth.ts`), `ApiError`/`errors` (`src/http/errors.ts`), `readJson`/`parse` (`src/http/validate.ts`), `hit()` + `limits` (`src/http/rateLimit.ts`, tambahkan bucket baru di `limits`), repo pattern `src/db/repo/*`, helper test `test/helpers/{resetDb,seed}.ts` (`call`, `createDevice`, `freshIp`).
- Fase 08: `GET /devices/me` (kontrak, D-alief-38) + usulan `DELETE /devices/me` (SECURITY §3 P3, flag sampai C19). Daftar tabel di `resetDb.ts` harus diperbarui kalau ada tabel baru.
- Fase 09: `test/helpers/schema.ts` (ajv) — lihat D-alief-B04(d) soal `new Function` di workerd.
- Fase 12: tambahkan `delete from rate_limit_hits where hit_at < now() - interval '1 day'` ke cron retensi + baris tabel di R2 §2/§6 (D-alief-B02).
- Rate limit `POST /devices` per IP: semua test memakai `cf-connecting-ip` berbeda (`freshIp()`), kecuali test rate limit itu sendiri.
- Lokal: `pnpm-workspace.yaml` (`allowBuilds`) dibutuhkan pnpm 12 supaya `workerd`/`esbuild` boleh menjalankan postinstall.
