# Design: getting the blocklist onto the phone (layer 1)

Status: **accepted** (21 Oct 2026, #5 + contract #6) · Owner: Umar (lead) · Implemented: extension side (`lists.js`, `lists-client.js`) · Next: Imelda M5

## Problem
Layer 1 = "domain is on a scam list → score 100" (PRD §5). The lists live on servers, the check must run on the phone,
and the visited URL must never be sent to check it (`contracts/api.md`). Today's contract says the detector
downloads the list itself. That can't work:

| Constraint | Why it blocks "detector fetches its own list" |
|---|---|
| `detector.js` runs as a **content script** inside every web page | It restarts on every page load: no lasting memory, it would re-download per page |
| Content-script `fetch` runs under the **page's origin** | Cross-origin calls to our backend hit CORS (that's why all EX-02 network goes through `background.js`) |
| `GET /blocklist` needs the **device token** | Only `background.js` has the session (`getSession`); content scripts must never see the token |
| Lists can be large | Parsing tens of thousands of domains on every page breaks the < 50 ms budget |

## Proposal

```
                 ┌──────────────── background.js (lead) ────────────────┐
 Backend ───────►│ lists.js: download, keep in storage.local, refresh   │
 GET /blocklist  │   shoo   ← apiBaseURL/blocklist?since=  (hourly)     │
 AI service ────►│   public ← aiBaseURL/public-blocklist?since= (6 h)   │
                 │   full refresh once a day (handles removed[])        │
                 │ match(hostname) → { source, domain, addedAt } | null │
                 └───────────────────────▲──────────────────────────────┘
                                         │ message { type: "listMatch", hostname }
 content script ─────────────────────────┘
   ShooLists.match(hostname)  ← injected helper, same scope as detector.js
   detector.js (Imelda): if a match → db_match signal (weight 100, labels EN/ID)
```

1. **`background.js` owns download, storage and refresh** (lead). Lists are kept as sets of registrable
   domains in `browser.storage.local`, loaded into memory when the background wakes. Nothing leaves the
   phone except the list downloads themselves, which carry no browsing data.
2. **Public lists are aggregated server-side by Team AI** (`ai/`), not shipped inside the extension and not
   fetched from third parties by the phone. One endpoint, same shape as `GET /blocklist`:
   `GET {aiBaseURL}/public-blocklist?since=` → `{ domains: [{ domain, addedAt }], removed?: [...], nextSince }`.
   Imelda picks the feeds (license noted in `ai/README.md`), normalizes to registrable domains, drops
   allowlisted/official domains and compromised-but-legit hosts.
3. **The detector makes no network calls.** It gets one helper in its scope:
   `await globalThis.ShooLists.match(hostname)` → `{ source: "shoo" | "public", domain, addedAt } | null`.
   `analyzeLocal(snapshot)` keeps its signature; Imelda decides the labels/weight of `db_match` and puts
   the source in `evidence`.
4. **Matching:** the full hostname and every parent down to the registrable domain
   (`a.b.scam.site` → `a.b.scam.site`, `b.scam.site`, `scam.site`). Never above the registrable domain
   (no `vercel.app`, no `co.id`).
5. **Not set up / offline:** no token → no `shoo` list; the last stored copy is used as long as it's
   < 7 days old. Layer 2 always runs.

### Size & timing
| | Target |
|---|---|
| Entries | ≤ 200 000 domains total (≈ 4 MB in storage) |
| `match()` | One message round trip + `Set.has` × ≤ 5 → a few ms |
| Refresh | `shoo` hourly (incremental `since`), `public` every 6 h, both full once a day |
| First install | Lists download on first background wake after onboarding; until then layer 2 only |

## Alternatives considered
| Option | Why not |
|---|---|
| Detector fetches lists itself (current contract) | CORS, no token, per-page restart (see Problem) |
| Ship the public list **inside the extension** (M5 wording today) | Stale until the next app release; phishing domains live hours to days. Could be added later as an offline seed |
| Phone downloads public feeds directly (OpenPhish, PhishTank…) | Third parties see every Shoo user's IP; formats differ; some feeds need API keys that would ship in the app |
| Ask the server "is this domain bad?" per page | Sends browsing history to the server — forbidden by the contract |

## Who does what
| Who | Work | Where |
|---|---|---|
| Umar | `lists.js` in background (download, storage, refresh, `match`), `ShooLists` helper for content scripts, contract PR | `ios/ShooExtension/`, `contracts/` |
| Imelda | `GET /public-blocklist` in `ai/` (feeds, license, normalization, allowlist); detector uses `ShooLists.match` → `db_match` | `ai/`, `detector/` |
| Alief | `GET /blocklist` as in PR #4 (reviewed list + `removed[]`) | `backend/` |

## Contract changes (after agreement)
- `detector-interface.md`: detector makes **no** network calls; layer-1 data comes from `globalThis.ShooLists.match(hostname)`.
- `api.md` (AI): add `GET /public-blocklist?since=`, same shape as `GET /blocklist`, Bearer device token.
- `mandates/imelda.md` M5: "aggregate public lists server-side + use `ShooLists`" instead of "package into the extension".

## Decided defaults (lead, 21 Oct)
1. **Feeds:** Imelda's choice. Licence must allow use in an app, noted in `ai/README.md`. Target after filtering: ≤ 200 000 domains (the extension's cap).
2. **Refresh:** 6 h for public, fixed by the extension. Ask the lead if a feed really needs faster.
3. **Offline seed inside the extension:** not in MVP.
