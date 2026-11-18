"""Apply our trained model (train.py) to any rows file and compare it with the current rules and with Alief's layer 3.

Usage:
  uv run --python 3.12 --project ~/Documents/Swift/Final-CH/shoo-layer3-lab python apply.py --variant all \
      --rows <rows.jsonl> [--compare <results.jsonl>] [--tag name]
--rows     one JSON per line: id, label (1 scam, 0 legit), url, host, title, text, baseline, feats. Made by build-rows.mjs from snapshots.
--compare  optional, the results.jsonl of test-layer3/v5 (it holds the current rules score and Alief's tier for the same ids).
Writes out/<variant>/applied-<tag>.jsonl (one line per page). model.joblib is our own file from train.py on this machine.
"""
import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np
from sklearn.metrics import roc_auc_score

import train as T
from popular import Popular

HERE = Path(__file__).resolve().parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=("all", "impersonation", "ablation"), default="all")
    ap.add_argument("--rows", required=True)
    ap.add_argument("--popular-n", type=int, default=0, help="treat hosts under the Tranco top-N domains as official (tier safe) for every pipeline. 0 = off")
    ap.add_argument("--compare")
    ap.add_argument("--tag", default="rows")
    args = ap.parse_args()

    # train.py ran as __main__, so the saved Judges object names __main__.Judges; point that name at the class in train.py.
    sys.modules["__main__"].Judges = T.Judges
    model = joblib.load(HERE / "out" / args.variant / "model.joblib")
    rows = [json.loads(line) for line in open(args.rows, encoding="utf-8")]
    y = np.array([r["label"] for r in rows])
    scores = model["judges"].score(rows)
    X = T.feature_matrices(scores, T.side_matrix(rows))
    per = {n: model["metas"][n].predict_proba(X[n])[:, 1] for n in ("with_address", "no_address")}
    final = (per["with_address"] + per["no_address"]) / 2
    indo = np.array([T.is_indonesian(r) for r in rows])
    official = np.array([bool(r["feats"].get("official")) for r in rows])
    popular = np.zeros(len(rows), dtype=bool)
    if args.popular_n:
        P = Popular(args.popular_n)
        popular = np.array([P.is_popular(r["host"]) for r in rows])
        official = official | popular
        print(f"popular rule, Tranco top {args.popular_n}: {int(popular.sum())} pages ({int((popular & (y == 1)).sum())} scam, {int((popular & (y == 0)).sum())} legit)")
    tiers = {"ours": T.tier_names(final, indo, official, model["thresholds"]["final"])}
    rules = np.array([r["baseline"]["score"] for r in rows])
    tiers["rules"] = np.where(rules >= 80, "block", np.where(rules >= 30, "warn", "safe"))
    sensitive = np.array([bool(r["feats"]["passwordField"]) or any(s.startswith("asks_") for s in r["baseline"]["signals"]) for r in rows])
    claim = np.array([bool(r["feats"]["brandOffsite"] or r["feats"]["brandTextOffsite"] or r["feats"]["brandInHost"]) for r in rows])
    tiers["ours+pass_rule"] = np.where(sensitive | claim, tiers["ours"], "safe")
    auc = {"rules": roc_auc_score(y, rules), "ours": roc_auc_score(y, final)}
    if args.compare:
        theirs = {}
        for line in open(args.compare, encoding="utf-8"):
            d = json.loads(line)
            theirs[d["id"]] = d["alief"]
        tiers["alief"] = np.array([theirs[r["id"]]["tier"] if r["id"] in theirs else "safe" for r in rows])
        auc["alief"] = roc_auc_score(y, [theirs[r["id"]]["final"] for r in rows])
    if args.popular_n:
        tiers = {k: np.where(popular, "safe", v) for k, v in tiers.items()}  # the same rule for every pipeline
    print(f"[{args.variant}] {len(rows)} pages from {args.rows}")
    print("AUC: " + "  ".join(f"{k} {v:.3f}" for k, v in auc.items()))
    subsets = {"all pages": np.ones(len(rows), dtype=bool), "pages with a password field": np.array([bool(r["feats"]["passwordField"]) for r in rows])}
    for d in sorted({r.get("dataset") for r in rows if r.get("dataset")}):
        subsets[f"dataset {d}"] = np.array([r.get("dataset") == d for r in rows])
    for sname, mask in subsets.items():
        print(f"\n{sname}   (columns: reach layer 4 or flagged / warn or block / block)")
        for tname in ("rules", "alief", "ours", "ours+pass_rule"):
            if tname in tiers:
                print(f"  {tname:15} {T.fmt(T.rates(tiers[tname], y, mask))}")
    out = HERE / "out" / args.variant / f"applied-{args.tag}.jsonl"
    with open(out, "w", encoding="utf-8") as f:
        for r, fin, t, s in zip(rows, final, tiers["ours"], scores):
            f.write(json.dumps({"id": r["id"], "label": r["label"], "final": round(float(fin), 4), "tier": str(t), "words": round(float(s[0]), 3), "address": round(float(s[1]), 3)}) + "\n")
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
