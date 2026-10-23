# Detector interface

Detection is split in two places (PRD §5, "Layer deteksi"):

| Layer | Runs | Owner | Folder |
|---|---|---|---|
| 1 Database, 2 Link name | On device, inside the extension | Team AI | `detector/` → built into `ios/ShooExtension/Resources/detector.js` |
| 3 Content & forms, 4 Reality check | Server | Team AI | `ai/` → `POST /analyze` (see api.md) |

The extension (lead) only collects the page, calls the detector, sums the score, and shows UI.
If the server is down, layer 1–2 still run; layer 3–4 are skipped (PRD §5).

## On-device API (`detector.js`)
Plain script (no ES modules — Safari content scripts can't `import`). It must define one global:

```js
globalThis.ShooDetector = {
  version: "0.1.0",
  /** @param {PageSnapshot} snapshot  @returns {Promise<Signal[]>} */
  analyzeLocal: async (snapshot) => [],
};
```
Must be fast (< 50 ms typical), never throw (return `[]` on error), and **never make network calls**.

### Layer-1 lists: `ShooLists` (provided by the extension)
The extension's `background.js` downloads and refreshes the lists (`GET /blocklist`, `GET /public-blocklist`) and exposes
one helper in the content-script scope, available before `analyzeLocal` runs:

```js
/** @returns {Promise<{ source: "shoo" | "public", domain: string, addedAt: string } | null>} */
globalThis.ShooLists.match(hostname);
```
- Checks the hostname and each parent down to the registrable domain (never above it: no `vercel.app`, no `co.id`).
- Resolves `null` when nothing matches, when lists aren't downloaded yet (app not set up), or on any error. Never rejects.
- On a match the detector returns `db_match` (weight 100) with `evidence` = `source`.
- Design and refresh timing: `docs/design/blocklist.md`.

## PageSnapshot (extension → detector / ai)
```ts
type PageSnapshot = {
  url: string;            // full URL
  domain: string;         // registrable domain, lowercase, no www
  title: string;
  lang: string | null;    // <html lang>
  text: string;           // visible text, max 20,000 chars
  forms: {
    action: string | null;
    fields: {
      type: string;        // input type
      name: string | null;
      id: string | null;
      label: string | null;        // associated <label> text
      placeholder: string | null;
      autocomplete: string | null;
      accept?: string | null;      // <input accept>, e.g. "image/*"
      capture?: string | null;     // <input capture>: "user" (front camera), "environment", "" (bare attribute)
    }[];                   // field VALUES are never included
  }[];
  imageAlts: string[];     // alt text of images (logo hints), max 50
  capturedAt: string;      // ISO date-time
};
```
`accept` and `capture` are optional (additive, #86): older extensions don't send them, so readers treat a missing value as `null`.

## Signal
Defined in `scan-result.schema.json#/$defs/Signal`.

`label` and `labelSimple` are **bilingual objects** — Team AI writes both languages; the app only picks one:
```json
{ "id": "new_domain", "layer": 3, "weight": 30,
  "label":       { "en": "Domain age 3 days",             "id": "Umur domain 3 hari" },
  "labelSimple": { "en": "This site was made 3 days ago", "id": "Situs ini baru dibuat 3 hari lalu" } }
```

## Scoring (owned by lead, implemented in extension)
- `score = min(100, sum(signal.weight))`, recomputed every time a layer returns.
- Any signal with `id: "db_match"` → score 100 immediately, skip remaining layers.
- Domain with a family/personal `safe` verdict → skip detection, score 0.
- Domain with `not_safe` verdict → blocked (100).
- Score resets to 0 on every navigation, including URL change without reload.

Team AI owns the **weights**. The lead owns the **thresholds** (contracts/README.md).

## `evidence` (EX-05 highlight)
Optional, but it drives what the extension marks on the page:
- **Layer 1–2 signals**: `evidence` is free-form and never highlighted (e.g. `db_match` → `"shoo"` or `"public"`, `lookalike_domain` → the brand it imitates).
- **Text signals, layer ≥ 3** (`urgent_language`, `brand_logo_offsite`, `unreasonable_request`, `hoax_claim`, …): `evidence` must be text that appears **exactly** on the page (case-insensitive, within one text block), e.g. `"diblokir dalam 24 jam"`. The extension highlights every occurrence at score ≥ 30. Paraphrased or translated evidence highlights nothing.
- **Field signals** (`asks_*`): `evidence` is the field's `name`/`id` (e.g. `"pin"`). Not highlighted as text — the extension strikes sensitive fields itself at score ≥ 50.
- Never put typed values in `evidence`.

## Known signal ids
| id | Layer | Meaning |
|---|---|---|
| `db_match` | 1 | Domain in Shoo DB (Verified scam) or public phishing list |
| `lookalike_domain` | 2 | Spelling close to an official brand (p0stindonesia) |
| `brand_plus_keyword` | 2 | Brand + extra word (bca-verifikasi) |
| `cheap_tld` | 2 | .xyz, .site, .click, ... |
| `new_domain` | 3 | Domain age in days (made by the server via RDAP) |
| `asks_pin` / `asks_otp` / `asks_password` / `asks_card` / `asks_cvv` / `asks_ktp` / `asks_selfie_ktp` | 3 | Form requests sensitive data |
| `brand_logo_offsite` | 3 | Brand logo on non-official domain |
| `urgent_language` | 3 | "blocked in 24 hours", etc. |
| `unreasonable_request` | 4 | LLM: requested data doesn't fit the page type |
| `hoax_claim` | 5 | Phase 2 — not used in MVP |

Adding a new id = contract change (PR to `contracts/`).
