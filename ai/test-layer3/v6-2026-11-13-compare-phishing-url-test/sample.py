"""Step 1: the test split of the phishing-url dataset, ready for build-rows.mjs.

Usage: python3 -I sample.py
Reads (read-only):
  ../v4-2026-11-12-phishing-url/dataset/pages-test.jsonl   test split made earlier: no site and no phishing kit is in two splits
  ~/Documents/dataset/out/{pages,extra,extra2}.jsonl         Alief's training data: only the site and split are read
Writes .hasil/sample-input.jsonl and .hasil/sample-meta.json.

Every test page is kept. A page whose site is in Alief's train or dev split gets dataset "seen-by-alief" (his model was fitted or
tuned on that site), all others get "unseen". Reports show both, and "unseen" is the fair comparison.
"""
import collections
import json
import re
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
PAGES = HERE.parent / "v4-2026-11-12-phishing-url/dataset/pages-test.jsonl"
ALIEF_OUT = Path.home() / "Documents/dataset/out"
SECOND_LEVEL = re.compile(r"^(co|go|ac|or|web|sch|my|biz|net|com|org|gov|edu|mil|desa|ponpes)\.[a-z]{2}$")


def site(host):
    p = (host or "").lower().removeprefix("www.").split(".")
    return ".".join(p[-3:] if SECOND_LEVEL.match(".".join(p[-2:])) else p[-2:])


def host_of(url):
    return (urlparse(url if "//" in url else "//" + url).hostname or "").lower()


def alief_seen_sites():
    seen = set()
    for name in ("pages", "extra", "extra2"):
        for line in open(ALIEF_OUT / f"{name}.jsonl", encoding="utf-8"):
            r = json.loads(line)
            if r["split"] in ("train", "dev"):
                seen.add(site(r["host"]))
    return seen


def main():
    seen = alief_seen_sites()
    out_dir = HERE / ".hasil"
    out_dir.mkdir(exist_ok=True)
    counts = collections.Counter()
    skipped = 0
    with open(out_dir / "sample-input.jsonl", "w", encoding="utf-8") as f:
        for line in open(PAGES, encoding="utf-8", errors="replace"):
            d = json.loads(line)
            host = host_of(d["url"])
            if not host:
                skipped += 1
                continue
            group = "seen-by-alief" if site(host) in seen else "unseen"
            counts[(group, d["label"])] += 1
            snap = {"url": d["url"], "domain": host, "title": d["title"], "text": d["text"], "forms": d["forms"], "imageAlts": d.get("imageAlts") or []}
            f.write(json.dumps({"id": "t_" + d["id"], "dataset": group, "label": d["label"], "url": d["url"], "snapshot": snap, "her_stored": None}, ensure_ascii=False) + "\n")
    meta = {"source": str(PAGES.relative_to(HERE.parent)), "alief_train_dev_sites": len(seen), "skipped_no_host": skipped,
            "pages": {g: {"scam": counts[(g, 1)], "legit": counts[(g, 0)]} for g in ("unseen", "seen-by-alief")}}
    json.dump(meta, open(out_dir / "sample-meta.json", "w"), indent=1)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main()
