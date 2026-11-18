"""Iteration 1: new cut-offs for Indonesian pages. The model stays the same; only the Indonesian thresholds change.

Why: train.py sets each language group's cut-offs from legit DEV pages. Alief's dev split holds only 30 legit Indonesian pages
(20 legit_top + 10 legit_tail, all easy). With 30 pages the 0.5% and 2% cut-offs are simply the highest score, so on real
Indonesian legit pages ours flagged 29% at warn or block (test-layer3 v7). The other group ("other") is not touched.

Calibration set (legit Indonesian pages our model never trained on, and never used in any evaluation below):
  A. Imelda's phishing-url dataset v4, train + dev splits (v6 tested only its test split), sites in Alief's train/dev removed
  B. Alief's test split, Indonesian legit pages whose site hashes to half "A"
Evaluation (old vs new cut-offs, popular top 1000 on in both):
  - Alief's test split, Indonesian pages, half "B" legit + every Indonesian scam page
  - phishing-url v4 test split (the v6 pages), Indonesian pages
  - test-layer3 v7: Kaggle pages and the fresh feed (Indonesian pages)

Usage (from this folder, lab environment):
  uv run --python 3.12 --project ../shoo-layer3-lab python idcal.py prep
  node ../Final-CH7/ai/test-layer3/v5-2026-11-13-compare-alief-l3/build-rows.mjs "$PWD/iter1-idcal"
  uv run ... python apply.py --variant impersonation --rows iter1-idcal/.hasil/rows.jsonl --tag idcal-v4
  uv run ... python apply.py --variant impersonation --rows iter1-idcal/alief-test-indo.jsonl --tag idcal-alieftest
  uv run ... python apply.py --variant impersonation --rows <v6 rows.jsonl> --tag idcal-v6
  uv run ... python idcal.py fit
Writes only new files: iter1-idcal/*, out/impersonation/thresholds-idcal.json, iter1-idcal/report.md
"""
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

import numpy as np

import train as T
from popular import Popular

HERE = Path(__file__).resolve().parent
OUT = HERE / "iter1-idcal"
AI = Path.home() / "Documents/Swift/Final-CH/Final-CH7/ai"
V4 = AI / "test-layer3/v4-2026-11-12-phishing-url/dataset"
V6 = AI / "test-layer3/v6-2026-11-13-compare-phishing-url-test/.hasil/rows.jsonl"
V7 = AI / "test-layer3/v7-2026-11-16-impersonation-new-data"
APPLIED = HERE / "out/impersonation"


def half(site):
    return "A" if hashlib.sha256(site.encode()).digest()[0] % 2 == 0 else "B"


def host_of(url):
    return (urlparse(url if "//" in url else "//" + url).hostname or "").lower()


def prep():
    if (OUT / "alief-test-indo.jsonl").exists():
        raise SystemExit("iter1-idcal already prepared: not overwriting")
    (OUT / ".hasil").mkdir(parents=True, exist_ok=True)
    every = T.load_rows()
    alief_fit = {T.site(r["host"]) for r in every if r["split"] in ("train", "dev")}
    n = {"v4": 0, "v4_dropped_alief_site": 0}
    with open(OUT / ".hasil/sample-input.jsonl", "w", encoding="utf-8") as f:
        for split in ("train", "dev"):
            for line in open(V4 / f"pages-{split}.jsonl", encoding="utf-8"):
                d = json.loads(line)
                row = {"title": d.get("title") or "", "text": d.get("text") or ""}
                if not T.is_indonesian(row):
                    continue
                host = host_of(d["url"])
                if T.site(host) in alief_fit:
                    n["v4_dropped_alief_site"] += 1
                    continue
                snap = {"url": d["url"], "domain": host, "title": row["title"], "text": row["text"], "forms": d.get("forms") or [], "imageAlts": d.get("imageAlts") or []}
                f.write(json.dumps({"id": "v4_" + str(d["id"]), "dataset": f"v4-{split}", "label": int(d["label"]), "url": d["url"], "snapshot": snap, "her_stored": None}, ensure_ascii=False) + "\n")
                n["v4"] += 1
    n["alief_test"] = 0
    with open(OUT / "alief-test-indo.jsonl", "w", encoding="utf-8") as f:
        for r in every:
            if r["split"] != "test" or not T.is_indonesian(r):
                continue
            if r.get("source") == "judol" or (r["label"] == 1 and r.get("scamType") == T.GAMBLING):
                continue  # out of scope, as in train.py
            out = {k: r[k] for k in ("label", "url", "host", "title", "text", "baseline", "feats")}
            out["id"] = "al_" + str(r["id"])
            out["half"] = half(T.site(r["host"]))
            out["source"] = r.get("source", "")
            f.write(json.dumps(out, ensure_ascii=False) + "\n")
            n["alief_test"] += 1
    print(n)


def load(path):
    return [json.loads(line) for line in open(path, encoding="utf-8")]


def finals(tag):
    return {d["id"]: d["final"] for d in load(APPLIED / f"applied-{tag}.jsonl")}


def rates(t, y):
    out = {}
    for lab, name in ((1, "scam"), (0, "legit")):
        m = y == lab
        k = int(m.sum())
        out[name] = (k, int((t[m] != "safe").sum()), int(np.isin(t[m], ("warn", "block")).sum()), int((t[m] == "block").sum()))
    return out


def fmt(r):
    def p(a, b):
        return f"{a} ({f'{100 * a / b:.1f}'.replace('.', ',')}%)" if b else "-"
    s, l = r["scam"], r["legit"]
    return f"{s[0]} | {p(s[1], s[0])} | {p(s[2], s[0])} | {p(s[3], s[0])} | {l[0]} | {p(l[1], l[0])} | {p(l[2], l[0])} | {p(l[3], l[0])}"


def fit():
    import joblib
    sys.modules["__main__"].Judges = T.Judges
    model = joblib.load(APPLIED / "model.joblib")
    old = model["thresholds"]["final"]
    P = Popular(1000)
    if (APPLIED / "thresholds-idcal.json").exists():
        raise SystemExit("out/impersonation/thresholds-idcal.json exists: not overwriting")

    v4 = load(OUT / ".hasil/rows.jsonl")
    al = load(OUT / "alief-test-indo.jsonl")
    f_v4, f_al, f_v6 = finals("idcal-v4"), finals("idcal-alieftest"), finals("idcal-v6")
    calib = [f_v4[r["id"]] for r in v4 if r["label"] == 0 and not r["feats"].get("official") and not P.is_popular(r["host"])]
    n_v4 = len(calib)
    calib += [f_al[r["id"]] for r in al if r["label"] == 0 and r["half"] == "A" and not r["feats"].get("official") and not P.is_popular(r["host"])]
    calib = np.array(calib)
    new_id = {t: T.threshold_at_fpr(calib, f) for t, f in T.TIERS}
    new = {"indonesian": new_id, "other": old["other"]}
    json.dump({"final": new, "calibration_pages": len(calib), "from_phishing_url_v4": n_v4, "from_alief_test_half_A": len(calib) - n_v4,
               "source": "idcal.py: legit Indonesian, not official, not popular top 1000", "old_indonesian": old["indonesian"]},
              open(APPLIED / "thresholds-idcal.json", "w"), indent=1)

    def tiers(rows, fin, th):
        f = np.array([fin[r["id"]] for r in rows])
        indo = np.array([T.is_indonesian(r) for r in rows])
        off = np.array([bool(r["feats"].get("official")) or P.is_popular(r["host"]) for r in rows])
        return T.tier_names(f, indo, off, th), np.array([r["label"] for r in rows])

    sets = []
    sets.append(("Test split Alief, Indonesia (legit separuh B, semua scam)", [r for r in al if r["label"] == 1 or r["half"] == "B"], f_al))
    sets.append(("phishing-url v4 test (halaman v6), Indonesia", [r for r in load(V6) if T.is_indonesian(r)], f_v6))
    sets.append(("v7 Kaggle, Indonesia", [r for r in load(V7 / ".hasil/rows.jsonl") if T.is_indonesian(r)], finals("v7")))
    fr_rows = [r for r in load(V7 / "fresh/.hasil/rows.jsonl") if T.is_indonesian(r)]
    sets.append(("v7 link segar (feed Alief + manual), Indonesia, semua kelompok", fr_rows, finals("v7-fresh")))
    tags = {}
    for line in open(V7 / "fresh/.hasil/sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        tags[d["id"]] = d["tags"]["group"]
    sets.append(("v7 link segar, Indonesia, hanya unseen", [r for r in fr_rows if tags[r["id"]] == "unseen"], finals("v7-fresh")))

    L = ["# Iterasi 1: ambang bahasa Indonesia", "",
         "_Dibuat oleh `idcal.py fit`. Model tidak dilatih ulang: hanya ambang kelompok `indonesian` yang diganti. Ambang `other` tetap._", "",
         "## Ambang", "",
         f"Kalibrasi: **{len(calib)}** halaman legit Indonesia ({n_v4} dari phishing-url v4 train+dev, {len(calib) - n_v4} dari separuh A test split Alief), "
         "bukan host resmi, bukan popular 1.000. Target sama: 15% / 2% / 0,5% sampai gate / warn / block.", "",
         "| | gate | warn | block |", "|---|---|---|---|",
         f"| Lama (30 halaman dev Alief) | {old['indonesian']['gate']:.4f} | {old['indonesian']['warn']:.4f} | {old['indonesian']['block']:.4f} |",
         f"| **Baru** | {new_id['gate']:.4f} | {new_id['warn']:.4f} | {new_id['block']:.4f} |",
         f"| Bahasa lain (tetap) | {old['other']['gate']:.4f} | {old['other']['warn']:.4f} | {old['other']['block']:.4f} |", "",
         "## Hasil (popular 1.000 aktif di keduanya, halaman Indonesia saja)", ""]
    for name, rows, fin in sets:
        t_old, y = tiers(rows, fin, {"indonesian": old["indonesian"], "other": old["other"]})
        t_new, _ = tiers(rows, fin, new)
        L += [f"### {name}", "", "| Ambang | Scam | sampai L4 | warn/block | block | Legit | sampai L4 | warn/block | block |", "|---|---|---|---|---|---|---|---|---|",
              f"| Lama | {fmt(rates(t_old, y))} |", f"| **Baru** | {fmt(rates(t_new, y))} |", ""]
    (OUT / "report.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L))


# fit2: two fixes found while reading the top-scoring calibration pages of `fit`.
# 1. train.is_indonesian() also fires on Italian, Turkish and French pages ("di" alone passes the 4% share). Those pages then get
#    the Indonesian cut-offs. indo_group() keeps a page in the Indonesian group only when it has more Indonesian words than common
#    Italian / French / Turkish / Spanish / Portuguese / English function words. The model's own `indo` input is NOT changed.
# 2. Some "legit" calibration pages are gambling or porn (label noise). They are left out of the calibration set.
FOREIGN = set(("il la le lo gli della delle dei del per che non una sono con come più les des et est pour vous nous avec sur dans une "
               "ve bir için ile olan daha veya en el los las que para por com não uma das dos the and of to is are for with this").split())
ADULT_GAMBLING = re.compile(r"\b(judi|slot|togel|gacor|maxwin|toto|bokep|live draw|casino|kasino|bandar|sbobet|jackpot|4d|porn|sex)\b", re.I)


def indo_group(r):
    if not T.is_indonesian(r):
        return False
    w = re.findall(r"[a-zçğıöşüàèéìòù]+", (r["title"] + " " + r["text"][:4000]).lower())
    return sum(x in T.ID_WORDS for x in w) > sum(x in FOREIGN for x in w)


def fit2():
    import joblib
    sys.modules["__main__"].Judges = T.Judges
    model = joblib.load(APPLIED / "model.joblib")
    old = model["thresholds"]["final"]
    P = Popular(1000)
    if (APPLIED / "thresholds-idcal2.json").exists():
        raise SystemExit("out/impersonation/thresholds-idcal2.json exists: not overwriting")
    v4 = load(OUT / ".hasil/rows.jsonl")
    al = load(OUT / "alief-test-indo.jsonl")
    f_v4, f_al, f_v6 = finals("idcal-v4"), finals("idcal-alieftest"), finals("idcal-v6")

    def calib_ok(r):
        return r["label"] == 0 and indo_group(r) and not r["feats"].get("official") and not P.is_popular(r["host"]) \
            and not ADULT_GAMBLING.search((r["title"] or "") + " " + r["text"][:3000])

    c_v4 = [f_v4[r["id"]] for r in v4 if calib_ok(r)]
    c_al = [f_al[r["id"]] for r in al if r["half"] == "A" and calib_ok(r)]
    calib = np.array(c_v4 + c_al)
    new_id = {t: T.threshold_at_fpr(calib, f) for t, f in T.TIERS}
    new = {"indonesian": new_id, "other": old["other"]}
    json.dump({"final": new, "group_rule": "idcal.indo_group (is_indonesian AND more Indonesian words than foreign function words)",
               "calibration_pages": len(calib), "from_phishing_url_v4": len(c_v4), "from_alief_test_half_A": len(c_al),
               "old_indonesian": old["indonesian"]}, open(APPLIED / "thresholds-idcal2.json", "w"), indent=1)

    def tiers(rows, fin, th, group):
        f = np.array([fin[r["id"]] for r in rows])
        indo = np.array([group(r) for r in rows])
        off = np.array([bool(r["feats"].get("official")) or P.is_popular(r["host"]) for r in rows])
        return T.tier_names(f, indo, off, th), np.array([r["label"] for r in rows])

    tags = {}
    for line in open(V7 / "fresh/.hasil/sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        tags[d["id"]] = d["tags"]["group"]
    fr = [r for r in load(V7 / "fresh/.hasil/rows.jsonl") if T.is_indonesian(r)]
    sets = [("Test split Alief (legit separuh B, semua scam)", [r for r in al if r["label"] == 1 or r["half"] == "B"], f_al),
            ("phishing-url v4 test (halaman v6)", [r for r in load(V6) if T.is_indonesian(r)], f_v6),
            ("v7 Kaggle", [r for r in load(V7 / ".hasil/rows.jsonl") if T.is_indonesian(r)], finals("v7")),
            ("v7 link segar, semua kelompok", fr, finals("v7-fresh")),
            ("v7 link segar, hanya unseen", [r for r in fr if tags[r["id"]] == "unseen"], finals("v7-fresh"))]
    old_th = {"indonesian": old["indonesian"], "other": old["other"]}
    L = ["# Iterasi 1b: ambang Indonesia + detektor bahasa yang diperbaiki", "",
         "_Dibuat oleh `idcal.py fit2`. Model tidak dilatih ulang. Yang berubah hanya: (1) halaman mana yang masuk kelompok Indonesia, "
         "(2) ambang kelompok itu. Ambang bahasa lain tetap._", "",
         "## Kenapa ada 1b", "",
         "Saat membaca halaman legit dengan skor tertinggi di kalibrasi `fit`, banyak yang ternyata halaman Italia, Turki, dan Prancis "
         "(`is_indonesian` lolos hanya karena kata \"di\"), ditambah halaman judi/porno yang berlabel legit. Keduanya mendorong ambang terlalu tinggi.", "",
         "## Ambang", "",
         f"Kalibrasi: **{len(calib)}** halaman legit Indonesia ({len(c_v4)} phishing-url v4 train+dev, {len(c_al)} separuh A test split Alief): "
         "lolos `indo_group`, bukan host resmi, bukan popular 1.000, tanpa kata judi/porno. Target 15% / 2% / 0,5%.", "",
         "| | gate | warn | block |", "|---|---|---|---|",
         f"| Lama (30 halaman dev Alief) | {old['indonesian']['gate']:.4f} | {old['indonesian']['warn']:.4f} | {old['indonesian']['block']:.4f} |",
         f"| **Baru (1b)** | {new_id['gate']:.4f} | {new_id['warn']:.4f} | {new_id['block']:.4f} |",
         f"| Bahasa lain (tetap) | {old['other']['gate']:.4f} | {old['other']['warn']:.4f} | {old['other']['block']:.4f} |", "",
         "## Hasil pada halaman yang dulu dianggap Indonesia (popular 1.000 aktif)", "",
         "- **Sekarang**: detektor lama + ambang lama (yang terpasang di model).",
         "- **Detektor baru saja**: halaman Italia/Turki/dll pindah ke ambang bahasa lain, ambang Indonesia tetap lama.",
         "- **1b**: detektor baru + ambang Indonesia baru.", ""]
    for name, rows, fin in sets:
        L += [f"### {name}", "", "| Versi | Scam | sampai L4 | warn/block | block | Legit | sampai L4 | warn/block | block |", "|---|---|---|---|---|---|---|---|---|"]
        for vname, th, g in (("Sekarang", old_th, T.is_indonesian), ("Detektor baru saja", old_th, indo_group), ("**1b**", new, indo_group)):
            t, y = tiers(rows, fin, th, g)
            L.append(f"| {vname} | {fmt(rates(t, y))} |")
        L.append("")
    (OUT / "report2.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L))


if __name__ == "__main__":
    {"prep": prep, "fit": fit, "fit2": fit2}[sys.argv[1]]()
