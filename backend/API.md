# Shoo API reference

What each backend endpoint is for, what it expects and what it returns. The shared contract is
[`contracts/api.md`](../contracts/api.md) (read-only, owned by the lead); this file describes how the
Worker in `backend/api` implements it. If the two ever disagree, `contracts/` wins and this file is a bug.

- **Base URL (cloud):** `https://shoo-api.afindo-mi01.workers.dev`
- **Local:** `http://localhost:8787` (`npm run dev` in `backend/api`, see [README](README.md#local-setup))

## Contents

- [General rules](#general-rules): auth, request format, errors, rate limits, caching
- [Health](#health): `GET /healthz`, `GET /healthz/db`
- [Devices](#devices): `POST /devices`, `GET /devices/me`, `PATCH /devices/me`, `POST /devices/me/protected`, `DELETE /devices/me`
- [Family](#family): `POST /family/code`, `POST /family/join`, `GET /family/members`, `PATCH /family/members/{deviceId}`, `POST /family/members/{deviceId}/remind`, `DELETE /family/members/{deviceId}`, `DELETE /family/guardian`
- [Scans](#scans): `POST /scans`, `GET /scans`, `GET /scans/{id}`
- [Screenshots](#screenshots): `GET /screenshots/{scanId}` (deprecated, removed in fase 18c)
- [Favicons](#favicons): `GET /favicons/{scanId}`
- [Verdicts](#verdicts): `POST /verdicts`, `GET /verdicts`
- [Blocklist](#blocklist): `GET /blocklist`
- [Web pages](#web-pages): `GET /j/{code}`, `GET /og/invite.jpg`, `GET /.well-known/apple-app-site-association`, `GET /privacy`, `GET /terms`, `GET /get`
- [Push notification](#push-notification) sent by `POST /scans`
- [Scheduled pushes](#scheduled-pushes): protection off, weekly summary (hourly cron)

> **PF-01 profile redesign (proposed, not yet in `contracts/api.md`).** Fields and endpoints marked
> *PF-01 proposed* below were added for the Figma profile screens. They only add to the contract (no
> existing field changed). The lead copies them into `contracts/api.md` or asks for changes in the PR.

## General rules

### Auth

There are no accounts or passwords. `POST /devices` creates a device and returns a **device token**
once. Every other call (except health, web pages, screenshot and favicon links) sends it:

```http
Authorization: Bearer shoo_<43 characters>
```

- The backend stores only a SHA-256 hash of the token and never logs it.
- Each device has a fixed **mode**: `guardian` (parent) or `protected` (family member). Some endpoints
  allow only one mode; the other mode gets `403 forbidden`.
- A missing, malformed or unknown token returns `401 unauthorized`. Treat 401 as "this token is dead"
  (for example after `DELETE /devices/me`): start onboarding again. After 60 unknown tokens in 10 min
  from one IP the answer is still 401, now with `Retry-After`.

### Request format

- JSON bodies with `Content-Type: application/json`, UTF-8.
- Maximum body size: 16 KB (most endpoints), 256 KB for `POST /scans`, 1 KB for `POST /verdicts`.
  A larger body returns `413 too_large`.
- Times are ISO 8601 with an offset, e.g. `2026-10-22T03:05:00Z`, between 1970 and 2100.
- Names are 1–20 characters after trimming, without control or bidi-override characters.
- Domains are lowercase registrable domains without `www.`, e.g. `bca-verifikasi.site`.

### Errors

Every error has the same shape:

```json
{ "error": { "code": "invalid_body", "message": "name: must be 1-20 characters" } }
```

`message` is for logs and debugging only; clients branch on `code`.

| HTTP | `code` | When |
|---|---|---|
| 400 | `bad_json` | Body is not valid JSON |
| 401 | `unauthorized` | Token missing, malformed or unknown |
| 403 | `forbidden` | Wrong device mode for this endpoint |
| 404 | `not_found` | The thing does not exist, or you may not see it (both look the same on purpose) |
| 413 | `too_large` | Body over the size limit |
| 422 | `invalid_body` | Body or query fails validation; `message` names the field |
| 409 | `has_members` | *PF-01 proposed.* `POST /devices/me/protected` while the Guardian still protects someone |
| 429 | `rate_limited` | Too many requests; wait `Retry-After` seconds and retry |
| 500 | `internal` | Unexpected server error |

Endpoint-specific codes are listed under each endpoint.

### Rate limits

Limits are per device (or per IP before a device exists) over a sliding window. Over the limit:
`429 rate_limited` with a `Retry-After` header in seconds. A 429 is never an empty answer: retry
after the wait.

### Caching and privacy headers

- Every response is `Cache-Control: private, no-store`, except `GET /blocklist` (`private, max-age=300`).
  Deleted or disconnected data must disappear at once (Apple privacy rule, `plan/alief/SECURITY.md` §3 P13).
- Every response also carries `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `X-Frame-Options: DENY`, HSTS and a strict CSP. There are no CORS headers: only the native app and
  extension call this API.
- Logs never contain tokens, device ids, names or URLs. Workers invocation logs are off.

## Health

### `GET /healthz`

**For:** uptime monitors. Checks that the Worker answers; does not touch the database.

- **Auth:** none
- **Response 200:** `{ "ok": true }`

### `GET /healthz/db`

**For:** checking the database path. Each call writes a heartbeat row, which also keeps the Supabase
Free project from pausing.

- **Auth:** none
- **Rate limit:** 1 per minute per IP
- **Response 200:** `{ "ok": true }`

## Devices

### `POST /devices`

**For:** onboarding (ON-02, ON-03). Registers this phone and returns its device token. Called once by
the app after the user picks a name and a mode.

- **Auth:** none
- **Rate limit:** 10 per hour per IP (and 1000 per day across all users)

**Request body**

| Field | Type | Required | Rules |
|---|---|---|---|
| `name` | string | yes | 1–20 characters |
| `mode` | `"guardian"` \| `"protected"` | yes | Cannot be changed later |
| `apnsToken` | string | no | Hex APNs device token (32–200 hex characters) |

```json
{ "name": "Mom", "mode": "protected" }
```

**Response 201**

```json
{ "deviceId": "0b6e0c1e-…", "token": "shoo_…", "avatarId": "avatar_07" }
```

- `token` is shown only in this response. The app stores it in the Keychain and writes the session
  keys for the extension to the App Group (`contracts/app-group-keys.md`).
- `avatarId` is random, `avatar_01` to `avatar_12`.

### `GET /devices/me`

**For:** the Profile screen (PF-01) and for a Protected device to learn whether it is still connected
to its Guardian.

- **Auth:** Bearer, either mode

**Response 200**

```json
{
  "deviceId": "0b6e0c1e-…",
  "name": "Mom",
  "avatarId": "avatar_07",
  "mode": "protected",
  "language": "en",
  "guardian": { "deviceId": "7d1f…", "name": "Adhella", "avatarId": "avatar_02" },
  "stats": { "blocked": 3, "warnings": 1, "since": "2026-09-14T02:10:00.000Z" },
  "timeZone": "Asia/Jakarta",
  "notifications": {
    "warning": true, "blocked": true, "family": true, "protectionOff": true,
    "weeklySummary": false, "quietHours": true, "quietStart": "22:00", "quietEnd": "06:00"
  }
}
```

`guardian` is `null` when a Protected device is not connected, and always `null` for a Guardian.

`stats` (*PF-01 proposed*): the profile numbers. `blocked` and `warnings` count every scan this device
ever posted, by status; they do not drop when the 14-day retention deletes scans (numbers only, no
addresses). `since` is when the device registered ("Hari terlindungi").

`timeZone` and `notifications` (*PF-01 proposed*, "Pengaturan/Notifikasi"): the switches the server
uses to decide which pushes go out (see [Push notification](#push-notification) and
[Scheduled pushes](#scheduled-pushes)). The values above are the defaults for every device:

| Key | Figma row | Effect |
|---|---|---|
| `warning` | Situs berbahaya | Push to this device for its own `warning` scans |
| `blocked` | Situs diblokir | Push to this device for its own `blocked` scans |
| `family` | Aktivitas orang dilindungi | Guardian: push for members' scans (together with the per-member "Kabari saya") |
| `protectionOff` | Perlindungan mati | Guardian: one push when a member's extension has not reported for 24 h |
| `weeklySummary` | Ringkasan mingguan | Monday from 08:00 local: counts of the last 7 days |
| `quietHours`, `quietStart`, `quietEnd` | Jam tenang | Local 24-hour `HH:MM` in `timeZone`. Warnings and scheduled pushes wait; `blocked` pushes still go out. `quietStart == quietEnd` means all day |

### `PATCH /devices/me`

**For:** renaming (PF-01), saving the APNs token after the notification prompt (ON-05), choosing the
push language, and the extension's hourly heartbeat that drives "Not connected" on the Guardian side.

- **Auth:** Bearer, either mode

**Request body** (send only the fields that change)

| Field | Type | Rules |
|---|---|---|
| `name` | string | 1–20 characters |
| `apnsToken` | string \| `null` | Hex APNs token; `null` clears it (push turned off) |
| `language` | `"en"` \| `"id"` | Language of push texts sent to this device |
| `extensionLastSeenAt` | ISO time | At most 5 minutes in the future. Sent by the extension at most once per hour and by the app when it comes to the foreground |
| `deviceModel` | string | *PF-01 proposed.* Marketing name, e.g. `"iPhone 15"`: 1–40 letters, digits, spaces, parentheses. Shown to the Guardian only |
| `osVersion` | string | *PF-01 proposed.* Major iOS version, e.g. `"26"`: 1–3 digits |
| `avatarId` | string | *PF-01 proposed* ("Ubah foto"). `avatar_01` … `avatar_12` |
| `timeZone` | string | *PF-01 proposed.* IANA zone of the phone, e.g. `"Asia/Makassar"`: at most 40 characters, `^[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}$`, and known to the runtime. Sent by the app once per launch with the device info |
| `notifications` | object | *PF-01 proposed.* Any of the keys in [`GET /devices/me`](#get-devicesme) `notifications`; only sent keys change. Booleans, and `quietStart` / `quietEnd` as `HH:MM` (00:00–23:59). Unknown keys → `422` |

```json
{ "language": "id" }
```

**Response 200:** `{ "ok": true }`

### `POST /devices/me/protected`

**For:** *PF-01 proposed.* "Punya kode undangan?" on "Mode akun": a Guardian who protects nobody joins
another family and is a Protected device from then on.

- **Auth:** Bearer, `guardian` only (`403` otherwise)
- **Request body:** `{ "code": "482193" }` (6 digits)
- A device's mode never changes, so the server makes a new Protected device with the same name, avatar,
  language, APNs token, device info, time zone and settings, joins it with the code (same checks and
  attempt limits as [`POST /family/join`](#post-familyjoin)), and only then deletes the old Guardian
  device and everything about it, as in [`DELETE /devices/me`](#delete-devicesme). A failed join
  deletes the new device again: nothing changes for the Guardian.
- Rate limit: the `POST /devices` limit per IP, plus the join attempt limits.

**Response 200**

```json
{
  "deviceId": "3c9a…",
  "token": "shoo_…",
  "avatarId": "avatar_07",
  "guardian": { "deviceId": "7d1f…", "name": "Budi", "avatarId": "avatar_04" }
}
```

The new token is shown only in this response; the old token returns `401` from now on. The app
saves it in the Keychain and the App Group, then sends its APNs token again.

**Errors:** `409 has_members` (disconnect the members first), and the `POST /family/join` errors
`code_invalid`, `code_expired`, `family_full`, `rate_limited`.

### `DELETE /devices/me`

**For:** "Delete account" in Profile (PF-01, App Store Guideline 5.1.1(v)). Deletes this device and
everything about it right away.

- **Auth:** Bearer, either mode
- **Deletes:** family links on either side, family codes, join attempts, all scans, screenshots and favicons,
  verdicts on its scans or made by it, push log.
- **Response 200:** `{ "ok": true }`
- After this the token returns `401` and every screenshot and favicon link returns `404`. The files are
  removed from storage just after the response; if storage cannot be reached, the daily cron retries.
- The app then clears the Keychain token and the App Group keys and starts onboarding again.

## Family

A Guardian can have at most 3 Protected devices; a Protected device has at most one Guardian.

### `POST /family/code`

**For:** "Family code" on the Guardian (GD-04, PR-03). Shows a 6-digit code and a QR the Protected
device scans or types, and the same code in the invite link shared on WhatsApp / AirDrop.

- **Auth:** Bearer, **guardian** only
- **Rate limit:** 6 per minute per device
- **Request body:** none, `{}`, or `{ "refresh": true }`

| Field | Type | Rules |
|---|---|---|
| `refresh` | boolean, optional | `true` always makes a new code. Any other field → `422 invalid_body` |

**Response 200**

```json
{ "code": "482193", "expiresAt": "2026-10-22T03:35:00.000Z", "inviteUrl": "https://shoo-api.afindo-mi01.workers.dev/j/482193" }
```

- The code is valid for 30 minutes and can be used by several Protected devices until the family is full.
- Without `refresh`, the Guardian's active code comes back while it has more than 5 minutes left, so the
  screen and a link shared earlier show the same code. With 5 minutes or less left, a new code replaces it.
- `refresh: true` ("Create new code") replaces the code; the old code and every link with it stop working
  at once (`404 code_invalid`).
- `inviteUrl` is an https link (see [`GET /j/{code}`](#get-jcode)). With the app installed it is a
  Universal Link and opens the app; otherwise a small page opens.

| Error | When |
|---|---|
| `422 invalid_body` | `refresh` is not a boolean, or the body has other fields |
| `503 code_unavailable` | No free 6-digit code was found. Show "Try again" |

### `POST /family/join`

**For:** "Connect" on the Protected device (PR-01, PR-03): scan the QR, type the code or open the
invite link.

- **Auth:** Bearer, **protected** only

**Request body**

| Field | Type | Rules |
|---|---|---|
| `code` | string | Exactly 6 digits |

```json
{ "code": "482193" }
```

**Response 200**

```json
{ "guardian": { "deviceId": "7d1f…", "name": "Adhella", "avatarId": "avatar_02" } }
```

| Error | When |
|---|---|
| `404 code_invalid` | No such code (also when the Guardian replaced it) |
| `410 code_expired` | The code is older than 30 minutes |
| `409 family_full` | The Guardian already has 3 Protected devices |
| `409 already_connected` | This device already has a Guardian |
| `429 too_many_attempts` | Too many wrong codes: 5 per 10 min per device or 20 per 10 min per IP. Has `Retry-After` |

Only wrong or expired codes count as failed attempts.

### `GET /family/members`

**For:** the Guardian's family cards on Shield (GD-03), including the "Not connected" state.

- **Auth:** Bearer, **guardian** only

**Response 200**

```json
{
  "members": [
    {
      "deviceId": "0b6e0c1e-…",
      "name": "Mom",
      "avatarId": "avatar_07",
      "extensionActive": true,
      "lastScan": { "status": "blocked", "score": 92, "url": "https://bca-verifikasi.site/login?ref=wa", "detectedAt": "2026-10-21T04:05:00.000Z" },
      "connectedAt": "2026-09-14T02:10:00.000Z",
      "lastSeenAt": "2026-10-28T03:58:00.000Z",
      "deviceModel": "iPhone 15",
      "osVersion": "26",
      "notify": true,
      "remindedAt": null,
      "stats": { "blocked": 3, "warnings": 5 }
    }
  ]
}
```

- Ordered by when each member joined.
- `extensionActive` is `false` only when the extension's last heartbeat is older than 24 hours. With
  no heartbeat yet it is `true` (never "Not connected" without evidence).
- `lastScan` is `null` when the member has no scans.
- *PF-01 proposed* (member detail, "Guardian/Detail Orang Dilindungi"): `connectedAt` = when the link
  was made ("Terhubung sejak"); `lastSeenAt` = last extension heartbeat, `null` before the first
  ("aktif 2 mnt lalu"); `deviceModel` / `osVersion` as sent by the member, `null` until then;
  `notify` = "Kabari saya"; `remindedAt` = last "Ingatkan" push or `null`; `stats` = the member's
  lifetime counters, as in `GET /devices/me`.

### `PATCH /family/members/{deviceId}`

**For:** *PF-01 proposed.* "Kabari saya" on the member detail.

- **Auth:** Bearer, **guardian** only
- **Request body:** `{ "notify": false }` (only `notify`, a boolean)
- **Response 200:** `{ "ok": true }`
- **Errors:** `404 not_found` when `deviceId` is not one of your members; `422 invalid_body`.
- `notify: false` skips the Guardian's push for this member's scans. The scans are still stored and
  still show in Activity.

### `POST /family/members/{deviceId}/remind`

**For:** *PF-01 proposed.* "Ingatkan" next to a member whose extension is off.

- **Auth:** Bearer, **guardian** only. No body.
- **Response 200:** `{ "ok": true }`. One push to the member, in the member's language:
  "Adhella reminds you: turn on Shoo in Safari" / "Adhella mengingatkan: nyalakan Shoo di Safari".
  No `scanId` in the payload, so a tap just opens the app.
- **Errors:** `404 not_found` (not your member); `409 push_unavailable` (the member has notifications
  off, nothing sent, the slot is not used); `429 remind_too_soon` with `Retry-After` (seconds) when the
  member was reminded in the last 6 hours.

### `DELETE /family/members/{deviceId}`

**For:** a Guardian removing a member (GD-04).

- **Auth:** Bearer, **guardian** only
- **Response 200:** `{ "ok": true }`
- **Errors:** `404 not_found` when `deviceId` is not one of your members.
- The Guardian loses access to that member's scans and screenshots at once, and the verdicts it made for
  that member are deleted.
- *PF-01 proposed:* the removed member gets one push when it has notifications on: "Adhella stopped
  protecting you" / "Adhella berhenti melindungimu" (no `scanId`).

### `DELETE /family/guardian`

**For:** "Disconnect" on the Protected device's Profile (PF-01).

- **Auth:** Bearer, **protected** only
- **Response 200:** `{ "ok": true }`
- **Errors:** `404 not_found` when the device has no Guardian.
- Same effect as the Guardian removing this member.

## Scans

A **scan** is one page the extension warned about or blocked (shape: `ScanResult` in
[`contracts/scan-result.schema.json`](../contracts/scan-result.schema.json)). Only score 30 or more is
ever sent. Scans and screenshots are deleted automatically after 14 days.

### `POST /scans`

**For:** the Safari extension (EX-07) after it blocks a page or finishes all layers on a warning
page. One page is one scan, one Activity item and (for a Protected device) one push to the Guardian.

- **Auth:** Bearer, either mode. The owner is always the token's device.
- **Rate limit:** 120 per hour per device
- **Body limit:** 256 KB

**Request body:** a `ScanResult` without `id`, `verdict` and `screenshotUrl`, plus an optional screenshot.

| Field | Type | Required | Rules |
|---|---|---|---|
| `url` | string | yes | http(s) URL, ≤ 2048 characters |
| `domain` | string | yes | Registrable domain; the URL's host must be this domain or a subdomain of it |
| `pageTitle` | string \| null | no | Trimmed and cut to 300 characters |
| `faviconUrl` | string \| null | no | The site's icon. Kept only if it is an http(s) URL ≤ 2048 characters; the server downloads it (see Favicon rules) |
| `score` | integer | yes | 30–100 |
| `status` | `"warning"` \| `"blocked"` | yes | Must be `blocked` when score ≥ 80, else `warning` |
| `signals` | array | yes | At most 20 items, see below |
| `detectedAt` | ISO time | yes | Not in the future (5 min tolerance) |
| `screenshotBase64` | string \| null | no | **Deprecated** (see Screenshot rules). JPEG or PNG, base64 without a `data:` prefix |

Each signal:

| Field | Type | Rules |
|---|---|---|
| `id` | string | 1–64 characters, e.g. `new_domain` |
| `layer` | integer | 1–5 |
| `weight` | integer | 0–100 |
| `label` | `{ en, id }` | Technical text for the Guardian, 1–500 characters each |
| `labelSimple` | `{ en, id }` | Plain text for the Protected user, 1–500 characters each |
| `evidence` | string | Optional, ≤ 500 characters |

`ownerDeviceId` and `ownerName` are accepted but ignored. Control and bidi characters are removed from
all text.

```json
{
  "url": "https://bca-verifikasi.site/login?ref=wa",
  "domain": "bca-verifikasi.site",
  "pageTitle": "KlikBCA - Verifikasi Akun",
  "score": 92,
  "status": "blocked",
  "signals": [
    {
      "id": "new_domain", "layer": 2, "weight": 30,
      "label": { "en": "Domain age 3 days", "id": "Umur domain 3 hari" },
      "labelSimple": { "en": "This site was made 3 days ago", "id": "Situs ini baru dibuat 3 hari lalu" }
    }
  ],
  "detectedAt": "2026-10-21T04:05:00Z",
  "screenshotBase64": "/9j/4AAQSkZJRg…"
}
```

**Response 201:** `{ "id": "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03" }`

> **Deprecated (EX-07).** Extension builds from `main` since PR #178 (29 Oct 2026) no longer send a screenshot; they send a page replica instead, which the backend stores from fase 18a. `screenshotBase64` and `GET /screenshots/{scanId}` stay only for older builds and for scans already stored, and are removed in fase 18c (plan/alief, D-alief-C24/C27).

**Screenshot rules.** The screenshot is optional, and a bad screenshot never fails the scan: the scan
is still stored and the answer is still 201. It is dropped when it is not JPEG/PNG, is over 150 KB or
1280 px on its longest side, or the device already sent 50 in the last 24 h. A second scan of the same
domain within 24 h reuses the earlier screenshot.

**Favicon rules.** When `faviconUrl` is set, the server downloads the icon once, after the response, and
stores it like the screenshot; the app never contacts the scam site (SECURITY P9). A favicon problem
never fails or delays the scan. The download only goes to public addresses (the name is resolved first;
no private, loopback or link-local hosts), http(s) on the default port, at most 2 redirects (each hop
checked again), 3 s in total, at most 64 KB and 512 px per side. Only PNG, ICO, JPEG, GIF and WebP are
kept, checked by `Content-Type` and by the file's first bytes; SVG and anything else is dropped. No cookies and no
`Referer` are sent. A scan of the same domain within 24 h reuses the earlier favicon without a new
download. At most 30 downloads per device and 200 for everyone per 24 h (failed downloads count);
past that the scan is stored without a favicon.

**Push.** When a Protected device sends a scan, its Guardian gets a push right after the response
(see [Push notification](#push-notification)). A push failure never fails the scan.

### `GET /scans`

**For:** the Activity lists: a Protected user's own history (PR-05) and the Guardian's family
activity (GD-05).

- **Auth:** Bearer, either mode

**Query parameters**

| Name | Default | Meaning |
|---|---|---|
| `owner` | `me` | `me` = my scans. `family` = mine plus all my members' (guardian only). A member's `deviceId` = only that member (guardian only) |
| `status` | all | `warning` or `blocked` |
| `limit` | 20 | 1–50 |
| `cursor` | – | `nextCursor` from the previous page |

```http
GET /scans?owner=family&status=blocked&limit=20
```

**Response 200**

```json
{ "items": [ { "id": "6f1c…", "url": "…", "domain": "bca-verifikasi.site", "score": 92, "status": "blocked", "signals": [], "screenshotUrl": null, "ownerDeviceId": "0b6e…", "ownerName": "Mom", "detectedAt": "2026-10-21T04:05:00.000Z", "verdict": null } ],
  "nextCursor": "MjAyNi0xMC0yMVQwNDowNTowMC4wMDBafDZmMWM…" }
```

- Newest first. `nextCursor` is `null` on the last page.
- Items are full `ScanResult`s, but `screenshotUrl` is always `null` in lists; open the scan to get it.
- `faviconUrl` is a link made for you to the stored icon (see [Favicons](#favicons)), valid for 1 hour,
  or `null` when no icon was stored. It is never the site's own favicon URL.
- `verdict` is the Guardian's decision for that owner and domain, or `null`.

| Error | When |
|---|---|
| `403 forbidden` | `owner=family` from a Protected device |
| `404 not_found` | `owner=<deviceId>` that is not one of your members |
| `422 invalid_body` | Bad `status`, `limit` or `cursor` |

### `GET /scans/{id}`

**For:** the Detail screen (DT-01 to DT-06), opened from Activity or from a push.

- **Auth:** Bearer, either mode. You can open your own scans and, as a Guardian, your members' scans.

**Response 200:** one `ScanResult`:

```json
{
  "id": "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03",
  "url": "https://bca-verifikasi.site/login?ref=wa",
  "domain": "bca-verifikasi.site",
  "pageTitle": "KlikBCA - Verifikasi Akun",
  "faviconUrl": "https://shoo-api.afindo-mi01.workers.dev/favicons/6f1c…?v=…&exp=…&sig=…",
  "score": 92,
  "status": "blocked",
  "signals": [ { "id": "new_domain", "layer": 2, "weight": 30, "label": { "en": "…", "id": "…" }, "labelSimple": { "en": "…", "id": "…" } } ],
  "screenshotUrl": "https://shoo-api.afindo-mi01.workers.dev/screenshots/6f1c…?v=…&exp=…&sig=…",
  "ownerDeviceId": "0b6e0c1e-…",
  "ownerName": "Mom",
  "detectedAt": "2026-10-21T04:05:00.000Z",
  "verdict": { "value": "not_safe", "byDeviceId": "7d1f…", "byName": "Adhella", "decidedAt": "2026-10-21T04:07:12.000Z" }
}
```

- `pageTitle` is left out when there is none.
- `screenshotUrl` is a link made for you, valid for 1 hour, or `null` when there is no screenshot.
- `faviconUrl` is the same kind of link to the stored icon, or `null` when there is none. The site's
  own favicon URL is never returned (PR-05).
- **Errors:** `404 not_found` when the scan does not exist, was deleted, or is not yours to see.

## Screenshots

> **Deprecated (EX-07).** Extension builds from `main` since PR #178 (29 Oct 2026) no longer send a screenshot; they send a page replica instead, which the backend stores from fase 18a. `screenshotBase64` and `GET /screenshots/{scanId}` stay only for older builds and for scans already stored, and are removed in fase 18c (plan/alief, D-alief-C24/C27).

### `GET /screenshots/{scanId}?v=&exp=&sig=`

**For:** showing the screenshot on the Detail screen. This is the `screenshotUrl` from
`GET /scans/{id}`; load it as is (e.g. `AsyncImage`), **without** an `Authorization` header.

- **Auth:** the signature in the link. The link names the viewer and expires after 1 hour.
- **Rate limit:** 120 per minute per viewer
- **Response 200:** the image (`image/jpeg` or `image/png`), `Cache-Control: private, no-store`.
- Access is re-checked in the database on every request. After the scan is deleted, the member
  disconnects or is removed, or the 14-day retention runs, the same link returns `404` at once.
- **Errors:** `404 not_found` for an expired, altered or no-longer-allowed link. An expired link also
  gives 404, so re-fetch `GET /scans/{id}` once for a fresh link before showing "deleted".

## Favicons

### `GET /favicons/{scanId}?v=&exp=&sig=`

**For:** the site icon in Activity rows and on Detail. This is the `faviconUrl` from `GET /scans` or
`GET /scans/{id}`; load it as is (e.g. `AsyncImage`), **without** an `Authorization` header. Works
exactly like a screenshot link.

- **Auth:** the signature in the link. The link names the viewer and expires after 1 hour.
- **Rate limit:** 600 per minute per viewer (a list page can show 50 icons)
- **Response 200:** the image (`image/png`, `image/x-icon`, `image/jpeg`, `image/gif` or `image/webp`;
  at most 64 KB and 512 px per side; never a redirect),
  `Cache-Control: private, no-store`, `X-Content-Type-Options: nosniff`,
  `Content-Security-Policy: default-src 'none'; sandbox`, `Referrer-Policy: no-referrer`.
- Access is re-checked in the database on every request: the owner, or the owner's current Guardian.
  After the scan is deleted, the member disconnects or is removed, or the 14-day retention runs, the
  same link returns `404` at once. Disconnect only hides the icon from the Guardian; the owner keeps it.
- Stored icons are deleted with their scan: after 14 days, or right away on `DELETE /devices/me`.
- **Errors:** `404 not_found` for an expired, altered or no-longer-allowed link. On 404 show a
  placeholder icon; re-fetch the list or scan for a fresh link.

## Verdicts

A **verdict** is the Guardian's decision on a blocked domain: `safe` ("It's safe") or `not_safe`
("Not safe"). It applies per owner and domain, so it covers every visit by that person to that site.

### `POST /verdicts`

**For:** the It's safe / Not safe buttons on Detail (GD-07). The decision applies at once, with no
confirmation step.

- **Auth:** Bearer, **guardian** only
- **Rate limit:** 60 per minute per device
- **Body limit:** 1 KB

**Request body**

| Field | Type | Rules |
|---|---|---|
| `scanId` | string | The blocked scan the Guardian is looking at |
| `value` | `"safe"` \| `"not_safe"` | |

```json
{ "scanId": "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03", "value": "not_safe" }
```

**Response 200**

```json
{ "verdict": { "value": "not_safe", "byDeviceId": "7d1f…", "byName": "Adhella", "decidedAt": "2026-10-21T04:07:12.000Z" } }
```

- A new verdict replaces the previous one for that owner and domain.
- A Guardian can decide on its own blocked scans and on its members' blocked scans.
- A `not_safe` on a connected member's scan also queues the domain for **manual** review before it can
  enter the global blocklist (at most 10 new domains per Guardian per 24 h). Government, education and bank domains, and
  shared roots such as `co.id` or `vercel.app`, are never queued.

| Error | When |
|---|---|
| `404 not_found` | Unknown scan id |
| `403 verdict_not_allowed` | Not your scan and not one of your members' scans |
| `409 verdict_not_allowed` | The scan is a warning, not blocked |

### `GET /verdicts?domain=`

**For:** the extension's block screen (EX-06). While it is open, the extension polls this every
5 seconds; when the Guardian taps "It's safe" the page opens.

- **Auth:** Bearer, either mode (a Guardian's own extension polls for pages it blocked itself)
- **Rate limit:** 30 per 10 seconds per device. On 429, wait `Retry-After` and poll again; it does not
  mean "no verdict".
- **Query:** `domain`, the registrable domain. Case, surrounding spaces, a trailing dot and a leading
  `www.` are tolerated.

**Response 200**

```json
{ "verdict": { "value": "safe", "byDeviceId": "7d1f…", "byName": "Adhella", "decidedAt": "2026-10-21T04:07:12.000Z" } }
```

`verdict` is `null` when there is no decision for (this device, this domain). When a member
disconnects or is removed, the old Guardian's verdicts for that member are deleted.

## Blocklist

### `GET /blocklist?since=`

**For:** detection layer 1 in the extension. It downloads the global list of manually approved scam
domains and checks visits against it on the device, so the visited URL is never sent to the server.
Incremental refresh every hour, full refresh daily (`docs/design/blocklist.md`).

- **Auth:** Bearer, either mode
- **Cache:** `private, max-age=300`, so a change can reach a device up to 5 minutes late.
- **Query:** `since` (optional ISO time), the `nextSince` of the previous response.

**Response 200, full download (no `since`)**

```json
{ "domains": [ { "domain": "bca-verifikasi.site", "addedAt": "2026-10-21T05:00:00.123456Z" } ], "nextSince": "2026-10-21T05:00:00.123456Z" }
```

**Response 200, incremental (`since` sent)**

```json
{ "domains": [], "removed": [ { "domain": "old-scam.site", "removedAt": "2026-10-22T01:00:00.000000Z" } ], "nextSince": "2026-10-22T01:00:00.000000Z" }
```

**Paging**

- One response holds about 1000 entries (`domains` + `removed`). It may go slightly over so that
  entries with the same timestamp are never split across pages.
- Repeat with `since=nextSince` until a response has no `domains` and no `removed`.
- A full refresh is the first request without `since`, then the same loop; replace the stored list
  only after the last page.
- An empty response returns `nextSince` equal to the `since` you sent (caught up).
- `nextSince` is `null` only when the list is empty and no `since` was sent; keep no cursor then.
- Times have microseconds so the cursor is exact; store `nextSince` as the string you got.

| Error | When |
|---|---|
| `422 invalid_body` | `since` is not an ISO time |

## Web pages

These return HTML for people, not JSON for the app.

### `GET /j/{code}`

**For:** the `inviteUrl` a Guardian shares on WhatsApp / AirDrop (PR-03). With Shoo installed the link is
a Universal Link and this page never shows. Otherwise it shows the code, an "Open Shoo" button
(`shoo://join?code=482193`) and an "Install" link to `APP_STORE_URL`. Tapping "Install" first copies the
invite link to the clipboard, so the app can offer "Paste invite" on first launch.

- **Auth:** none. No database lookup: the page never says whether a code is valid. Anything other than
  6 digits shows "no valid code" and is never echoed.
- Language: Bahasa Indonesia when `Accept-Language` starts with `id`, else English.
- Strict CSP: the one inline script (copy, then go to the store) runs under a per-request `nonce`.
  No cookies, no analytics, nothing sent.
- Link preview: Open Graph tags (`og:title`, `og:description`, `og:image` = `INVITE_BASE_URL/og/invite.jpg`,
  `twitter:card`), so WhatsApp / Messages show the Shoo picture above the invite text. The same tags for
  every invite: no code, no name.
- The old `GET /join?code=` page and 4-digit codes are gone (`404`).

### `GET /og/invite.jpg`

**For:** link preview crawlers (WhatsApp, Messages, Telegram) reading `og:image` on `/j/{code}`.
1200×628 JPEG under 300 KB (WhatsApp skips larger images), bundled into the Worker (`src/assets/`).

- **Auth:** none. `Cache-Control: public, max-age=86400` (no user data).

### `GET /.well-known/apple-app-site-association`

**For:** iOS, to open `/j/*` links in the app (Universal Link, issue #129). Lists the app ids from
`APPLINKS_APP_IDS`; empty → `{ "applinks": { "details": [] } }` and the link stays a web page.

- **Auth:** none. JSON, no redirect, `Cache-Control: public, max-age=3600` (no user data).

### `GET /privacy?lang=en|id`

**For:** the privacy policy linked from the app and App Store Connect (SECURITY §3 P12): what is
stored, who can see it, the 14-day deletion, and how "Delete my data" works.

- **Auth:** none. No database.
- Language: `lang` first, then `Accept-Language`, else English.
- *PF-01 proposed:* also says which notification choices, quiet hours and time zone are stored.

### `GET /terms?lang=en|id`

**For:** *PF-01 proposed.* "Syarat & ketentuan" in "Tentang Shoo". Draft text for the team to review
before public release.

- **Auth:** none. No database. Language as for `/privacy`.

### `GET /get`

**For:** *PF-01 proposed.* The link "Bagikan Shoo" shares. `302` to `APP_STORE_URL` (the same store
link the invite page uses).

- **Auth:** none. No database, nothing logged about the visitor.

## Push notification

Not an endpoint: `POST /scans` from a Protected device sends its Guardian this APNs payload, straight
from the Worker over HTTP/2 (GD-06):

```json
{ "aps": { "alert": { "body": "Mom hit a blocked site · 92%" }, "sound": "default" }, "scanId": "6f1c2a4e-…" }
```

- The text is in the Guardian's `language` and never contains the URL:

  | Status | `en` | `id` |
  |---|---|---|
  | `blocked` | `Mom hit a blocked site · 92%` | `Mom membuka situs yang diblokir · 92%` |
  | `warning` | `Mom opened a suspicious site · 41%` | `Mom membuka situs mencurigakan · 41%` |

- No push for a Guardian's own scans, when the Guardian has no APNs token, or (*PF-01 proposed*) when
  the Guardian turned "Kabari saya" off for that member or `notifications.family` off.
- *PF-01 proposed:* the scanning device itself also gets a push for its own scan when its
  `notifications.blocked` / `notifications.warning` is on (default on). It carries the `scanId`;
  the body never names the site.

  | Status | `en` | `id` |
  |---|---|---|
  | `blocked` | `Shoo blocked a dangerous site · 92%` | `Shoo memblokir situs berbahaya · 92%` |
  | `warning` | `Shoo warned you about a risky site · 41%` | `Shoo memperingatkanmu soal situs berisiko · 41%` |

- *PF-01 proposed:* quiet hours of the receiving device hold `warning` pushes (they are not sent
  later); `blocked` pushes always go out.
- Tapping it opens Detail for `scanId`.
- *PF-01 proposed:* family pushes to a **Protected** device (reminder, disconnect, see
  [`POST /family/members/{deviceId}/remind`](#post-familymembersdeviceidremind) and
  [`DELETE /family/members/{deviceId}`](#delete-familymembersdeviceid)) carry no `scanId`. The
  Protected app now sends its APNs token too.
- At most 10 pushes per Guardian per 10 minutes. A `410 Unregistered`/`ExpiredToken` from Apple clears
  the Guardian's `apnsToken`.

## Scheduled pushes

*PF-01 proposed.* An hourly Cron (`5 * * * *`, next to the daily retention `0 19 * * *`) sends at most
40 pushes per run (Workers subrequest limit); the rest go out on the next run. Rows are claimed before
sending, so two runs never push twice.

- **Protection off** (`notifications.protectionOff`, Guardian): a member whose extension has not
  reported for 24 hours (the same rule as "Ekstensi mati" in `GET /family/members`). Once per off
  period: the mark clears when the member reports again. A member that never reported is not "off".
  During the Guardian's quiet hours it waits for a later run.
  - `en`: `Mom's protection is off: Shoo has not run in Safari for a day`
  - `id`: `Perlindungan Mom mati: Shoo tidak berjalan di Safari sejak sehari`
- **Weekly summary** (`notifications.weeklySummary`, off by default): Monday from 08:00 in the
  device's `timeZone`, outside quiet hours, once per local Monday. Counts of `blocked` and `warning`
  scans in the last 7 days, the Guardian's members included. Counts only, no sites.
  - `en`: `Your week for you and your family: 2 sites blocked, 1 warning.`
  - `id`: `Ringkasan minggu ini untuk kamu dan keluargamu: 2 situs diblokir, 1 peringatan.`

These pushes carry no `scanId`; tapping one opens the app.
