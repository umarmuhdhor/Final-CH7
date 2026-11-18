"""Step 3 (v7): pick pages for a hand check, because most `scam` labels in this dataset are stale (v4 report: 92 of 100).

Usage: python3 -I eyecheck_sample.py
Reads  .hasil/sample-input.jsonl, .hasil/rows.jsonl, shoo-impersonation-lab/out/impersonation/applied-v7-pop1000.jsonl
Writes .hasil/eyecheck-todo.jsonl: short excerpts only (host, title, first 400 characters, form field types), never opened.

Strata (unseen sites only, fixed seed, at most 1 page per site):
  S1 scam label, ours warn or block      -> are the pages ours flags really scam today?
  S2 legit label, ours warn or block     -> are these real false alarms?
  S3 scam label, password field, ours safe -> live phishing that ours misses?
  S4 scam label, any tier                -> how stale is the scam label in this larger set?
  S5 legit label, ours gate              -> what layer 4 would be asked about
"""
import json
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
N = {"S1": 30, "S2": 30, "S3": 30, "S4": 30, "S5": 15}


def main():
    tags = {}
    snaps = {}
    for line in open(HERE / ".hasil/sample-input.jsonl", encoding="utf-8"):
        r = json.loads(line)
        tags[r["id"]] = r["tags"]
        s = r["snapshot"]
        fields = [f.get("type") or "?" for fm in (s.get("forms") or []) for f in (fm.get("fields") or [])]
        snaps[r["id"]] = {"host": s["domain"], "title": (s.get("title") or "")[:120], "text": " ".join((s.get("text") or "").split())[:400], "fields": fields[:12]}
    pw = {}
    for line in open(HERE / ".hasil/rows.jsonl", encoding="utf-8"):
        r = json.loads(line)
        pw[r["id"]] = bool(r["feats"]["passwordField"])
    ours = {}
    for line in open(LAB / "out/impersonation/applied-v7-pop1000.jsonl", encoding="utf-8"):
        o = json.loads(line)
        ours[o["id"]] = o
    pools = {k: [] for k in N}
    for i, o in ours.items():
        if tags[i]["group"] != "unseen":
            continue
        flagged = o["tier"] in ("warn", "block")
        if o["label"] == 1 and flagged:
            pools["S1"].append(i)
        if o["label"] == 0 and flagged:
            pools["S2"].append(i)
        if o["label"] == 1 and pw[i] and o["tier"] == "safe":
            pools["S3"].append(i)
        if o["label"] == 1:
            pools["S4"].append(i)
        if o["label"] == 0 and o["tier"] == "gate":
            pools["S5"].append(i)
    rnd = random.Random(20261116)
    out = []
    for k, ids in pools.items():
        ids.sort()
        rnd.shuffle(ids)
        used, taken = set(), 0
        for i in ids:
            if taken >= N[k]:
                break
            if tags[i]["site"] in used:
                continue
            used.add(tags[i]["site"])
            taken += 1
            out.append({"stratum": k, "pool": len(ids), "id": i, "label": ours[i]["label"], "tier": ours[i]["tier"], "final": ours[i]["final"], **snaps[i]})
    with open(HERE / ".hasil/eyecheck-todo.jsonl", "w", encoding="utf-8") as f:
        for r in out:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print({k: (len(v), sum(1 for x in out if x["stratum"] == k)) for k, v in pools.items()})


if __name__ == "__main__":
    main()
