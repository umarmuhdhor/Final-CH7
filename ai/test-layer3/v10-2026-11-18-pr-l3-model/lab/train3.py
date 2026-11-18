"""Model "smallbiz" (iteration 4, 2026-11-17): train2.py plus small-business legit pages from the v7 Kaggle (maliciousphish) set.

Why (FP-ANALISIS.md in the v7 folder): v2 scores ordinary small-business sites (dentist, limo, contractor, chiropractor) high,
because Alief's legit training pages are mostly big, popular sites. The warn cut-off (2% of legit dev pages) is also set on those
big sites, so on real traffic with many small sites it lets through more than 2%.

Change (everything else is train2.py as is: language rule, cleaning, noisy-label drop, judges, combiner, TIERS):
  Kaggle v7 legit pages of the "unseen" group (sites not in Alief's train/dev) are split by site hash (kaggle_half):
    half A -> added: 80% of the A sites to train, 20% to dev, so the cut-offs are also set on small sites;
    half B -> never used here. It is the held-out Kaggle test (eval_v3.py --kaggle-half B).
  Added pages: at most PER_SITE per site (wikipedia alone has 2,600 pages), dead-like and gambling/porn pages dropped
  (stale labels, same rules as train2), sites that appear in any other test or calibration set left out.
  Kaggle scam pages are NOT added: their labels are stale (0 of 30 still scam in the v7 eye-check).

Usage (lab environment):
  uv run --python 3.12 --project ../shoo-layer3-lab python train3.py          # train, writes out/impersonation-smallbiz/
  (apply2.py --variant impersonation-smallbiz on the five row files, tags idcal-v4, idcal-alieftest, v6, v7, v7-fresh)
  uv run --python 3.12 --project ../shoo-layer3-lab python train3.py calib    # Indonesian cut-offs, same outside set as eval_v2.py
Writes only new files in out/impersonation-smallbiz/ (refuses to overwrite).
"""
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

import joblib
import numpy as np
from sklearn.metrics import roc_auc_score

import idcal as I
import train2 as T
from popular import Popular

HERE = Path(__file__).resolve().parent
OUT = HERE / "out/impersonation-smallbiz"
V7 = I.V7
PER_SITE = 3


def load(p):
    return [json.loads(line) for line in open(p, encoding="utf-8")]


def kaggle_half(site):
    """A = may be used for training/dev, B = held-out test. Salted so it is independent of idcal.half and the train2 dev move."""
    return "A" if hashlib.sha256(("kaggle-v7:" + site).encode()).digest()[0] % 2 == 0 else "B"


def added_rows():
    tag = {d["id"]: d["tags"]["group"] for d in load(V7 / ".hasil/sample-input.jsonl")}
    other = set()
    for p in (V7 / "fresh/.hasil/rows.jsonl", I.V6, I.OUT / ".hasil/rows.jsonl", I.OUT / "alief-test-indo.jsonl"):
        other |= {T.site(r["host"]) for r in load(p)}
    pool = [r for r in load(V7 / ".hasil/rows.jsonl") if r["label"] == 0 and tag[r["id"]] == "unseen"]
    pool.sort(key=lambda r: hashlib.sha256(r["id"].encode()).hexdigest())  # fixed order for the per-site cap
    per, out, n = Counter(), [], Counter(pool=len(pool))
    for r in pool:
        s = T.site(r["host"])
        if kaggle_half(s) != "A":
            n["half_B_held_out"] += 1
            continue
        if s in other:
            n["site_in_other_test_set"] += 1
            continue
        r = dict(r, title=r.get("title") or "", text=r.get("text") or "")
        if T.is_dead(r) or T.is_adult_gambling(r):
            n["dead_or_gambling_porn"] += 1
            continue
        if per[s] >= PER_SITE:
            n["over_site_cap"] += 1
            continue
        per[s] += 1
        r.update(split="dev" if hashlib.sha256(s.encode()).digest()[1] % 5 == 0 else "train", source="kaggle_v7", scamType=None, _i=-1)
        out.append(r)
    n["added_train"] = sum(r["split"] == "train" for r in out)
    n["added_dev"] = sum(r["split"] == "dev" for r in out)
    n["added_sites"] = len(per)
    return out, dict(n)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if (OUT / "model.joblib").exists():
        raise SystemExit("out/impersonation-smallbiz/model.joblib exists: not overwriting")
    every = T.load_rows()
    alief = np.load(T.SRC / "scores.npz")["final"]
    alief_limits = json.load(open(T.SRC / "report.json"))["thresholds"]["final"]
    added, info = added_rows()
    print(f"smallbiz: {info}", flush=True)
    json.dump(info, open(OUT / "added.json", "w"), indent=1)
    rows = [r for r in every if T.keep(r, "impersonation")] + added
    kag = np.array([r.get("source") == "kaggle_v7" for r in rows])
    y = np.array([r["label"] for r in rows])
    split = np.array([r["split"] for r in rows])
    tr, dv, te = split == "train", split == "dev", split == "test"
    groups = np.array([T.site(r["host"]) for r in rows])
    indo = np.array([T.is_indonesian(r) for r in rows])
    official = np.array([bool(r["feats"].get("official")) for r in rows])
    # train2 changes 2, 3, 4 (train and dev only; test untouched). Added pages are already cleaned; the Indonesian move applies to them too.
    dead = np.array([T.is_dead(r) for r in rows])
    adult = np.array([T.is_adult_gambling(r) for r in rows])
    drop = (tr | dv) & (((y == 1) & dead) | ((y == 0) & adult))
    move = tr & indo & (y == 0) & np.array([hashlib.sha256(T.site(r["host"]).encode()).digest()[0] % 4 == 0 for r in rows])
    tr, dv = (tr & ~drop & ~move), ((dv & ~drop) | move)
    print(f"pages {len(rows)}: train {tr.sum()} (Kaggle {int((tr & kag).sum())}) dev {dv.sum()} (Kaggle {int((dv & kag).sum())}) test {te.sum()} "
          f"| scam {y.sum()} legit {(y == 0).sum()} | dev legit Indonesian {int((dv & indo & (y == 0)).sum())}", flush=True)

    first, _ = T.oof_scores(rows, y, tr, groups)
    noisy = tr & (((y == 1) & (first.max(axis=1) < 0.2)) | ((y == 0) & (first[:, 0] > 0.97)))
    tr = tr & ~noisy
    print(f"training pages dropped as wrong labels: scam {int((noisy & (y == 1)).sum())}, legit {int((noisy & (y == 0)).sum())} "
          f"(Kaggle {int((noisy & kag).sum())})", flush=True)
    scores, judges = T.oof_scores(rows, y, tr, groups)

    X = T.feature_matrices(scores, T.side_matrix(rows))
    metas, per = {}, {}
    for name, x in X.items():
        metas[name] = T.combiner().fit(x[tr], y[tr])
        per[name] = metas[name].predict_proba(x)[:, 1]
    per["final"] = (per["with_address"] + per["no_address"]) / 2

    thresholds = {n: {g: {t: T.threshold_at_fpr(s[dv & (y == 0) & m], f) for t, f in T.TIERS} for g, m in (("indonesian", indo), ("other", ~indo))}
                  for n, s in per.items()}
    tiers = {n: T.tier_names(s, indo, official, thresholds[n]) for n, s in per.items()}
    rules_score = np.array([r["baseline"]["score"] for r in rows])
    tiers["rules"] = np.where(rules_score >= 80, "block", np.where(rules_score >= 30, "warn", "safe"))
    a_final = np.array([alief[r["_i"]] if r["_i"] >= 0 else 0.0 for r in rows])
    tiers["alief"] = T.tier_names(a_final, indo, official, alief_limits)

    auc = {"rules": roc_auc_score(y[te], rules_score[te]), "alief": roc_auc_score(y[te], a_final[te])}
    auc.update({f"judge_{n}": roc_auc_score(y[te], scores[te, i]) for i, n in enumerate(T.Judges.NAMES)})
    auc.update({n: roc_auc_score(y[te], s[te]) for n, s in per.items()})
    print("\nAUC on the held-out test pages (Alief's test split, unchanged): " + "  ".join(f"{k} {v:.3f}" for k, v in auc.items()), flush=True)
    v2_th = joblib.load(HERE / "out/impersonation-v2/model.joblib")["thresholds"]["final"]
    print(f"cut-offs 'other' v2 {v2_th['other']}\n          smallbiz {thresholds['final']['other']}")

    imp_scam = np.array([r["label"] == 1 and (r.get("source", "scamweb") in ("phish", "phish_id") or r.get("scamType") in T.IMPERSONATION_TYPES) for r in rows])
    sets = {"test: all": te, "test: pages with a password field": te & np.array([bool(r["feats"]["passwordField"]) for r in rows]),
            "test: impersonation-type scam + all legit": te & (imp_scam | (y == 0))}
    report = {"scam_types": "impersonation-smallbiz", "pages": len(rows), "added": info, "auc_test": auc, "thresholds": thresholds,
              "v2_thresholds_final": v2_th, "sets": {}}
    for sname, mask in sets.items():
        print(f"\n{sname}   (columns: reach layer 4 or flagged / warn or block / block)")
        report["sets"][sname] = {}
        for tname in ("rules", "alief", "final", "with_address", "no_address"):
            r = T.rates(tiers[tname], y, mask)
            report["sets"][sname][tname] = r
            print(f"  {tname:16} {T.fmt(r)}")
    json.dump(report, open(OUT / "report.json", "w"), indent=1)
    joblib.dump({"judges": judges, "metas": metas, "thresholds": {n: thresholds[n] for n in ("final", "with_address", "no_address")},
                 "no_address_columns": T.NO_ADDRESS_COLUMNS, "scam_types": "impersonation"}, OUT / "model.joblib")
    print(f"\nsaved {OUT}")


def calib():
    """Indonesian cut-offs from the same outside set as eval_v2.py (phishing-url v4 train+dev + Alief test half A, legit Indonesian,
    not official, not popular, no gambling/porn words). 'other' keeps the model's own dev cut-offs (now set with small sites in dev)."""
    if (OUT / "thresholds-idcal.json").exists():
        raise SystemExit("out/impersonation-smallbiz/thresholds-idcal.json exists: not overwriting")
    P = Popular(1000)
    th_model = joblib.load(OUT / "model.joblib")["thresholds"]["final"]
    f = {}
    for t in ("idcal-v4", "idcal-alieftest"):
        f.update({d["id"]: d["final"] for d in load(OUT / f"applied-{t}.jsonl")})

    def ok(r):
        return r["label"] == 0 and T.is_indonesian(r) and not r["feats"].get("official") and not P.is_popular(r["host"]) and not T.is_adult_gambling(r)

    c = np.array([f[r["id"]] for r in load(I.OUT / ".hasil/rows.jsonl") if ok(r)] +
                 [f[r["id"]] for r in load(I.OUT / "alief-test-indo.jsonl") if r["half"] == "A" and ok(r)])
    th = {"indonesian": {t: T.threshold_at_fpr(c, fpr) for t, fpr in T.TIERS}, "other": th_model["other"]}
    json.dump({"final": th, "calibration_pages": len(c), "model_indonesian": th_model["indonesian"]}, open(OUT / "thresholds-idcal.json", "w"), indent=1)
    print(json.dumps(th, indent=1), f"\ncalibration pages {len(c)}")


if __name__ == "__main__":
    sys.modules["__main__"].Judges = T.Judges
    calib() if sys.argv[1:] == ["calib"] else main()
