# HTTP API

Two services:
| Service | Owner | Base URL key | Folder |
|---|---|---|---|
| Backend | Team App | `api.baseURL` | `backend/` |
| AI | Team AI | `ai.baseURL` | `ai/` |

Team App may pick the stack (Supabase recommended). If Supabase tables/RPCs are used instead of REST, keep the **same JSON shapes** and update this file via PR.

Auth: no login (PRD §10). `POST /devices` returns a token; every other call sends `Authorization: Bearer <token>`.
All bodies are JSON. Times are ISO 8601 UTC. Errors: `{ "error": { "code": string, "message": string } }`.

Common error codes: `invalid_body`, `bad_json`, `too_large`, `rate_limited`, `internal`. Endpoint-specific codes are listed per section.
`rate_limited` = HTTP 429 with a `Retry-After` header (seconds). Clients retry after it; it is **not** an empty answer (e.g. not `verdict: null`).

## Backend (Team App)

### Devices
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/devices` | `{ name, mode: "guardian"\|"protected", apnsToken? }` | `{ deviceId, token, avatarId }` | ON-02, ON-03 |
| GET | `/devices/me` | — | `{ deviceId, name, avatarId, mode, language, guardian: { deviceId, name, avatarId } \| null }` — Protected learns its guardian, or that it was disconnected | PR-04, PF-01, EX-06 |
| PATCH | `/devices/me` | `{ name?, apnsToken?, language?, extensionLastSeenAt? }` | `{ ok }` | ON-05, PF-01, GD-03 |

`extensionLastSeenAt` (ISO): sent by the **extension** at most once per hour with its heartbeat, and by the app when it comes to the foreground. The backend uses it for `extensionActive` in `GET /family/members` ("Not connected", GD-03). No data yet → `extensionActive: true` (never "Not connected" without evidence).

### Family (max 3 protected per guardian)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/family/code` | — (guardian) | `{ code: "4821", expiresAt, inviteUrl }` — 60 s validity | GD-04 |
| POST | `/family/join` | `{ code }` (protected) | `{ guardian: { deviceId, name, avatarId } }` | PR-01, PR-03 |
| GET | `/family/members` | — (guardian) | `{ members: [{ deviceId, name, avatarId, extensionActive, lastScan? }] }` | GD-03 |
| DELETE | `/family/members/{deviceId}` | — (guardian) | `{ ok }` | GD-04 |
| DELETE | `/family/guardian` | — (protected) | `{ ok }` | PF-01 |

Join errors: `code_invalid`, `code_expired`, `family_full`, `too_many_attempts` (rate-limit attempts, PRD §10), `already_connected`.

`inviteUrl` is an **https** link, e.g. `https://<api host>/join?code=4821`: a small page that opens `shoo://join?code=4821` (contracts/app-group-keys.md "Deep links"). WhatsApp doesn't make `shoo://` links tappable.

### Scans (Activity)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/scans` | ScanResult without `id`/`verdict`, + `screenshotBase64?` | `{ id }` — sends push to guardian if owner is protected. `ownerDeviceId`/`ownerName` come from the token; body values are ignored | EX-07, GD-06 |
| GET | `/scans?owner=me\|family\|{deviceId}&status=warning\|blocked&cursor=` | — | `{ items: ScanResult[], nextCursor }` newest first. `owner=family` = the guardian's own scans **plus** their protected members' (as in `fixtures/activity-family.json`). `screenshotUrl` is always `null` in lists | PR-05, GD-05 |
| GET | `/scans/{id}` | — | ScanResult, `screenshotUrl` = signed URL valid 1 h | DT-* |

Only score ≥ 30 is ever sent. Scans auto-delete after 14 days (PRD §10).

### Verdicts (per domain)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/verdicts` | `{ scanId, value: "safe"\|"not_safe" }` (guardian) | `{ verdict }` — applies to the scan's domain for that owner. Error `verdict_not_allowed`: not the owner's guardian, or the scan isn't `blocked` (`warning` scans keep `verdict: null` in MVP) | GD-07 |
| GET | `/verdicts?domain=` | — | `{ verdict: Verdict \| null }` | EX-06 auto-open |

Extension polls `GET /verdicts?domain=` every 5 s while a protected user's block screen is open (or Team App offers realtime — propose via PR).

### Blocklist (layer 1 database)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| GET | `/blocklist?since=` | — | `{ domains: [{ domain, addedAt }], removed?: [{ domain, removedAt }], nextSince }` — domains **approved** into the global list (see below) | §5 Layer 1 |

A `not_safe` verdict always applies at once **for that family** (`GET /verdicts`). It reaches the **global** list only after review, because anyone can register without login and could otherwise get a real bank's domain blocked for every user (blocklist poisoning):
1. Eligible: the verdict is on a scan owned by a **connected Protected** member, and the domain is not on the official/popular allowlist → it goes into a review queue.
2. Published: only after manual approval by Alief/Umar. `addedAt` = approval time; `nextSince` follows it.
3. Removed: optional `removed[]` lists domains taken off the list since `since`. Until clients handle it, do a full refresh (no `since`) once a day.

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

`/analyze` is **stateless**: it must not store the snapshot. Timeout on client: 8 s → treat as no signals.

> Decided with PM (2026-10-21): pages are **sent for analysis but not stored**. Only results with score ≥ 30 are stored (`POST /scans`).
