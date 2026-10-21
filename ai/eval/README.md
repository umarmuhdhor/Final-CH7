# ai/eval — M2 eval set

A labelled set of scam and legit pages, and one command that scores them with the real detector. It is the ruler for M1, M3, M4 and for the weight calibration in M6.

```bash
node ai/eval/run.mjs                              # layers 1-2 only (M1). Works today.
node ai/eval/run.mjs --analyze-url http://localhost:8787   # + POST /analyze (M3/M4), once it exists
node ai/eval/run.mjs --tag lookalike-trap         # only samples with a tag
node ai/eval/run.mjs --json                       # machine-readable
node --test ai/eval/test                          # tests for the eval tools
```

It prints one row per page (score, status, signals), then: how many scam pages reach 30 / 50 / 80, how many legit pages are flagged (false positives, split by signal and level), the mandate targets, and `analyzeLocal` timing.

**The targets are only judged with `--analyze-url` and 50+ samples per class.** Layers 1-2 alone are not meant to block (they max out at 54), so "0% reach 50" with layer 2 only is expected, not a failure.

## Targets (docs/mandates/imelda.md)
- 0 legit pages with score >= 30
- >= 90% of scam pages >= 50, and >= 70% >= 80
- `analyzeLocal` < 50 ms, `/analyze` < 8 s (p95)

## Sample format
`data/scam/*.json` and `data/legit/*.json`. A file holds one sample or an array of samples.

```json
{
  "id": "lowercase-slug",
  "label": "scam | legit",
  "tags": ["lookalike-trap"],
  "synthetic": false,
  "redacted": true,
  "source": "where it came from (required)",
  "collectedAt": "2026-10-22T00:00:00.000Z",
  "notes": "free text",
  "snapshot": { "url": "https://...", "title": "", "lang": null, "text": "", "forms": [], "imageAlts": [], "capturedAt": "..." },
  "meta": { "iframes": [] }
}
```
- `snapshot` is a `PageSnapshot` (contracts/detector-interface.md). **Only `url` is required**: `domain` is computed with the extension's own Public Suffix List code, and missing fields get empty values. A URL-only sample is enough for layers 1-2; layer 3-4 needs `title`, `text`, `forms`, `imageAlts`.
- Form fields never carry values (the validator rejects a `value` key).
- `synthetic: true` marks an invented example (shown with `*`). Real scam samples must have `redacted: true`, which you set **after reading the file yourself**.
- `meta` is not part of the contract. `meta.iframes` records iframes in the static HTML: a login form inside an iframe is invisible to `snapshot.forms`.
- Suggested tags: `official`, `popular`, `lookalike-trap`, `common-word`, `clean-domain-scam` (a scam on a normal-looking domain: M1 will miss it, on purpose), `lookalike-brand`, `credential-iframe`.

## Adding a page
```bash
node ai/eval/tools/capture.mjs "https://example/page" --label scam --id short-slug \
  --source "PhishTank 2026-10-22" --tags lookalike-brand
```
Then **open the JSON, remove anything personal that is left, set `"redacted": true`.** `run.mjs` refuses real scam samples until you do.
Use `--file saved.html` to parse HTML you already saved: scam sites die fast and are hostile, so fetch once and keep the file.

What `capture.mjs` does: a static GET (no JavaScript, no cookies, 500 KB cap), then masks e-mail addresses, phone numbers and 13-19 digit numbers in the text, and replaces query values and the fragment in the URL with `REDACTED`.
Known limits: it reads static HTML only (content added by scripts is not seen), and text inside `<svg>` is dropped.

## Rules for the data
- Never open a scam page in a normal browser to "check" it.
- Public pages only. No logged-in pages, nothing with a victim's data.
- Check the licence of any feed you copy from, and write the source in `source`.
- Keep a part of the set (about 30%) out of weight tuning, and look at it only at the end, or M6 will just memorise the samples.

## What is here now
13 seed samples: one real scam page (`lphone-login`), three domains from `contracts/fixtures/`, four official/popular pages (URL only) and traps for false positives (common words, a shop that sells iPhones, a 5-letter word). Everything marked `synthetic` is invented. The real work is collecting 50+ of each.
