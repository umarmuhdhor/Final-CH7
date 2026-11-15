# R3 — Catatan implementasi API

> **Kontrak = `contracts/api.md`.** File ini hanya menjelaskan detail yang tidak ditulis kontrak (error code tambahan, rate limit, cursor, otorisasi). Kalau ada selisih, kontrak menang dan file ini diperbaiki. Referensi lengkap per endpoint: `backend/API.md`.
> Base URL: `https://shoo-api.afindo-mi01.workers.dev` (cloud), `http://localhost:8787` (lokal). Semua body JSON, waktu ISO 8601 UTC.
> Diperbarui 15 Nov 2026 terhadap `main` `c14abbcf`.

## 1. Bentuk error

Selalu `{ "error": { "code": string, "message": string } }`. `message` bahasa Inggris untuk developer; app menampilkan teks lokal berdasarkan `code`. Daftar: `backend/api/src/http/errors.ts`.

| HTTP | code | Kapan |
|---|---|---|
| 400 | `bad_json` | body bukan JSON valid |
| 401 | `unauthorized` | header Authorization hilang / token tidak dikenal |
| 403 | `forbidden` | mode salah (mis. Protected memanggil `POST /family/code`) |
| 404 | `not_found` | resource tidak ada **atau** tidak boleh dilihat (anti-enumerasi) |
| 409 | `already_connected` | Protected yang sudah punya Guardian memanggil `POST /family/join` |
| 409 | `has_members` | `POST /devices/me/protected` oleh Guardian yang masih punya anggota |
| 403 | `verdict_not_allowed` | Guardian bukan guardian pemilik scan (kontrak) |
| 409 | `verdict_locked` | verdict `safe` di link itu masih terkunci sampai review AI mingguan; body membawa `lockedUntil` (#476, `routes/verdicts.ts:93`) |
| 410 | `code_expired` | kode join kedaluwarsa (kontrak) |
| 404 | `code_invalid` | kode join tidak ada, atau kode milik device itu sendiri di become-protected (kontrak) |
| 409 | `family_full` | Guardian sudah punya 3 Protected (kontrak) |
| 409 | `push_unavailable` | `POST /family/members/{id}/remind`: anggota tanpa token APNs |
| 413 | `too_large` | body > batas |
| 422 | `invalid_body` | validasi zod gagal (detail field di `message`) |
| 429 | `too_many_attempts` | batas percobaan join (kontrak), juga batas `POST /devices/me/protected` |
| 429 | `remind_too_soon` | "Ingatkan" < 6 jam sejak yang terakhir (+ `Retry-After`) |
| 429 | `rate_limited` | batas umum lain |
| 503 | `code_unavailable` | `POST /family/code` tidak menemukan kode 6 digit bebas setelah 20 percobaan (`services/family.ts:8,41-47`); app menampilkan "Coba lagi" |
| 500 | `internal` | error tak dikenal (tanpa detail ke klien, detail di log Worker) |

Riwayat: 409 `verdict_not_allowed` untuk scan `warning` sudah tidak ada. Sekarang (15 Nov 2026) scan `warning` juga bisa diberi verdict (GD-07, `db/repo/verdicts.ts:60`).

Kode umum kontrak: `invalid_body`, `bad_json`, `too_large`, `rate_limited` (429 + header `Retry-After` detik), `internal`. Kode di luar kontrak (`code_unavailable`, dll.) dilaporkan ke Umar di PR fase yang memperkenalkannya.

## 2. Auth

- Tanpa Bearer: `POST /devices`, `GET /healthz`, `GET /healthz/db`, halaman web (`GET /j/{code}`, `/og/*`, `/.well-known/apple-app-site-association`, `/privacy`, `/support`, `/terms`, `/get`), dan link bertanda tangan (`GET /screenshots|/favicons|/replicas/{scanId}?v=&exp=&sig=`). `GET /ops/status` memakai token sendiri (`OPS_STATUS_TOKEN`); tanpa token yang cocok = 404. Semua route lain wajib `Authorization: Bearer <token>` (`http/auth.ts:12`).
- Token: `shoo_` + 32 byte acak base64url. DB menyimpan `sha256(token)`. Lookup by hash unik, jadi `timingSafeEqual` tidak perlu.
- Middleware menaruh `principal = { deviceId, mode, name, language }` di context Hono dan memperbarui `last_seen_at` paling sering 1×/5 menit (`db/repo/devices.ts:22-25`).

## 3. Otorisasi per endpoint

| Endpoint | Mode | Aturan |
|---|---|---|
| `GET /devices/me` | semua | profil sendiri; `guardian` hanya untuk Protected |
| `PATCH /devices/me` | semua | hanya baris sendiri; `name` 1–20, `language` en/id, `apnsToken`, `liveActivityStartToken`, `liveActivityUpdateToken` (EX-03, #49), `notifications`, `timeZone`, `deviceModel`, `osVersion`, `avatarId`, `extensionLastSeenAt` |
| `POST /devices/me/protected` | guardian | tanpa anggota (409 `has_members`); kode 6 digit Guardian lain; satu transaksi (fase 27a, `services/becomeProtected.ts:47`) |
| `DELETE /devices/me` | semua | hapus device + semua datanya; keluarga diberi push |
| `GET /config/public` | semua | ambang skor dari dashboard, `Cache-Control: private, max-age=3600` |
| `POST /live` | semua | relay skor ke Dynamic Island (EX-03, #49); tidak ada baris tabel |
| `POST /family/code` | guardian | 403 untuk protected |
| `POST /family/join` | protected | 403 untuk guardian; 409 kalau sudah terhubung |
| `GET /family/members` | guardian | hanya `family_links.guardian_id = me` |
| `PATCH /family/members/{id}` | guardian | `{ notify }` "Kabari saya"; 404 kalau `{id}` bukan anggota saya |
| `POST /family/members/{id}/remind` | guardian | maks 1 per 6 jam per anggota; 404 kalau bukan anggota |
| `DELETE /family/members/{id}` | guardian | 404 kalau `{id}` bukan Protected saya; verdict saya untuk dia ikut terhapus |
| `DELETE /family/guardian` | protected | hapus link saya; 404 kalau tidak ada; verdict Guardian itu ikut terhapus |
| `POST /scans` | semua | `owner_id = me` selalu (body tidak bisa memilih pemilik) |
| `GET /scans?owner=me` | semua | `owner_id = me` |
| `GET /scans?owner=family` | guardian | `owner_id in (me + protected aktif saya)` (`routes/scans.ts:274`; fixture `activity-family.json`, D-alief-19); protected → 403 |
| `GET /scans?owner={deviceId}` | guardian | `{deviceId}` = me atau Protected aktif saya, selain itu 404 |
| `GET /scans/{id}` | semua | pemilik = me, atau pemilik = Protected aktif saya; selain itu 404 |
| `POST /verdicts` | guardian | scan milik saya atau Protected aktif saya; status `warning` atau `blocked` |
| `GET /verdicts?url=&domain=` | semua | verdict untuk `(owner_id = me, link)` — dipakai extension kedua mode (EX-02, EX-06). `?domain=` saja = usang (build sebelum #241) |
| `GET /blocklist` | semua (token) | publik antar-device; tidak ada data pribadi (hanya domain + waktu) |

## 4. Detail per endpoint

- **`POST /devices`**: `avatarId` dari ON-02 dipakai kalau `avatar_01..avatar_12`, selain itu acak (#120, `routes/devices.ts:104-107`). Rate limit 30/jam per IP + 1000/hari semua (R3 §5).
- **`POST /family/code`** (R4 §3): body kosong / `{}` → kode aktif Guardian kalau sisa waktunya > 5 menit, selain itu kode baru; `{ "refresh": true }` → selalu kode baru, kode lama langsung mati (issue #128, `services/family.ts:27-49`). Kode 6 digit, berlaku 30 menit (`db/repo/codes.ts:4`). Respons `{ code, expiresAt, inviteUrl }` dengan `inviteUrl = ${INVITE_BASE_URL}/j/<code>` (`routes/family.ts:32`). Riwayat D-alief-03: dulu `/join?code=`; sekarang (15 Nov 2026) `/j/<code>`, Universal Link (#129).
- **`GET /j/{code}`** (HTML, tanpa auth, `routes/join-page.ts:235`): halaman EN/ID dengan kode besar, tombol "Open Shoo" → `shoo://join?code=<code>`, dan link App Store/TestFlight (`APP_STORE_URL`). Kalau app terpasang, Universal Link membuka app dan halaman ini tidak tampil (AASA dari `APPLINKS_APP_IDS`). `code` **wajib** `^\d{6}$`. Hanya navigasi top-level (`Sec-Fetch-Mode: navigate` + `Sec-Fetch-Dest: document`) yang mencari kode (baca saja); kode tidak dikenal/kedaluwarsa tampil sebagai halaman "tidak valid" yang sama dengan kode rusak, dan dicatat sebagai percobaan gagal IP (anggaran sama dengan `POST /family/join`, 20/10 menit). Lewat anggaran, lewat batas global 600/10 menit, atau DB gagal → halaman undangan biasa tanpa cek. Tidak pernah menyebut nama (T13). Header: CSP dengan nonce, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`. Halaman lama `GET /join?code=` sudah dihapus (`ios/ShooApp/App/DeepLink.swift:58`).
- **`GET /family/members`**: `extensionActive` = `ext_last_seen_at > now() - 24 h` atau belum pernah ada heartbeat (`db/repo/families.ts:81`). `extensionLastSeenAt` dikirim **oleh extension** maks 1×/jam saat heartbeat dan oleh app saat foreground. `lastScan` = scan terbaru pemilik itu. Field PF-01 tambahan: `connectedAt`, `lastSeenAt`, `deviceModel`, `osVersion`, `notify`, `remindedAt`, `stats`.
- **`POST /scans`**: body = ScanResult tanpa `id`/`verdict` (kontrak) + `pageReplicaBase64?` (EX-07) + `evidenceFragmentsBase64?` (ADM-07) + `thresholdsVersion?` + `rdapRegisteredAt?`. Batas body 1 MiB **hanya** untuk `POST` + path persis `/scans`, route lain 256 KB (`http/bodyLimit.ts`). URL disimpan dalam bentuk normal `new URL(url).href` (≤ 2048). Validasi: skor 30–100, `blocked` hanya kalau skor ≥ 50 (pagar), dan kalau `thresholdsVersion` = versi aktif, status harus cocok persis dengan ambang dashboard; `domain` = registrable domain, host `url` = `domain` atau subdomain; `signals` ≤ 20. Field `ownerDeviceId`/`ownerName` diterima tapi diabaikan (server selalu memakai principal). **Satu baris per link** (owner + `verdict_link(url)`, #241): kunjungan ulang link yang sama memakai baris lama (`created: false`); push tetap per situs (kunjungan pertama ke domain + blokir pertama) (`db/repo/scans.ts:35-92`). Respons 201 `{ id, notified }` (`notified = { name }` Guardian yang push-nya diantrekan, atau null, #377). Push, favicon, replica, fragmen jalan di `waitUntil` (R4 §6).
- **Screenshot (usang sejak fase 20a, 8 Nov 2026)**: `POST /scans` mengabaikan `screenshotBase64` (nilai apa pun diterima, hanya dicatat `screenshot_ignored`, `routes/scans.ts:76-78,173`). Bukti halaman sekarang = salinan halaman (replica) di R2. Aturan lama di bawah hanya berlaku untuk scan lama yang masih punya `screenshot_path` sampai retensi 14 hari:
  - ~~Decode base64 → > 150 KB atau bukan JPEG/PNG → dibuang. Dedupe 24 jam per pemilik+domain. Kuota 50/24 jam per pemilik. Upload ke `screenshots/<owner_id>/<scan_id>.jpg`.~~
  - `screenshotUrl` di `GET /scans/{id}` = link Worker `<INVITE_BASE_URL>/screenshots/{scanId}?v=<viewer>&exp=<unix>&sig=<HMAC-SHA256>` berlaku 3600 s (D-alief-B08). `GET /screenshots/{scanId}` (tanpa Bearer): sig + exp dicek, lalu **setiap request** cek DB scan masih ada + viewer = pemilik atau Guardian saat ini, objek dialirkan dari Storage dengan `Cache-Control: private, no-store`; gagal apa pun → 404.
- **Replica (EX-07)**: diproses di `waitUntil` setelah push (`routes/scans.ts:234-243`, `services/replicas.ts:85`): kill-switch `REPLICAS_ENABLED`, reuse per link 24 jam, kuota pemilik/keluarga/global, 300/24 jam per IP, inflate ≤ 3 MiB, `put` ke R2 `shoo-replicas`, lalu `replica_ready_at`. `pageReplicaUrl` di `GET /scans/{id}` = `<INVITE_BASE_URL>/replicas/{scanId}?v=&exp=&sig=` (3600 s, `null` kalau kill-switch mati atau belum ready); di `GET /scans` selalu `null`. `GET /replicas/{scanId}`: sig + exp, tolak `Sec-Fetch-Mode: navigate` / `Sec-Fetch-Dest` ≠ `empty`, 10/menit + 500/hari per viewer, cek akses DB, objek R2 dialirkan apa adanya (`Content-Encoding: gzip`, `Content-Disposition: attachment`, CSP sandbox).
- **Favicon (PR-05)**: Worker mengunduh `faviconUrl` sekali setelah respons (`routes/scans.ts:194-200`), simpan di R2, `favicon_ready_at` setelah `put` (fase 27k F-B8). `faviconUrl` di list dan detail = link HMAC per viewer; `GET /favicons/{scanId}` 600/menit per viewer.
- **`GET /scans`**: cursor = base64url(`<detected_at ISO µs>|<id>`), `limit` default 20 maks 50, urutan `detected_at desc, id desc`. Filter `status`. `screenshotUrl` dan `pageReplicaUrl` = `null` di daftar (D-alief-04). `ownerName` = nama device pemilik saat ini. `verdict` = verdict link itu, kalau tidak ada: `not_safe` pemilik di domain itu kecuali host bersama (`verdict_shared`); berlaku untuk scan `warning` dan `blocked` (`db/repo/scans.ts:529-556`). Verdict membawa `url` (link tempat keputusan dibuat) dan `lockedUntil` untuk `safe` yang masih terkunci. Baris yang dikunjungi ulang naik ke atas (paging `(detected_at, id)`, F-N9 diterima).
- **`POST /verdicts`**: upsert `(owner_id, url)` dengan `url = verdict_link(scan.url)` (origin + path, #241); `by_name` = nama Guardian saat itu; `notes?` ≤ 280 karakter (dihapus setelah 14 hari). `safe` yang masih terkunci → 409 `verdict_locked` (#476: terkunci sampai Minggu 18:00 UTC pertama setelah diputuskan, `db/repo/verdictLock.ts:13-21`). Respons `{ verdict }`.
- **`GET /verdicts?url=&domain=`**: `{ verdict: Verdict | null }`. Urutan: verdict link persis → `not_safe` pemilik di domain itu (bukan host bersama) → null. `safe` tidak pernah berlaku di luar link-nya (`db/repo/verdicts.ts:167-180`). `?domain=` saja (usang): `not_safe` mana pun di domain, kalau tidak ada `safe` terbaru (`:186-195`). Rate limit 30 req / 10 s per device (D-alief-B10); 429 membawa `Retry-After`. Layar blokir polling adaptif: 2 s selama 2 menit, 5 s sampai 10 menit, lalu 15 s (`ios/ShooExtension/Resources/blocked-page.js:8-12`, PR #414); 429 → tunggu `Retry-After`, bukan "tanpa verdict" (C8).
- **`GET /blocklist?since=`**: R2 §5 (hanya entri `blocklist_entries` yang sudah disetujui). `since` kosong = dari awal. Header `Cache-Control: private, max-age=300` (`routes/blocklist.ts:22`).
- **`GET /config/public`**: `{ warnAt, blockAt, version, updatedAt }` dari `admin.public_config` (dashboard) (fase 05 dashboard).
- **`POST /live`**: `{ domain, score, status, analyzing, open }`; start (token push-to-start, diklaim atomik, tunggu 30 s), update (token update), end (`open: false`, tidak dibatasi). Domain dan skor hanya di payload APNs, tidak ditulis ke DB/log (`services/push/live.ts:72-152`). Respons 202.
- **`GET /terms`, `/privacy`, `/support`**: halaman statis EN/ID. **`GET /get`**: 302 ke `APP_STORE_URL` ("Bagikan Shoo").
- **`GET /healthz`**: `{ ok: true }` tanpa DB. **`GET /healthz/db`**: upsert `ops_heartbeat` (MENULIS, supaya dihitung aktivitas DB), 1/menit per IP + 120/jam semua. **`GET /ops/status`**: angka agregat (umur run cron, `ops_jobs`, backlog, antrean blocklist, tombstone macet, ukuran DB, kuota replica) untuk workflow ops-watch (fase 21a); 30/jam.

## 5. Rate limit

Daftar: `backend/api/src/http/rateLimit.ts:12-68`. `hit` = tabel Postgres `rate_limit_hits` (cache Hyperdrive dimatikan, D-alief-17). `hitEdge` = binding Rate Limiting di `wrangler.jsonc`, cadangan Postgres kalau binding tidak ada. `hitLight` = satu statement, boleh lewat sedikit (hanya untuk batas kapasitas).

| Kunci | Batas | Error |
|---|---|---|
| join gagal per device | 5 / 10 menit (`joinAttempts.ts:4,7`) | 429 `too_many_attempts` |
| join gagal per IP (IPv6: /64) | 20 / 10 menit (CGNAT, D-alief-B06), termasuk kode salah di `GET /j/{code}` | 429 `too_many_attempts` + `Retry-After` |
| `GET /j/{code}` semua | 600 / 10 menit (`hitLight`) | lewat batas = halaman tanpa cek |
| `POST /devices` per IP | 30 / jam (QA 11 Nov #2; dulu 10) | 429 `rate_limited` |
| `POST /devices` semua | 1000 / hari | 429 `rate_limited` |
| `POST /devices/me/protected` per device | 30 / jam | 429 `too_many_attempts` |
| `POST /family/code` per guardian | 6 / menit | 429 `rate_limited` |
| `POST /scans` per device | 120 / jam (+ 2000 / jam semua, `hitLight`) | 429 `rate_limited` |
| `GET /verdicts` per device | 30 / 10 s (`hitEdge` `VERDICTS_GET_LIMITER`, D-alief-B10) | 429 `rate_limited` + `Retry-After` |
| `POST /verdicts` per Guardian | 60 / menit | 429 `rate_limited` |
| `POST /live` per device (`open: true`) | 10 / 10 s (`hitEdge` `LIVE_PUSH_LIMITER`) | 429 `rate_limited` |
| `GET /screenshots/{id}` per viewer | 120 / menit (`hitEdge`, D-alief-B08) | 429 `rate_limited` |
| `GET /favicons/{id}` per viewer | 600 / menit (`hitEdge`) | 429 `rate_limited` |
| Unduh favicon per pemilik | 30 / hari (+ 1000 / hari semua) | favicon dibuang, scan tetap 201 |
| `GET /replicas/{id}` per viewer | 10 / menit (`hitEdge`) + 500 / hari, tanpa batas global (D-alief-C26) | 429 `rate_limited` |
| Upload replica per IP | 300 / 24 jam (`replicaIp`, hanya setelah pre-check reuse + kuota) | replica dibuang (`ip_quota`), scan tetap 201 |
| Token tidak dikenal per IP | 60 / 10 menit (+ 1000 / 10 menit semua) | tetap 401 + `Retry-After` |
| `GET /healthz/db` per IP | 1 / menit (+ 120 / jam semua) | 429 `rate_limited` |
| `GET /ops/status` | 30 / jam (hanya setelah token cocok) | 429 `rate_limited` |

## 6. Push

Push dikirim **langsung dari Worker ke APNs** (`services/push/apns.ts`, D-alief-B01/B11). Tidak ada Edge Function relay (`backend/db/supabase/functions/` tidak ada).

`PushSender.send({ toDeviceId, apnsToken, body, scanId? })`. Penerima scan push (`services/push/notify.ts`): `guardianPush` (Guardian pemilik scan Protected, `l.notify` + `notify_family`) dan `ownPush` (device itu sendiri, switch `notify_blocked`/`notify_warning`). Teks dari `messages.ts` sesuai `language` penerima:

| Status | EN (kontrak) | ID |
|---|---|---|
| blocked | `{name} hit a blocked site · {score}%` | `{name} membuka situs yang diblokir · {score}%` |
| warning | `{name} opened a suspicious site · {score}%` | `{name} membuka situs mencurigakan · {score}%` |

Push keluarga tanpa `scanId`: putus ("… stopped protecting you"), hapus akun ("… deleted their Shoo account"), "Ingatkan". Push cron per jam (`cron/notifications.ts`, `5 * * * *`): "Perlindungan mati" (extension anggota diam > 24 jam) dan ringkasan mingguan (Senin 08:00 lokal, Guardian saja). Maks 40 push per run.

Payload: kontrak + `sound` (aditif, C9): `{ "aps": { "alert": { "body": … }, "sound": "default" }, "scanId": "…" }`. Header APNs: `apns-push-type: alert`, `apns-topic: <APNS_TOPIC>`, `apns-priority: 10`, `apns-expiration` = sekarang + 1 jam. Live Activity memakai `apns-push-type: liveactivity`, topic `<APNS_TOPIC>.push-type.liveactivity`, dan token sendiri (`services/push/apns.ts:109-110`) (`services/push/live.ts`). Hanya status 410 (`Unregistered`/`ExpiredToken`) yang mengosongkan token (compare-and-clear: token baru tetap, `db/repo/push.ts:30-32`). Quiet hours menahan push **waspada** saja; push blokir tetap terkirim (`notify.ts:34-36`). Maks 10 push / 10 menit per penerima (`notify.ts:8`). Tanpa retry; `push_log.result` = `sent` / `logged` / `failed:<status>[ <reason>]` / `failed:timeout|network|config`. `400 BadDeviceToken` (juga kalau environment salah) → catat di `push_log`, token TIDAK dihapus. Build TestFlight = APNs production (`APNS_ENV=production`, sekarang di `wrangler.jsonc`).

## 7. Env Worker

Var (bukan rahasia) di `vars` `backend/api/wrangler.jsonc` (ter-commit). Secret cloud: `npx wrangler secret put <NAMA>` (nilai diketik di prompt). Secret lokal: `backend/api/.dev.vars` (gitignored; contoh di `.dev.vars.example`), dan untuk test lewat `miniflare.bindings` di `vitest.config.ts`. Tidak ada secret Edge Function (tidak ada Edge Function).

| Nama | Jenis | Di mana diset | Contoh / catatan |
|---|---|---|---|
| `DB` | binding Hyperdrive | `wrangler.jsonc` (`id` + `localConnectionString`) | `shoo-db`, cache mati (fase 07) |
| `REPLICAS` | binding R2 | `wrangler.jsonc` `r2_buckets` | bucket `shoo-replicas`: replica (EX-07) + favicon baru (PR-05); lifecycle 17 hari |
| `REPLICA_ARCHIVE` | binding R2 | `wrangler.jsonc` `r2_buckets` | bucket `shoo-replica-archive`: fragmen bukti + favicon per domain untuk arsip admin (ADM-07), tanpa lifecycle |
| `VERDICTS_GET_LIMITER`, `SCREENSHOTS_VIEW_LIMITER`, `FAVICONS_VIEW_LIMITER`, `REPLICAS_VIEW_LIMITER`, `LIVE_PUSH_LIMITER` | binding Rate Limiting | `wrangler.jsonc` `ratelimits` | sama dengan `limits` di `rateLimit.ts`; tanpa binding → Postgres |
| `SUPABASE_URL` | var | `wrangler.jsonc` `vars` (cloud) · `.dev.vars` / `vitest.config.ts` (lokal) | cloud `https://nmekxihgjszgcibqytyj.supabase.co`, lokal `http://127.0.0.1:54321`. Bukan rahasia (D-alief-B07) |
| `SUPABASE_SERVICE_ROLE_KEY` | secret | `wrangler secret put` · `.dev.vars` | hanya untuk Storage API (screenshot lama + tombstone). Kosong → objek Supabase tidak bisa dihapus/dibaca |
| `INVITE_BASE_URL` | var | `wrangler.jsonc` `vars` · lokal `.dev.vars` / `miniflare.bindings` | URL Worker; basis `/j/<code>`, link replica/favicon/screenshot |
| `APP_STORE_URL` | var | `wrangler.jsonc` `vars` | link TestFlight/App Store di `/j/<code>` dan `/get`; kosong → `https://apps.apple.com/` |
| `APPLINKS_APP_IDS` | var | `wrangler.jsonc` `vars` | `<Team ID>.<bundle ID>` untuk AASA (Universal Link #129); kosong → link tetap halaman web |
| `APNS_TOPIC` | var | `wrangler.jsonc` `vars` | `com.umarmuhdhor.shoo`; kosong → `LogSender` |
| `APNS_ENV` | var | `wrangler.jsonc` `vars` | `production` (sejak fase 16; `sandbox` untuk build Debug) |
| `APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID` | secret | `wrangler secret put` · `.dev.vars` | `ApnsSender` langsung dari Worker (D-alief-B01); salah satu kosong → `LogSender` (`push_log` `logged`) |
| `SCREENSHOT_MAX_BYTES` | var | `wrangler.jsonc` `vars` | `153600`. Usang sejak fase 20a (screenshot baru tidak disimpan) |
| `SCREENSHOT_URL_SECRET` | secret | `wrangler secret put` · `.dev.vars` · `miniflare.bindings` | kunci HMAC semua link bertanda tangan (screenshot, favicon, replica; D-alief-B08), ≥ 32 byte; kosong → semua URL itu null. Mengganti nilai = semua link lama 404 |
| `RATE_KEY_SECRET` | secret | `wrangler secret put` · `.dev.vars` | HMAC kunci rate limit + IP percobaan join (D-alief-B12); kosong → sha256 |
| `REPLICAS_ENABLED` | var | `wrangler.jsonc` `vars` | `"true"`; selain itu replica tidak disimpan/dilayani (kill-switch D-alief-C25 d). Hapus tetap jalan |
| `INACTIVE_DEVICES` | var | `wrangler.jsonc` `vars` | `dry_run` sekarang; `delete` / `off` (E7, fase 24a) |
| `OPS_STATUS_TOKEN` | secret | `wrangler secret put` | bearer `GET /ops/status` (≥ 32 karakter; kurang → route 404) |
