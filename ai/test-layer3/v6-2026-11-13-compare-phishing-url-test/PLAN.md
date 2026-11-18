# Plan v6: the phishing-url test split, current rules against Alief's layer 3 and our two models

Owner: Imelda (`ai/`). Folder: `ai/test-layer3/v6-2026-11-13-compare-phishing-url-test/`. `src/` and `prompts/` are not changed.
Result: [HASIL.md](HASIL.md) (local only, gitignored).

## Goal

Test the pages in `../v4-2026-11-12-phishing-url/dataset/pages-test.jsonl` with four pipelines on the same saved snapshots:
the current layer 3 (rules), Alief's trained layer 3 (`bge-m3`), and our two models from `shoo-impersonation-lab`
(all scam types, impersonation only). Layers 1, 2, 4 and domain age are off.

## Pages

All 5,940 test pages (587 scam, 5,353 legit). No site and no phishing kit is in two splits of this dataset.
Pages whose site is in Alief's train or dev split are tagged `seen-by-alief` (264 scam, 183 legit). The rest are `unseen`
(323 scam, 5,170 legit). `unseen` is the fair comparison.

## Steps

| # | Command | What it does |
|---|---|---|
| 1 | `python3 -I sample.py` | Writes `.hasil/sample-input.jsonl` |
| 2 | `node ../v5-2026-11-13-compare-alief-l3/build-rows.mjs <this folder>` | Builds the rows the models read, with the current layer 3 score |
| 3 | `uv run --python 3.12 python ../v5-2026-11-13-compare-alief-l3/score.py --dir <this folder>` (from `shoo-layer3-lab`) | Scores with Alief's model, loaded with an allowlist, not `joblib.load` |
| 4 | `uv run --python 3.12 python report.py` (from `shoo-layer3-lab`) | Applies our models and writes `HASIL.md` and `detail.csv` |

## Not done on purpose

No retraining on these pages, no cut-off tuning on this test set, no new labels.
