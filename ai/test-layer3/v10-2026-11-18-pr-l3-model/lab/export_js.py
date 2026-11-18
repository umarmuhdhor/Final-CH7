"""Export model v2 (out/impersonation-v2) to a compact JS module for Shoo's Worker (ai/src/layer3/model/).

Format (little endian, one binary blob, base64 in the JS module so it loads the same way in Node and in the Worker):
  three term tables (words-word, words-char, address), each (format 2, lossless, 2026-11-18, to fit the 3 MB Workers bundle):
    uint32 n | uint32 L | L bytes: n varint gaps between the sorted hashes | pad to 4 |
    uint32 k | float32 idf_palette[k] | uint16 idf_index[n] | pad to 4 | float32 coef[n]
    (format 1 was: uint32 n | uint32 hash[n] | float32 idf[n] | float32 coef[n]; same numbers, ~3.6 MB gzip)
    hash = FNV-1a 32 over the UTF-16 code units of the term (same in JS). Terms are looked up by binary search, so the Worker
    builds nothing at start-up. A term whose |coef| < --prune is left out (it then counts as an unknown term, like sklearn
    does for words outside the vocabulary: it no longer adds to the L2 norm either; --check measures what that costs).
  two tree ensembles (with_address, no_address), each:  uint32 trees | uint32 nodes | uint32 first_node[trees] |
    uint8 feature[nodes] | uint8 flags[nodes] (1 leaf, 2 missing goes left) | uint16 left[nodes] | uint16 right[nodes] |
    float64 threshold_or_value[nodes]   (+ padding to 8 bytes before the float64 part)
Everything else (feature names, cut-offs, intercepts, baselines, Tranco top 1000) goes in a plain JSON object.

Usage (lab environment):
  uv run --python 3.12 --project ../shoo-layer3-lab python export_js.py --check [--prune 0.0]   # compression vs sklearn, no file written
  uv run --python 3.12 --project ../shoo-layer3-lab python export_js.py --out <ai/src/layer3/model> [--prune 0.0]
  --out also writes out/impersonation-v2/parity-fixture.json (100 rows: inputs + sklearn scores) for parity_js.mjs.
  It holds page text, so it stays here and never goes into Shoo's repo.
"""
import argparse
import base64
import csv
import json
import struct
import sys
from pathlib import Path

import joblib
import numpy as np

import train2 as T
from popular import TOP

HERE = Path(__file__).resolve().parent
V2 = HERE / "out/impersonation-v2"
V7 = Path.home() / "Documents/Swift/Final-CH/Final-CH7/ai/test-layer3/v7-2026-11-16-impersonation-new-data"


def fnv(s):
    h = 0x811C9DC5
    b = s.encode("utf-16-le", "surrogatepass")
    for i in range(0, len(b), 2):
        h ^= b[i] | (b[i + 1] << 8)
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def table(vec, coef, prune):
    terms = vec.vocabulary_
    idf = vec.idf_
    rows = {}
    clash = 0
    for term, col in terms.items():
        c = float(coef[col])
        if abs(c) < prune:
            continue
        h = fnv(term)
        if h in rows:
            clash += 1
            if abs(c) <= abs(rows[h][1]):
                continue
        rows[h] = (float(idf[col]), c)
    hs = np.array(sorted(rows), dtype=np.uint32)
    return hs, np.array([rows[h][0] for h in hs], dtype=np.float32), np.array([rows[h][1] for h in hs], dtype=np.float32), clash


def varint(values):
    out = bytearray()
    for v in values:
        v = int(v)
        while v >= 128:
            out.append((v & 127) | 128)
            v >>= 7
        out.append(v)
    return bytes(out)


def packed_table(hs, idf, coef, coef16=False):
    """Format 2 term table (see the module docstring). Starts and ends on a 4-byte boundary."""
    gaps = varint(np.diff(np.concatenate([[0], hs.astype(np.int64)])))
    palette, index = np.unique(idf, return_inverse=True)
    assert len(palette) < 65536
    b = struct.pack("<II", len(hs), len(gaps)) + gaps
    b += b"\0" * (-len(b) % 4)
    b += struct.pack("<I", len(palette)) + palette.astype("<f4").tobytes() + index.astype("<u2").tobytes()
    b += b"\0" * (-len(b) % 4)
    return b + (coef.astype("<f2").tobytes() + b"\0" * (len(coef) % 2) * 2 if coef16 else coef.astype("<f4").tobytes())


def trees(meta):
    first, feat, flags, left, right, val = [], [], [], [], [], []
    for it in meta._predictors:
        (p,) = it  # binary: one tree per iteration
        nodes = p.nodes
        first.append(len(feat))
        for nd in nodes:
            assert not nd["is_categorical"]
            feat.append(int(nd["feature_idx"]))
            flags.append((1 if nd["is_leaf"] else 0) | (2 if nd["missing_go_to_left"] else 0))
            left.append(int(nd["left"]))
            right.append(int(nd["right"]))
            val.append(float(nd["value"] if nd["is_leaf"] else nd["num_threshold"]))
    return first, feat, flags, left, right, val, float(np.ravel(meta._baseline_prediction)[0])


class Compact:
    """Python twin of the JS inference on the exported tables (tokens from sklearn's own analyzers, so only compression is measured)."""

    def __init__(self, tabs):
        self.tabs = tabs

    def part(self, tab, terms):
        hs, idf, coef = tab
        counts = {}
        for t in terms:
            h = fnv(t)
            i = np.searchsorted(hs, h)
            if i < len(hs) and hs[i] == h:
                counts[i] = counts.get(i, 0) + 1
        if not counts:
            return 0.0
        w = {i: (1 + np.log(c)) * float(idf[i]) for i, c in counts.items()}
        norm = np.sqrt(sum(v * v for v in w.values()))
        return sum(v / norm * float(coef[i]) for i, v in w.items())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prune", type=float, default=0.0)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--coef16", action="store_true", help="store coef as float16 (lossy; --check shows what it costs)")
    args = ap.parse_args()
    sys.modules["__main__"].Judges = T.Judges
    M = joblib.load(V2 / "model.joblib")
    th = json.load(open(V2 / "thresholds-idcal.json"))["final"]
    j = M["judges"]
    nw = len(j.word_vec.vocabulary_)
    wc = j.words.coef_[0]
    tw = table(j.word_vec, wc[:nw], args.prune)
    tc = table(j.char_vec, wc[nw:], args.prune)
    ta = table(j.addr_vec, j.address.coef_[0], args.prune)
    if args.coef16:
        tw, tc, ta = [(h, i, c.astype(np.float16).astype(np.float32), k) for h, i, c, k in (tw, tc, ta)]
    print(f"prune {args.prune}: terms word {len(tw[0])} char {len(tc[0])} address {len(ta[0])} | hash clashes {tw[3]} {tc[3]} {ta[3]}")

    if args.check or args.out:
        rows = [json.loads(l) for l in open(V7 / "fresh/.hasil/rows.jsonl", encoding="utf-8")]
        rows += [json.loads(l) for l in open(V7 / ".hasil/rows.jsonl", encoding="utf-8")][::10]
        rows = [r for r in rows if r.get("title") is not None and r.get("text") is not None]
        sk = j.score(rows)
        X = T.feature_matrices(sk, T.side_matrix(rows))
        fin = (M["metas"]["with_address"].predict_proba(X["with_address"])[:, 1] + M["metas"]["no_address"].predict_proba(X["no_address"])[:, 1]) / 2
        cm = Compact(None)
        aw, ac, aa = j.word_vec.build_analyzer(), j.char_vec.build_analyzer(), j.addr_vec.build_analyzer()
        sig = lambda z: 1 / (1 + np.exp(-z))
        cs = []
        for r in rows:
            t = T.words_text(r)
            ws = sig(cm.part(tw[:3], aw(t)) + cm.part(tc[:3], ac(t)) + j.words.intercept_[0])
            ad = sig(cm.part(ta[:3], aa(T.address_text(r))) + j.address.intercept_[0])
            cs.append((ws, ad))
        cs = np.array(cs)
        X2 = T.feature_matrices(cs, T.side_matrix(rows))
        fin2 = (M["metas"]["with_address"].predict_proba(X2["with_address"])[:, 1] + M["metas"]["no_address"].predict_proba(X2["no_address"])[:, 1]) / 2
        indo = [T.is_indonesian(r) for r in rows]
        off = [bool(r["feats"].get("official")) for r in rows]
        t1 = T.tier_names(fin, indo, off, th)
        t2 = T.tier_names(fin2, indo, off, th)
        print(f"check on {len(rows)} rows: words |diff| max {np.abs(sk[:, 0] - cs[:, 0]).max():.4f} | address max {np.abs(sk[:, 1] - cs[:, 1]).max():.4f} "
              f"| final max {np.abs(fin - fin2).max():.4f} | tier changed {int((t1 != t2).sum())}")

    if not args.out:
        return
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    blob = bytearray()
    for hs, idf, coef, _ in (tw, tc, ta):
        blob += packed_table(hs, idf, coef, args.coef16)
    meta = {}
    for name in ("with_address", "no_address"):
        first, feat, flags, left, right, val, base = trees(M["metas"][name])
        assert max(left + right) < 65536 and max(feat) < 256
        blob += struct.pack("<II", len(first), len(feat)) + np.array(first, "<u4").tobytes() + np.array(feat, "u1").tobytes() + np.array(flags, "u1").tobytes()
        blob += np.array(left, "<u2").tobytes() + np.array(right, "<u2").tobytes()
        blob += b"\0" * (-len(blob) % 8)
        blob += np.array(val, "<f8").tobytes()
        meta[name] = {"baseline": base}
    top = []
    with open(TOP, encoding="utf-8") as f:
        for i, row in enumerate(csv.reader(f)):
            if i >= 1000:
                break
            top.append(row[1].strip().lower())
    info = {
        "source": "shoo-impersonation-lab out/impersonation-v2 (train2.py), cut-offs thresholds-idcal.json; exported by export_js.py",
        "format": 2,
        "coef16": bool(args.coef16),
        "prune": args.prune,
        "words_intercept": float(j.words.intercept_[0]),
        "address_intercept": float(j.address.intercept_[0]),
        "baselines": {k: v["baseline"] for k, v in meta.items()},
        "feats": T.FEATS, "logged": sorted(T.LOGGED), "rule_signals": T.RULE_SIGNALS, "no_address_columns": T.NO_ADDRESS_COLUMNS,
        "thresholds": th,
        "popular_top1000": top,
    }
    b64 = base64.b64encode(bytes(blob)).decode()
    (out / "impersonation-data.js").write_text(
        "// Generated by shoo-impersonation-lab/export_js.py. Do not edit by hand: re-export instead.\n"
        "// Model v2 of the layer 3 impersonation lab: TF-IDF + logistic regression judges and two gradient-boosted combiners.\n"
        f"export const INFO = {json.dumps(info)};\n"
        f"export const BLOB = \"{b64}\";\n", encoding="utf-8")
    # Parity fixture: 100 rows (inputs the JS needs + sklearn's numbers), fresh feed and Kaggle, no page text kept beyond what scoring needs.
    pick = rows[::max(1, len(rows) // 100)][:100]
    sk_p = j.score(pick)
    Xp = T.feature_matrices(sk_p, T.side_matrix(pick))
    fin_p = (M["metas"]["with_address"].predict_proba(Xp["with_address"])[:, 1] + M["metas"]["no_address"].predict_proba(Xp["no_address"])[:, 1]) / 2
    fx = [{"url": r["url"], "host": r["host"], "title": r["title"], "text": r["text"][:6000], "feats": r["feats"], "signals": r["baseline"]["signals"],
           "words": float(s[0]), "address": float(s[1]), "final": float(f), "indonesian": bool(T.is_indonesian(r))}
          for r, s, f in zip(pick, sk_p, fin_p)]
    # Page text: stays in the lab's out/ folder, never in Shoo's (public) repo.
    (V2 / "parity-fixture.json").write_text(json.dumps(fx), encoding="utf-8")
    print(f"wrote {out}/impersonation-data.js ({len(b64) / 1e6:.2f} MB base64, blob {len(blob) / 1e6:.2f} MB) and {V2}/parity-fixture.json ({len(fx)} rows)")


if __name__ == "__main__":
    main()
