# R3 — Catatan implementasi API

> **Kontrak = `contracts/api.md`.** File ini hanya menjelaskan detail yang tidak ditulis kontrak (error code tambahan, rate limit, cursor, otorisasi). Kalau ada selisih, kontrak menang dan file ini diperbaiki.
> Base URL: `https://shoo-api.<akun>.workers.dev` (cloud), `http://localhost:8787` (lokal). Semua body JSON, waktu ISO 8601 UTC.

## 1. Bentuk error

Selalu `{ "error": { "code": string, "message": string } }`. `message` bahasa Inggris untuk developer; app menampilkan teks lokal berdasarkan `code`.

| HTTP | code | Kapan |
|---|---|---|
| 400 | `bad_json` | body bukan JSON valid |
| 401 | `unauthorized` | header Authorization hilang / token tidak dikenal |
| 403 | `forbidden` | mode salah (mis. Protected memanggil `POST /family/code`) |
| 404 | `not_found` | resource tidak ada **atau** tidak boleh dilihat (anti-enumerasi) |
| 409 | `already_connected` | Protected yang sudah punya Guardian memanggil `POST /family/join` |
| 409 | `verdict_not_allowed` | verdict untuk scan `warning` (skema: hanya item blocked bisa diberi verdict di MVP) |
| 410 | `code_expired` | kode join kedaluwarsa (kontrak) |
| 404 | `code_invalid` | kode join tidak ada (kontrak) |
| 409 | `family_full` | Guardian sudah punya 3 Protected (kontrak) |
| 413 | `too_large` | body > batas |
| 422 | `invalid_body` | validasi zod gagal (detail field di `message`) |
| 429 | `too_many_attempts` | batas percobaan join (kontrak) |
| 429 | `rate_limited` | batas umum lain |
| 500 | `internal` | error tak dikenal (tanpa detail ke klien, detail di log Worker) |

Kode di luar daftar kontrak (`bad_json`, `already_connected`, `verdict_not_allowed`, `rate_limited`, dll.) dilaporkan ke Umar di PR fase yang memperkenalkannya.

## 2. Auth

- `POST /devices`, `GET /healthz`, `GET /healthz/db`, dan `GET /join` (halaman undangan) tanpa auth. Semua route lain wajib `Authorization: Bearer <token>`.
- Token: `shoo_` + 32 byte acak base64url. DB menyimpan `sha256(token)`. Lookup by hash, bandingkan dengan `timingSafeEqual` tidak perlu karena lookup by hash unik.
- Middleware menaruh `principal = { deviceId, mode, name, language }` di context Hono dan memperbarui `last_seen_at` paling sering 1×/5 menit.

## 3. Otorisasi per endpoint

| Endpoint | Mode | Aturan |
|---|---|---|
| `PATCH /devices/me` | semua | hanya baris sendiri; `name` 1–20, `language` en/id |
| `POST /family/code` | guardian | 403 untuk protected |
| `POST /family/join` | protected | 403 untuk guardian; 409 kalau sudah terhubung |
| `GET /family/members` | guardian | hanya `family_links.guardian_id = me` |
| `DELETE /family/members/{id}` | guardian | 404 kalau `{id}` bukan Protected saya |
| `DELETE /family/guardian` | protected | hapus link saya; 404 kalau tidak ada |
| `POST /scans` | semua | `owner_id = me` selalu (body tidak bisa memilih pemilik) |
| `GET /scans?owner=me` | semua | `owner_id = me` |
| `GET /scans?owner=family` | guardian | `owner_id in (me + protected aktif saya)` — mengikuti fixture `activity-family.json` yang memuat scan Guardian sendiri (`dev_me`); dikonfirmasi ke Umar (TODO C13, D-alief-19); protected → 403 |
| `GET /scans?owner={deviceId}` | guardian | `{deviceId}` = me atau Protected aktif saya, selain itu 404 |
| `GET /scans/{id}` | semua | pemilik = me, atau pemilik = Protected aktif saya; selain itu 404 |
| `POST /verdicts` | guardian | scan milik saya atau Protected aktif saya; scan harus `blocked` |
| `GET /verdicts?domain=` | semua | verdict untuk `(owner_id = me, domain)` — dipakai extension Protected (EX-06) dan juga extension Guardian untuk halaman yang dia blokir sendiri |
| `GET /blocklist` | semua (token) | publik antar-device; tidak ada data pribadi (hanya domain + waktu) |

## 4. Detail per endpoint

- **`POST /devices`**: `avatarId` dipilih acak dari `avatar_01..avatar_12`. Rate limit 10/jam per IP.
- **`POST /family/code`**: R4 §1. Respons `{ code, expiresAt, inviteUrl }` dengan `inviteUrl = ${INVITE_BASE_URL}/join?code=<code>` (D-alief-03).
- **`GET /join?code=`** (HTML, tanpa auth): halaman kecil EN/ID berisi tombol "Open Shoo" → `shoo://join?code=<code>`, kode besar untuk diketik manual, dan link App Store (placeholder sampai ada). `code` **wajib** cocok `^\d{4}$`; selain itu halaman tampil tanpa kode dan tanpa tombol. Nilai di-escape HTML, header `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'`, `X-Content-Type-Options: nosniff`. Tidak memeriksa apakah kode aktif (tidak membocorkan status). Test XSS: `?code=<script>`, `?code=1234"onclick=`, `?code=12345`.
- **`GET /family/members`**: `extensionActive` = `ext_last_seen_at > now() - 24 h` (jendela sama dengan `AppGroup.extensionActiveWindow`). Kontrak belum punya jalur data dari extension ke server. Usulan D-alief-15 (TODO C11, dikirim sebelum fase 05/08): field opsional `extensionLastSeenAt` di `PATCH /devices/me`, dikirim **oleh extension** (punya token dari App Group) paling sering 1×/jam saat heartbeat, dan oleh app saat foreground. Sampai disetujui: `ext_last_seen_at` tidak diketahui → `extensionActive: true` (jangan pernah menampilkan "Not connected" tanpa bukti; deviasi PRD dicatat di D-alief-15). `lastScan` = scan terbaru pemilik itu (objek ringkas sesuai fixture `family-members.json`).
- **`POST /scans`**: body = ScanResult tanpa `id`/`verdict` (kontrak) + `screenshotBase64?`. Field `ownerDeviceId`/`ownerName` **diterima tapi diabaikan** (server selalu memakai principal); schema zod tidak `.strict()` untuk dua field itu. Test: body berisi `ownerDeviceId` device lain → tersimpan sebagai milik principal, bukan 422. Validasi: skor 30–100, `status` konsisten, `domain` = host `url` lowercase tanpa `www.`, `signals` ≤ 20 item sesuai skema Signal, body ≤ 256 KB. Respons `{ id }` lalu push (R4 §3) dijalankan dengan `ctx.waitUntil`.
- **Screenshot**: decode base64 → kalau > 150 KB atau bukan JPEG/PNG → dibuang (scan tetap disimpan, `metric` log). Dedupe: kalau ada scan pemilik+domain < 24 jam yang punya screenshot, pakai `screenshot_path` itu. Kuota: > 50 screenshot pemilik itu dalam 24 jam → dibuang. Upload ke `screenshots/<owner_id>/<scan_id>.jpg`.
- **`GET /scans`**: cursor = base64url(`<detected_at ISO>|<id>`), `limit` default 20 maks 50, urutan `detected_at desc, id desc`. Filter `status`. `screenshotUrl` = `null` di daftar (D-alief-04). `ownerName` = nama device pemilik saat ini. `verdict` = join `verdicts` (owner, domain) **hanya untuk scan `blocked`**; scan `warning` selalu `verdict: null` (skema: hanya item blocked bisa diberi verdict di MVP). `pageTitle` null → field dihilangkan (skema: string). Setiap respons divalidasi dengan `contracts/scan-result.schema.json` (ajv) di test.
- **`GET /scans/{id}`**: `screenshotUrl` = signed URL Storage 3600 s (satu subrequest).
- **`POST /verdicts`**: upsert `(owner_id, domain)`; `by_name` = nama Guardian saat itu. Respons `{ verdict }` (bentuk `Verdict` kontrak).
- **`GET /verdicts?domain=`**: `{ verdict: Verdict | null }`. Rate limit 1 req/2 s per device (polling 5 s cukup).
- **`GET /blocklist?since=`**: R2 §5. `since` kosong = dari awal. Header `Cache-Control: max-age=300`.
- **`GET /healthz`**: `{ ok: true }` tanpa DB. **`GET /healthz/db`**: upsert `ops_heartbeat` (MENULIS, supaya dihitung aktivitas DB dan tidak terlayani cache), rate limit 1/menit per IP. Dipakai monitor harian (B9).

## 5. Rate limit

Disimpan di Postgres (tidak ada KV), cukup untuk skala MVP. Karena cache Hyperdrive dimatikan (D-alief-17), hitungan selalu segar:

| Kunci | Batas | Error |
|---|---|---|
| join gagal per device | 5 / 10 menit | 429 `too_many_attempts` |
| join gagal per IP | 5 / 10 menit | 429 `too_many_attempts` |
| `POST /devices` per IP | 10 / jam | 429 `rate_limited` |
| `POST /family/code` per guardian | 6 / menit | 429 `rate_limited` |
| `POST /scans` per device | 120 / jam | 429 `rate_limited` |
| `GET /verdicts` per device | 1 / 2 s (memori isolate, best effort) | 429 `rate_limited` |
| `GET /healthz/db` per IP | 1 / menit | 429 `rate_limited` |

## 6. Push

`PushSender.send({ toDeviceId, apnsToken, body, scanId })`. Teks dari `messages.ts` sesuai `language` Guardian:

| Status | EN (kontrak) | ID |
|---|---|---|
| blocked | `{name} hit a blocked site · {score}%` | `{name} membuka situs yang diblokir · {score}%` |
| warning | `{name} opened a suspicious site · {score}%` | `{name} membuka situs mencurigakan · {score}%` |

Payload: kontrak + `sound` (aditif, disampaikan di C9): `{ "aps": { "alert": { "body": … }, "sound": "default" }, "scanId": "…" }`. Header APNs: `apns-push-type: alert`, `apns-topic: com.shoo.app`, `apns-priority: 10`. Hanya `410 Unregistered` yang mengosongkan `devices.apns_token`. `400 BadDeviceToken` (juga muncul kalau environment salah: token sandbox ke host production atau sebaliknya) → catat di `push_log`, token TIDAK dihapus. Build TestFlight = APNs production → set `APNS_ENV=production` sebelum QA-E2E.

## 7. Env Worker

| Nama | Jenis | Contoh / catatan |
|---|---|---|
| `DB` | binding Hyperdrive | `shoo-db` |
| `SUPABASE_URL` | secret | `https://<ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | secret | hanya untuk Storage API |
| `INVITE_BASE_URL` | var | URL Worker |
| `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` | secret | di Worker (JWT dibuat Worker lalu dikirim ke relay) atau di Edge Function (relay membuat JWT sendiri) — dipilih di fase 11; kosong → `LogSender` |
| `APNS_ENV` | var | `sandbox` \| `production` |
| `PUSH_RELAY_URL`, `PUSH_RELAY_SECRET` | var/secret | jalur utama (relay Edge Function `push`, D-alief-16); secret yang sama diset di Edge Function (`supabase secrets set`) |
| `BLOCKLIST_MIN_FAMILIES` | var | `1` (R2 §5) |
| `APNS_SPIKE` | var | `1` hanya saat spike fase 07; endpoint debug dihapus di fase 11 |
| `SCREENSHOT_MAX_BYTES` | var | `153600` |
