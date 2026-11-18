"""Step 1 (v7): every opened maliciousphish page -> PageSnapshot rows for build-rows.mjs.

Usage: python3 -I sample.py
Reads (read-only):
  A  ../../test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/database-link-label.csv   (Imelda's link list + labels)
  B  ../../test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/train-page.jsonl          (saved page snapshots, same ids)
  C  ~/Documents/dataset/out/{pages,extra,extra2}.jsonl   (Alief's training data: only site + split are read)
  D  ../v5-2026-11-13-compare-alief-l3/.hasil/sample-input.jsonl   (ids already used in v5)
Writes: .hasil/sample-input.jsonl, .hasil/sample-meta.json

Difference from v5: no per-class cap of 2000. Every page that opened with content and stayed on its host is scored.
Each row carries tags so the report can cut it several ways: group (unseen / seen-by-alief), in_v5, site_rank (1st, 2nd, ...
page of its site in a fixed shuffle, so a site cap can be applied later), cek_manual (Imelda's hand check, if any).
No page is opened here. Links are never visited.
"""
import csv
import json
import random
import re
import collections
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
AI = HERE.parent.parent
SRC = AI / "test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil"
ALIEF_OUT = Path.home() / "Documents/dataset/out"
V5 = AI / "test-layer3/v5-2026-11-13-compare-alief-l3/.hasil/sample-input.jsonl"
SEED = 20261116
SECOND_LEVEL = re.compile(r"^(co|go|ac|or|web|sch|my|biz|net|com|org|gov|edu|mil|desa|ponpes)\.[a-z]{2}$")


def site(host):
    p = (host or "").lower().removeprefix("www.").split(".")
    return ".".join(p[-3:] if SECOND_LEVEL.match(".".join(p[-2:])) else p[-2:])


def host_of(url):
    return (urlparse(url if "//" in url else "//" + url).hostname or "").lower()


def alief_sites():
    seen = collections.defaultdict(set)
    for name in ("pages", "extra", "extra2"):
        for line in open(ALIEF_OUT / f"{name}.jsonl", encoding="utf-8"):
            r = json.loads(line)
            seen[r["split"]].add(site(r["host"]))
    return seen


def main():
    links = {r["id"]: r for r in csv.DictReader(open(SRC / "database-link-label.csv", encoding="utf-8"))}
    v5_ids = {json.loads(line)["id"] for line in open(V5, encoding="utf-8")}
    sites = alief_sites()
    blocked = sites["train"] | sites["dev"]
    meta = {"seed": SEED, "csv_links": len(links), "csv_label": dict(collections.Counter(r["label"] for r in links.values())),
            "csv_halaman": dict(collections.Counter(r["halaman"] for r in links.values())), "skipped": collections.Counter()}
    rows = []
    for line in open(SRC / "train-page.jsonl", encoding="utf-8"):
        d = json.loads(line)
        lid = str(d["id"])
        link = links.get(lid)
        if link is None:
            meta["skipped"]["not_in_csv"] += 1
            continue
        if d["keadaan"] != "ok":
            meta["skipped"]["empty_page"] += 1
            continue
        if d.get("pindah_host"):
            meta["skipped"]["moved_to_other_host"] += 1
            continue
        url = d.get("final_url") or d["url"]
        if "//" not in url:
            url = "http://" + url
        host = host_of(url)
        snap = {"url": url, "domain": host, "title": d["title"], "text": d["text"], "forms": d["forms"], "imageAlts": d.get("imageAlts") or []}
        label = 1 if link["label"] == "scam" else 0
        rows.append({"id": "mp_" + lid, "dataset": "maliciousphish", "label": label, "url": url, "snapshot": snap, "her_stored": None,
                     "tags": {"group": "seen-by-alief" if site(host) in blocked else "unseen", "in_v5": ("mp_" + lid) in v5_ids,
                              "site": site(host), "shared_host": link["shared_host"], "cek_manual": link["cek_manual"], "sumber": link["sumber"]}})
    rnd = random.Random(SEED)
    rnd.shuffle(rows)
    rank = collections.Counter()
    for r in rows:
        rank[r["tags"]["site"]] += 1
        r["tags"]["site_rank"] = rank[r["tags"]["site"]]
    meta["skipped"] = dict(meta["skipped"])
    meta["kept"] = len(rows)
    meta["kept_by"] = {f"{g}|{'scam' if y else 'legit'}|in_v5={v}": n for (g, y, v), n in sorted(collections.Counter(
        (r["tags"]["group"], r["label"], r["tags"]["in_v5"]) for r in rows).items())}
    meta["sites"] = len(rank)
    out = HERE / ".hasil"
    out.mkdir(exist_ok=True)
    with open(out / "sample-input.jsonl", "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    json.dump(meta, open(out / "sample-meta.json", "w"), indent=1)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main()
