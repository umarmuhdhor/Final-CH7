"""Step 5: turn .hasil/results.jsonl into HASIL.md and detail.csv.

Usage (from the lab folder, for numpy and scipy):
  cd ~/Documents/Swift/Final-CH/shoo-layer3-lab
  uv run --python 3.12 python <this folder>/report.py
Hosts are written with [.] so nothing in HASIL.md is clickable; HASIL.md, detail.csv and .hasil/ are gitignored (public repo).
"""
import collections
import csv
import datetime
import json
from pathlib import Path

import numpy as np
from scipy.stats import rankdata

HERE = Path(__file__).resolve().parent
H = HERE / ".hasil"
rows = [json.loads(line) for line in open(H / "results.jsonl", encoding="utf-8")]
meta = json.load(open(H / "sample-meta.json"))
smeta = json.load(open(H / "score-meta.json"))


def defang(host):
    return host.replace(".", "[.]")


def clean(text, n=60):
    return " ".join((text or "").split())[:n].replace("`", "'").replace("|", "/")


def pct(a, b):
    return f"{a} of {b} ({100 * a / b:.1f}%)" if b else "n/a"


def auc(scores, labels):
    scores, labels = np.asarray(scores, dtype=float), np.asarray(labels)
    pos, neg = int((labels == 1).sum()), int((labels == 0).sum())
    if not pos or not neg:
        return float("nan")
    ranks = rankdata(scores)
    return float((ranks[labels == 1].sum() - pos * (pos + 1) / 2) / (pos * neg))


LEVELS = [
    ("Reaches layer 4 or is flagged (her score 30 or more / Alief tier gate, warn or block)", lambda r: r["her"]["score"] >= 30, lambda r: r["alief"]["tier"] != "safe"),
    ("Shown to the user without asking the LLM (her 30 or more, as in Alief's script / Alief warn or block)", lambda r: r["her"]["score"] >= 30, lambda r: r["alief"]["tier"] in ("warn", "block")),
    ("Blocked (her 80 or more / Alief block)", lambda r: r["her"]["score"] >= 80, lambda r: r["alief"]["tier"] == "block"),
]


def level_table(subset):
    scam = [r for r in subset if r["label"] == 1]
    legit = [r for r in subset if r["label"] == 0]
    out = ["| Level | Pipeline | Scam caught | Legit flagged |", "|---|---|---|---|"]
    for name, her, alief in LEVELS:
        out.append(f"| {name} | Current layer 3 (rules) | {pct(sum(her(r) for r in scam), len(scam))} | {pct(sum(her(r) for r in legit), len(legit))} |")
        out.append(f"| | Alief's layer 3 | {pct(sum(alief(r) for r in scam), len(scam))} | {pct(sum(alief(r) for r in legit), len(legit))} |")
    return "\n".join(out)


def subsets():
    yield "phishing-url", [r for r in rows if r["dataset"] == "phishing-url"]
    yield "maliciousphish", [r for r in rows if r["dataset"] == "maliciousphish"]
    yield "Both datasets together", rows


def table_row(r):
    a = r["alief"]
    return f"| `{r['id']}` | `{defang(r['host'])}` | `{clean(r['title'])}` | {r['her']['score']} {','.join(r['her']['signals']) or '-'} | {a['final']:.2f} {a['tier']} |"


def examples(title, picked):
    if not picked:
        return f"**{title}**: none.\n"
    return f"**{title}**\n\n| id | host | title | current layer 3 | Alief |\n|---|---|---|---|---|\n" + "\n".join(table_row(r) for r in picked) + "\n"


md = []
md.append("# Result v5: current layer 3 (rules) against Alief's rebuilt layer 3, same pages\n")
md.append(f"_Generated {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')} by `report.py` from `.hasil/results.jsonl`. Plan: [PLAN.md](PLAN.md). Hosts are written with `[.]`: do not open them, and read this before any commit (public repo)._\n")
md.append("## 0. How to read this\n")
md.append("- **Current layer 3** is this repo's real layer 3 (`analyzeSnapshot`: form rules and content rules) on the saved snapshot. Layers 1, 2 and 4, domain age and local signals are off. Alief's own `rules` column is the same code, and on the 2,623 phishing-url pages it matched the score stored in your v4 snapshots exactly.")
md.append("- **Alief's layer 3** is his trained model (`bge-m3` plus five small models plus two combiners) loaded from his `layer3_*.joblib`. Cut-offs per language group come from his files. Official brand hosts are always safe, as in his script.")
md.append("- **Same snapshot, same sample** for both. Pages come from your two v4 datasets. Pages from a site in Alief's train or dev split were removed, so his model never saw them.")
md.append("- **Labels are the datasets' labels, not checked by hand.** Both datasets are old, so many scam labels are stale. Compare the two pipelines with each other, not with 100 percent.")
md.append("- Her score has no `warn` level in production: 30 to 79 goes to layer 4, 80 or more blocks. Alief's script treats 30 or more as both gate and warn, so rows 1 and 2 are the same for her.\n")

md.append("## 1. The sample\n")
md.append(f"Fixed seed {meta['seed']}. At most {meta['max_per_site']} pages per site, at most {meta['per_class']} per label and dataset. Alief's train sites: {meta['alief_train_sites']}, dev sites: {meta['alief_dev_sites']}.\n")
md.append("| Dataset | Opened, not moved to another host | After removing Alief's train and dev sites | After site cap | In the sample (scam / legit / sites) |")
md.append("|---|---|---|---|---|")
for name, d in meta["datasets"].items():
    md.append(f"| {name} | {d['opened_not_moved']} (scam {d['by_label_opened'].get('1', 0)}, legit {d['by_label_opened'].get('0', 0)}) | {d['after_removing_alief_train_dev_sites']['pages']} | {d['after_site_cap']['pages']} | {d['sampled']['scam']} / {d['sampled']['legit']} / {d['sampled']['sites']} |")
md.append(f"\nScored: {smeta['pages']} pages, {smeta['chunks']} text chunks, {smeta['seconds']} s on `{smeta['device']}`.\n")

md.append("## 2. How many scam are caught, how many legit are flagged\n")
for name, sub in subsets():
    md.append(f"### {name}\n")
    scam_n = sum(r["label"] for r in sub)
    md.append(f"{scam_n} scam pages, {len(sub) - scam_n} legit pages.\n")
    md.append(level_table(sub) + "\n")
    labels = [r["label"] for r in sub]
    md.append(f"AUC (1.0 is perfect, 0.5 is a coin flip): current layer 3 **{auc([r['her']['score'] for r in sub], labels):.3f}**, Alief's final score **{auc([r['alief']['final'] for r in sub], labels):.3f}**.\n")

md.append("## 3. Pages with a password field\n")
md.append("These are the pages that matter most for the goal (a fake page that asks for a login).\n")
pw = [r for r in rows if r["password_field"]]
md.append(level_table(pw) + "\n")

md.append("## 4. Do the two agree?\n")
md.append("Counts of pages by (current layer 3 caught at 30 or more) and (Alief not safe).\n")
md.append("| Label | Both | Only current | Only Alief | Neither |\n|---|---|---|---|---|")
for lab, name in ((1, "scam"), (0, "legit")):
    sub = [r for r in rows if r["label"] == lab]
    both = sum(r["her"]["score"] >= 30 and r["alief"]["tier"] != "safe" for r in sub)
    only_her = sum(r["her"]["score"] >= 30 and r["alief"]["tier"] == "safe" for r in sub)
    only_al = sum(r["her"]["score"] < 30 and r["alief"]["tier"] != "safe" for r in sub)
    md.append(f"| {name} | {both} | {only_her} | {only_al} | {len(sub) - both - only_her - only_al} |")
md.append("")

md.append("## 5. Which signals fire\n")
for lab, name in ((1, "scam"), (0, "legit")):
    c = collections.Counter(s for r in rows if r["label"] == lab for s in r["her"]["signals"])
    n = sum(1 for r in rows if r["label"] == lab)
    md.append(f"- Current layer 3 on {name} ({n} pages): " + (", ".join(f"`{k}` {v}" for k, v in c.most_common()) or "no signal fired"))
md.append("")
md.append("Average score of each of Alief's five small models (0 to 1):\n")
md.append("| Label | meaning | chunkmax | gambling | words | address |\n|---|---|---|---|---|---|")
for lab, name in ((1, "scam"), (0, "legit")):
    sub = [r for r in rows if r["label"] == lab]
    vals = [np.mean([r["alief"]["base_scores"][k] for r in sub]) for k in ("meaning", "chunkmax", "gambling", "words", "address")]
    md.append(f"| {name} | " + " | ".join(f"{v:.2f}" for v in vals) + " |")
md.append("")

md.append("## 6. Examples\n")
scam = [r for r in rows if r["label"] == 1]
legit = [r for r in rows if r["label"] == 0]
md.append(examples("Scam that Alief catches and the current layer 3 misses (highest Alief score first)", sorted([r for r in scam if r["her"]["score"] < 30 and r["alief"]["tier"] in ("warn", "block")], key=lambda r: -r["alief"]["final"])[:8]))
md.append(examples("Scam that both miss (lowest Alief score first)", sorted([r for r in scam if r["her"]["score"] < 30 and r["alief"]["tier"] == "safe"], key=lambda r: r["alief"]["final"])[:8]))
md.append(examples("Legit that Alief warns or blocks (highest score first)", sorted([r for r in legit if r["alief"]["tier"] in ("warn", "block")], key=lambda r: -r["alief"]["final"])[:8]))
md.append(examples("Legit that the current layer 3 flags (highest score first)", sorted([r for r in legit if r["her"]["score"] >= 30], key=lambda r: -r["her"]["score"])[:8]))

md.append("## 7. Limits\n")
md.append("- Both layer 3s see a static page (one GET, no JavaScript). Pages built by JavaScript look empty to both.")
md.append("- Scam labels are old and unchecked. Many labelled-scam pages are no longer phishing. Read the catch rates as a comparison.")
md.append("- Alief's model was trained on ScamWeb, a CC0 phishing set and other sources. We removed pages from his train and dev sites, but a site that is new to him can still look like one he knows.")
md.append("- His model needs `bge-m3` (2.3 GB) and has no Worker version yet. These numbers say how well it works, not that it can ship.")
md.append(f"- Model files: base sha256 `{smeta['base_sha256'][:16]}…`, meta sha256 `{smeta['meta_sha256'][:16]}…`. Loaded with an allowlist of 24 class names, not `joblib.load`.")
(HERE / "HASIL.md").write_text("\n".join(md) + "\n", encoding="utf-8")

with open(HERE / "detail.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["id", "dataset", "label", "host", "title", "text_len", "forms", "password_field", "her_score", "her_signals", "alief_final", "alief_tier", "alief_with_address", "alief_no_address", "meaning", "chunkmax", "gambling", "words", "address"])
    for r in rows:
        a = r["alief"]
        b = a["base_scores"]
        w.writerow([r["id"], r["dataset"], "scam" if r["label"] else "legit", defang(r["host"]), clean(r["title"], 80), r["text_len"], r["forms"], r["password_field"], r["her"]["score"], ";".join(r["her"]["signals"]),
                    a["final"], a["tier"], a["with_address"], a["no_address"], b["meaning"], b["chunkmax"], b["gambling"], b["words"], b["address"]])
print("wrote HASIL.md and detail.csv for", len(rows), "pages")
