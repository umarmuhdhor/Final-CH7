"""v7 extra, iteration 3 check: does reading the RENDERED page (what the Safari extension sees) change v3f?

Pages: every page that v2 flags (warn/block) but v3f drops to gate because it makes no claim, in the fresh feed, the 1,500 Kaggle
legit sample, the Indonesian legit calibration set, plus 150 seeded-random such pages from the 17,410 Kaggle unseen legit set.
Their saved text came from one static GET; some kits (the Pinterest clones) are empty until JavaScript runs.

Usage (lab environment):
  cd ~/Documents/Swift/Final-CH/shoo-impersonation-lab
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/render_check.py prep     -> .hasil/render/todo.jsonl
  node <this folder>/render_fetch.mjs                                                                 -> .hasil/render/rendered.jsonl
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/render_check.py report   -> RENDER.md
Claim on the rendered page = the v3f claim rules on rendered title+text, plus a brand name from detector/data/brands.json
(main + the 4 new brands of branch feat/brands-games) in the rendered title/text on a host that is not that brand's own domain.
"""
import json
import random
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
BRANDS = Path.home() / "Documents/Swift/Final-CH/Final-CH7-brands/detector/data/brands.json"
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(HERE))
import eval_v3 as E  # noqa: E402
import links_measure as LM  # noqa: E402
import train as T1  # noqa: E402
import train2 as T2  # noqa: E402

OUT = HERE / ".hasil/render"


def setup():
    from popular import Popular
    P = Popular(1000)
    th = json.load(open(E.V2 / "thresholds-idcal.json"))["final"]
    fin, words = {}, {}
    for t in ("v2-idcal-v4", "v2-idcal-alieftest", "v2-v6", "v2-v7", "v2-v7-fresh"):
        for d in E.load(E.V2 / f"applied-{t}.jsonl"):
            fin[d["id"]], words[d["id"]] = d["final"], d["words"]
    chat = {d["id"]: d for d in E.load(HERE / ".hasil/links.jsonl") if d.get("keadaan") == "ok"}

    def v2_tier(r):
        off = bool(r["feats"].get("official")) or P.is_popular(r["host"])
        return T1.tier_names([fin[r["id"]]], [T2.is_indonesian(r)], [off], th)[0]

    def claim_text(r, title, text):
        tx = (title or "") + " " + (text or "")[:4000]
        host = r["host"].lower()
        builder = any(host == b or host.endswith("." + b) for b in E.BUILDERS)
        head = ((title or "") + " " + host).lower()
        return bool(E.LURE.search(tx) or E.CRED.search(tx) or E.ODD_PASS.search(tx)
                    or (builder and E.PASS_LABEL.search(tx) and E.USER_LABEL.search(tx))
                    or any(b in head and not (host == d or host.endswith("." + d)) for b, d in E.EXTRA_BRANDS.items()))

    def v3f(r):
        t = v2_tier(r)
        if t not in ("warn", "block"):
            return t
        c = E.claims(r, chat)
        ok = (c["brand"] or c["ask"] or c["chat"] or claim_text(r, r.get("title"), r.get("text"))
              or (bool(r["feats"].get("passwordField")) and words[r["id"]] >= E.PASS_WORDS))
        return t if ok else "gate"

    return v2_tier, v3f, claim_text


def pages():
    G = {k: [E.norm(r) for r in v] for k, v in LM.groups().items()}
    ktag = {}
    for line in open(HERE / ".hasil/sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        ktag[d["id"]] = d["tags"]["group"]
    kag = [E.norm(r) for r in E.load(HERE / ".hasil/rows.jsonl") if ktag[r["id"]] == "unseen" and int(r["label"]) == 0]
    return {"fresh": G["scam_fresh"] + G["legit_manual"], "legit_kaggle1500": G["legit_kaggle"],
            "legit_indonesian": G["legit_indonesian"], "legit_kaggle17k": kag}


def prep():
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "todo.jsonl"
    if out.exists():
        raise SystemExit("todo.jsonl exists: not overwriting")
    v2_tier, v3f, _ = setup()
    rnd = random.Random(3)
    seen, todo = set(), []
    for name, rows in pages().items():
        dropped = [r for r in rows if v2_tier(r) in ("warn", "block") and v3f(r) == "gate" and r["id"] not in seen]
        if name == "legit_kaggle17k":
            rnd.shuffle(dropped)
            dropped = dropped[:150]
        for r in dropped:
            seen.add(r["id"])
            url = r["url"] if "//" in r["url"] else "http://" + r["url"]
            todo.append({"id": r["id"], "url": url, "set": name, "label": r["label"]})
    with open(out, "w", encoding="utf-8") as f:
        for x in todo:
            f.write(json.dumps(x) + "\n")
    print("pages", len(todo), dict(Counter((x["set"], x["label"]) for x in todo)))


def report():
    _, _, claim_text = setup()
    brands = json.load(open(BRANDS))["brands"]
    todo = E.load(OUT / "todo.jsonl")
    rend = {d["id"]: d for d in E.load(OUT / "rendered.jsonl")}
    rows = {r["id"]: r for rows in pages().values() for r in rows}

    def brand_claim(r, title, text):
        host = r["host"].lower()
        tx = ((title or "") + " " + (text or "")[:4000]).lower()
        for b in brands:
            if any(host == d or host.endswith("." + d) for d in b["domains"]):
                continue
            for n in b["names"]:
                if n in b.get("commonNames", []):
                    continue
                if re.search(r"(?<![a-z0-9])" + re.escape(n) + r"(?![a-z0-9])", tx):
                    return b["id"]
        return None

    stats = Counter()
    examples = []
    for x in todo:
        d = rend.get(x["id"], {})
        key = (x["set"], x["label"])
        stats[key + ("pages",)] += 1
        if not d.get("ok"):
            stats[key + ("failed",)] += 1
            continue
        r = rows[x["id"]]
        b = brand_claim(r, d["title"], d["text"])
        c = claim_text(r, d["title"], d["text"])
        if b or c:
            stats[key + ("restored",)] += 1
            examples.append((x["set"], x["label"], b or "kata", r["host"].replace(".", "[.]")[:40], (d["title"] or "")[:50]))
    L = ["# Iterasi 3: cek ulang dengan halaman yang dirender", "",
         "_Dibuat oleh `render_check.py report`. Chrome headless memuat halaman (JavaScript jalan, 8 detik, tanpa klik/ketik), "
         "teks DOM diambil dengan `parseHtml` (sama seperti snapshot eval). HTML tidak disimpan. Halaman = yang ditandai v2 tapi diturunkan "
         "v3f ke `gate` karena tidak ada klaim di teks statis._", "",
         "**Kembali ditandai** = di teks render ada klaim v3f atau nama brand dari `brands.json` (termasuk 4 brand baru) di host yang bukan domain brand itu.", "",
         "| Set | Label | Halaman | Gagal render | Kembali ditandai |", "|---|---|---|---|---|"]
    for name in ("fresh", "legit_kaggle1500", "legit_indonesian", "legit_kaggle17k"):
        for lab in (1, 0):
            n = stats[(name, lab, "pages")]
            if n:
                L.append(f"| {name} | {'scam' if lab else 'legit'} | {n} | {stats[(name, lab, 'failed')]} | {stats[(name, lab, 'restored')]} |")
    L += ["", "## Halaman yang kembali ditandai", "", "| Set | Label | Alasan | Host | Judul render |", "|---|---|---|---|---|"]
    for e in sorted(examples, key=lambda e: (-e[1], e[0])):
        L.append(f"| {e[0]} | {'scam' if e[1] else 'legit'} | {e[2]} | `{e[3]}` | {e[4].replace('|', '/')} |")
    (HERE / "RENDER.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L[:20]))


if __name__ == "__main__":
    {"prep": prep, "report": report}[sys.argv[1]]()
