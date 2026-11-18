"""What does the popular-sites rule (popular.py) change? For each list size N: legit pages flagged, scam pages caught, and the scam
pages that only disappear because they sit on a popular domain (the risk of the rule).

Usage (uses the Python environment of shoo-layer3-lab):
  uv run --python 3.12 --project ~/Documents/Swift/Final-CH/shoo-layer3-lab python popular_effect.py \
      --rows <rows.jsonl> --compare <results.jsonl> --tag v6 [--variant impersonation] [--ns 1000 10000 50000]
--rows / --compare are the files of test-layer3/v5 and v6 (.hasil/rows.jsonl and .hasil/results.jsonl).
Writes out/<variant>/popular-<tag>.json. Hosts are written with [.].
The same rule is applied to our model and to Alief's tiers, so the comparison between them stays fair.
"""
import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np

import train as T
from popular import Popular

HERE = Path(__file__).resolve().parent
WATCH = ("amazon.co.uk", "telekom", "tedms", "okulizyon", "lastpass", "ripio")  # real brand logins we saw flagged in v6


def defang(host):
    return host.replace(".", "[.]")


def pct(a, b):
    return f"{100 * a / b:5.1f}%" if b else "  n/a"


def counts(tier, y, mask):
    out = {}
    for label, name in ((1, "scam"), (0, "legit")):
        m = mask & (y == label)
        out[name] = {"n": int(m.sum()), "reach_l4_or_flagged": int((tier[m] != "safe").sum()), "warn_or_block": int(np.isin(tier[m], ("warn", "block")).sum())}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=("all", "impersonation", "ablation"), default="impersonation")
    ap.add_argument("--rows", required=True)
    ap.add_argument("--compare", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--ns", type=int, nargs="+", default=[1000, 10000, 50000])
    args = ap.parse_args()

    sys.modules["__main__"].Judges = T.Judges  # our saved models name __main__.Judges
    model = joblib.load(HERE / "out" / args.variant / "model.joblib")
    rows = [json.loads(line) for line in open(args.rows, encoding="utf-8")]
    y = np.array([r["label"] for r in rows])
    group = np.array([r["dataset"] for r in rows])
    hosts = [r["host"] for r in rows]
    X = T.feature_matrices(model["judges"].score(rows), T.side_matrix(rows))
    final = sum(model["metas"][n].predict_proba(X[n])[:, 1] for n in ("with_address", "no_address")) / 2
    indo = np.array([T.is_indonesian(r) for r in rows])
    official = np.array([bool(r["feats"].get("official")) for r in rows])
    alief = {}
    for line in open(args.compare, encoding="utf-8"):
        d = json.loads(line)
        alief[d["id"]] = d["alief"]
    alief_base = np.array([alief[r["id"]]["tier"] for r in rows])
    ours_base = T.tier_names(final, indo, official, model["thresholds"]["final"])

    order = [g for g in ("unseen", "seen-by-alief", "phishing-url", "maliciousphish") if g in set(group)]
    masks = {g: group == g for g in order}
    masks["all pages"] = np.ones(len(rows), dtype=bool)

    result = {"variant": args.variant, "rows": len(rows), "by_n": {}, "scam_lost": {}}
    setups = [(0, np.zeros(len(rows), dtype=bool))]
    for n in args.ns:
        P = Popular(n)
        setups.append((n, np.array([P.is_popular(h) for h in hosts])))

    for n, pop in setups:
        ours = T.tier_names(final, indo, official | pop, model["thresholds"]["final"])
        theirs = np.where(pop, "safe", alief_base)
        key = "off" if n == 0 else f"top{n}"
        result["by_n"][key] = {"popular_pages": {"scam": int((pop & (y == 1)).sum()), "legit": int((pop & (y == 0)).sum())}, "groups": {}}
        print(f"\n=== popular rule: {'off' if n == 0 else f'Tranco top {n}'}   popular pages: scam {int((pop & (y == 1)).sum())}, legit {int((pop & (y == 0)).sum())}")
        for g, m in masks.items():
            co, ca = counts(ours, y, m), counts(theirs, y, m)
            result["by_n"][key]["groups"][g] = {"ours": co, "alief": ca}
            print(f"  {g:14} ours : scam reach L4 {pct(co['scam']['reach_l4_or_flagged'], co['scam']['n'])} warn+ {pct(co['scam']['warn_or_block'], co['scam']['n'])} | legit reach L4 {pct(co['legit']['reach_l4_or_flagged'], co['legit']['n'])} warn+ {pct(co['legit']['warn_or_block'], co['legit']['n'])}   (scam n={co['scam']['n']}, legit n={co['legit']['n']})")
            print(f"  {'':14} Alief: scam reach L4 {pct(ca['scam']['reach_l4_or_flagged'], ca['scam']['n'])} warn+ {pct(ca['scam']['warn_or_block'], ca['scam']['n'])} | legit reach L4 {pct(ca['legit']['reach_l4_or_flagged'], ca['legit']['n'])} warn+ {pct(ca['legit']['warn_or_block'], ca['legit']['n'])}")
        if n:
            lost = [int(i) for i in np.where(pop & (y == 1) & ((ours_base != "safe") | (alief_base != "safe")))[0]]
            result["scam_lost"][key] = [{"id": rows[i]["id"], "group": str(group[i]), "host": defang(hosts[i]), "ours_tier_before": str(ours_base[i]), "alief_tier_before": str(alief_base[i]), "ours_score": round(float(final[i]), 3)} for i in lost]
            print(f"  scam pages flagged by ours or Alief that are now safe only because the host is popular: {len(lost)}")
            for i in lost[:12]:
                print(f"    {rows[i]['id']:>12}  {defang(hosts[i])[:50]:50}  ours {ours_base[i]:6} ({final[i]:.2f})  Alief {alief_base[i]}")
            watch = [i for i in range(len(rows)) if y[i] == 0 and ours_base[i] != "safe" and any(w in hosts[i] for w in WATCH)]
            print("  real brand logins we flagged before, now: " + ", ".join(f"{defang(hosts[i])} {'safe' if pop[i] else ours_base[i]}" for i in watch))
    out = HERE / "out" / args.variant / f"popular-{args.tag}.json"
    json.dump(result, open(out, "w", encoding="utf-8"), indent=1)
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
