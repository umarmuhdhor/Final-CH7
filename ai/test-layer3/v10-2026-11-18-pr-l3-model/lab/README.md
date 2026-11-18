# shoo-impersonation-lab

Our own layer 3 experiment. One question: does this page pretend to be someone, and does it ask for something?
Simplified from Alief's `shoo-layer3-lab` (commit c29f2b2). Nothing here ships. The Shoo repo is not touched.

## Architecture

```
PageSnapshot (url, title, text, forms)
   |
   +--> judge 1: words on the page      (TF-IDF + logistic regression)
   +--> judge 2: shape of the address   (TF-IDF + logistic regression)
   +--> facts: brand name on a domain the brand does not own, password field, form sent to another site,
   |           cheap TLD, shared host, current-rules signals (asks_password, asks_otp, ...), Indonesian flag
   |
   v
two combiners (gradient-boosted trees): one sees the address, one does not. Final score = their average.
   |
   v
tier: safe / gate (ask layer 4) / warn / block
      cut-offs set so that only 15% / 2% / 0.5% of legit dev pages reach gate / warn / block, per language group
      official brand hosts are always safe
```

## What we kept from Alief, and what we removed

| Kept | Why |
|---|---|
| Split by site, out-of-fold judge scores | No site is in both train and test |
| Words judge, address judge | Best single parts (test AUC 0.973 and 0.943), tiny, no GPU |
| Brand, form and address facts, Shoo's `brands.json` | These are the impersonation signals |
| Combiner, cut-offs by false-alarm rate, official hosts safe | Lets us choose how many legit pages we can afford to flag |
| Dropping training pages with a clearly wrong label | Our labels are stale |

| Removed | Why |
|---|---|
| `bge-m3` and the judges that need it (meaning, best chunk) | 2.3 GB, extra service, no measurable gain on our tests |
| Gambling judge, gambling data, "togel" and "gacor" | Out of scope, weakest judge |
| Pickle files from other machines | We load only files we wrote here |
| Hardcoded paths and GPU setting | Mac-only |

Not done yet: export the weights to JSON for the Cloudflare Worker.

## Run

Both scripts reuse the Python environment of `../shoo-layer3-lab` (Python 3.12, scikit-learn). Training data is Alief's rows in
`~/Documents/dataset/out/` (read only).

```bash
uv run --python 3.12 --project ../shoo-layer3-lab python train.py --scam-types all
uv run --python 3.12 --project ../shoo-layer3-lab python train.py --scam-types impersonation
uv run --python 3.12 --project ../shoo-layer3-lab python apply.py --variant impersonation --rows <rows.jsonl> --compare <results.jsonl>
```

`--scam-types impersonation` keeps the real phishing sets plus the ScamWeb types Phishing, Business, Bank and Government
impersonation, Spoofed Login Page, E-commerce Customer Service Impersonation and Technical Support Scam. Training takes about 6 minutes.

## Results (details in out/*/report.json)

Held-out test pages from Alief's split, AUC (1.0 perfect, 0.5 coin flip):

| | Current rules | Alief (full) | Ours, all scam types | Ours, impersonation only |
|---|---|---|---|---|
| Test pages (his split) | 0.54 | 0.983 | 0.983 | 0.988 |
| v5 sample, 6,623 pages from our two datasets | 0.50 | 0.654 | 0.653 | 0.690 |

## Limits

- Both test sets come from the same collections as the training data, split by site. The v5 sample is the harder, more honest test.
- Scam labels in the v5 sample are old and unchecked. Compare models with each other, not with 100 percent.
- The simple rule "no sensitive form and no brand claim means pass" removes about two thirds of the scam we catch on these pages
  (static HTML shows no form or brand on most of them). It is evaluated as `final+pass_rule`, not applied by default.
- Static snapshots only. The extension sees the rendered page.
