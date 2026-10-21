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
| POST | `/devices` | `{ name, mode: "guardian"\|"protected", apnsToken? }` | `{ deviceId, token, avatarId }` | ON-02, ON-03 |
| GET | `/devices/me` | — | `{ deviceId, name, avatarId, mode, language, guardian: { deviceId, name, avatarId } \| null }` — Protected learns its guardian, or that it was disconnected | PR-04, PF-01, EX-06 |
| PATCH | `/devices/me` | `{ name?, apnsToken?, language?, extensionLastSeenAt? }` | `{ ok }` | ON-05, PF-01, GD-03 |
| DELETE | `/devices/me` | — | `{ ok }` — deletes the device and everything about it: family links (either side), codes, join attempts, scans + screenshots, verdicts on its scans or made by it, push log. The token stops working. App Store Guideline 5.1.1(v) | PF-01 |

`extensionLastSeenAt` (ISO): sent by the **extension** at most once per hour with its heartbeat, and by the app when it comes to the foreground. The backend uses it for `extensionActive` in `GET /family/members` ("Not connected", GD-03). No data yet → `extensionActive: true` (never "Not connected" without evidence).

### Family (max 3 protected per guardian)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/family/code` | — (guardian) | `{ code: "4821", expiresAt, inviteUrl }` — 60 s validity, replaces the guardian's previous code. `503 code_unavailable` when no free code is found: show "Try again" | GD-04 |
| POST | `/family/join` | `{ code }` (protected) | `{ guardian: { deviceId, name, avatarId } }` | PR-01, PR-03 |
| GET | `/family/members` | — (guardian) | `{ members: [{ deviceId, name, avatarId, extensionActive, lastScan? }] }` | GD-03 |
| DELETE | `/family/members/{deviceId}` | — (guardian) | `{ ok }` | GD-04 |
| DELETE | `/family/guardian` | — (protected) | `{ ok }` | PF-01 |

Join errors: `code_invalid`, `code_expired`, `family_full`, `too_many_attempts` (rate-limit attempts, PRD §10; HTTP 429 with `Retry-After`, like `rate_limited`), `already_connected`.

`inviteUrl` is an **https** link, e.g. `https://<api host>/join?code=4821`: a small page that opens `shoo://join?code=4821` (contracts/app-group-keys.md "Deep links"). WhatsApp doesn't make `shoo://` links tappable.

### Scans (Activity)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/scans` | ScanResult without `id`/`verdict`, + `screenshotBase64?` | `{ id }` — sends push to guardian if owner is protected. `ownerDeviceId`/`ownerName` come from the token; body values are ignored | EX-07, GD-06 |
| GET | `/scans?owner=me\|family\|{deviceId}&status=warning\|blocked&cursor=` | — | `{ items: ScanResult[], nextCursor }` newest first. `owner=family` = the guardian's own scans **plus** their protected members' (as in `fixtures/activity-family.json`). `screenshotUrl` is always `null` in lists | PR-05, GD-05 |
| GET | `/scans/{id}` | — | ScanResult, `screenshotUrl` = signed URL valid 1 h | DT-* |

Only score ≥ 30 is ever sent. Scans auto-delete after 14 days (PRD §10).

The extension sends **one scan per page**: when the page is blocked, or when a warning page has finished all layers. So one page = one Activity item = one push.

`screenshotBase64` (optional — some Safari builds can't capture): JPEG, base64, **no `data:` prefix**, longest side ≤ 1280 px, ≤ 150 KB (the backend drops larger screenshots and still stores the scan). Evidence area only (the sensitive form, else the visible screen), every text field blurred before capture (PRD §10). Backend stores it and returns it as `screenshotUrl`.

### Verdicts (per domain)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/verdicts` | `{ scanId, value: "safe"\|"not_safe" }` (guardian) | `{ verdict }` — applies to the scan's domain for that owner. Error `verdict_not_allowed`: not the owner's guardian, or the scan isn't `blocked` (`warning` scans keep `verdict: null` in MVP) | GD-07 |
| GET | `/verdicts?domain=` | — | `{ verdict: Verdict \| null }` | EX-06 auto-open |

Extension polls `GET /verdicts?domain=` every 5 s while the block screen is open, for **both modes**: Protected waits for the guardian, Guardian reopens the page after marking it safe for themselves (PRD §5 Validasi). Also polls once when the user comes back from the app. Realtime instead of polling: propose via PR.

The extension only asks for a verdict once a page reaches score 30 — the point where the domain would be sent with `POST /scans` anyway. Low-score browsing never reaches the backend.

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

The extension's `background.js` downloads this list and refreshes it (incremental `since` hourly, full daily); the visited URL is never sent to check one domain. Design: `docs/design/blocklist.md`.

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
| POST | `/analyze` | `{ snapshot: PageSnapshot, localSignals: Signal[] }` | `{ signals: Signal[] }` — layer 3–4 only |
| GET | `/public-blocklist?since=` | — | `{ domains: [{ domain, addedAt }], removed?: [{ domain, removedAt }], nextSince }` — public phishing feeds aggregated server-side, registrable domains, allowlist applied. Same shape and `nextSince` rules as `GET /blocklist`; paging is optional here (one response with every entry is fine). Downloaded by the extension every 6 h (full daily) |

**Auth on the AI service:** the extension sends `Authorization: Bearer <device token>` on both calls, but the AI service has no access to the backend's device table, so in MVP it does **not** verify the token. Protect it with a per-IP rate limit and a body-size limit instead (M7). Never log the token.

`/analyze` is **stateless**: it must not store the snapshot. Timeout on client: 8 s → treat as no signals.

> Decided with PM (2026-10-21): pages are **sent for analysis but not stored**. Only results with score ≥ 30 are stored (`POST /scans`).
