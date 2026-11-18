"""Iteration 3: cut false flags on legit login pages and official sites on free hosting, without an LLM and without retraining.

Finding from the v7 eye-check (50 flagged pages): most legit pages that v2 flags have a high ADDRESS score (shared host, random
subdomain) and a low WORDS score, and make no claim at all: no brand, no OTP/PIN/KTP/card ask, no prize/bansos/CS words, no chat
link. Real impersonation pages almost always make one of those claims. So v3 = v2 tiers + a "claim" gate:
  warn/block stay only when the page makes a claim; otherwise the page drops to gate (no banner without an LLM).

Variants:
  v2      model v2 as is (popular 1000, outside-calibrated Indonesian cut-offs).
  v3a     claim = brand (title/text/host/offsite logo) or sensitive ask (OTP, PIN, KTP, CVV, card, selfie+KTP) or lure words.
  v3b     v3a, or chat link (t.me / wa.me) found on the page (only known for pages fetched by links_fetch.mjs).
  v3c     v3b, and a page with no claim but a high WORDS score (>= 0.5) keeps its tier (the text itself reads like a scam).
  v3d-f   see the report header below.
  v3g     v3f with two leaks fixed (FP-ANALISIS.md in the v7 folder):
          A: a brand found only in the page text (footer "Follow us on Facebook") counts only when the page has a form
             (password field, or a form with at least 2 fields) or a strong lure word. Brand in title, host or offsite logo still counts.
          B: lure words narrowed to scam phrases and strong Indonesian words; generic shop/insurance words dropped.
  v3g+umur  v3g, and a page on its own domain (not a shared host, not official/popular) registered < 30 days ago is at least warn.
            Age comes from the v7 RDAP lookups (.hasil/rdap.jsonl); unknown age = not young.

Usage: uv run --python 3.12 --project ../shoo-layer3-lab python eval_v3.py [--model impersonation-v2] [--kaggle-half all|B] [--report eval-v3g.md]
  --model       model folder under out/ with applied-*.jsonl and thresholds-idcal.json (v2 files carry a "v2-" tag prefix).
  --kaggle-half B keeps only Kaggle pages whose site is in train3.kaggle_half "B" (never trained on by impersonation-smallbiz),
                in the Kaggle sets and in the eye-check, so v2 and smallbiz are compared on the same held-out pages.
Writes out/impersonation-v3/<report> (new file, refuses to overwrite; eval.md of the earlier run is kept). Model files are not changed.
"""
import argparse
import ast
import json
import re
import sys
from pathlib import Path

import numpy as np  # noqa: F401

import idcal as I
import train as T1
import train2 as T2
from popular import Popular

HERE = Path(__file__).resolve().parent
V2 = HERE / "out/impersonation-v2"
OUT = HERE / "out/impersonation-v3"
V7 = I.V7
EYE = V7 / ".hasil/eyecheck50"
sys.path.insert(0, str(V7))
import links_measure as LM  # noqa: E402

BRAND_FEATS = ("brandsInTitle", "brandsInText", "brandInHost", "brandOffsite", "brandTextOffsite")
ASKS = {"asks_otp", "asks_pin", "asks_ktp", "asks_cvv", "asks_card", "asks_selfie_ktp", "brand_logo_offsite"}
LURE = re.compile(r"klaim|hadiah|bansos|bantuan sosial|subsidi|undian|pemenang|pencairan|refund|pembatalan|verifikasi|aktivasi|diblokir|"
                  r"blokir|call center|customer service|\bcs\b|pinjaman|investasi|profit|saldo|dana gratis|menang|giveaway|gratis|"
                  r"prize|winner|congratulations|claim|reward|verify your|account (is )?(locked|suspended)|unusual activity", re.I)
WORDS_KEEP = 0.5
# v3d: credential-phishing words that carry no brand name Shoo's brand list knows (webmail kits, Microsoft/Office clones, wallets).
CRED = re.compile(r"\b(webmail|mailbox|e-?mail password|sign in to (your account|continue)|secured? login|login session|"
                  r"shared (a |the )?(document|file)|view (the )?document|onedrive|sharepoint|office ?365|outlook|microsoft|docusign|"
                  r"seed phrase|recovery phrase|metamask|"
                  r"don.t recognize (you|your device)|incorrect (e-?mail|password)|account verification|update your (account|payment))\b", re.I)
PASS_WORDS = 0.75
# v3e: credential forms built with site builders, and password labels spelled to dodge filters (Passvvord, P@ssw0rd, Pαssword, WebmaiI).
BUILDERS = ("weebly.com", "ubpages.com", "godaddysites.com", "wixsite.com", "jimdosite.com", "square.site", "mystrikingly.com",
            "sites.google.com", "webflow.io", "carrd.co", "site123.me", "yolasite.com")
PASS_LABEL = re.compile(r"password|passcode|kata (sandi|laluan)|mot de passe|contrase[nñ]a|senha|passwort|parola|wachtwoord|密码|密碼|пароль", re.I)
USER_LABEL = re.compile(r"e-?mail|user ?(name|id)|username|identifiant|usuario|utente|nome utente|login", re.I)
# v3f: brands missing from Shoo's brand list that the v7 eye-check found (title or host only; official sites excluded).
EXTRA_BRANDS = {"roblox": "roblox.com", "garena": "garena.com", "free fire": "garena.com", "xfinity": "xfinity.com", "pinterest": "pinterest.com"}
ODD_PASS = re.compile(r"\bp(?!assword\b)[a@äαàá4][s$5ѕ][s$5ѕ*][wvｗ]{1,2}[o0οø*][r][d]\b|\bpassvvord\b|\bwebmai[I1]\b|\bpasswrd\b", re.I)
# v3g (A): brand seen only in body text needs a form or a strong lure to count; brand in title/host/offsite logo counts as before.
BRAND_STRONG = ("brandsInTitle", "brandInHost", "brandOffsite")
BRAND_TEXT = ("brandsInText", "brandTextOffsite")
# v3g (B): narrowed lure words. Dropped: claim (English), reward, refund, profit, customer service, cs, gratis, saldo, menang,
# verifikasi, aktivasi, blokir, pinjaman, investasi, subsidi, giveaway, prize, winner (all common on legit shops/insurers/banks).
# Indonesian "klaim" and "pemenang" stay: dropping them lost 6 real Indonesian prize scams on the fresh feed (M-KIOS, Telkomsel, cek tunai).
LURE_B = re.compile(r"\bklaim\b|pemenang|hadiah|undian|bansos|bantuan sosial|pencairan|pembatalan|call center|"
                    r"claim (your|now)|you have won|congratulations|verify your|account (is )?(locked|suspended)|unusual activity", re.I)
REPORT = "eval-v3g.md"
AGE_DAYS = 30


def load(p):
    return [json.loads(line) for line in open(p, encoding="utf-8")]


def as_dict(x):
    return x if isinstance(x, dict) else ast.literal_eval(x)


def norm(r):
    return dict(r, feats=as_dict(r["feats"]), baseline=as_dict(r["baseline"]), label=int(r["label"]))


def claims(r, chat):
    f = r["feats"]
    c = chat.get(r["id"], {})
    return {"brand": any(f.get(k) for k in BRAND_FEATS),
            "ask": bool(ASKS & set(r["baseline"].get("signals", []))),
            "lure": bool(LURE.search((r.get("title") or "") + " " + (r.get("text") or "")[:4000])),
            "chat": bool(c.get("msg") or c.get("msg_in_script"))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="impersonation-v2")
    ap.add_argument("--kaggle-half", choices=("all", "B"), default="all")
    ap.add_argument("--report", default=REPORT)
    args = ap.parse_args()
    MODEL = HERE / "out" / args.model
    prefix = "v2-" if args.model == "impersonation-v2" else ""
    OUT.mkdir(parents=True, exist_ok=True)
    if (OUT / args.report).exists():
        raise SystemExit(f"out/impersonation-v3/{args.report} exists: not overwriting")
    import rdap_measure as R  # v7 folder (on sys.path); RDAP ages measured on 2026-11-16
    import train3
    ages = {d["domain"]: R.age_days(d) for d in load(V7 / ".hasil/rdap.jsonl")}
    P = Popular(1000)
    th = json.load(open(MODEL / "thresholds-idcal.json"))["final"]
    fin, words = {}, {}
    for t in ("idcal-v4", "idcal-alieftest", "v6", "v7", "v7-fresh"):
        for d in load(MODEL / f"applied-{prefix}{t}.jsonl"):
            fin[d["id"]], words[d["id"]] = d["final"], d["words"]
    chat = {d["id"]: d for d in load(V7 / ".hasil/links.jsonl") if d.get("keadaan") == "ok"}

    every = T1.load_rows()
    fit_rows = [r for r in every if r["split"] in ("train", "dev")]
    a_sites, a_hosts = {T1.site(r["host"]) for r in fit_rows}, {r["host"] for r in fit_rows}

    def unseen(r):
        return (r["host"] not in a_hosts) if r["feats"]["sharedHost"] else (T1.site(r["host"]) not in a_sites)

    def v2_tier(r):
        off = bool(r["feats"].get("official")) or P.is_popular(r["host"])
        return T1.tier_names([fin[r["id"]]], [T2.is_indonesian(r)], [off], th)[0]

    OWNED = ("mandirikartukredit.com",)  # brand-owned domains outside brands.json (Imelda checked 2026-11-18)

    def official(r):
        h = r["host"].lower()
        return bool(r["feats"].get("official")) or P.is_popular(r["host"]) or any(h == d or h.endswith("." + d) for d in OWNED)

    def young(r):
        if r["feats"]["sharedHost"] or official(r):
            return False
        a = ages.get(T1.site(r["host"]))
        return a is not None and a < AGE_DAYS

    def claim_g(r, tx):
        f = r["feats"]
        host = r["host"].lower()
        head = ((r.get("title") or "") + " " + host).lower()
        lure = bool(LURE_B.search(tx))
        form = bool(f.get("passwordField")) or (f.get("forms", 0) >= 1 and f.get("fields", 0) >= 2)
        brand = any(f.get(k) for k in BRAND_STRONG) or (any(f.get(k) for k in BRAND_TEXT) and (form or lure))
        c = chat.get(r["id"], {})
        builder = any(host == b or host.endswith("." + b) for b in BUILDERS)
        return (brand or lure
                or bool(ASKS & set(r["baseline"].get("signals", [])))
                or bool(c.get("msg") or c.get("msg_in_script"))
                or bool(CRED.search(tx))
                or (bool(f.get("passwordField")) and words[r["id"]] >= PASS_WORDS)
                or bool(ODD_PASS.search(tx))
                or (builder and bool(PASS_LABEL.search(tx) or ODD_PASS.search(tx)) and bool(USER_LABEL.search(tx)))
                or any(b in head and not (host == d or host.endswith("." + d)) for b, d in EXTRA_BRANDS.items()))

    brand_names = {n.lower().replace(" ", "") for b in json.load(open(HERE.parent / "Final-CH7/detector/data/brands.json"))["brands"]
                   for n in [b["name"], *(b.get("names") or []), *(b.get("commonNames") or [])]}
    restricted = re.compile(r"\.(ac|sch|go|mil|desa)\.id$|\.(edu|gov|mil)$|\.(ac|edu|gov|go|mil)\.[a-z]{2}$")

    def brand_host(r, strict, owner_check=False):
        f = r["feats"]
        if official(r) or not f.get("brandInHost"):
            return False
        if owner_check:
            host = r["host"].lower()
            labels = T1.site(host).split(".")
            if restricted.search(host) or labels[0] in brand_names or labels[-1] in brand_names:
                return False
        return (bool(f.get("brandsInTitle")) or bool(f.get("brandsInText"))) if strict else True

    host_lure = re.compile(r"hadiah|undian|bansos|pemenang|klaim|pencairan|bantuan")

    def lure_host(r, strict):
        if official(r) or restricted.search(r["host"].lower()):
            return False
        label = r["host"].lower().split(".")[0] if r["feats"]["sharedHost"] else T1.site(r["host"].lower()).split(".")[0]
        if not host_lure.search(label):
            return False
        return bool(r["feats"].get("brandsInTitle") or r["feats"].get("brandsInText") or LURE_B.search((r.get("title") or "") + " " + (r.get("text") or "")[:4000])) if strict else True

    LOGIN = {"asks_password", "asks_otp", "asks_pin", "asks_card", "asks_cvv"}

    def imp_login(r):
        f = r["feats"]
        if official(r):
            return False
        sig = set(r["baseline"].get("signals", []))
        imp = brand_host(r, True, True) or "brand_logo_offsite" in sig
        return imp and (bool(f.get("passwordField")) or bool(LOGIN & sig))

    def tier(r, variant):
        if variant == "lb":
            t = tier(r, "host3+lure2")
            return "block" if imp_login(r) else t
        if variant in ("host3+lure", "host3+lure2"):
            t = tier(r, "v3g+umur+host3")
            return "warn" if t not in ("warn", "block") and lure_host(r, variant.endswith("2")) else t
        if variant in ("v3g+umur+host", "v3g+umur+host2", "v3g+umur+host3"):
            t = tier(r, "v3g+umur")
            return "warn" if t not in ("warn", "block") and brand_host(r, variant[-1] in "23", variant.endswith("3")) else t
        if variant == "v3g+umur":
            t = tier(r, "v3g")
            return "warn" if t not in ("warn", "block") and young(r) else t
        t = v2_tier(r)
        if variant == "v3g" and t in ("warn", "block"):
            tx = (r.get("title") or "") + " " + (r.get("text") or "")[:4000]
            return t if claim_g(r, tx) else "gate"
        if variant == "v2" or t not in ("warn", "block"):
            return t
        c = claims(r, chat)
        ok = c["brand"] or c["ask"] or c["lure"]
        if variant in ("v3b", "v3c"):
            ok = ok or c["chat"]
        if variant == "v3c":
            ok = ok or words[r["id"]] >= WORDS_KEEP
        tx = (r.get("title") or "") + " " + (r.get("text") or "")[:4000]
        if variant in ("v3d", "v3e"):
            ok = (ok or c["chat"] or bool(CRED.search(tx))
                  or (bool(r["feats"].get("passwordField")) and words[r["id"]] >= PASS_WORDS))
        if variant == "v3f":
            host = r["host"].lower()
            head = ((r.get("title") or "") + " " + host).lower()
            ok = ok or tier(r, "v3e") != "gate" or any(b in head and not (host == d or host.endswith("." + d)) for b, d in EXTRA_BRANDS.items())
        if variant == "v3e":
            host = r["host"].lower()
            builder = any(host == b or host.endswith("." + b) for b in BUILDERS)
            ok = ok or bool(ODD_PASS.search(tx)) or (builder and bool(PASS_LABEL.search(tx) or ODD_PASS.search(tx)) and bool(USER_LABEL.search(tx)))
        return t if ok else "gate"

    ktag = {}
    for line in open(V7 / ".hasil/sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        ktag[d["id"]] = d["tags"]["group"]
    kag_all = [norm(r) for r in load(V7 / ".hasil/rows.jsonl") if ktag[r["id"]] == "unseen"]
    kag_out = set() if args.kaggle_half == "all" else {r["id"] for r in kag_all if train3.kaggle_half(T1.site(r["host"])) != "B"}
    kag = [r for r in kag_all if r["id"] not in kag_out]
    fresh = [norm(r) for r in load(V7 / "fresh/.hasil/rows.jsonl")]
    v6 = [norm(r) for r in load(I.V6) if r.get("dataset") == "unseen"]
    al = [norm(r) for r in load(I.OUT / "alief-test-indo.jsonl")]
    sets = [
        ("Link segar, unseen", [r for r in fresh if unseen(r)]),
        ("Link aman manual (legit)", [r for r in fresh if r["label"] == 0]),
        ("phishing-url test (v6), unseen", v6),
        ("Test split Alief, Indonesia (legit separuh B, semua scam)", [r for r in al if r["label"] == 1 or r["half"] == "B"]),
        ("Kaggle v7 unseen, legit saja", [r for r in kag if r["label"] == 0]),
        ("Kaggle v7 unseen, legit Indonesia", [r for r in kag if r["label"] == 0 and T2.is_indonesian(r)]),
        ("Legit Indonesia kalibrasi (link chat diketahui)", [norm(r) for r in LM.groups()["legit_indonesian"]]),
    ]
    variants = ("v3g+umur", "host3+lure2", "lb")

    def pct(k, n):
        return f"{k}/{n} ({f'{100 * k / n:.1f}'.replace('.', ',')}%)" if n else "-"

    L = ["# Iterasi 3: klaim wajib untuk warn/block", "",
         f"_Model: `out/{args.model}`. Kaggle: {'semua halaman unseen' if args.kaggle_half == 'all' else 'hanya situs separuh B (tidak pernah dilatih model smallbiz); cek mata tanpa halaman Kaggle separuh A'}._", "",
         "_Dibuat oleh `eval_v3.py`. Model v2 tidak dilatih ulang; v3 hanya menurunkan warn/block ke `gate` kalau halaman tidak membuat klaim. "
         "Tanpa LLM: hanya warn/block yang dihitung ditandai. Link chat hanya diketahui untuk halaman yang diambil `links_fetch.mjs` "
         "(link segar, 1.500 Kaggle, legit Indonesia kalibrasi); di set lain v3b = v3a._", "",
         "- **v3a**: klaim = brand (judul/teks/host/logo di luar situs resmi), minta OTP/PIN/KTP/CVV/kartu/selfie, atau kata pancingan (hadiah, bansos, CS, verifikasi, ...).",
         "- **v3b**: v3a atau ada link t.me/wa.me.",
         f"- **v3c**: v3b, dan halaman tanpa klaim tetap ditandai kalau skor kata minimal {WORDS_KEEP}.",
         f"- **v3d**: v3b, ditambah kata phishing kredensial tanpa nama brand (webmail, Microsoft/Office, dokumen dibagikan, paket/resi, wallet, ...), "
         f"atau ada kolom password **dan** skor kata minimal {PASS_WORDS}.",
         "- **v3e**: v3d, ditambah kata password yang disamarkan (Passvvord, P@ssw0rd, Pαssword, WebmaiI), atau form login (email/user + password) "
         "di site builder (Weebly, ubpages, GoDaddy Sites, Wix, Jimdo, Google Sites, ...).",
         "- **v3f**: v3e, ditambah 5 brand yang belum ada di daftar brand Shoo (Roblox, Garena/Free Fire, Xfinity, Pinterest) di judul atau host. "
         "Ini mengukur celah daftar brand, bukan aturan baru.",
         "- **v3g**: v3f dengan dua kebocoran ditutup (`FP-ANALISIS.md`). A: brand yang hanya ada di teks halaman baru dihitung kalau ada form "
         "(kolom password, atau form minimal 2 kolom) atau kata pancingan kuat. B: kata pancingan dipersempit ke frasa scam dan kata Indonesia yang kuat "
         "(hadiah, undian, bansos, pencairan, pembatalan, call center, claim your/now, you have won, congratulations, verify your).",
         f"- **v3g+umur**: v3g, ditambah domain sendiri (bukan hosting gratis, bukan resmi/populer) yang umurnya < {AGE_DAYS} hari minimal `warn`. "
         "Umur dari RDAP v7; hanya diketahui untuk link segar, 1.500 Kaggle, dan legit Indonesia kalibrasi. Di set lain umur tidak diketahui = tidak muda.", "",
         "| Set | Scam / legit | " + " | ".join(f"{v} scam | {v} legit" for v in variants) + " |",
         "|---|---|" + "---|---|" * len(variants)]
    for name, rows in sets:
        ys = [r for r in rows if r["label"] == 1]
        yl = [r for r in rows if r["label"] == 0]
        cells = []
        for v in variants:
            cells.append(pct(sum(tier(r, v) in ("warn", "block") for r in ys), len(ys)))
            cells.append(pct(sum(tier(r, v) in ("warn", "block") for r in yl), len(yl)))
        L.append(f"| {name} | {len(ys)} / {len(yl)} | " + " | ".join(cells) + " |")

    pick = [p for p in load(EYE / "pick.jsonl") if p["id"] not in kag_out]
    ver = json.load(open(EYE / "verdict.json"))
    byid = {r["id"]: r for r in fresh + kag_all}
    for g in LM.groups().values():
        for r in g:
            byid.setdefault(r["id"], norm(r))
    L += ["", "## Cek mata 50 halaman (semuanya ditandai v2)", "",
          "Berapa yang **masih ditandai** (warn/block) per hasil cek mata.", "",
          "| Kelompok | Jumlah | " + " | ".join(variants) + " |", "|---|---|" + "---|" * len(variants)]
    for lab, lname in ((0, "Legit"), (1, "Scam")):
        for vv in ("benar", "salah", "ragu"):
            ids = [p["id"] for p in pick if p["label"] == lab and ver[p["id"]]["v"] == vv]
            if ids:
                row = [str(sum(tier(byid[i], v) in ("warn", "block") for i in ids)) for v in variants]
                L.append(f"| {lname}, cek mata {vv} | {len(ids)} | " + " | ".join(row) + " |")
    for v in ("host3+lure2", "lb"):
        lost = [i + 1 for i, p in enumerate(pick) if ver[p["id"]]["v"] == "benar" and tier(byid[p["id"]], v) not in ("warn", "block")]
        kept = [i + 1 for i, p in enumerate(pick) if ver[p["id"]]["v"] == "salah" and tier(byid[p["id"]], v) in ("warn", "block")]
        L.append(f"\n{v}: nomor baris laporan cek mata yang benar ditandai tapi hilang {lost}; salah tanda yang masih ditandai {kept}.")
    import os
    if os.environ.get("SHOW_HOST_FP"):  # stdout only, never written to the report
        print("\nBLOCK counts")
        for name, rows in sets:
            ys = [r for r in rows if r["label"] == 1]
            yl = [r for r in rows if r["label"] == 0]
            print(name, "|", " | ".join(f"{v}: scam {sum(tier(r, v) == 'block' for r in ys)}/{len(ys)} legit {sum(tier(r, v) == 'block' for r in yl)}/{len(yl)}" for v in ("host3+lure2", "lb")))
            for r in yl:
                if tier(r, "lb") == "block" and tier(r, "host3+lure2") != "block":
                    print("   legit newly block:", r["host"])
    (OUT / args.report).write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L))


if __name__ == "__main__":
    main()
