# Log fase 09 — Scans + screenshot

| Field | Nilai |
|---|---|
| Status | `[m]` berhenti di LANGKAH MANUAL (secret Storage + deploy). Belum ada PR |
| Track / branch | be · `feat/BE-scans` (worktree sesi `happy-mcnulty-9fc732`) |
| Basis | ditumpuk di atas `feat/BE-family` (PR #11, stacked on #9) → PR nanti menulis "Stacked on #11" |
| Mulai | 21 Okt 2026 22:40 WITA |
| Model | Opus 5.5 |

## Ringkasan rencana

Rencana lengkap: [`fase-09-plan.md`](fase-09-plan.md). Dua butir BELUM DIVERIFIKASI dicek dulu: auth Storage REST lokal, dan ajv di workerd. Lalu `ScreenshotStore` (Supabase Storage REST), `POST /scans` (validasi kontrak + screenshot), `GET /scans` (owner dari `family_links` saat request, cursor keyset), `GET /scans/{id}` (signed URL 1 jam), hook push `LogSender`.

## Checklist langkah kerja

- [x] 0. Verifikasi: Storage REST lokal (upload/sign/delete) dengan kunci `sb_secret_…` dan JWT `service_role` (header `apikey` + `Authorization`) → keduanya 200. ajv `compile` jalan di workerd lewat `@cloudflare/vitest-plugin` → D-alief-B04(d) terjawab, tanpa ajv standalone
- [x] 1. `POST /scans`: zod sesuai skema + R3 §4, `ownerDeviceId`/`ownerName` diabaikan, domain = host atau `*.domain`, `owner = principal`, screenshot (≤ `SCREENSHOT_MAX_BYTES`, magic JPEG/PNG, sisi ≤ 1280 px, dedupe 24 jam, kuota 50/24 jam) → `201 { id }`, hook `PushSender` = `LogSender`
- [x] 2. `GET /scans?owner=&status=&cursor=&limit=` + validasi JSON schema (ajv) di test
- [x] 3. `GET /scans/{id}`: otorisasi R3 §3, signed URL 3600 s
- [x] 4. Bentuk body = yang dikirim extension (`report.js` `scanBody` + `background.js` owner fields) — test `extensionBody()`
- [x] 5. Test IDOR + disconnect
- [ ] 6. Review berurutan: security → TypeScript → database
- [ ] 7. LANGKAH MANUAL (di bawah) — menunggu Alief

## File dibuat / diubah

- `backend/api/src/routes/scans.ts`, `src/db/repo/scans.ts`, `src/services/{scans,images,screenshots}.ts`, `src/services/push/{sender,notify,messages}.ts`
- `backend/api/src/{app,env}.ts`, `src/http/rateLimit.ts` (bucket `scans_create`), `wrangler.jsonc` (`SUPABASE_URL`, `SCREENSHOT_MAX_BYTES`), `vitest.config.ts` (Storage lokal dari `supabase status`), `.dev.vars.example`, `package.json` (dev: `ajv`, `ajv-formats`)
- `backend/api/test/{scans,push-messages}.test.ts`, `test/devices-me.test.ts` (hapus objek Storage), `test/helpers/{schema,images}.ts`, `test/env.d.ts`
- `plan/alief/log/{fase-09,fase-09-plan,DECISIONS}.md`, `PROGRESS.md`, `backend/README.md`

## Hasil verifikasi (lokal)

VERIFIKASI_PLACEHOLDER

## DoD

- [x] `GET /scans?owner=family` cocok dengan bentuk dan isi `activity-family.json` (seed dari 5 fixture, termasuk scan Guardian sendiri `dev_me`, dengan verdict) dan lolos JSON schema (`scans.test.ts` "matches contracts/fixtures/activity-family.json").
- [x] Body berisi `ownerDeviceId` device lain → tersimpan sebagai milik principal (`scans.test.ts` "owner comes from the token").
- [x] Screenshot > 150 KB dibuang, scan tetap 201; dedupe (reuse path, tidak ada objek baru, lewat 24 jam → upload baru) dan kuota 50/24 jam terbukti (`scans.test.ts` "POST /scans screenshot").
- [x] Semua test IDOR hijau: Guardian lain → 404 (`/scans/{id}` dan `?owner=`), Protected membaca scan Guardian-nya → 404, `owner=family` Protected → 403, setelah disconnect → 404.
- [x] LANGKAH MANUAL deploy fase 09 + secret `SUPABASE_SERVICE_ROLE_KEY` (B5) tertulis (di bawah).

## Review

REVIEW_PLACEHOLDER

## Deviasi

- D-alief-B07 (detail fase 09).

## Placeholder aktif

- `backend/api/src/services/push/sender.ts` `pushSender` → `LogSender`; diganti `ApnsSender` di fase 11 (`TODO(sync:alief)`).
- `backend/api/src/routes/join-page.ts` `APP_STORE_URL` → fase 16.
- Dari fase 07: `POST /debug/apns-spike` + `APNS_SPIKE` + secret `SPIKE_KEY` → dihapus di fase 11.
- ~~`deleteScreenshots` placeholder (fase 08)~~ → sekarang menghapus objek Storage sungguhan.

## LANGKAH MANUAL (Alief) — secret Storage + deploy fase 09

Dijalankan dari root worktree ini, di branch `feat/BE-scans`. Satu migrasi baru (batas bucket). Nilai secret **diketik di prompt wrangler**, tidak pernah di file atau chat.

- [ ] 0. **Migrasi bucket** (`20261021170000_screenshot_bucket.sql`):
  ```bash
  (cd backend/db && supabase migration list --linked)   # 20261021170000 tampil hanya di kolom Local
  (cd backend/db && supabase db push)
  (cd backend/db && supabase db query --linked "select file_size_limit, allowed_mime_types from storage.buckets where id = 'screenshots'")
  ```
  Harapan: `153600 | {image/jpeg,image/png}`.
- [ ] 1. **B5 secret Storage.** Supabase Dashboard → proyek `shoo-demo` → Settings → API Keys → **Secret keys** → buat kunci baru bernama `shoo-worker` (atau pakai `service_role` legacy kalau hanya itu yang ada). Salin nilainya, lalu:
  ```bash
  pnpm -C backend/api exec wrangler secret put SUPABASE_SERVICE_ROLE_KEY   # tempel kunci di prompt
  ```
  `SUPABASE_URL` sudah di `wrangler.jsonc` `vars` (`https://nmekxihgjszgcibqytyj.supabase.co`, bukan rahasia).
- [ ] 2. **Deploy Worker:**
  ```bash
  pnpm -C backend/api run deploy
  ```
- [ ] 3. **Uji asap cloud:**
  ```bash
  U=https://shoo-api.afindo-mi01.workers.dev
  tok() { python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'; }
  GT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke G","mode":"guardian"}' | tok)
  PT=$(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke P","mode":"protected"}' | tok)
  CODE=$(curl -s -X POST $U/family/code -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["code"])')
  curl -s -o /dev/null -X POST $U/family/join -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}"
  SHOT=$(python3 -c 'import base64;print(base64.b64encode(bytes([0xff,0xd8,0xff,0xe0,0,16])+b"JFIF\0\1\1\0\0\1\0\1\0\0"+bytes([0xff,0xc0,0,17,8,0,10,0,10,3,1,0x22,0,2,0x11,1,3,0x11,1,0xff,0xd9])).decode())')
  BODY=$(python3 -c "import json;f=json.load(open('contracts/fixtures/blocked-92.json'));[f.pop(k) for k in ('id','verdict','screenshotUrl')];f['screenshotBase64']='$SHOT';print(json.dumps(f))")
  ID=$(curl -s -X POST $U/scans -H "authorization: Bearer $PT" -H 'content-type: application/json' -d "$BODY" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])'); echo "scan $ID"
  curl -s "$U/scans?owner=family" -H "authorization: Bearer $GT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d["items"]), d["items"][0]["ownerName"], d["items"][0]["screenshotUrl"], d["nextCursor"])'
  SURL=$(curl -s $U/scans/$ID -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["screenshotUrl"])')
  curl -s -o /dev/null -w "signed url: %{http_code} %{content_type}\n" "$SURL"
  curl -s -o /dev/null -w "IDOR other guardian: %{http_code}\n" $U/scans/$ID -H "authorization: Bearer $(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke X","mode":"guardian"}' | tok)"
  curl -s -X DELETE $U/devices/me -H "authorization: Bearer $PT"; curl -s -X DELETE $U/devices/me -H "authorization: Bearer $GT"; echo
  curl -s -o /dev/null -w "signed url after delete: %{http_code}\n" "$SURL"
  ```
  Harapan: `scan <uuid>`; `1 Smoke P None None`; `signed url: 200 image/jpeg`; `IDOR other guardian: 404`; `{"ok":true}{"ok":true}`; `signed url after delete` bukan 200 (objek terhapus). Tempel hasilnya (tanpa token dan tanpa `$SURL`). Device `Smoke X` tertinggal (tanpa data).
- [ ] 4. Ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent memeriksa hasil, membuka PR `feat/BE-scans` (stacked on #11), dan lanjut ke fase 10.

## Catatan handoff

- Lokal: setelah `supabase link`, file `supabase/.temp/storage-version` mematok versi Storage cloud (v1.80.2) dan `db reset` memigrasi skema `storage` ke versi itu. Container Storage yang sudah jalan dari sebelum link (v1.69.0) lalu gagal upload (`42P10`). Perbaikan: `(cd backend/db && supabase stop && supabase start -x …)`.
- Fase 10: `verdict` di `ScanRow` dibaca lewat join `verdicts (owner_id, domain)` hanya untuk scan `blocked`; `POST /verdicts` cukup upsert tabel itu. `findVisibleScan` bisa dipakai ulang untuk otorisasi verdict (lalu 403 `verdict_not_allowed`, bukan 404).
- Fase 11: `services/push/{sender,notify,messages}.ts` sudah ada; ganti `pushSender` dengan `ApnsSender` (D-alief-B01), tulis `push_log`, test teks sudah di `push-messages.test.ts`.
- Fase 12: retensi memakai `deleteScreenshots(env, paths)` (satu `DELETE` dengan `prefixes` per batch); dedupe berarti satu path bisa dipakai beberapa scan → hapus objek hanya kalau tidak ada scan tersisa yang menunjuk ke path itu (R4 §5).
