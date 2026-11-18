# Plan v5: current layer 3 (rules) against Alief's rebuilt layer 3, on the same pages

Owner: Imelda (`ai/`). Folder: `ai/test-layer3/v5-2026-11-13-compare-alief-l3/`. `src/` and `prompts/` are not changed.
Result: [HASIL.md](HASIL.md) (local only, gitignored).

## Goal

Put the two layer 3s side by side on the same saved pages and record, per page, the snapshot facts, the score of the current
layer 3 (rules) and the score and tier of Alief's trained layer 3.

## The two sides

| | Current layer 3 | Alief's layer 3 |
|---|---|---|
| What it is | Hand-written form and content rules in `ai/src/layer3/` | `bge-m3` (not trained) plus five small models and two combiners (scikit-learn, trained by Alief) |
| Score | Sum of signal weights, 0 to 100. 30 or more reaches layer 4, 80 or more blocks | Probability 0 to 1, then a tier: safe, gate, warn, block |
| Source | `analyzeSnapshot` in `ai/src/analyze.js` | `~/Documents/dataset/out/layer3_base.joblib` and `layer3_meta.joblib` (from the `shoo-layer3-lab` repo, commit c29f2b2) |
| Off for both | Layers 1, 2 and 4, local signals, domain age | same |

## Pages

From two earlier tests of this repo, no new fetching:

- `../v4-2026-11-12-phishing-url/snapshots/` (status ok)
- `../../test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/train-page.jsonl` (state ok)

Rules, written to `.hasil/sample-meta.json`:

1. Only pages that opened with content.
2. Drop pages redirected to a different host: the label belongs to the link, the text to another site.
3. Drop pages whose site is in Alief's train or dev split, so his model never saw them.
4. At most 3 pages per site, then at most 2,000 per label and dataset, seed 20261113.

## Steps

All scripts are in this folder. Python runs from `shoo-layer3-lab` so its environment (Python 3.12, scikit-learn, torch) is used.

| # | Script | What it does |
|---|---|---|
| 1 | `python3 -I sample.py` | Freezes the sample into `.hasil/sample-input.jsonl` |
| 2 | `node build-rows.mjs` | Builds the rows Alief's model reads. Copies two functions from the lab's `build_snapshots.mjs`. Check: recomputed layer 3 score equals the stored `scoreNoAge` on every phishing-url page |
| 3 | (inside `score.py`) | The two `.joblib` files are pickles. They were first listed without running anything: 24 names, no `os`, `subprocess`, `builtins` or `eval`. The loader allows exactly those names |
| 4 | `uv run --python 3.12 python <folder>/score.py` | Scores the sample in batches. Writes `.hasil/results.jsonl` |
| 5 | `uv run --python 3.12 python <folder>/report.py` | Writes `HASIL.md` and `detail.csv` |

## Not done on purpose

- No new labels. The datasets' labels are used as they are, and many scam labels are stale.
- No retraining. Alief's files are used as they are.
- No change to `ai/src/`.

## Limits

See section 7 of HASIL.md.
