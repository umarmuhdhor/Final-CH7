# ai — layer 3 & 4 (server)

Stateless service behind the Safari extension. Stack: Cloudflare Worker + [Hono](https://hono.dev), plain JavaScript (ESM + JSDoc), no build step (decision D-imelda-01).

Today it does layer 3 for **form fields**, **page text** (`urgent_language`, `brand_logo_offsite`) and **domain age** (`new_domain`, RDAP). The public blocklist (M5 server) and the LLM reality check (M4) are not here yet.

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
| Wrong shape, no `snapshot.url`, URL not http(s) | `400 invalid_body` |
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
