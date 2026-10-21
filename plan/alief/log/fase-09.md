# Log fase 09 — Scans + screenshot

| Field | Nilai |
|---|---|
| Status | `[m]` berhenti di LANGKAH MANUAL (c): secret `SCREENSHOT_URL_SECRET` + deploy + uji asap (screenshot setelah delete/disconnect = 404). Belum ada PR |
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
- [x] 6. Review berurutan: security → TypeScript → database (tabel Review)
- [ ] 7. LANGKAH MANUAL (di bawah) — menunggu Alief

## File dibuat / diubah

- `backend/db/supabase/migrations/20261021170000_screenshot_bucket.sql` (batas bucket + index `scans_owner_shot`), `tests/storage.test.sql`
- `backend/api/src/routes/scans.ts`, `src/db/repo/scans.ts`, `src/services/{scans,images,screenshots}.ts`, `src/services/push/{sender,notify,messages}.ts`
- `backend/api/src/{app,env}.ts`, `src/http/rateLimit.ts` (bucket `scans_create`), `wrangler.jsonc` (`SUPABASE_URL`, `SCREENSHOT_MAX_BYTES`), `vitest.config.ts` (Storage lokal dari `supabase status`), `.dev.vars.example`, `package.json` (dev: `ajv`, `ajv-formats`)
- `backend/api/test/{scans,push-messages}.test.ts`, `test/{images,push-notify}.test.ts`, `test/devices-me.test.ts` (hapus objek Storage), `test/helpers/{schema,images}.ts`, `test/env.d.ts`
- `plan/alief/log/{fase-09,fase-09-plan,DECISIONS}.md`, `PROGRESS.md`, `backend/README.md`

## Hasil verifikasi (lokal)

- `(cd backend/db && supabase db reset && supabase test db)` → **PASS, 71 test** (4 file; baru `storage.test.sql`: bucket privat, `file_size_limit 153600`, MIME JPEG/PNG, index `scans_owner_shot`).
- `pnpm -C backend/api typecheck` → bersih. `pnpm -C backend/api test` → **12 file, 170 test lulus** (setelah D-alief-B08: 13 file, 182) (baru: `scans.test.ts`, `images.test.ts`, `push-notify.test.ts`, `push-messages.test.ts`; `devices-me.test.ts` + hapus objek Storage).
- Respons `GET /scans` dan `GET /scans/{id}` divalidasi dengan ajv terhadap `contracts/scan-result.schema.json` di setiap test list/detail.
- Cloud: belum (LANGKAH MANUAL di bawah).

## DoD

- [x] `GET /scans?owner=family` cocok dengan bentuk dan isi `activity-family.json` (seed dari 5 fixture, termasuk scan Guardian sendiri `dev_me`, dengan verdict) dan lolos JSON schema (`scans.test.ts` "matches contracts/fixtures/activity-family.json").
- [x] Body berisi `ownerDeviceId` device lain → tersimpan sebagai milik principal (`scans.test.ts` "owner comes from the token").
- [x] Screenshot > 150 KB dibuang, scan tetap 201; dedupe (reuse path, tidak ada objek baru, lewat 24 jam → upload baru) dan kuota 50/24 jam terbukti (`scans.test.ts` "POST /scans screenshot").
- [x] Semua test IDOR hijau: Guardian lain → 404 (`/scans/{id}` dan `?owner=`), Protected membaca scan Guardian-nya → 404, `owner=family` Protected → 403, setelah disconnect → 404.
- [x] LANGKAH MANUAL deploy fase 09 + secret `SUPABASE_SERVICE_ROLE_KEY` (B5) tertulis (di bawah).

## Review

Berurutan, satu per satu (aturan Alief: subagent tidak paralel).

| Reviewer | CRITICAL | HIGH | MEDIUM | Diperbaiki | Commit |
|---|---|---|---|---|---|
| `ecc:security-reviewer` | 0 | 0 | 3 | kuota/dedupe atomik (`reserveScreenshot` + advisory lock), teks kontrol/bidi dibersihkan, lookup Guardian sebelum respons (hanya `send` di `waitUntil`), try/catch screenshot, migrasi batas bucket | `78da6c3` |
| `ecc:typescript-reviewer` | 0 | 2 | 7 | H1 lookup push gagal → tetap 201 (`push_lookup_failed`); H2 `url` dengan karakter kontrol → 422, `faviconUrl` → null. M: cursor tepat 2 bagian, signature PNG penuh + panjang segmen JPEG, body Storage dilepas saat error, respons sign divalidasi zod, upload timeout dihapus, `screenshotBase64: null` diterima. L: `signals[].id` bebas (kontrak tanpa pola), alasan `bad_size`, `send` sinkron tertangkap | `b145024` |
| `ecc:database-reviewer` | 0 | 1 (+1 fase 12) | 3 | H: upload gagal mengosongkan path di semua scan owner yang memakainya (dedupe). M: index parsial `scans_owner_shot (owner_id, created_at desc) where screenshot_path is not null`; hapus Storage dibatch 100. Fase 12: retensi hapus objek hanya kalau tidak ada scan tersisa yang menunjuknya (catatan handoff) | commit fase 09 terakhir |

Ditunda (bukan blocker, dicatat): `owner=family` mengurutkan semua scan keluarga dalam retensi (kecil untuk ≤ 3 member); sort key = `detectedAt` dari klien (scan backdated bisa jatuh di belakang cursor yang sudah dibagikan); regex domain menerima IPv4 literal; komentar kolom `screenshot_path` di init masih `.jpg` saja; header gambar dicek, isi tidak di-decode (content-type tetap `image/*`).

## Deviasi

- D-alief-B07 (detail fase 09).

## Placeholder aktif

- `backend/api/src/services/push/sender.ts` `pushSender` → `LogSender`; diganti `ApnsSender` di fase 11 (`TODO(sync:alief)`).
- `backend/api/src/routes/join-page.ts` `APP_STORE_URL` → fase 16.
- Dari fase 07: `POST /debug/apns-spike` + `APNS_SPIKE` + secret `SPIKE_KEY` → dihapus di fase 11.
- ~~`deleteScreenshots` placeholder (fase 08)~~ → sekarang menghapus objek Storage sungguhan.

## LANGKAH MANUAL (Alief) — secret Storage + deploy fase 09

Dijalankan dari root worktree ini, di branch `feat/BE-scans`. Satu migrasi baru (batas bucket). Nilai secret **diketik di prompt wrangler**, tidak pernah di file atau chat.

- [x] 0. **Migrasi bucket** (`20261021170000_screenshot_bucket.sql`):
  ```bash
  (cd backend/db && supabase migration list --linked)   # 20261021170000 tampil hanya di kolom Local
  (cd backend/db && supabase db push)
  (cd backend/db && supabase db query --linked "select file_size_limit, allowed_mime_types from storage.buckets where id = 'screenshots'")
  ```
  Harapan: `153600 | {image/jpeg,image/png}`.
- [x] 1. **B5 secret Storage.** Supabase Dashboard → proyek `shoo-demo` → Settings → API Keys → **Secret keys** → buat kunci baru bernama `shoo-worker` (atau pakai `service_role` legacy kalau hanya itu yang ada). Salin nilainya, lalu:
  ```bash
  pnpm -C backend/api exec wrangler secret put SUPABASE_SERVICE_ROLE_KEY   # tempel kunci di prompt
  ```
  `SUPABASE_URL` sudah di `wrangler.jsonc` `vars` (`https://nmekxihgjszgcibqytyj.supabase.co`, bukan rahasia).
- [x] 2. **Deploy Worker:**
  ```bash
  pnpm -C backend/api run deploy
  ```
- [x] 3. **Uji asap cloud:**
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
- [x] 4. Ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent memeriksa hasil, membuka PR `feat/BE-scans` (stacked on #11), dan lanjut ke fase 10.

### Hasil LANGKAH MANUAL (21 Okt 2026 ±23:25 WITA, dijalankan agent coordinator atas permintaan Alief; kunci secret ditempel Alief sendiri)

- 0: `supabase db push --yes` → `"migrations":["20261021170000_screenshot_bucket.sql"] … Finished supabase db push.` Bucket `screenshots`: `file_size_limit 153600`, `allowed_mime_types {image/jpeg,image/png}`.
- 1: kunci secret Supabase `shoo_worker` dibuat Alief, ditempel di prompt `wrangler secret put SUPABASE_SERVICE_ROLE_KEY` → `Success! Uploaded secret SUPABASE_SERVICE_ROLE_KEY`.
- 2: deploy → Version `be621201-27f9-4f3a-8601-5c58d4967157` (binding `DB`, `SUPABASE_URL`, `SCREENSHOT_MAX_BYTES 153600`).
- 3: `scan 3affdd87-…`; `1 Smoke P None None`; `signed url: 200 image/jpeg`; `IDOR other guardian: 404`; delete → `{"ok":true}` ×3 (Smoke X ikut dihapus); **`signed url after delete: 200` — tidak sesuai harapan.** Cek DB: `storage.objects` bucket `screenshots` kosong, `scans` = 0 → objek benar terhapus. Penyebab paling mungkin: upload tanpa `cache-control`, jadi Supabase memakai default `max-age=3600` dan CDN Storage menyajikan salinan cache sampai signed URL kedaluwarsa (≤ 1 jam). **Temuan untuk agent (TINGGI, privasi SECURITY §3):** set `cache-control: no-store` (atau `max-age=0`) saat upload screenshot dan tambahkan test; deploy ulang = LANGKAH MANUAL berikutnya.

### Perbaikan temuan smoke (21 Okt 2026 ±23:35 WITA, agent track be)

- Temuan (TINGGI, privasi SECURITY §3 P3 / T6): signed URL masih `200` setelah `DELETE /devices/me`. Penyebab: upload tanpa `cache-control` → Storage memakai `max-age=3600`, CDN menyajikan salinan.
- Perbaikan: `SupabaseStorageStore.put` mengirim `cache-control: no-store` (disimpan sebagai `cache_control` objek, dikirim di setiap GET). D-alief-B07 (l), SECURITY T6.
- Test (merah dulu, lalu hijau): `scans.test.ts` "owner gets a 1-hour signed URL" memeriksa `object/info` → `cache_control === "no-store"` (lokal default `no-cache`; Storage lokal tidak meneruskan header lewat Kong, jadi header nyata dicek di cloud). `pnpm test` → 12 file, **170 test lulus**; typecheck bersih.
- Review: perubahan 1 header + 1 assertion, direview manual (tanpa subagent).
- Objek lama di cloud: tidak ada (smoke sudah menghapus semuanya), jadi tidak ada objek dengan `max-age=3600` yang tersisa.

## LANGKAH MANUAL (b) (Alief) — deploy ulang + cek ulang cache

Dari root worktree, branch `feat/BE-scans` (setelah `git pull`). Tidak ada migrasi atau secret baru.

- [x] 1. Deploy:
  ```bash
  pnpm -C backend/api run deploy
  ```
- [x] 2. Jalankan lagi blok uji asap langkah 3 di atas, lalu tambahan cek header (sebelum `DELETE`):
  ```bash
  curl -s -D - -o /dev/null "$SURL" | grep -i '^cache-control'
  ```
  Harapan: `cache-control: no-store`; semua harapan langkah 3 sama, dan **`signed url after delete` bukan 200**. Tempel hasilnya (tanpa token dan tanpa `$SURL`).
  Hasil (21 Okt 2026 ±23:32 WITA, coordinator): deploy Version `5668ab54-a504-49fc-b7ee-339e52eebab4`. Uji asap: `scan d4bbcd74-…`; `1 Smoke P None None`; `signed url: 200 image/jpeg`; `IDOR other guardian: 404`; delete `{"ok":true}` ×3; **`signed url after delete: 200` — masih gagal.** Header `cache-control` **tidak dikirim** oleh Storage.
  Probe tambahan (scan baru, URL tidak dicetak): `storage.objects.metadata.cacheControl = "no-store"` (perbaikan tersimpan), tetapi respons signed URL dari `nmekxihgjszgcibqytyj.supabase.co/storage/v1/object/sign/…` hanya membawa `expires` = waktu upload + 1 jam (= TTL signed URL) dan `cf-cache-status: MISS`; setelah delete `cf-cache-status: HIT`, `age: 3`, `200`. Kesimpulan: CDN Supabase (Free, tanpa Smart CDN purge) meng-cache respons signed URL sampai URL kedaluwarsa, **mengabaikan `cacheControl` objek**. `no-store` saat upload tidak cukup.
  **Temuan untuk agent (TINGGI, tetap terbuka):** pilih dan catat di DECISIONS: (a) TTL signed URL pendek (mis. 60–300 s) untuk membatasi jendela, atau (b) Worker menyajikan screenshot sendiri (auth device, `Cache-Control: no-store`) lalu `screenshotUrl` menunjuk ke Worker; keduanya mungkin butuh catatan kontrak untuk Umar (kontrak menyebut signed URL 1 jam). Deploy ulang = LANGKAH MANUAL berikutnya.
- [x] 3. Diganti oleh perbaikan D-alief-B08 + LANGKAH MANUAL (c) di bawah.

### Perbaikan D-alief-B08 (21 Okt 2026 ±23:50 WITA, agent track be)

- Keputusan Alief: "so lets follow apple privacy" → screenshot yang dihapus/diputus harus langsung tidak bisa dilihat. `screenshotUrl` = link Worker `/screenshots/{scanId}?v=&exp=&sig=` (HMAC 1 jam); route mengecek sig + exp lalu DB **setiap request** (scan ada, viewer = pemilik atau Guardian saat ini), lalu mengalirkan objek dengan `Cache-Control: private, no-store`. Detail: D-alief-B08.
- Test baru `test/screenshots.test.ts` (merah dulu: modul belum ada, URL masih Supabase): gambar + `no-store` + `nosniff` tanpa header auth; PNG; Guardian setelah disconnect → 404; pemilik setelah `DELETE /devices/me` → 404; scan dihapus (retensi) → 404; sig salah/hilang/diubah, `exp` diubah, `v` diubah → 404; link kedaluwarsa → 404; link scan A tidak membuka scan B; viewer bukan pemilik/Guardian dengan link bertanda tangan sah → 404; tanpa screenshot / id asing / id buruk → 404. `scans.test.ts`: `screenshotUrl` = link Worker, `v` = viewer, TTL 3590–3600 s.
- Verifikasi: `pnpm typecheck` (+ `--noUnusedLocals`) bersih; `pnpm test` → **13 file, 182 test lulus**.
- Review `ecc:security-reviewer` (satu subagent): 0 CRITICAL, 0 HIGH, 2 MEDIUM, 4 LOW; syarat "langsung tidak bisa dilihat" terpenuhi di semua skenario. Diperbaiki (test merah dulu): fetch Worker → Storage `cache: "no-store"` + `cache-control: no-cache` (path dedupe bisa hidup lebih lama dari satu scan); rate limit `screenshots_view` 120/menit per viewer (429 juga `no-store`); origin link = `INVITE_BASE_URL` (URL Worker yang dipatok, bukan Host request); hanya encoding base64url kanonik untuk `sig`. Ditunda (dicatat D-alief-B08): device id viewer + sig terlihat di log URL Cloudflare (link bearer ≤ 1 jam, tetap dicek DB); signed URL Supabase lama sebelum deploy (c) hidup ≤ 1 jam (satu kali, semua data smoke sudah dihapus); app harus membuang cache memori gambar saat disconnect/hapus (SECURITY P9, fase 13).
- Catatan kontrak untuk Umar: TODO C20 (draf, belum dikirim).

## LANGKAH MANUAL (c) (Alief) — secret link screenshot + deploy + uji asap

Dari root worktree, branch `feat/BE-scans` (setelah `git pull`). Tidak ada migrasi baru. Nilai secret **tidak pernah** ditempel di chat atau file.

- [ ] 1. Secret HMAC (acak, langsung dipipe ke wrangler, tidak tampil di layar):
  ```bash
  openssl rand -base64 32 | pnpm -C backend/api exec wrangler secret put SCREENSHOT_URL_SECRET
  ```
- [ ] 2. Deploy:
  ```bash
  pnpm -C backend/api run deploy
  ```
- [ ] 3. Uji asap (sama dengan langkah 3 di atas sampai `ID=`, lalu):
  ```bash
  GURL=$(curl -s $U/scans/$ID -H "authorization: Bearer $GT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["screenshotUrl"])')
  PURL=$(curl -s $U/scans/$ID -H "authorization: Bearer $PT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["screenshotUrl"])')
  echo "$GURL" | grep -q "^$U/screenshots/$ID?" && echo "worker url: ok"
  curl -s -o /dev/null -w "screenshot guardian: %{http_code} %{content_type}
" "$GURL"
  curl -s -D - -o /dev/null "$GURL" | grep -i '^cache-control'
  curl -s -o /dev/null -w "IDOR other guardian: %{http_code}
" $U/scans/$ID -H "authorization: Bearer $(curl -s -X POST $U/devices -H 'content-type: application/json' -d '{"name":"Smoke X","mode":"guardian"}' | tok)"
  curl -s -X DELETE $U/family/guardian -H "authorization: Bearer $PT"; echo
  curl -s -o /dev/null -w "screenshot guardian after disconnect: %{http_code}
" "$GURL"
  curl -s -o /dev/null -w "screenshot owner before delete: %{http_code}
" "$PURL"
  curl -s -X DELETE $U/devices/me -H "authorization: Bearer $PT"; curl -s -X DELETE $U/devices/me -H "authorization: Bearer $GT"; echo
  curl -s -o /dev/null -w "screenshot after delete: %{http_code}
" "$PURL"
  ```
  Harapan: `worker url: ok`; `screenshot guardian: 200 image/jpeg`; `cache-control: private, no-store`; `IDOR other guardian: 404`; `{"ok":true}`; **`screenshot guardian after disconnect: 404`**; `screenshot owner before delete: 200`; `{"ok":true}{"ok":true}`; **`screenshot after delete: 404`**. Tempel hasilnya (tanpa token dan tanpa URL). Device `Smoke X` tertinggal (tanpa data).
- [ ] 4. Ketik lagi: `Saya Alief, track be. Kerjakan otomatis sesuai plan/alief/PROMPT.md (mode auto).` Agent memeriksa hasil, membuka PR `feat/BE-scans` (stacked on #11, sertakan catatan C20), dan lanjut ke fase 10.

## Catatan handoff

- Lokal: setelah `supabase link`, file `supabase/.temp/storage-version` mematok versi Storage cloud (v1.80.2) dan `db reset` memigrasi skema `storage` ke versi itu. Container Storage yang sudah jalan dari sebelum link (v1.69.0) lalu gagal upload (`42P10`). Perbaikan: `(cd backend/db && supabase stop && supabase start -x …)`.
- Fase 10: `verdict` di `ScanRow` dibaca lewat join `verdicts (owner_id, domain)` hanya untuk scan `blocked`; `POST /verdicts` cukup upsert tabel itu. `findVisibleScan` bisa dipakai ulang untuk otorisasi verdict (lalu 403 `verdict_not_allowed`, bukan 404).
- Fase 11: `services/push/{sender,notify,messages}.ts` sudah ada; ganti `pushSender` dengan `ApnsSender` (D-alief-B01), tulis `push_log`, test teks sudah di `push-messages.test.ts`.
- Fase 12: retensi memakai `deleteScreenshots(env, paths)` (`DELETE` dengan `prefixes`, batch 100); dedupe berarti satu path bisa dipakai beberapa scan → hapus objek hanya kalau tidak ada scan tersisa yang menunjuk ke path itu (R4 §5).
