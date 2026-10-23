# ai — layer 3 & 4 (server)

Stateless service behind the Safari extension. Stack: Cloudflare Worker + [Hono](https://hono.dev), plain JavaScript (ESM + JSDoc), no build step (decision D-imelda-01).

Today it does layer 3 for **form fields**, **page text** (`urgent_language`, `brand_logo_offsite`) and **domain age** (`new_domain`, RDAP). `GET /public-blocklist` (M5 server) works but has **no real feed yet** (source not approved, see below). The LLM reality check (M4) is built and tested against a fake provider only; it stays off until a model and key are configured.

## Run it locally

```bash
cd ai
npm install            # one dependency: hono
npm run dev            # http://127.0.0.1:8787  (PORT=... to change)
npm test               # node --test, calls app.request(), no server needed
```

Score the eval set through the running service (from the repo root):

```bash
node ai/eval/run.mjs --analyze-url http://localhost:8787
```

`npm run dev` does not call RDAP (so eval runs never send a scam domain to a registry). To try `new_domain` by hand: `SHOO_RDAP=1 npm run dev`, and only with neutral public domains such as `example.com`.

The dev server is plain HTTP with no rate limit. Deploying the Worker (wrangler config, per-IP rate limit, secrets) is M7.

## Endpoint

`POST /analyze` exactly as in `contracts/api.md`: `{ snapshot, localSignals }` in, `{ signals }` out (layer 3 only).

| Case | Answer |
|---|---|
| Valid | `200 { "signals": [...] }`, strongest signal first, `Cache-Control: no-store` |
| Not JSON | `400 bad_json` |
| Wrong shape, no `snapshot.url`, URL not http(s) | `422 invalid_body` |
| Body over 200 KB | `413 too_large`, decided from `Content-Length` or while streaming, before parsing |
| Other method on `/analyze` | `405 method_not_allowed` with `Allow: POST` |
| Other path | `404 not_found` |
| Anything unexpected | `500 internal`, fixed message |

Errors are `{ "error": { "code", "message" } }`. `method_not_allowed` is not in the common list of `contracts/api.md`; see D-imelda-09.

`Authorization` is accepted and ignored (the AI service cannot verify device tokens). It is never read, so it can't be logged.

Caps applied before any rule runs (`src/limits.js`): `text` 20,000 chars, 20 forms, 60 fields per form, 300 fields in total, 120 chars per field string, 50 `imageAlts`. Anything past a cap is ignored, so a sensitive field past the cap gives no signal.

## Form signals (layer 3)

Pure keyword rules over each field's `name`, `id`, `label`, `placeholder` and `autocomplete`, in Indonesian and English. Words are matched whole (`pin` does not fire in `shipping` or `pinjaman`); camelCase, `_`, `-` and digits split words. No model, no network.

| id | Weight | Fires on |
|---|---|---|
| `asks_pin` | 35 | pin, passcode, kode sandi, kode akses |
| `asks_otp` | 30 | otp, kode verifikasi, verification code, one-time (`one-time-code`) |
| `asks_password` | 15 | `type=password` on a non-official site |
| `asks_card` | 30 | nomor kartu, card number, kartu kredit/debit (`cc-number`) |
| `asks_cvv` | 30 | cvv, cvc, kode keamanan, security code (`cc-csc`) |
| `asks_ktp` | 30 | ktp, nik, nomor induk, national id |
| `asks_selfie_ktp` | 35 | selfie + KTP in one field, or a selfie field next to a KTP field in the same form |

Weights are the starting proposal in `plan/imelda/ref/R1`; they are tuned in phase 07.

- One field gives at most one signal (most specific wins: selfie+KTP, KTP, CVV, card, OTP, PIN, password). One signal per id per request; `evidence` is the first matching field's `name`, else `id`. Never a typed value.
- Hosts under an official domain of `detector/data/brands.json` (and their subdomains) give **no** signal.
- Fields of type `hidden`, `submit`, `button`, `reset`, `image`, `checkbox` and `radio` are ignored.

## Content signals (layer 3)

Fixed phrase lists matched with plain string search (no regular expressions, no model). Text is folded first (NFKC, invisible characters dropped, Cyrillic look-alikes mapped, lowercase, spaces collapsed) and matched as whole words; a match never spans a line break. `evidence` is cut from the **original** page text through an offset map, so it is always an exact substring (the extension highlights it at score 30+).

| id | Weight | Fires on |
|---|---|---|
| `urgent_language` | 15 | an account threat or countdown in `text` or `title`: "diblokir dalam 24 jam", "akun Anda akan ditutup", "klaim sekarang", "terakhir hari ini", "your account will be suspended"... Shop wording ("dalam 24 jam", "within 24 hours", "act now") counts only with a threat word within 80 characters |
| `brand_logo_offsite` | 25 | a brand of `detector/data/brands.json` in an `imageAlts` entry that also says logo/ikon/icon, or in a `title` that also says login/verifikasi/akun..., on a host that is not that official domain (user-content hosts such as `sites.google.com` are not exempt) |

- One signal per id per request. `urgent_language` evidence is the earliest matching phrase (text first, then title); its label quotes OUR phrase, never page text.
- `brand_logo_offsite` ignores common words (`dana`, `mandiri`, `meta`, `apple`) in titles, and ignores alts that name 3+ different brands (a payment-method strip).
- Known false positives to measure in phase 04/07: "Diskon terakhir hari ini" in a shop; a shop that shows one bank logo.

## Domain age: `new_domain` (layer 3, RDAP)

Done on the server so a phone never tells a third party where its user browses. Starts first and runs while the rules run; the rules never wait for it longer than the deadline.

- Only the **registrable domain** (`login.bca-aman.co.id` -> `bca-aman.co.id`) leaves the server, as `GET <rdap server>domain/<domain>`. No URL, path, query, text or title. IPs, `localhost`, `.local`, `.internal`, malformed names and anything over 253 characters are never looked up.
- The RDAP server comes from the IANA bootstrap file (`https://data.iana.org/rdap/dns.json`), not from the page. A bootstrap server must be plain public `https` on port 443, no credentials, no IP. Redirects are not followed.
- One 1.5 s deadline for bootstrap + lookup (D-imelda-08). Any failure (network, status, shape, timeout, too big) gives no signal and a normal 200.
- Official domains are not looked up.
- Weight by age: under 7 days 30, 7-30 days 20, 31-90 days 10, older none. Label "Domain age N days" / "Umur domain N hari"; `evidence` is N as a string.
- Cache (`src/rdap/cache.js`): domain -> registration date only, in memory per Worker isolate, 24 h for a success, 10 min for a failure, at most 1000 entries (oldest dropped). A Cloudflare KV adapter (`createKvCache`) is written and tested but **not enabled**: it needs a KV namespace and wrangler (M7).
- `createApp()` without `fetch` has `new_domain` off; `src/index.js` passes the real `fetch`. Tests pass a mock.

## Privacy

Nothing from a request is stored or logged (the only cache is RDAP domain -> registration date): no `console.*` in `src/`, and a test spies on console and stdout/stderr across success and every error path. Responses are `no-store`.

## Layout

```
src/index.js          Worker entry (default export = Hono app)
src/app.js            routes, error mapping
src/http.js           error format, size-capped body reader
src/validate.js       request check + snapshot sanitising
src/limits.js         all caps
src/analyze.js        runs layer 3 (rules + RDAP in parallel)
src/layer3/           text.js (word splitting) match.js (phrase search, exact evidence) forms.js content.js (rules) signals.js (weights + wording) official.js
src/rdap/             domain.js (registrable domain, validation) rdap.js (IANA bootstrap + lookup) cache.js
src/dev-server.mjs    local HTTP wrapper, development only
test/                 node --test files
eval/                 labelled pages + scorer (M2)
```

`.env.example` lists variable names only. Real values go in `.env` / `.dev.vars`, both gitignored.

## Public blocklist: `GET /public-blocklist?since=` (layer 1, server side)

Serves the list the extension downloads every 6 h (`docs/design/blocklist.md`). Shape exactly as in `contracts/api.md`: `{ domains: [{ domain, addedAt }], removed?: [{ domain, removedAt }], nextSince }`.

| Case | Answer |
|---|---|
| No `since` | Full list (newest 200,000 at most), no `removed`, `nextSince` = newest timestamp, or `null` when the list is empty |
| `since=<ISO 8601>` | Only entries with `addedAt > since`, plus `removed` since then. Caught up: empty `domains`, `nextSince` = `since` |
| Bad `since` | `422 invalid_body` (same code as `GET /blocklist`, `contracts/api.md`) |
| Other method | `405 method_not_allowed` with `Allow: GET` |
| Too many requests | `429 rate_limited` with `Retry-After` (30 per IP per 10 min; IPv6 counted per /64) |

Paging is not used (contract: optional): one response holds everything. `Authorization` is never read, so it cannot be logged. Nothing about a request is logged.

How a feed entry becomes a published domain (`src/blocklist/`):
1. `source.js`: the only part that knows the feed. Today: `emptySource` in the Worker (honest empty list), `fixtureSource` in `npm run dev` (invented `shoo-fixture-*` domains in `data/public-blocklist.seed.json`).
2. `domains.js`: hostname or URL -> registrable domain with the **same Public Suffix List copy the extension uses** (`ios/ShooExtension/Resources/psl.js`), so what we publish is what the extension looks up. Public suffixes (`co.id`, `github.io`), IPs and junk are dropped.
3. `build.js` + `allowlist.js`: drops official domains (`detector/data/brands.json`) and their subdomains, ~100 popular sites, and platform apexes (`wordpress.com`, `github.io`, `vercel.app`...). A customer site on a platform (`bad.github.io`) is its own registrable domain and may be published. Duplicates keep the earliest `addedAt`.

### Source and licence (TODO A3: NOT DECIDED)

Checked on the official pages on 22 Oct 2026. Nothing here is legal advice. No feed was downloaded.

| Candidate | Licence / terms found | Usable in the app? | Format, frequency | Size |
|---|---|---|---|---|
| OpenPhish Community | Terms of Use: personal/research only, **commercial use prohibited without written consent**, no redistribution or derivative works | **No**, without written permission | text file, every 12 h | not stated |
| PhishTank | Terms point to a Cisco end-user licence agreement; **no data licence stated**. API key needed for regular downloads | **BELUM DIVERIFIKASI** (read the EULA first) | XML/CSV/JSON, hourly | not stated |
| URLhaus (abuse.ch) | Free under "fair use principles"; commercial/for-profit users "may require a paid subscription". Auth-Key needed. Not CC0 as far as found | **BELUM DIVERIFIKASI**; mostly malware URLs, not phishing | CSV/JSON/hostfile, every 5 min | not stated |
| Phishing Army | Third-party catalogues list **CC BY-NC 4.0** (own licence page not reachable) | Doubtful if the app is monetised (NC) | plain domain list, hostnames only | not stated |

Recommendation: **ask PhishTank** (phishing-specific, hourly, hostnames) whether the app may use the feed and read its EULA; if the answer is not clearly yes, ask OpenPhish or the Phishing Army author for written permission. Until then the endpoint stays empty in production, which is safe: layer 2 still runs and the extension treats an empty list as "no match".

## Layer 4: reality check (`unreasonable_request`, M4)

Off by default. It switches on when `LLM_API_KEY`, `LLM_MODEL` and an `https://` `LLM_BASE_URL` are set (see `.env.example`; Worker secrets in production). **No model has been chosen and the real provider was never called**: every test uses a fake `fetch`.

| Rule | Detail |
|---|---|
| Gate (D-imelda-05, proposal) | Not an official site, a form with at least one field, and OUR rules' score >= 15 (numbers in `localSignals` from the client do not count), plus 20 calls per IP per hour (`clientCallsPerHour`; the local dev server turns it off, since every local request is one `unknown` client, unless `LLM_CLIENT_CALLS_PER_HOUR` is set). Otherwise no call, no cost |
| What the model sees | `site` (registrable domain only; IPs and intranet names are never sent), `title` (120 chars), up to 12 field labels; emails and long digit runs are masked, ids of rules that fired. Never page text, URL path/query, typed values or the key. Sent as JSON between `DATA_START` / `DATA_END`; the system prompt (`prompts/reality-check.js`, `reality-check.v2`) is a fixed string |
| Answer | One JSON object `{page_type, asks[], reasonable, confidence, evidence}`; one ```` ```json ```` fence around it is stripped; anything else off-schema is ignored (200, layer 3 only) |
| Signal | `reasonable=false`, `confidence >= 0.6`, at least one `asks` -> `unreasonable_request`, layer 4, weight 30, fixed bilingual labels. `evidence` only if the phrase (at least 8 characters, folded and space-collapsed like layer 3; a `[number]`/`[email]` mask splits it and the longest piece is used) is in the title AND in the page text; the evidence is the exact slice of `text`, because the extension highlights `<body>` text, never `<title>`. Else omitted |
| Only adds | Layer 4 never lowers a score (D-imelda-06). A model that says "reasonable" changes nothing |
| Failure | Timeout (<= 4 s, hard even if the provider ignores abort), HTTP error, bad JSON, daily cap reached -> layer 3 answer, no error, provider text never forwarded |
| Cost breaker | `LLM_DAILY_CAP` calls per UTC day per Worker isolate (in memory), so NOT a real bound in production. The real cap is the spend limit in the provider dashboard: required before deploy (phase 08 checklist) |
| Outcomes | Each check ends as one of `gated / capped / timeout / http_error / bad_schema / reasonable / flagged` (counts only, no page data). The dev server serves them at `GET /_dev/layer4`; `eval/run.mjs --analyze-url` prints the delta under LAYER 4 and warns when calls gave no verdict. A wrong `LLM_MODEL` shows up as `http_error`/`bad_schema`, not as "always reasonable" |
| Determinism | `temperature: 0`; record `PROMPT_VERSION` and the model with every eval run |

Privacy note for Alief/Umar (TODO C5): when layer 4 is on, the host, page title and form field labels of pages that pass the gate go to the LLM provider.
