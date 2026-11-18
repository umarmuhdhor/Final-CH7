"""Last step: current rules, Alief's layer 3 and our two models on the same test pages -> HASIL.md and detail.csv.

Usage:
  cd ~/Documents/Swift/Final-CH/shoo-layer3-lab
  uv run --python 3.12 python <this folder>/report.py
Needs .hasil/rows.jsonl (v5/build-rows.mjs), .hasil/results.jsonl (v5/score.py --dir <this folder>) and the models trained in
~/Documents/Swift/Final-CH/shoo-impersonation-lab/out/{all,impersonation}/model.joblib (our own files).
Hosts are written with [.]; HASIL.md, detail.csv and .hasil/ are gitignored (public repo).
"""
import csv
import datetime
import json
import sys
from pathlib import Path

import joblib
import numpy as np
from scipy.stats import rankdata

HERE = Path(__file__).resolve().parent
H = HERE / ".hasil"
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
sys.path.insert(0, str(LAB))
import train as T  # noqa: E402

sys.modules["__main__"].Judges = T.Judges  # our saved models name __main__.Judges
rows = [json.loads(line) for line in open(H / "rows.jsonl", encoding="utf-8")]
res = {}
for line in open(H / "results.jsonl", encoding="utf-8"):
    d = json.loads(line)
    res[d["id"]] = d
meta = json.load(open(H / "sample-meta.json"))
y = np.array([r["label"] for r in rows])
group = np.array([r["dataset"] for r in rows])
indo = np.array([T.is_indonesian(r) for r in rows])
official = np.array([bool(r["feats"].get("official")) for r in rows])

tiers, scores = {}, {}
rules = np.array([r["baseline"]["score"] for r in rows])
scores["Current rules"] = rules.astype(float)
tiers["Current rules"] = np.where(rules >= 80, "block", np.where(rules >= 30, "warn", "safe"))
scores["Alief (bge-m3)"] = np.array([res[r["id"]]["alief"]["final"] for r in rows])
tiers["Alief (bge-m3)"] = np.array([res[r["id"]]["alief"]["tier"] for r in rows])
for variant, label in (("all", "Ours, all scam types"), ("impersonation", "Ours, impersonation only")):
    model = joblib.load(LAB / "out" / variant / "model.joblib")
    sc = model["judges"].score(rows)
    X = T.feature_matrices(sc, T.side_matrix(rows))
    final = sum(model["metas"][n].predict_proba(X[n])[:, 1] for n in ("with_address", "no_address")) / 2
    scores[label] = final
    tiers[label] = T.tier_names(final, indo, official, model["thresholds"]["final"])
    if variant == "impersonation":
        sensitive = np.array([bool(r["feats"]["passwordField"]) or any(s.startswith("asks_") for s in r["baseline"]["signals"]) for r in rows])
        claim = np.array([bool(r["feats"]["brandOffsite"] or r["feats"]["brandTextOffsite"] or r["feats"]["brandInHost"]) for r in rows])
        tiers["Ours, impersonation + pass rule"] = np.where(sensitive | claim, tiers[label], "safe")
        scores["Ours, impersonation + pass rule"] = np.where(sensitive | claim, final, 0.0)
NAMES = ["Current rules", "Alief (bge-m3)", "Ours, all scam types", "Ours, impersonation only", "Ours, impersonation + pass rule"]


def defang(host):
    return host.replace(".", "[.]")


def clean(text, n=60):
    return " ".join((text or "").split())[:n].replace("`", "'").replace("|", "/")


def pct(a, b):
    return f"{a} of {b} ({100 * a / b:.1f}%)" if b else "n/a"


def auc(s, lab):
    s, lab = np.asarray(s, dtype=float), np.asarray(lab)
    pos, neg = int((lab == 1).sum()), int((lab == 0).sum())
    if not pos or not neg:
        return float("nan")
    return float((rankdata(s)[lab == 1].sum() - pos * (pos + 1) / 2) / (pos * neg))


def table(mask):
    sc, lg = mask & (y == 1), mask & (y == 0)
    out = ["| Pipeline | Scam: reaches layer 4 or flagged | Scam: warn or block | Scam: block | Legit: reaches layer 4 or flagged | Legit: warn or block | Legit: block |", "|---|---|---|---|---|---|---|"]
    for name in NAMES:
        t = tiers[name]
        cells = []
        for m in (sc, lg):
            n = int(m.sum())
            cells += [pct(int((t[m] != "safe").sum()), n), pct(int(np.isin(t[m], ("warn", "block")).sum()), n), pct(int((t[m] == "block").sum()), n)]
        out.append(f"| {name} | " + " | ".join(cells) + " |")
    out.append("")
    out.append("AUC (1.0 perfect, 0.5 coin flip): " + ", ".join(f"{name} **{auc(scores[name][mask], y[mask]):.3f}**" for name in NAMES[:4]) + ".")
    return "\n".join(out) + "\n"


unseen, seen, everything = group == "unseen", group == "seen-by-alief", np.ones(len(rows), dtype=bool)
pw = np.array([bool(r["feats"]["passwordField"]) for r in rows])
md = ["# Result v6: the phishing-url test split, current rules against Alief and our models\n"]
md.append(f"_Generated {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')} by `report.py`. Hosts are written with `[.]`: do not open them, and read this before any commit (public repo)._\n")
md.append("## 0. How to read this\n")
md.append("- **Pages:** the test split of `../v4-2026-11-12-phishing-url/dataset/` (no site and no phishing kit is in two of its splits). Layers 1, 2, 4 and domain age are off for every pipeline, so these are layer 3 results.")
md.append("- **Unseen** pages are from sites that are not in Alief's train or dev split. That is the fair comparison. **Seen-by-alief** pages are from sites he trained on or tuned on, so his model is flattered there.")
md.append("- **Ours** was trained on Alief's data (see `shoo-impersonation-lab`): same inputs, but no `bge-m3`, no gambling. It never saw these pages. Its cut-offs were set on Alief's dev pages, not on this test set.")
md.append("- **Pass rule:** no password field or `asks_*` signal and no brand claim means safe. It is an option, not a default.")
md.append("- Labels are the dataset's. Many scam pages here come from phishing feeds, so a few may have been replaced since.\n")
md.append("## 1. The pages\n")
md.append("| Group | Scam | Legit |\n|---|---|---|")
for g in ("unseen", "seen-by-alief"):
    md.append(f"| {g} | {meta['pages'][g]['scam']} | {meta['pages'][g]['legit']} |")
md.append("")
md.append("## 2. Unseen sites (the fair comparison)\n")
md.append(table(unseen))
md.append("## 3. Unseen sites, pages with a password field\n")
md.append(table(unseen & pw))
md.append("## 4. All test pages, including sites Alief trained on\n")
md.append(table(everything))
md.append("## 5. Only sites Alief trained on\n")
md.append(table(seen))

ours, alief_t, imp = tiers["Ours, impersonation only"], tiers["Alief (bge-m3)"], scores["Ours, impersonation only"]


def ex_table(title, pick):
    if not pick:
        return f"**{title}**: none.\n"
    lines = [f"**{title}**\n", "| id | host | title | rules | Alief | ours (impersonation) |", "|---|---|---|---|---|---|"]
    for i in pick:
        r = rows[i]
        lines.append(f"| `{r['id']}` | `{defang(r['host'])}` | `{clean(r['title'])}` | {r['baseline']['score']} | {scores['Alief (bge-m3)'][i]:.2f} {alief_t[i]} | {imp[i]:.2f} {ours[i]} |")
    return "\n".join(lines) + "\n"


idx = np.arange(len(rows))
u = unseen
md.append("## 6. Examples (unseen sites)\n")
md.append(ex_table("Scam that all three miss (lowest ours score first)", [int(i) for i in sorted(idx[u & (y == 1) & (rules < 30) & (alief_t == "safe") & (ours == "safe")], key=lambda i: imp[i])[:8]]))
md.append(ex_table("Scam that ours catches and Alief misses (highest ours score first)", [int(i) for i in sorted(idx[u & (y == 1) & (ours != "safe") & (alief_t == "safe")], key=lambda i: -imp[i])[:8]]))
md.append(ex_table("Scam that Alief catches and ours misses (highest Alief score first)", [int(i) for i in sorted(idx[u & (y == 1) & (ours == "safe") & (alief_t != "safe")], key=lambda i: -scores["Alief (bge-m3)"][i])[:8]]))
md.append(ex_table("Legit that ours warns or blocks (highest first)", [int(i) for i in sorted(idx[u & (y == 0) & np.isin(ours, ("warn", "block"))], key=lambda i: -imp[i])[:8]]))
md.append(ex_table("Legit that Alief warns or blocks (highest first)", [int(i) for i in sorted(idx[u & (y == 0) & np.isin(alief_t, ("warn", "block"))], key=lambda i: -scores["Alief (bge-m3)"][i])[:8]]))
md.append("## 7. Limits\n")
md.append("- All pipelines see a static page (one GET, no JavaScript). Forms built by JavaScript are invisible to all of them.")
md.append("- About 100 pages have garbled text (wrong character encoding when the dataset was made). They hurt every pipeline the same way.")
md.append("- Our two models and Alief's were trained on the same sources, so they share blind spots. None of them saw these pages.")
md.append("- Pass rule and cut-offs were not tuned on this test set.")
(HERE / "HASIL.md").write_text("\n".join(md) + "\n", encoding="utf-8")

with open(HERE / "detail.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["id", "group", "label", "host", "title", "forms", "password_field", "rules_score", "alief_final", "alief_tier", "ours_all_final", "ours_all_tier", "ours_imp_final", "ours_imp_tier"])
    for i, r in enumerate(rows):
        w.writerow([r["id"], r["dataset"], "scam" if r["label"] else "legit", defang(r["host"]), clean(r["title"], 80), r["feats"]["forms"], r["feats"]["passwordField"], r["baseline"]["score"],
                    round(float(scores["Alief (bge-m3)"][i]), 4), tiers["Alief (bge-m3)"][i], round(float(scores["Ours, all scam types"][i]), 4), tiers["Ours, all scam types"][i],
                    round(float(imp[i]), 4), ours[i]])
print("wrote HASIL.md and detail.csv for", len(rows), "pages")
