"""Compare model v1 (out/impersonation, iteration-1b cut-offs) with model v2 (out/impersonation-v2, train2.py) on every test set.

Both get the same treatment: popular top 1000 = safe, Indonesian cut-offs calibrated on the same outside set as idcal.fit2
(phishing-url v4 train+dev + Alief test half A, legit Indonesian, not official, not popular, no gambling/porn words).
Main view is WITHOUT an LLM: only warn/block count as caught; gate is reported for reference.
"Unseen" for the fresh feed is fixed here: a page on a shared host (vercel.app, pages.dev ...) is unseen when its FULL host is not in
Alief's train/dev data (v7 used the parent domain, which marked almost every shared-host page as seen).

Usage: uv run --python 3.12 --project ../shoo-layer3-lab python eval_v2.py
Writes out/impersonation-v2/thresholds-idcal.json and out/impersonation-v2/eval.md (new files, refuses to overwrite).
"""
import json
import sys
from pathlib import Path

import joblib
import numpy as np

import idcal as I
import train as T1
import train2 as T2
from popular import Popular

HERE = Path(__file__).resolve().parent
V1, V2 = HERE / "out/impersonation", HERE / "out/impersonation-v2"
V6 = I.V6
V7 = I.V7


def load(p):
    return [json.loads(line) for line in open(p, encoding="utf-8")]


def finals(folder, tag):
    return {d["id"]: d["final"] for d in load(folder / f"applied-{tag}.jsonl")}


def main():
    if (V2 / "eval.md").exists():
        raise SystemExit("out/impersonation-v2/eval.md exists: not overwriting")
    sys.modules["__main__"].Judges = T1.Judges
    P = Popular(1000)
    th1 = json.load(open(V1 / "thresholds-idcal2.json"))["final"]
    th2_model = joblib.load(V2 / "model.joblib")["thresholds"]["final"]

    v4 = load(I.OUT / ".hasil/rows.jsonl")
    al = load(I.OUT / "alief-test-indo.jsonl")
    f2 = {}
    for t in ("v2-idcal-v4", "v2-idcal-alieftest", "v2-v6", "v2-v7", "v2-v7-fresh"):
        f2.update(finals(V2, t))
    f1 = {}
    for t in ("idcal-v4", "idcal-alieftest", "idcal-v6", "v7", "v7-fresh"):
        f1.update(finals(V1, t))

    def calib_ok(r):
        return r["label"] == 0 and T2.is_indonesian(r) and not r["feats"].get("official") and not P.is_popular(r["host"]) and not T2.is_adult_gambling(r)

    calib = np.array([f2[r["id"]] for r in v4 if calib_ok(r)] + [f2[r["id"]] for r in al if r["half"] == "A" and calib_ok(r)])
    th2 = {"indonesian": {t: T2.threshold_at_fpr(calib, f) for t, f in T2.TIERS}, "other": th2_model["other"]}
    json.dump({"final": th2, "calibration_pages": len(calib), "model_indonesian": th2_model["indonesian"]}, open(V2 / "thresholds-idcal.json", "w"), indent=1)

    every = T1.load_rows()
    fit_rows = [r for r in every if r["split"] in ("train", "dev")]
    alief_sites = {T1.site(r["host"]) for r in fit_rows}
    alief_hosts = {r["host"] for r in fit_rows}

    def unseen(r):
        return (r["host"] not in alief_hosts) if r["feats"]["sharedHost"] else (T1.site(r["host"]) not in alief_sites)

    def tiers(rows, fin, th, group):
        f = np.array([fin[r["id"]] for r in rows])
        g = np.array([group(r) for r in rows])
        off = np.array([bool(r["feats"].get("official")) or P.is_popular(r["host"]) for r in rows])
        return T1.tier_names(f, g, off, th)

    def cell(t, y, lab):
        m = y == lab
        n = int(m.sum())
        if not n:
            return ["-", "-", "-"]

        def p(k):
            return f"{k} ({f'{100 * k / n:.1f}'.replace('.', ',')}%)"
        return [p(int(np.isin(t[m], ("warn", "block")).sum())), p(int((t[m] == "block").sum())), p(int((t[m] != "safe").sum()))]

    ktag = {}
    for line in open(V7 / ".hasil/sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        ktag[d["id"]] = d["tags"]["group"]
    kag = [r for r in load(V7 / ".hasil/rows.jsonl") if ktag[r["id"]] == "unseen"]
    fresh = load(V7 / "fresh/.hasil/rows.jsonl")
    v6 = load(V6)
    sets = [
        ("Link segar, unseen (definisi diperbaiki)", [r for r in fresh if unseen(r)]),
        ("Link segar, semua", fresh),
        ("Link aman manual (legit)", [r for r in fresh if r["label"] == 0]),
        ("phishing-url test (v6), unseen", [r for r in v6 if r.get("dataset") == "unseen"]),
        ("Test split Alief, Indonesia (legit separuh B, semua scam)", [r for r in al if r["label"] == 1 or r["half"] == "B"]),
        ("Kaggle v7 unseen, legit saja (label scam basi)", [r for r in kag if r["label"] == 0]),
        ("Kaggle v7 unseen, legit mirip parkir/error", [r for r in kag if r["label"] == 0 and T2.is_dead(r)]),
        ("Kaggle v7 unseen, legit Indonesia", [r for r in kag if r["label"] == 0 and T2.is_indonesian(r)]),
    ]
    L = ["# Model v2 (train2.py) dibanding v1", "",
         "_Dibuat oleh `eval_v2.py`. Keduanya: popular 1.000 aktif, ambang Indonesia dikalibrasi dari set luar yang sama. "
         "**Tampilan utama tanpa LLM**: hanya warn/block yang dihitung tertangkap. Gate ditulis sebagai pembanding._", "",
         f"Ambang v2: Indonesia gate {th2['indonesian']['gate']:.4f} / warn {th2['indonesian']['warn']:.4f} / block {th2['indonesian']['block']:.4f} "
         f"(kalibrasi {len(calib)} halaman); bahasa lain {th2['other']['gate']:.4f} / {th2['other']['warn']:.4f} / {th2['other']['block']:.4f}. "
         f"Ambang v1 (1b): Indonesia {th1['indonesian']['gate']:.4f} / {th1['indonesian']['warn']:.4f} / {th1['indonesian']['block']:.4f}; "
         f"bahasa lain {th1['other']['gate']:.4f} / {th1['other']['warn']:.4f} / {th1['other']['block']:.4f}.", ""]
    for name, rows in sets:
        y = np.array([r["label"] for r in rows])
        L += [f"### {name}", "", f"Scam {int((y == 1).sum())}, legit {int((y == 0).sum())}.", "",
              "| Model | Scam warn/block | Scam block | Scam sampai gate | Legit warn/block | Legit block | Legit sampai gate |", "|---|---|---|---|---|---|---|"]
        for mname, fin, th, g in (("v1 (1b)", f1, th1, I.indo_group), ("**v2**", f2, th2, T2.is_indonesian)):
            t = tiers(rows, fin, th, g)
            L.append(f"| {mname} | " + " | ".join(cell(t, y, 1) + cell(t, y, 0)) + " |")
        L.append("")
    (V2 / "eval.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L))


if __name__ == "__main__":
    main()
