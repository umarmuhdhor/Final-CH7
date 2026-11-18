"""v2 of train.py (iteration 2, 2026-11-16). Copy of train.py with four changes, marked "v2:" below:
  1. language: a page counts as Indonesian only when it has more Indonesian words than common foreign function words
     (train.py also flagged Italian, Turkish and French pages). Used both as model input and for the cut-off group.
  2. scam training/dev rows that are parked, for sale, expired, coming soon, bot checks or error pages are dropped (stale labels).
  3. legit training/dev rows with gambling or porn words are dropped (label noise).
  4. 25% of the Indonesian legit TRAIN sites (by site hash) move to dev, so the Indonesian cut-offs come from hundreds of pages
     instead of 30. The test split is unchanged.
Writes out/<scam-types>-v2/. train.py and its outputs are not touched.

Original docstring:
Our layer 3 experiment: does this page pretend to be someone and ask for something? No bge-m3, no gambling.

Simplified from shoo-layer3-lab/src/train_eval.py (Alief, commit c29f2b2). Kept: site-based split, out-of-fold judge scores,
facts about brand and form, gradient-boosted combiner, cut-offs picked by false-alarm rate per language group, removal of
training pages with a clearly wrong label. Removed: bge-m3 and the three judges that need it (meaning, best chunk, gambling),
all gambling data, pickled files meant for other machines.

Usage (reuses the Python environment of shoo-layer3-lab):
  uv run --python 3.12 --project ~/Documents/Swift/Final-CH/shoo-layer3-lab python train.py --scam-types all
  uv run --python 3.12 --project ~/Documents/Swift/Final-CH/shoo-layer3-lab python train.py --scam-types impersonation
Data: Alief's rows in ~/Documents/dataset/out/{pages,extra,extra2}.jsonl (read only). They already hold the PageSnapshot fields,
the brand and form facts (feats) and the current rules result (baseline).
Writes out/<scam-types>/model.joblib and report.json. Those files are ours, written and read on this machine only.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

import joblib
import numpy as np
from scipy.sparse import hstack
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import GroupKFold

HERE = Path(__file__).resolve().parent
SRC = Path.home() / "Documents/dataset/out"

RULE_SIGNALS = ["asks_password", "asks_otp", "asks_pin", "asks_ktp", "asks_cvv", "asks_card", "asks_selfie_ktp", "urgent_language", "brand_logo_offsite"]
LOGGED = {"textLen", "fields", "forms", "imageAlts", "hostLen", "pathLen"}
FEATS = [
    "textLen", "fields", "passwordField", "forms", "imageAlts", "formActionOffsite",
    "official", "brandsInTitle", "brandsInText", "brandOffsite", "brandTextOffsite", "brandInHost", "cheapTld", "sharedHost",
    "hostLen", "hostDigits", "hostHyphens", "subdomains", "pathLen", "pathDepth", "ipHost", "punycode", "urlKeywords",
]
ADDRESS_FEATS = {"official", "brandInHost", "cheapTld", "sharedHost", "hostLen", "hostDigits", "hostHyphens", "subdomains", "pathLen", "pathDepth", "ipHost", "punycode", "urlKeywords"}
TIERS = (("block", 0.005), ("warn", 0.02), ("gate", 0.15))  # share of legit dev pages allowed at or above each cut-off
GAMBLING = "Online Gambling Scam"
IMPERSONATION_TYPES = {"Phishing", "Business Impersonation Scam", "Bank Impersonation Scam", "Spoofed Login Page",
                       "E-commerce Customer Service Impersonation Scam", "Government/Law Enforcement Impersonation Scam", "Technical Support Scam"}
SECOND_LEVEL = re.compile(r"^(co|go|ac|or|web|sch|my|biz|net|com|org|gov|edu|mil|desa|ponpes)\.[a-z]{2}$")
# Alief's list without the gambling words (togel, gacor).
ID_WORDS = set("yang dan di untuk dengan dari ini itu pada adalah atau juga akan tidak kami anda daftar masuk situs terbaru hari lebih dalam ke oleh sebagai bisa dapat beranda resmi terpercaya hubungi promosi permainan bermain menang mudah".split())


def site(host):
    p = host.removeprefix("www.").split(".")
    return ".".join(p[-3:] if SECOND_LEVEL.match(".".join(p[-2:])) else p[-2:])


# v2: foreign function words (Italian, French, Turkish, Spanish, Portuguese, English).
FOREIGN = set(("il la le lo gli della delle dei del per che non una sono con come più les des et est pour vous nous avec sur dans une "
               "ve bir için ile olan daha veya en el los las que para por com não uma das dos the and of to is are for with this").split())
DEAD = re.compile(
    r"for sale|domain (name )?(has )?expired|registration has expired|has expired|parked|coming soon|under construction|en construction|"
    r"maintenance|checking your browser|verify you.{0,8}re human|confirm you are human|security check|welcome to nginx|apache.{0,20}(default|test) page|"
    r"it works!|dns resolution error|does not exist|not found|404|account (has been )?suspended|domain is suspended|fatal error|"
    r"has been (recently )?registered|registered with|hello world! welcome to wordpress|just another wordpress site|не прилинкован|"
    r"site is undergoing|website is under|this domain|domain name", re.I)
ADULT_GAMBLING = re.compile(r"\b(judi|slot|togel|gacor|maxwin|toto|bokep|live draw|casino|kasino|bandar|sbobet|jackpot|4d|porn|sex)\b", re.I)


def is_indonesian(row):
    """v2: Alief's 4% rule AND more Indonesian words than foreign function words."""
    words = re.findall(r"[a-zçğıöşüàèéìòù]+", (row["title"] + " " + row["text"][:4000]).lower())
    if len(words) < 15:
        return False
    i = sum(w in ID_WORDS for w in words)
    return i / len(words) >= 0.04 and i > sum(w in FOREIGN for w in words)


def is_dead(row):
    return bool(DEAD.search((row["title"] or "") + " " + (row["text"] or "")[:600]))


def is_adult_gambling(row):
    return bool(ADULT_GAMBLING.search((row["title"] or "") + " " + (row["text"] or "")[:3000]))


def words_text(row):
    return row["title"] + " \n " + row["text"][:6000]


def address_text(row):
    path = re.sub(r"^https?://[^/]+", "", row.get("url") or "")
    return row["host"] + " " + path.split("?")[0][:120]


def side_matrix(rows):
    """Brand and form facts, current-rules signals, Indonesian flag."""
    def value(r, k):
        v = float(r["feats"].get(k, 0))
        return np.log1p(v) if k in LOGGED else v

    f = np.array([[value(r, k) for k in FEATS] for r in rows], dtype=np.float32)
    rules = np.array([[float(s in r["baseline"]["signals"]) for s in RULE_SIGNALS] for r in rows], dtype=np.float32)
    indo = np.array([[float(is_indonesian(r))] for r in rows], dtype=np.float32)
    return np.hstack([f, rules, indo])


NO_ADDRESS_COLUMNS = [i for i, k in enumerate(FEATS) if k not in ADDRESS_FEATS] + list(range(len(FEATS), len(FEATS) + len(RULE_SIGNALS) + 1))


class Judges:
    """Two small text judges, both logistic regression on TF-IDF: the words on the page, and the shape of the address."""

    NAMES = ("words", "address")

    def __init__(self, rows, y):
        texts = [words_text(r) for r in rows]
        self.word_vec = TfidfVectorizer(analyzer="word", ngram_range=(1, 2), min_df=3, max_features=150_000, sublinear_tf=True, lowercase=True)
        self.char_vec = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), min_df=5, max_features=200_000, sublinear_tf=True, lowercase=True)
        x = hstack([self.word_vec.fit_transform(texts), self.char_vec.fit_transform(texts)]).tocsr()
        self.words = LogisticRegression(C=3.0, max_iter=2000, class_weight="balanced", solver="liblinear").fit(x, y)
        self.addr_vec = TfidfVectorizer(analyzer="char", ngram_range=(2, 4), min_df=3, max_features=80_000, sublinear_tf=True, lowercase=True)
        self.address = LogisticRegression(C=1.0, max_iter=2000, class_weight="balanced", solver="liblinear").fit(self.addr_vec.fit_transform([address_text(r) for r in rows]), y)

    def score(self, rows):
        texts = [words_text(r) for r in rows]
        x = hstack([self.word_vec.transform(texts), self.char_vec.transform(texts)]).tocsr()
        return np.column_stack([self.words.predict_proba(x)[:, 1], self.address.predict_proba(self.addr_vec.transform([address_text(r) for r in rows]))[:, 1]])


def oof_scores(rows, y, mask, groups):
    """Judge scores for the pages in `mask` come from judges that never saw their site (5-fold by site); the rest use judges fitted on all of `mask`."""
    out = np.zeros((len(rows), 2))
    idx = np.where(mask)[0]
    for a, b in GroupKFold(n_splits=5).split(idx, y[idx], groups[idx]):
        j = Judges([rows[i] for i in idx[a]], y[idx[a]])
        out[idx[b]] = j.score([rows[i] for i in idx[b]])
    full = Judges([rows[i] for i in idx], y[idx])
    rest = np.where(~mask)[0]
    out[rest] = full.score([rows[i] for i in rest])
    return out, full


def combiner():
    return HistGradientBoostingClassifier(max_iter=300, learning_rate=0.06, max_leaf_nodes=15, l2_regularization=1.0, class_weight="balanced", random_state=0)


def threshold_at_fpr(benign_scores, fpr):
    s = np.sort(benign_scores)[::-1]
    return float(s[min(len(s) - 1, int(np.floor(fpr * len(s))))]) + 1e-12


def feature_matrices(scores, side):
    return {"with_address": np.hstack([scores, side]), "no_address": np.hstack([scores[:, :1], side[:, NO_ADDRESS_COLUMNS]])}


def tier_names(final, indo, official, thresholds):
    out = []
    for s, i, o in zip(final, indo, official):
        lim = thresholds["indonesian" if i else "other"]
        out.append("safe" if o else next((t for t in ("block", "warn", "gate") if s >= lim[t]), "safe"))
    return np.array(out)


def load_rows():
    rows = []
    for name in ("pages", "extra", "extra2"):
        for line in open(SRC / f"{name}.jsonl", encoding="utf-8"):
            r = json.loads(line)
            r.pop("html", None)
            r["_i"] = len(rows)  # position in Alief's files, to line up his saved scores
            rows.append(r)
    return rows


def keep(r, scam_types, keep_gambling=False):
    src = r.get("source", "scamweb")
    if src == "indo_phish":  # reported URLs that now show unrelated pages (Alief dropped these too)
        return False
    if not keep_gambling and (src == "judol" or (r["label"] == 1 and r.get("scamType") == GAMBLING)):
        return False
    if r["label"] == 1 and scam_types == "impersonation" and src == "scamweb" and r.get("scamType") not in IMPERSONATION_TYPES:
        return False
    return r["split"] in ("train", "dev", "test")


def rates(tier, y, mask):
    """Share of scam and legit pages in `mask` at each level: reach layer 4 or flagged / shown without LLM / blocked."""
    out = {}
    for label, name in ((1, "scam"), (0, "legit")):
        m = mask & (y == label)
        n = int(m.sum())
        out[name] = {"n": n, "gate_or_more": int((tier[m] != "safe").sum()), "warn_or_more": int(np.isin(tier[m], ("warn", "block")).sum()), "block": int((tier[m] == "block").sum())}
    return out


def fmt(r):
    def p(a, b):
        return f"{100 * a / b:5.1f}%" if b else "  n/a"
    s, l = r["scam"], r["legit"]
    return (f"scam n={s['n']:4} | reach L4 or flagged {p(s['gate_or_more'], s['n'])}  warn+ {p(s['warn_or_more'], s['n'])}  block {p(s['block'], s['n'])}"
            f" || legit n={l['n']:4} | {p(l['gate_or_more'], l['n'])}  {p(l['warn_or_more'], l['n'])}  {p(l['block'], l['n'])}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scam-types", choices=("all", "impersonation"), default="all")
    ap.add_argument("--keep-gambling", action="store_true", help="ablation: Alief's data exactly (gambling included); only the bge-m3 judges are missing")
    ap.add_argument("--popular-n", type=int, default=0, help="treat hosts under the Tranco top-N domains as official (tier safe). 0 = off. Output goes to out/<name>-popular<N>/")
    args = ap.parse_args()
    name = ("ablation" if args.keep_gambling else args.scam_types) + "-v2"
    if args.popular_n:
        name += f"-popular{args.popular_n}"
    if args.keep_gambling:
        ID_WORDS.update({"togel", "gacor"})  # Alief's own Indonesian word list
    out_dir = HERE / "out" / name
    out_dir.mkdir(parents=True, exist_ok=True)

    every = load_rows()
    alief = np.load(SRC / "scores.npz")["final"]  # Alief's saved final score, one per row of pages+extra+extra2
    alief_limits = json.load(open(SRC / "report.json"))["thresholds"]["final"]
    rows = [r for r in every if keep(r, args.scam_types, args.keep_gambling)]
    y = np.array([r["label"] for r in rows])
    split = np.array([r["split"] for r in rows])
    tr, dv, te = split == "train", split == "dev", split == "test"
    groups = np.array([site(r["host"]) for r in rows])
    indo = np.array([is_indonesian(r) for r in rows])
    official = np.array([bool(r["feats"].get("official")) for r in rows])
    if args.popular_n:  # the list is a traffic ranking, not built from labels; only the tier step uses it, the model inputs stay the same
        from popular import Popular

        P = Popular(args.popular_n)
        official = official | np.array([P.is_popular(r["host"]) for r in rows])
    # v2: changes 2, 3, 4 (train and dev only; test untouched).
    dead = np.array([is_dead(r) for r in rows])
    adult = np.array([is_adult_gambling(r) for r in rows])
    drop = (tr | dv) & (((y == 1) & dead) | ((y == 0) & adult))
    move = tr & indo & (y == 0) & np.array([hashlib.sha256(site(r["host"]).encode()).digest()[0] % 4 == 0 for r in rows])
    print(f"v2: dropped scam dead-like {int((drop & (y == 1)).sum())}, legit gambling/porn {int((drop & (y == 0)).sum())}; "
          f"moved Indonesian legit train -> dev {int(move.sum())}", flush=True)
    tr, dv = (tr & ~drop & ~move), ((dv & ~drop) | move)
    print(f"v2: dev legit Indonesian pages now {int((dv & indo & (y == 0)).sum())}", flush=True)
    print(f"[{name}] pages {len(rows)} (of {len(every)}): train {tr.sum()} dev {dv.sum()} test {te.sum()} | scam {y.sum()} legit {(y == 0).sum()}", flush=True)

    first, _ = oof_scores(rows, y, tr, groups)
    noisy = tr & (((y == 1) & (first.max(axis=1) < 0.2)) | ((y == 0) & (first[:, 0] > 0.97)))
    tr = tr & ~noisy
    print(f"training pages dropped as wrong labels: scam {int((noisy & (y == 1)).sum())}, legit {int((noisy & (y == 0)).sum())}", flush=True)
    scores, judges = oof_scores(rows, y, tr, groups)

    side = side_matrix(rows)
    X = feature_matrices(scores, side)
    metas, per = {}, {}
    for name, x in X.items():
        metas[name] = combiner().fit(x[tr], y[tr])
        per[name] = metas[name].predict_proba(x)[:, 1]
    per["final"] = (per["with_address"] + per["no_address"]) / 2

    thresholds = {n: {g: {t: threshold_at_fpr(s[dv & (y == 0) & m], f) for t, f in TIERS} for g, m in (("indonesian", indo), ("other", ~indo))} for n, s in per.items()}
    tiers = {n: tier_names(s, indo, official, thresholds[n]) for n, s in per.items()}
    rules_score = np.array([r["baseline"]["score"] for r in rows])
    tiers["rules"] = np.where(rules_score >= 80, "block", np.where(rules_score >= 30, "warn", "safe"))
    if args.popular_n:
        tiers["rules"] = np.where(official, "safe", tiers["rules"])
    a_final = alief[[r["_i"] for r in rows]]
    tiers["alief"] = tier_names(a_final, indo, official, alief_limits)

    # The simple rule we discussed: no sensitive form and no brand claim means pass.
    sensitive = np.array([bool(r["feats"]["passwordField"]) or any(s.startswith("asks_") for s in r["baseline"]["signals"]) for r in rows])
    claim = np.array([bool(r["feats"]["brandOffsite"] or r["feats"]["brandTextOffsite"] or r["feats"]["brandInHost"]) for r in rows])
    tiers["final+pass_rule"] = np.where(sensitive | claim, tiers["final"], "safe")

    auc = {"rules": roc_auc_score(y[te], rules_score[te]), "alief": roc_auc_score(y[te], a_final[te])}
    auc.update({f"judge_{n}": roc_auc_score(y[te], scores[te, i]) for i, n in enumerate(Judges.NAMES)})
    auc.update({n: roc_auc_score(y[te], s[te]) for n, s in per.items()})
    print("\nAUC on the held-out test pages: " + "  ".join(f"{k} {v:.3f}" for k, v in auc.items()), flush=True)

    imp_scam = np.array([r["label"] == 1 and (r.get("source", "scamweb") in ("phish", "phish_id") or r.get("scamType") in IMPERSONATION_TYPES) for r in rows])
    sets = {"test: all": te, "test: pages with a password field": te & np.array([bool(r["feats"]["passwordField"]) for r in rows]),
            "test: impersonation-type scam + all legit": te & (imp_scam | (y == 0))}
    report = {"scam_types": name, "pages": len(rows), "auc_test": auc, "thresholds": thresholds, "sets": {}}
    for sname, mask in sets.items():
        print(f"\n{sname}   (columns: reach layer 4 or flagged / warn or block / block)")
        report["sets"][sname] = {}
        for tname in ("rules", "alief", "final", "with_address", "no_address", "final+pass_rule"):
            r = rates(tiers[tname], y, mask)
            report["sets"][sname][tname] = r
            print(f"  {tname:16} {fmt(r)}")
    json.dump(report, open(out_dir / "report.json", "w"), indent=1)
    joblib.dump({"judges": judges, "metas": metas, "thresholds": {n: thresholds[n] for n in ("final", "with_address", "no_address")}, "no_address_columns": NO_ADDRESS_COLUMNS, "scam_types": args.scam_types}, out_dir / "model.joblib")
    print(f"\nsaved {out_dir}")


if __name__ == "__main__":
    main()
