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

## Sources and licences
| Source | Licence / terms | Used for |
|---|---|---|
| Hand-written synthetic scam and trap samples (`synthetic: true`) | ours, repo licence | 49 scam, 12 legit traps |
| `lphone-login` (one real scam page, captured earlier) | a single page kept as a text snapshot, fields stripped of values | 1 scam |
| Public pages of Indonesian banks, shops, government sites, news (`legit/real.json`, `legit/seed.json`) | **no licence granted** by these sites. Fetched once with `tools/capture.mjs` on 2026-10-22; only a short excerpt is kept (text up to 1500 chars, up to 10 image alts of 80 chars, form field names) as a limited quotation for measurement. The owner accepts this risk (D-imelda-22). Wikipedia text is CC BY-SA 4.0 (attribution in that sample's `source`) | 39 legit |
| OpenPhish community feed | **not used**: terms forbid redistribution and derivative works without written permission | - |
| PhishTank | **not used**: no licence stated on its developer page (refers to a Cisco EULA) | - |
| URLhaus | **not used**: malware URLs, not phishing; no licence stated on its page | - |

Captured legit pages are not copied in full: no raw HTML is stored, text is cut to 1500 characters and image alts to 10 x 80, and query values (page, iframe and form action URLs) and fragments are replaced by `REDACTED`.

## Composition (D-imelda-20) and live counts
Run `node ai/eval/tools/check-corpus.mjs` for the current numbers. Each sample carries exactly one category tag.

| Class | Category tag | Target |
|---|---|---|
| scam | `bank` 10, `e-wallet` 8, `courier` 8, `prize` 8, `government` 8, `apple` 4, `other` 4 | 50 |
| legit | `bank-login` 8, `checkout` 12, `official-gov` 8, `popular` 10, `lookalike-trap` 12 | 50 |

Extra tags: `clean-domain-scam` (scam on a neutral domain), `lookalike-brand`, `brand-plus-keyword`, `cheap-tld`, `credential-iframe`, `bank-logo-checkout`, `brand-mention-blog`, `shared-host`, `social-login`, `kyc-legit`, `news-about-scam`, `school-login`, `insurance`.

**Real vs synthetic.** Synthetic samples are written by us, so they cannot prove recall: `run.mjs` prints real and synthetic separately, and the verdict `targets MET/NOT met` is computed from real samples only (needs 50 real per class, otherwise it says "not judged"; `--strict` then exits 2). Today there is one real scam page, so the scam-side targets cannot be proven from real data until more real scam pages are available under a clear licence (see D-imelda-19, TODO A4).

## Holdout (D-imelda-21)
About 30% of the samples carry the tag `holdout`. It is **derived**, never picked: `sha256("<seed>:<id>")` read as a number in [0,1) is below 0.3. The seed is random and recorded in `data/HOLDOUT.json`; it never changes (changing it would move holdout samples into tuning). `tools/assign-holdout.mjs` writes the tags, `tools/check-corpus.mjs` fails when a tag disagrees with the seed. Weights are tuned on non-holdout samples only; the holdout is looked at once, at the end of phase 07. `run.mjs` therefore lists holdout samples only as totals; `--show-holdout` lists them one by one. (Hiding is a guard against habit, not a lock: the JSON files are readable.) Today all 12 holdout scam samples are synthetic and the only real scam page is in the tuning part, so the holdout cannot measure real recall yet.

## Adding samples
1. `node ai/eval/tools/capture.mjs <url> --label legit --id slug --source "..." --tags <category> --out <empty scratch dir>` (public hosts only: private addresses, odd ports and redirects to them are refused). Never use it on a scam URL; write a synthetic sample instead.
2. Move the sample into `data/`, run `node ai/eval/tools/assign-holdout.mjs`.
3. `node ai/eval/tools/check-redaction.mjs` must report 0 findings.
4. Read the sample, then the owner runs `node ai/eval/tools/mark-redacted.mjs --confirm-read --ids <id>`. An agent never sets `redacted: true` on a real sample. Limit: nothing in the repo proves a human ran it (the flag is a plain field); a reviewed-hash scheme is a possible later step.
5. `node ai/eval/tools/check-corpus.mjs` shows whether the set is complete.

## Known limits
- Static HTML only: pages built by JavaScript (several bank and shop shells) come out with little or no text and no forms, so they exercise layers 1-2 only.
- The redaction checker is pattern based (e-mail incl. spelled-out, mobile and landline numbers, 13-19 digit runs with space/dot/hyphen separators, fullwidth and Arabic digits folded, common token formats, URL query values). It cannot know a person's name; names in page text are the owner's job when reading.
- `capture.mjs` resolves the host name and then `fetch` resolves it again, so a host that changes its DNS answer in between (rebinding) is not stopped.
- `new_domain` is not measured here: scam domains must not be sent to a registry.
- Hard cases kept on purpose: `trap-fintech-kyc-sah` (a legitimate KYC page asks for KTP and OTP like a scam) and `credential-iframe` scam pages (the login form is invisible to the snapshot).
