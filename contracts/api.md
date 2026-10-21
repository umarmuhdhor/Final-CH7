# HTTP API

Two services:
| Service | Owner | Base URL key | Folder |
|---|---|---|---|
| Backend | Team App | `api.baseURL` | `backend/` |
| AI | Team AI | `ai.baseURL` | `ai/` |

Team App may pick the stack (Supabase recommended). If Supabase tables/RPCs are used instead of REST, keep the **same JSON shapes** and update this file via PR.

Auth: no login (PRD §10). `POST /devices` returns a token; every other call sends `Authorization: Bearer <token>`.
All bodies are JSON. Times are ISO 8601 UTC. Errors: `{ "error": { "code": string, "message": string } }`.

## Backend (Team App)

### Devices
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/devices` | `{ name, mode: "guardian"\|"protected", apnsToken? }` | `{ deviceId, token, avatarId }` | ON-02, ON-03 |
| PATCH | `/devices/me` | `{ name?, apnsToken?, language? }` | `{ ok }` | ON-05, PF-01 |

### Family (max 3 protected per guardian)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/family/code` | — (guardian) | `{ code: "4821", expiresAt, inviteUrl }` — 60 s validity | GD-04 |
| POST | `/family/join` | `{ code }` (protected) | `{ guardian: { deviceId, name, avatarId } }` | PR-01, PR-03 |
| GET | `/family/members` | — (guardian) | `{ members: [{ deviceId, name, avatarId, extensionActive, lastScan? }] }` | GD-03 |
| DELETE | `/family/members/{deviceId}` | — (guardian) | `{ ok }` | GD-04 |
| DELETE | `/family/guardian` | — (protected) | `{ ok }` | PF-01 |

Join errors: `code_invalid`, `code_expired`, `family_full`, `too_many_attempts` (rate-limit attempts, PRD §10).

### Scans (Activity)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/scans` | ScanResult without `id`/`verdict`, + `screenshotBase64?` | `{ id }` — sends push to guardian if owner is protected | EX-07, GD-06 |
| GET | `/scans?owner=me\|family\|{deviceId}&status=warning\|blocked&cursor=` | — | `{ items: ScanResult[], nextCursor }` newest first | PR-05, GD-05 |
| GET | `/scans/{id}` | — | ScanResult | DT-* |

Only score ≥ 30 is ever sent. Scans auto-delete after 14 days (PRD §10).

### Verdicts (per domain)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/verdicts` | `{ scanId, value: "safe"\|"not_safe" }` (guardian) | `{ verdict }` — applies to the scan's domain for that owner | GD-07 |
| GET | `/verdicts?domain=` | — | `{ verdict: Verdict \| null }` | EX-06 auto-open |

Extension polls `GET /verdicts?domain=` every 5 s while a protected user's block screen is open (or Team App offers realtime — propose via PR).

### Push payloads (APNs)
```json
{ "aps": { "alert": { "body": "Mom hit a blocked site · 92%" } }, "scanId": "…" }
{ "aps": { "alert": { "body": "Mom opened a suspicious site · 41%" } }, "scanId": "…" }
```
Tap → open Detail for `scanId` (GD-06).

## AI (Team AI)
| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/analyze` | `{ snapshot: PageSnapshot, localSignals: Signal[] }` | `{ signals: Signal[] }` — layer 3–4 only |

`/analyze` is **stateless**: it must not store the snapshot. Timeout on client: 8 s → treat as no signals.

> Decided with PM (2026-10-21): pages are **sent for analysis but not stored**. Only results with score ≥ 30 are stored (`POST /scans`).
