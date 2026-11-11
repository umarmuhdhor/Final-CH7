# HTTP API

Two services:
| Service | Owner | Base URL key | Folder |
|---|---|---|---|
| Backend | Team App | `api.baseURL` | `backend/` |
| AI | Team AI | `ai.baseURL` | `ai/` |

Team App may pick the stack (Supabase recommended). If Supabase tables/RPCs are used instead of REST, keep the **same JSON shapes** and update this file via PR.

Auth: no login (PRD §10). `POST /devices` returns a token; every other call sends `Authorization: Bearer <token>`.
All bodies are JSON. Times are ISO 8601 UTC. Errors: `{ "error": { "code": string, "message": string } }`.

Common error codes: `invalid_body`, `bad_json`, `too_large`, `rate_limited`, `internal`, `unauthorized` (401: token missing or unknown), `forbidden` (403: not allowed for this device or mode), `not_found` (404). Endpoint-specific codes are listed per section.
`rate_limited` = HTTP 429 with a `Retry-After` header (seconds). Clients retry after it; it is **not** an empty answer (e.g. not `verdict: null`).

## Backend (Team App)

### Devices
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/devices` | `{ name, mode: "guardian"\|"protected", avatarId?, apnsToken? }` | `{ deviceId, token, avatarId }` | ON-02, ON-03 |
| GET | `/devices/me` | — | `{ deviceId, name, avatarId, mode, language, guardian: { deviceId, name, avatarId } \| null }` — Protected learns its guardian, or that it was disconnected | PR-04, PF-01, EX-06 |
| PATCH | `/devices/me` | `{ name?, apnsToken?, language?, extensionLastSeenAt?, liveActivityStartToken?, liveActivityUpdateToken? }` | `{ ok }` | ON-05, PF-01, GD-03, EX-03 |
| DELETE | `/devices/me` | — | `{ ok }` — deletes the device and everything about it: family links (either side), codes, join attempts, scans + screenshots + page replicas, verdicts on its scans or made by it, push log. The token stops working. App Store Guideline 5.1.1(v) | PF-01 |

`avatarId` (ON-02, #120): optional, one of `avatar_01`…`avatar_12`. The 4 memoji in the ON-02 picker are `avatar_01`…`avatar_04`; `avatar_05`…`avatar_12` stay for the random pick. Missing or unknown → the server picks at random, as before. The response `avatarId` is the source of truth. Chosen once at registration: `PATCH /devices/me` does not change it (not in the MVP).

`extensionLastSeenAt` (ISO): sent by the **extension** at most once per hour with its heartbeat, and by the app when it comes to the foreground. The backend uses it for `extensionActive` in `GET /family/members` ("Not connected", GD-03). No data yet → `extensionActive: true` (never "Not connected" without evidence).

`liveActivityStartToken` / `liveActivityUpdateToken` (EX-03, #49): the two APNs tokens of the Dynamic Island. Sent by the **app** only. See "Live score (Dynamic Island)" below.
- `liveActivityStartToken`: hex string from `Activity<ScoreActivityAttributes>.pushToStartTokenUpdates`, or `null` to clear. The app sends it while it is on screen (onboarding and every launch), and again when it changes.
- `liveActivityUpdateToken`: `{ activityId, token }` from the running activity's `id` and `pushTokenUpdates`, or `null` when that activity ended. `activityId`: letters, digits and `-`, max 64. `token`: hex. The backend keeps only the latest one (a device has at most one island).

### Family (max 3 protected per guardian)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/family/code` | `{ refresh?: boolean }` (guardian; empty body allowed) | `{ code: "482193", expiresAt, inviteUrl }` — 6 digits, valid 30 min, multi-use until the family is full. Returns the guardian's active code while it has more than 5 min left, otherwise a new one. `refresh: true` always makes a new code and the old one stops working at once (`code_invalid`). `503 code_unavailable` when no free code is found: show "Try again" | GD-04, PR-03 |
| POST | `/family/join` | `{ code }` (protected, 6 digits) | `{ guardian: { deviceId, name, avatarId } }` | PR-01, PR-03 |
| GET | `/family/members` | — (guardian) | `{ members: [{ deviceId, name, avatarId, extensionActive, lastScan? }] }` | GD-03 |
| DELETE | `/family/members/{deviceId}` | — (guardian) | `{ ok }` | GD-04 |
| DELETE | `/family/guardian` | — (protected) | `{ ok }` | PF-01 |

Join errors: `code_invalid`, `code_expired`, `family_full`, `too_many_attempts` (rate-limit attempts, PRD §10; HTTP 429 with `Retry-After`, like `rate_limited`), `already_connected`.

`inviteUrl` is an **https** link, `https://<api host>/j/<code>` (e.g. `/j/482193`), and a Universal Link (`GET /.well-known/apple-app-site-association` lists `/j/*`): with Shoo installed it opens the app. Otherwise a small page with "Open Shoo" (`shoo://join?code=482193`, contracts/app-group-keys.md "Deep links") and "Install" (copies the invite, then goes to TestFlight / the App Store). WhatsApp doesn't make `shoo://` links tappable. The 4-digit code and `/join?code=` are removed with no transition (#128).

### Scans (Activity)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/scans` | ScanResult without `id`/`verdict`, + `pageReplicaBase64?` + `evidenceFragmentsBase64?` + `thresholdsVersion?` + `rdapRegisteredAt?` (`screenshotBase64?` deprecated). Body ≤ 1 MiB | `{ id }` — sends push to guardian if owner is protected. `ownerDeviceId`/`ownerName` come from the token; body values are ignored | EX-07, GD-06 |
| GET | `/scans?owner=me\|family\|{deviceId}&status=warning\|blocked&cursor=` | — | `{ items: ScanResult[], nextCursor }` newest first. `owner=family` = the guardian's own scans **plus** their protected members' (as in `fixtures/activity-family.json`). `screenshotUrl` and `pageReplicaUrl` are always `null` in lists | PR-05, GD-05 |
| GET | `/scans/{id}` | — | ScanResult, `pageReplicaUrl` (and `screenshotUrl` for older scans) = short-lived URL valid 1 h, re-checked on every request (404 once the scan is deleted or the family link is gone). Load it as-is, without `Authorization` | DT-* |

Only score ≥ 30 is ever sent. Scans auto-delete after 14 days (PRD §10).

The extension sends **one scan per page**: when the page is blocked, or when a warning page has finished all layers. The backend keeps one row per site (`backend/API.md`, #248), so one site (owner + domain) = one Activity item. The Guardian's push goes out on the first visit, and once more if that site goes from `warning` to `blocked`.

`faviconUrl`: in `POST /scans` it is the site's own icon URL (or `null`); the server downloads it once. In responses (lists and `GET /scans/{id}`) it is a 1-hour signed link to the server's stored copy (`GET /favicons/{scanId}`, see `backend/API.md`), or `null`; never the site's own URL, so the app never contacts the scam host (#166).

#### Page replica (evidence, EX-07)

The evidence is a **copy of the page's DOM**, not a screenshot (#176). A screenshot needs the page to still be painted on screen; a page blocked at ≥ 80 is gone (block screen) before a capture is reliable, and a scam site is often taken down within hours. The extension serializes the DOM the moment it reports, and the app rebuilds the page from it later.

`pageReplicaBase64` (optional, `null` = absent): one HTML document, UTF-8, **gzip-compressed, then base64** (no `data:` prefix). ≤ 400 KB as base64, ≤ 3 MB once decompressed (the backend drops a replica over either limit, or one that isn't valid gzip, and still stores the scan). Backend stores it and returns it as `pageReplicaUrl`.

What the extension guarantees in the document:
- **Static**: no `<script>`, `<noscript>`, `<iframe>`/`<frame>`/`<object>`/`<embed>` (a grey box of the same size instead), no `on*` attribute, no `javascript:` URL, no `<base>`, no `<meta http-equiv>` except the CSP below, no form `action`/`formaction`.
- **Nothing loads from the network**: every stylesheet is inlined as `<style>`, small images (≤ 40 KB each, ≤ 300 KB total) are inlined as `data:` URIs, every other resource URL is removed. Links keep their look but point to `#`; the original link is in `data-shoo-href` (evidence for the Guardian, never opened).
- **No typed input** (PRD §10): no `value` attribute on `<input>`, empty `<textarea>`, form fields keep only the attributes that shape their look (`type`, `name`, `id`, `class`, `style`, `placeholder`, size and state attributes; never `data-*`, `aria-*` or `title`), editable areas (`[contenteditable]`, `[role=textbox|searchbox|combobox]`) emptied, and an empty `<body>` when the page is in `designMode`. Open shadow roots become declarative shadow DOM (`<template shadowrootmode="open">`).
- `<head>` starts with:
  - `<meta charset="utf-8">`
  - `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'">`
  - `<meta name="viewport" content="width=<page viewport width>">`
  - `<meta name="shoo-replica" content="<JSON>">`: `{ "v": 1, "url", "capturedAt", "viewport": { "width", "height" }, "focusY", "truncated", "marks"? }`. `url` is the shareable URL (origin + path). `focusY` = document y (CSS px) of the sensitive form, else of what was on screen: scroll there first. `truncated: true` = the page was too big and the end was cut. `viewport.width` is the page's CSS width, the same value as the viewport meta above, so the copy lays out at that width.
  - `marks` (optional, #176; absent when no signal has an element on the page): `[{ "signalId", "x", "y", "w", "h" }]`, where each signal sits on the page, heaviest signal first, for the spotlight on Detail. `signalId` = a signal id (detector-interface.md, `[a-z_]`, 1–40 chars). `x`, `y`, `w`, `h` = whole CSS px in **document** coordinates (same space as `focusY`), `x`, `y` ≥ 0, `w`, `h` ≥ 1, all < 100000. Max 24 entries, max 3 per signal; the same `signalId` more than once = several places (numbered variant). Text signals (`urgent_language`, `brand_logo_offsite`, `unreasonable_request`, `hoax_claim`) → where their `evidence` text is (`brand_logo_offsite`: an image whose `alt` holds it first); `asks_*` → the field whose `name`/`id` is the `evidence`, else the field of that kind. Other signals (`new_domain`, `db_match`, layer 2) get none. Measured on the live page: images that weren't inlined and web fonts change the copy's layout a little, so treat a mark as approximate.

What the **app must do anyway** (a replica comes from a device, so the backend can't vouch for it): render with JavaScript off (`WKWebpagePreferences.allowsContentJavaScript = false`), cancel every navigation after the first load (`decidePolicyFor` → `.cancel`), no network (load with `loadHTMLString(_, baseURL: nil)`, non-persistent `WKWebsiteDataStore`), and label it "Copy of the page, <time>". Show a placeholder when `pageReplicaUrl` is `null`.

`screenshotBase64` / `screenshotUrl` are **deprecated**: the extension no longer sends a screenshot. Backend keeps accepting it and the app keeps showing `screenshotUrl` until the last old scan is deleted (14 days), then both are removed in a follow-up PR.

`GET <pageReplicaUrl>` answers the HTML with `Content-Type: text/html; charset=utf-8` (it may send `Content-Encoding: gzip`; URLSession decompresses it), `Content-Security-Policy: sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:`, `X-Content-Type-Options: nosniff` and `Cache-Control: private, no-store`, so the link stays inert even if it is opened in a browser.

#### Evidence fragments (ADM-07, admin scan archive)

`evidenceFragmentsBase64` (optional, `null` = absent): only the **parts of the page that made Shoo flag it**, kept by the admin dashboard to improve detection (dashboard decision D-dash-17). Sent with every report (warning or blocked), **with or without a family**. One HTML document, UTF-8, gzip + base64, same limits as the replica (≤ 400 KB base64, ≤ 3 MB decompressed); the backend drops it over either limit, or when it isn't gzip, and still stores the scan. Never returned to devices.

- Same static guarantees as the page replica above (no script, no handler, no typed value, nothing loads; same CSP first in `<head>`), made by the same serializer.
- `<head>`: charset, CSP, viewport, `<meta name="shoo-fragments" content="<JSON>">` (`{ "v": 1, "url", "capturedAt", "truncated" }`, `url` = origin + path), then the page's stylesheets once, so the parts look as they did on the page.
- `<body>`: one `<section data-shoo-fragment data-shoo-signals="<ids>">` per part, heaviest signal first; `<ids>` = space-separated signal ids. `asks_*` → the field's `<form>` (no form: the field's container up to 3 levels up); text signals → the block element around the `evidence` text (`brand_logo_offsite`: around the logo image too). A part inside another part is written once, inside the outer one, with both ids. Never `<html>`, `<head>` or `<body>` as a part. Signals with nothing on the page (`db_match`, `new_domain`, layer 2) add no part.
- No cap on the number of parts. Too big → again without images, then fewer parts (lightest first), then without stylesheets, then none.
- An extension that doesn't send it is still valid (no parts for that scan). Older backends ignore the field; a `413` makes the extension send again without it.

#### Score thresholds (X1, admin dashboard phase 05)

`GET /config/public` (Bearer, either mode, `Cache-Control: private, max-age=3600`) → `{ warnAt, blockAt, version, updatedAt }`. `warnAt` 30–60, `blockAt` 50–95, `blockAt` at least 15 above `warnAt`. `version` 0 = the built-in 30/80 (admins have not switched their thresholds live). No user data; a missing or invalid answer keeps the last good value, or 30/80.

- The Safari extension reads it hourly (last good value kept up to 7 days) and decides `warning` / `blocked` with it. Popup tier 2 starts at 50, or in the middle of the warning band when `warnAt` ≥ 50. Chrome keeps the built-in values.
- `thresholdsVersion` (optional integer ≥ 0) on `POST /scans` = the `version` the status was decided with. Equal to the current version: the status must match those thresholds exactly, else `422`. Another version or absent: only the fence (`warning` ≥ 30, `blocked` ≥ 50). On a `422` the extension sends the scan again without it.
- The app shows the `status` the extension sent and does not recompute it from the score.

### Verdicts (per link)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/verdicts` | `{ scanId, value: "safe"\|"not_safe", notes? }` (guardian) | `{ verdict }` — applies to the scan's link for that owner. Error `verdict_not_allowed`: not the owner's guardian. `warning` and `blocked` scans can both get a verdict (#190) | GD-07 |
| GET | `/verdicts?url=&domain=` | — | `{ verdict: Verdict \| null }` | EX-06 auto-open |
| GET | `/verdicts?domain=` | — | `{ verdict: Verdict \| null }` — **deprecated**, for builds from before #241 | EX-06 auto-open |

A **link** is origin + path, with no query or fragment (`shareableUrl` in the extension). `domain` is the registrable domain, as on a scan: the backend can't derive it from the link.

Lookup (#241), first match wins:
1. A verdict on exactly this link, `safe` or `not_safe`.
2. A `not_safe` by this owner on another link of the same domain, unless the domain is a shared host (`ai/data/shared-hosts.json`): one page there says nothing about the others.
3. Otherwise `null`. A `safe` never reaches past its own link.

A scan's `verdict` in Activity follows the same rule. `?domain=` alone answers with any `not_safe` on that domain, else the newest `safe`. It goes once the last older build is gone.

`notes` (optional, at most 280 characters): why the Guardian decided. The app requires it on `not_safe`; the backend accepts a verdict without it, because older builds don't send it. It is never returned in a `Verdict`. It is cleared after 14 days and the decision stays, otherwise the link would be blocked again on day 15.

Extension polls `GET /verdicts?url=&domain=` while the block screen is open (#350): every 2 s for the first 2 minutes, every 5 s up to 10 minutes, then every 15 s (a `429` waits out `Retry-After`), for **both modes**: Protected waits for the guardian, Guardian reopens the page after marking it safe for themselves (PRD §5 Validasi). Also polls once when the user comes back from the app. Realtime instead of polling: propose via PR.

The extension only asks for a verdict once a page reaches score 30 — the point where the page would be sent with `POST /scans` anyway. Low-score browsing never reaches the backend.

### Blocklist (layer 1 database)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| GET | `/blocklist?since=` | — | `{ domains: [{ domain, addedAt }], removed?: [{ domain, removedAt }], nextSince }` — domains **approved** into the global list (see below) | §5 Layer 1 |

A `not_safe` verdict always applies at once **for that family** (`GET /verdicts`). It reaches the **global** list only after review, because anyone can register without login and could otherwise get a real bank's domain blocked for every user (blocklist poisoning):
1. Eligible: the verdict is on a scan owned by a **connected Protected** member, and the domain is not on the official/popular allowlist → it goes into a review queue.
2. Published: only after manual approval by Alief/Umar. `addedAt` = approval time; `nextSince` follows it.
3. Removed: optional `removed[]` lists domains taken off the list since `since`. Until clients handle it, do a full refresh (no `since`) once a day.

**Paging and `nextSince`:**
- One response holds at most about 1000 entries (`domains` + `removed` together). It may go slightly over so that entries sharing one timestamp are never split across pages.
- Client: repeat with `since=nextSince` until a response has no `domains` and no `removed`. A full refresh is the first request without `since`, then the same loop; replace the stored list only after the last page.
- An empty response returns `nextSince` = the `since` it was given (caught up).
- `nextSince` is `null` only when the list is empty and no `since` was sent. Keep no cursor; the next request is a full refresh.
- A `since` that is not a valid ISO 8601 timestamp (or is out of range) → HTTP 422 `invalid_body`, the same code as a bad body. The client only ever sends back a `nextSince` it was given, so this only happens on a client bug.

The extension's `background.js` downloads this list and refreshes it (incremental `since` hourly, full daily); the visited URL is never sent to check one domain. Design: `docs/design/blocklist.md`.

### Live score (Dynamic Island, EX-03, #49)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/live` | `{ domain, score, status: "normal"\|"warning"\|"blocked", analyzing: boolean, open: boolean }` | `202 { ok }` | EX-03 |

The running score of the page on screen in Safari, forwarded to this device's Dynamic Island by Live Activity push. It works with Shoo closed, once the app has sent `liveActivityStartToken`.

- **Who sends it:** the **extension** (`background.js`), and only when the online check is on (`getSession` has `aiBaseURL`, same rule as `/analyze`). Online check off → no call, the in-page pill only.
- **`domain`:** registrable domain only, never a URL. Same rule as `/scans`. `score`: integer 0–100. Extra keys or a bad value → `422 invalid_body`, like every other bad body.
- **`open: false`:** no page of Safari is on screen any more (tab hidden, Safari left, page closed), so the island ends. The other fields are still sent (last values).
- **When:**
  - a page comes on screen;
  - its `status` or `analyzing` changes → right away;
  - a score-only change → coalesced, at most 1 call per second;
  - `open: false` → after 1.5 s without another page coming on screen, so a tab switch doesn't end and restart the island.
- **Privacy (#49 decision 3): forward, never store.** `domain` and `score` go into the APNs payload only. No table row, no `push_log` row, and log lines carry the event kind and result only.
- **Rate limit:** 10 calls per 10 s per device → `429 rate_limited`. `open: false` is never limited.

**Backend → APNs.** Header `apns-push-type: liveactivity`, topic `<bundle id>.push-type.liveactivity`.
| Case | Token | `event` | Priority | `apns-expiration` |
|---|---|---|---|---|
| No update token stored | start token | `start` | 10 | +60 s |
| Update token stored, `open: true` | update token | `update` | 10 if `analyzing` or `status` ≠ `normal`, else 5 | +60 s |
| Update token stored, `open: false` | update token | `end` | 10 | +1 h |

While a `start` waits for the app's update token, there is no second `start` for 30 s, so islands don't stack. APNs `410` clears the token it was sent to.

```json
{ "aps": {
    "timestamp": 1731200000,
    "event": "start",
    "content-state": { "domain": "hadiah-gratis.xyz", "score": 60, "isAnalyzing": false, "isBlocked": false },
    "attributes-type": "ScoreActivityAttributes",
    "attributes": {},
    "stale-date": 1731200600
} }
```
- `content-state` = `ScoreActivityAttributes.ContentState` in `ios/ShooShared/`. Keys are fixed: renaming one breaks decoding on the phone. `isBlocked` = `status == "blocked"`.
- `attributes` (start only) = `ScoreActivityAttributes`: empty. The island follows the page, so the domain lives in `content-state`.
- `update` has `timestamp`, `event`, `content-state`, `stale-date` (+10 min). `end` has `timestamp`, `event`, `content-state` and `dismissal-date` (= `timestamp`, gone at once).

**App side.** When `Activity<ScoreActivityAttributes>.activityUpdates` delivers a new activity (also in the background after a `start` push), the app ends every other `ScoreActivityAttributes` activity with `.immediate`, then sends the new update token. When an activity ends, it sends `liveActivityUpdateToken: null`.

### Push payloads (APNs)
```json
{ "aps": { "alert": { "body": "Mom hit a blocked site · 92%" } }, "scanId": "…" }
{ "aps": { "alert": { "body": "Mom opened a suspicious site · 41%" } }, "scanId": "…" }
```
Text is localized to the **guardian's** language (`PATCH /devices/me {language}`). The backend may add `aps.sound: "default"`.
Tap → open Detail for `scanId` (GD-06).

## AI (Team AI)
| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/analyze` | `{ snapshot: PageSnapshot, localSignals: Signal[] }` | `{ signals: Signal[], rdapRegisteredAt?: string \| null }` — layer 3–4 only |
| POST | `/review` | `{ domains: ReviewInput[] }` | `{ model, prompt, results: ReviewResult[] }` — layer 5, server to server |
| GET | `/public-blocklist?since=` | — | `{ domains: [{ domain, addedAt }], removed?: [{ domain, removedAt }], nextSince }` — public phishing feeds aggregated server-side, registrable domains, allowlist applied. Same shape, `nextSince` rules and bad-`since` error (422 `invalid_body`) as `GET /blocklist`; paging is optional here (one response with every entry is fine). Downloaded by the extension every 6 h (full daily) |

**Auth on the AI service:** the extension sends `Authorization: Bearer <device token>` on both calls, but the AI service has no access to the backend's device table, so in MVP it does **not** verify the token. Protect it with a per-IP rate limit and a body-size limit instead (M7). Never log the token. `POST /review` is the exception: see below.

`/analyze` is **stateless**: it must not store the snapshot. Timeout on client: 8 s → treat as no signals.

`rdapRegisteredAt` (#270) = the domain's RDAP registration date, `YYYY-MM-DD`, returned whether or not `new_domain` fires. `null` when RDAP failed or timed out; may be absent (older AI service). The extension copies it into `POST /scans` when it has one. A page blocked before `/analyze` answers is reported without it. Public RDAP data, not personal data.

**`POST /review`** (layer 5, #241): the `shoo-admin` weekly job asks for a suggestion on domains in the review queue. No device calls it. Auth: `Authorization: Bearer <AI_REVIEW_SECRET>`, a Wrangler secret on `shoo-ai` and `shoo-admin`.
- `ReviewInput`, 1–25 per request: `{ domain, signal_counts, avg_score, max_score, families_safe, families_not_safe }`. `signal_counts` = `{ [signalId]: count }`. `avg_score` and `max_score` = 0–100 or `null`. No notes and no page text until the LLM provider has written zero data retention.
- `ReviewResult`: `{ index, result: "scam"|"legit"|"unsure"|null, confidence: 0–1|null, reason: string|null, suggestion: "approve"|"reject"|"none" }`. `index` = position in `domains`. `suggestion` is computed from `result` + `confidence`, never copied from the model.
- `result: null` = no usable answer for that domain. A shared host gets `result: "unsure"`, `reason: "shared_host"`, `suggestion: "none"`, with no LLM call.
- Errors: 404 while `AI_REVIEW_SECRET` is unset, 401 wrong Bearer, 422 bad body, 429 daily cap, 503 LLM not configured.
- The answer is only stored. It changes no block: the global list still needs manual approval. Stateless, and nothing from the request or the answer is logged.

> Decided with PM (2026-10-21): pages are **sent for analysis but not stored**. Only results with score ≥ 30 are stored (`POST /scans`).
