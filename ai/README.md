# ai — layer 3 & 4 (server)

Stateless service behind the Safari extension. Stack: Cloudflare Worker + [Hono](https://hono.dev), plain JavaScript (ESM + JSDoc), no build step (decision D-imelda-01).

Today it does layer 3 for **form fields** only. Text signals and `new_domain` (phase 03), the public blocklist (M5 server) and the LLM reality check (M4) are not here yet.

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

## Privacy

Nothing is stored, cached or logged: no `console.*` in `src/`, and a test spies on console and stdout/stderr across success and every error path. Responses are `no-store`.

## Layout

```
src/index.js          Worker entry (default export = Hono app)
src/app.js            routes, error mapping
src/http.js           error format, size-capped body reader
src/validate.js       request check + snapshot sanitising
src/limits.js         all caps
src/analyze.js        runs layer 3
src/layer3/           text.js (word splitting) forms.js (rules) signals.js (weights + wording) official.js
src/dev-server.mjs    local HTTP wrapper, development only
test/                 node --test files
eval/                 labelled pages + scorer (M2)
```

`.env.example` lists variable names only. Real values go in `.env` / `.dev.vars`, both gitignored.
