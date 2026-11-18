"""v7 final: the no-LLM pipeline = rules (current) vs model v1 vs model v2 vs model v2 + domain age < N days.

Usage (lab environment):
  cd ~/Documents/Swift/Final-CH/shoo-impersonation-lab
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/combine.py
Reads existing results only (no network): applied-*.jsonl of v1 and v2, .hasil/rdap.jsonl, thresholds of v1 (1b) and v2.
Writes .hasil/combine.md (numbers), used by HASIL-AKHIR-tanpa-LLM.md.
Flagged = warn or block. Domain age applies only to pages NOT on a shared host (on vercel.app, pages.dev ... the age is the platform's)
and turns a page into warn (never block). Unknown age = not young.
"""
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(HERE))
import idcal as I  # noqa: E402
import rdap_measure as R  # noqa: E402
import train as T1  # noqa: E402
import train2 as T2  # noqa: E402
from popular import Popular  # noqa: E402


def load(p):
    return [json.loads(line) for line in open(p, encoding="utf-8")]


def main():
    P = Popular(1000)
    th1 = json.load(open(LAB / "out/impersonation/thresholds-idcal2.json"))["final"]
    th2 = json.load(open(LAB / "out/impersonation-v2/thresholds-idcal.json"))["final"]
    f1, f2 = {}, {}
    for t in ("v7", "v7-fresh", "idcal-v4", "idcal-alieftest"):
        f1.update({d["id"]: d["final"] for d in load(LAB / f"out/impersonation/applied-{t}.jsonl")})
    for t in ("v2-v7", "v2-v7-fresh", "v2-idcal-v4", "v2-idcal-alieftest"):
        f2.update({d["id"]: d["final"] for d in load(LAB / f"out/impersonation-v2/applied-{t}.jsonl")})
    ages = {d["domain"]: R.age_days(d) for d in load(HERE / ".hasil/rdap.jsonl")}
    fit_rows = [r for r in T1.load_rows() if r["split"] in ("train", "dev")]
    a_sites, a_hosts = {T1.site(r["host"]) for r in fit_rows}, {r["host"] for r in fit_rows}

    def unseen(r):
        return (r["host"] not in a_hosts) if r["feats"]["sharedHost"] else (T1.site(r["host"]) not in a_sites)

    fresh = load(HERE / "fresh/.hasil/rows.jsonl")
    S = R.sets()
    sets = [
        ("Scam feed segar, unseen (semua host)", [r for r in fresh if r["label"] == 1 and unseen(r)]),
        ("Scam feed segar, unseen, domain sendiri", [r for r in fresh if r["label"] == 1 and unseen(r) and not r["feats"]["sharedHost"]]),
        ("Scam feed segar, unseen, hosting gratis", [r for r in fresh if r["label"] == 1 and unseen(r) and r["feats"]["sharedHost"]]),
        ("Legit global (Kaggle, 1 halaman per situs, 1.500)", S["legit_kaggle_sample"]),
        ("Legit Indonesia (bukan hosting gratis)", S["legit_indonesian"]),
        ("Link aman manual", [r for r in fresh if r["label"] == 0]),
    ]

    def flags(rows, variant, days=0):
        out = []
        for r in rows:
            off = bool(r["feats"].get("official")) or P.is_popular(r["host"])
            if variant == "rules":
                out.append(r["baseline"]["score"] >= 30)
                continue
            fin, th, g = (f1, th1, I.indo_group) if variant == "v1" else (f2, th2, T2.is_indonesian)
            t = T1.tier_names([fin[r["id"]]], [g(r)], [off], th)[0]
            a = None if r["feats"]["sharedHost"] else ages.get(T1.site(r["host"]))
            young = days and a is not None and a < days and not off
            out.append(t in ("warn", "block") or bool(young))
        return np.array(out)

    variants = [("Rules sekarang", "rules", 0), ("Model v1 (1b)", "v1", 0), ("Model v2", "v2", 0),
                ("**v2 + umur < 30 hari**", "v2", 30), ("v2 + umur < 90 hari", "v2", 90)]
    L = ["| Pipeline tanpa LLM | " + " | ".join(n for n, _ in sets) + " |", "|---|" + "---|" * len(sets)]
    L.append("| Jumlah halaman | " + " | ".join(str(len(rows)) for _, rows in sets) + " |")
    for vname, v, d in variants:
        cells = []
        for _, rows in sets:
            f = flags(rows, v, d)
            cells.append(f"{int(f.sum())} ({f'{100 * f.mean():.1f}'.replace('.', ',')}%)" if len(rows) else "-")
        L.append(f"| {vname} | " + " | ".join(cells) + " |")
    (HERE / ".hasil/combine.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L))


if __name__ == "__main__":
    main()
