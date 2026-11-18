"""Step 1: freeze the page sample that both layer 3s are scored on.

Usage: python3 -I sample.py
Reads (read-only):
  A  ../v4-2026-11-12-phishing-url/snapshots/*.json                              (Imelda's layer 3 test v4, phishing-url)
  B  ../../test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/train-page.jsonl   (Kaggle malicious_phish)
  C  ~/Documents/dataset/out/{pages,extra,extra2}.jsonl                          (Alief's training data: only the site + split are read)
Writes: .hasil/sample-input.jsonl, .hasil/sample-meta.json

Rules (all written to sample-meta.json):
  - only pages that opened with content (status ok)
  - drop pages that were redirected to a different host: the label belongs to the link, the text to the other site
  - drop pages whose site is in Alief's train or dev split (his model was fitted or tuned on them)
  - at most MAX_PER_SITE pages per site, then at most PER_CLASS pages per label and dataset, fixed seed
"""
import glob
import json
import random
import re
import collections
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
AI = HERE.parent.parent
ALIEF_OUT = Path.home() / "Documents/dataset/out"
SEED, MAX_PER_SITE, PER_CLASS = 20261113, 3, 2000
SECOND_LEVEL = re.compile(r"^(co|go|ac|or|web|sch|my|biz|net|com|org|gov|edu|mil|desa|ponpes)\.[a-z]{2}$")


def site(host):
    p = (host or "").lower().removeprefix("www.").split(".")
    return ".".join(p[-3:] if SECOND_LEVEL.match(".".join(p[-2:])) else p[-2:])


def host_of(url):
    return (urlparse(url if "//" in url else "//" + url).hostname or "").lower()


def alief_sites():
    seen = {"train": set(), "dev": set(), "test": set(), "drop": set()}
    for name in ("pages", "extra", "extra2"):
        for line in open(ALIEF_OUT / f"{name}.jsonl", encoding="utf-8"):
            r = json.loads(line)
            seen[r["split"]].add(site(r["host"]))
    return seen


def load_a():
    out = []
    for f in glob.glob(str(AI / "test-layer3/v4-2026-11-12-phishing-url/snapshots/*.json")):
        d = json.load(open(f, encoding="utf-8"))
        if d["status"] != "ok" or d.get("movedHost"):
            continue
        s = d["snapshot"]
        out.append({"id": "pu_" + d["id"], "dataset": "phishing-url", "label": 1 if d["label"] == "scam" else 0, "url": s["url"], "snapshot": s,
                    "her_stored": {"score": d["l3"]["score"], "scoreNoAge": d["l3"]["scoreNoAge"], "signals": [x["id"] if isinstance(x, dict) else x for x in d["l3"]["signals"]]}})
    return out


def load_b():
    out = []
    path = AI / "test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/train-page.jsonl"
    for line in open(path, encoding="utf-8"):
        d = json.loads(line)
        if d["keadaan"] != "ok" or d.get("pindah_host"):
            continue
        url = d.get("final_url") or d["url"]
        if "//" not in url:
            url = "http://" + url
        snap = {"url": url, "domain": host_of(url), "title": d["title"], "text": d["text"], "forms": d["forms"], "imageAlts": d.get("imageAlts") or []}
        out.append({"id": "mp_" + str(d["id"]), "dataset": "maliciousphish", "label": 1 if d["label"] == "scam" else 0, "url": url, "snapshot": snap, "her_stored": None})
    return out


def main():
    rnd = random.Random(SEED)
    sites = alief_sites()
    blocked = sites["train"] | sites["dev"]
    meta = {"seed": SEED, "max_per_site": MAX_PER_SITE, "per_class": PER_CLASS, "alief_train_sites": len(sites["train"]), "alief_dev_sites": len(sites["dev"]), "datasets": {}}
    final = []
    for name, rows in (("phishing-url", load_a()), ("maliciousphish", load_b())):
        info = {"opened_not_moved": len(rows)}
        info["by_label_opened"] = dict(collections.Counter(r["label"] for r in rows))
        kept = [r for r in rows if site(host_of(r["url"])) not in blocked]
        info["after_removing_alief_train_dev_sites"] = {"pages": len(kept), "by_label": dict(collections.Counter(r["label"] for r in kept))}
        rnd.shuffle(kept)
        per_site, capped = collections.Counter(), []
        for r in kept:
            s = site(host_of(r["url"]))
            if per_site[s] < MAX_PER_SITE:
                per_site[s] += 1
                capped.append(r)
        info["after_site_cap"] = {"pages": len(capped), "by_label": dict(collections.Counter(r["label"] for r in capped))}
        chosen = []
        for label in (1, 0):
            chosen += [r for r in capped if r["label"] == label][:PER_CLASS]
        info["sampled"] = {"pages": len(chosen), "scam": sum(r["label"] for r in chosen), "legit": sum(1 - r["label"] for r in chosen), "sites": len({site(host_of(r["url"])) for r in chosen})}
        meta["datasets"][name] = info
        final += chosen
    out = HERE / ".hasil"
    out.mkdir(exist_ok=True)
    with open(out / "sample-input.jsonl", "w", encoding="utf-8") as f:
        for r in final:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    json.dump(meta, open(out / "sample-meta.json", "w"), indent=1)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main()
