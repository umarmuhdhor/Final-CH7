"""Step 1c (v7): fresh/.hasil/pages.jsonl (fresh.mjs) -> fresh/.hasil/sample-input.jsonl for build-rows.mjs.

Usage: python3 -I fresh_sample.py
Same rules as sample.py: only pages that opened with content and stayed on their host. Tag group = Alief's split of the site
(train / dev / test / unseen), because his feed of 2026-11-09 overlaps his own training data.
"""
import json
import collections
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sample import alief_sites, host_of, site  # noqa: E402

F = HERE / "fresh/.hasil"


def main():
    sites = alief_sites()
    out, skipped = [], collections.Counter()
    for line in open(F / "pages.jsonl", encoding="utf-8"):
        d = json.loads(line)
        if d["keadaan"] != "ok":
            skipped[d["keadaan"]] += 1
            continue
        if d.get("pindah_host"):
            skipped["moved_to_other_host"] += 1
            continue
        url = d["final_url"]
        host = host_of(url)
        g = next((k for k in ("train", "dev", "test") if site(host) in sites[k]), "unseen")
        snap = {"url": url, "domain": host, "title": d["title"], "text": d["text"], "forms": d["forms"], "imageAlts": d.get("imageAlts") or []}
        out.append({"id": "fr_" + d["id"], "dataset": d["sumber"], "label": 1 if d["label"] == "scam" else 0, "url": url, "snapshot": snap,
                    "her_stored": None, "tags": {"group": g, "sumber": d["sumber"], "kategori": d.get("kategori") or "", "site": site(host)}})
    with open(F / "sample-input.jsonl", "w", encoding="utf-8") as f:
        for r in out:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    meta = {"kept": len(out), "skipped": dict(skipped),
            "kept_by": {f"{s}|{g}|{'scam' if y else 'legit'}": n for (s, g, y), n in sorted(collections.Counter((r["dataset"], r["tags"]["group"], r["label"]) for r in out).items())}}
    json.dump(meta, open(F / "sample-meta.json", "w"), indent=1)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main()
