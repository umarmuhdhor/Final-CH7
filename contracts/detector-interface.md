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
Must be fast (< 50 ms typical), never throw (return `[]` on error), never make network calls except fetching/refreshing its own phishing list.

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
    }[];                   // field VALUES are never included
  }[];
  imageAlts: string[];     // alt text of images (logo hints), max 50
  capturedAt: string;      // ISO date-time
};
```

## Signal
Defined in `scan-result.schema.json#/$defs/Signal`.

## Scoring (owned by lead, implemented in extension)
- `score = min(100, sum(signal.weight))`, recomputed every time a layer returns.
- Any signal with `id: "db_match"` → score 100 immediately, skip remaining layers.
- Domain with a family/personal `safe` verdict → skip detection, score 0.
- Domain with `not_safe` verdict → blocked (100).
- Score resets to 0 on every navigation, including URL change without reload.

Team AI owns the **weights**. The lead owns the **thresholds** (contracts/README.md).

## Known signal ids
| id | Layer | Meaning |
|---|---|---|
| `db_match` | 1 | Domain in Shoo DB (Verified scam) or public phishing list |
| `lookalike_domain` | 2 | Spelling close to an official brand (p0stindonesia) |
| `brand_plus_keyword` | 2 | Brand + extra word (bca-verifikasi) |
| `cheap_tld` | 2 | .xyz, .site, .click, ... |
| `new_domain` | 2 | Domain age in days |
| `asks_pin` / `asks_otp` / `asks_password` / `asks_card` / `asks_cvv` / `asks_ktp` / `asks_selfie_ktp` | 3 | Form requests sensitive data |
| `brand_logo_offsite` | 3 | Brand logo on non-official domain |
| `urgent_language` | 3 | "blocked in 24 hours", etc. |
| `unreasonable_request` | 4 | LLM: requested data doesn't fit the page type |
| `hoax_claim` | 5 | Phase 2 — not used in MVP |

Adding a new id = contract change (PR to `contracts/`).
