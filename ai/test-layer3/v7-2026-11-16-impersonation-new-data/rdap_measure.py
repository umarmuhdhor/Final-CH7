"""v7 extra: is domain age (RDAP) a useful no-LLM signal next to our layer 3 model?

Usage (lab environment, because the report step reuses idcal.py from shoo-impersonation-lab):
  cd ~/Documents/Swift/Final-CH/shoo-impersonation-lab
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/rdap_measure.py fetch
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/rdap_measure.py report
fetch : looks up the registration date of each domain below. Only the bare registrable domain is sent, to the registry named in
        IANA's RDAP bootstrap list (same method as shoo-layer3-lab/src/rdap_ages.py). No page is opened. Appends to .hasil/rdap.jsonl
        (safe to stop and rerun). Alief's cache ~/Documents/dataset/data/rdap.jsonl is reused when it has the domain.
report: writes RDAP.md (new file).
Domains:
  scam  : fresh feed (fresh/.hasil/rows.jsonl), scam pages NOT on a shared host (on vercel.app, pages.dev ... the age is the platform's)
  legit : (a) Kaggle unseen legit, 1,500 random sites, fixed seed; (b) legit Indonesian pages of the iteration-1 calibration set;
          (c) the manual safe links
"""
import collections
import datetime as dt
import json
import random
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
sys.path.insert(0, str(LAB))
import idcal as I  # noqa: E402
import train as T  # noqa: E402

OUT = HERE / ".hasil/rdap.jsonl"
ALIEF_CACHE = Path.home() / "Documents/dataset/data/rdap.jsonl"
BOOT = Path.home() / "Documents/dataset/data/lists/rdap_bootstrap.json"
TODAY = dt.date(2026, 11, 16)
SEED = 20261116


def load(p):
    return [json.loads(line) for line in open(p, encoding="utf-8")]


def sets():
    """Return {name: [row]} with rows that carry id, host, label, feats, baseline, title, text."""
    fresh = load(HERE / "fresh/.hasil/rows.jsonl")
    ftag = {d["id"]: d["tags"]["group"] for d in load(HERE / "fresh/.hasil/sample-input.jsonl")}
    kag = load(HERE / ".hasil/rows.jsonl")
    ktag = {}
    for line in open(HERE / ".hasil/sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        ktag[d["id"]] = d["tags"]["group"]
    by_site = {}
    for r in kag:
        if r["label"] == 0 and ktag[r["id"]] == "unseen" and not r["feats"]["sharedHost"]:
            by_site.setdefault(T.site(r["host"]), r)
    keys = sorted(by_site)
    random.Random(SEED).shuffle(keys)
    cal = [r for r in load(LAB / "iter1-idcal/.hasil/rows.jsonl") if r["label"] == 0] + \
          [r for r in load(LAB / "iter1-idcal/alief-test-indo.jsonl") if r["label"] == 0 and r["half"] == "A"]
    return {
        "scam_fresh_unseen": [r for r in fresh if r["label"] == 1 and not r["feats"]["sharedHost"] and ftag[r["id"]] == "unseen"],
        "scam_fresh_seen": [r for r in fresh if r["label"] == 1 and not r["feats"]["sharedHost"] and ftag[r["id"]] != "unseen"],
        "scam_fresh_shared_host": [r for r in fresh if r["label"] == 1 and r["feats"]["sharedHost"]],
        "legit_kaggle_sample": [by_site[k] for k in keys[:1500]],
        "legit_indonesian": [r for r in cal if I.indo_group(r) and not r["feats"]["sharedHost"]],
        "legit_manual": [r for r in fresh if r["label"] == 0 and not r["feats"]["sharedHost"]],
    }


def fetch():
    boot = {}
    for tlds, urls in json.load(open(BOOT))["services"]:
        for t in tlds:
            boot[t.lower()] = urls[0].rstrip("/")
    want = set()
    for name, rows in sets().items():
        if name != "scam_fresh_shared_host":
            want |= {T.site(r["host"]) for r in rows if r["host"] and not r["feats"]["ipHost"]}
    done = {d["domain"] for d in load(OUT)} if OUT.exists() else set()
    cache = {d["domain"]: d for d in load(ALIEF_CACHE)} if ALIEF_CACHE.exists() else {}
    todo = sorted(want - done, key=lambda d: hash(d))  # interleave registries
    print("domains", len(want), "already", len(done), "to do", len(todo), flush=True)

    def lookup(domain):
        if domain in cache and cache[domain]["status"] == "ok":
            return {**cache[domain], "from": "alief_cache"}
        base = boot.get(domain.rsplit(".", 1)[-1])
        if not base:
            return {"domain": domain, "registered": None, "status": "no-rdap"}
        for attempt in range(4):
            try:
                req = urllib.request.Request(f"{base}/domain/{domain}", headers={"Accept": "application/rdap+json", "User-Agent": "rdap-age-lookup"})
                with urllib.request.urlopen(req, timeout=12) as res:
                    data = json.load(res)
                for ev in data.get("events", []):
                    if ev.get("eventAction") == "registration":
                        return {"domain": domain, "registered": ev.get("eventDate"), "status": "ok"}
                return {"domain": domain, "registered": None, "status": "no-date"}
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(8 * (attempt + 1))
                    continue
                return {"domain": domain, "registered": None, "status": f"http-{e.code}"}
            except Exception:
                time.sleep(2)
        return {"domain": domain, "registered": None, "status": "failed"}

    OUT.parent.mkdir(exist_ok=True)
    with open(OUT, "a", encoding="utf-8") as f, ThreadPoolExecutor(8) as pool:
        for i, res in enumerate(pool.map(lookup, todo)):
            f.write(json.dumps(res) + "\n")
            if i % 200 == 0:
                f.flush()
                print(i, flush=True)


def age_days(rec):
    if not rec or rec["status"] != "ok" or not rec["registered"]:
        return None
    return (TODAY - dt.date.fromisoformat(rec["registered"][:10])).days


def report():
    import numpy as np
    from popular import Popular
    ages = {d["domain"]: d for d in load(OUT)}
    th = json.load(open(LAB / "out/impersonation/thresholds-idcal2.json"))["final"]
    P = Popular(1000)
    fin = {}
    for tag in ("v7", "v7-fresh", "idcal-v4", "idcal-alieftest"):
        fin.update(I.finals(tag))

    def tier(r):
        off = bool(r["feats"].get("official")) or P.is_popular(r["host"])
        return T.tier_names([fin[r["id"]]], [I.indo_group(r)], [off], th)[0]

    S = sets()
    L = ["# Umur domain (RDAP) sebagai sinyal tanpa LLM", "",
         "_Dibuat oleh `rdap_measure.py report`. Umur dihitung sampai 2026-11-16. Model: ours impersonation + popular 1.000, ambang iterasi 1b._", "",
         "## Cakupan", "", "| Kelompok | Halaman | Domain | Umur diketahui | Median umur (hari) | < 30 hari | < 90 hari | < 365 hari |", "|---|---|---|---|---|---|---|---|"]
    per = {}
    for name, rows in S.items():
        if name == "scam_fresh_shared_host":
            L.append(f"| {name} | {len(rows)} | (umur platform, tidak dipakai) | - | - | - | - | - |")
            continue
        a = [age_days(ages.get(T.site(r["host"]))) for r in rows]
        per[name] = (rows, a)
        known = [x for x in a if x is not None]
        n = len(known)

        def share(lim):
            k = sum(x < lim for x in known)
            return f"{k} ({round(100 * k / n)}%)" if n else "-"

        L.append(f"| {name} | {len(rows)} | {len({T.site(r['host']) for r in rows})} | {n} | {int(np.median(known)) if n else '-'} | {share(30)} | {share(90)} | {share(365)} |")
    L += ["", "Status RDAP: " + ", ".join(f"`{k}` {v}" for k, v in sorted(collections.Counter(d["status"] for d in ages.values()).items())), ""]

    L += ["## Aturan yang dicoba", "",
          "- **Model saja**: warn/block dari model (tanpa LLM, `gate` dihitung aman).",
          "- **A**: umur < N hari saja sudah warn.",
          "- **B**: model `gate` atau lebih **dan** umur < N hari jadi warn (umur menggantikan LLM untuk halaman `gate`).",
          "- **C**: umur < N hari **dan** ada klaim brand (`brandInHost`, `brandOffsite`, `brandTextOffsite`) atau form sensitif jadi warn.",
          "", "Umur tidak diketahui dihitung tidak muda.", "",
          "| Aturan | N hari | Scam unseen ditandai | Scam seen ditandai | Legit Kaggle ditandai | Legit Indonesia ditandai | Link aman manual ditandai |", "|---|---|---|---|---|---|---|"]

    def flagged(rule, n_days):
        out = {}
        for name, (rows, a) in per.items():
            k = 0
            for r, x in zip(rows, a):
                t = tier(r)
                young = x is not None and x < n_days
                claim = r["feats"]["brandInHost"] or r["feats"]["brandOffsite"] or r["feats"]["brandTextOffsite"] or r["feats"]["passwordField"] \
                    or any(s.startswith("asks_") for s in r["baseline"]["signals"])
                k += bool(t in ("warn", "block") or {"model": False, "A": young, "B": young and t == "gate", "C": young and claim}[rule])
            out[name] = f"{k}/{len(rows)} ({f'{100 * k / len(rows):.1f}'.replace('.', ',')}%)" if rows else "-"
        return out

    for rule, days in [("model", 0)] + [(r, d) for r in ("A", "B", "C") for d in (30, 90, 180, 365)]:
        f = flagged(rule, days)
        L.append(f"| {'Model saja' if rule == 'model' else rule} | {days or '-'} | {f['scam_fresh_unseen']} | {f['scam_fresh_seen']} | {f['legit_kaggle_sample']} | {f['legit_indonesian']} | {f['legit_manual']} |")
    L.append("")
    (HERE / "RDAP.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L))


if __name__ == "__main__":
    {"fetch": fetch, "report": report}[sys.argv[1]]()
