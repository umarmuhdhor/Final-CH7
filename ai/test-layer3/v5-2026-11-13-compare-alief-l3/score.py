"""Step 4: score the sample with Alief's rebuilt layer 3 and put it next to the current layer 3 (rules).

Usage (from the lab folder, so its Python environment is used):
  cd ~/Documents/Swift/Final-CH/shoo-layer3-lab
  uv run --python 3.12 python <this folder>/score.py
Reads  .hasil/rows.jsonl (build-rows.mjs), Alief's layer3_base.joblib + layer3_meta.joblib.
Writes .hasil/results.jsonl (one line per page) and .hasil/score-meta.json.

The two .joblib files are pickles. They are NOT loaded with joblib.load. Every class they reference was listed first
without running anything (24 names); the loader below allows exactly those names and refuses everything else.
The scoring steps are the ones in shoo-layer3-lab/src/analyze.py, run in batches.
"""
import argparse
import hashlib
import json
import pickle
import sys
import time
from pathlib import Path

import numpy as np
from joblib import numpy_pickle as NP
from joblib.numpy_pickle_utils import _validate_fileobject_and_memmap

HERE = Path(__file__).resolve().parent
LAB_SRC = Path.home() / "Documents/Swift/Final-CH/shoo-layer3-lab/src"
ALIEF_OUT = Path.home() / "Documents/dataset/out"
sys.path.insert(0, str(LAB_SRC))
import train_eval  # noqa: E402  (Alief's Base class is needed to rebuild the bundle)
from embed import chunks, encode, load_model  # noqa: E402

ALLOWED = {
    ("__main__", "Base"),  # mapped to train_eval.Base below
    ("joblib.numpy_pickle", "NumpyArrayWrapper"),
    ("numpy", "dtype"), ("numpy", "float64"), ("numpy", "ndarray"), ("numpy._core.multiarray", "scalar"),
    ("numpy.random._pcg64", "PCG64"), ("numpy.random._pickle", "__bit_generator_ctor"), ("numpy.random._pickle", "__generator_ctor"),
    ("numpy.random.bit_generator", "SeedSequence"), ("numpy.random.bit_generator", "__pyx_unpickle_SeedSequence"),
    ("sklearn._loss._loss", "CyHalfBinomialLoss"), ("sklearn._loss.link", "Interval"), ("sklearn._loss.link", "LogitLink"), ("sklearn._loss.loss", "HalfBinomialLoss"),
    ("sklearn.ensemble._hist_gradient_boosting.binning", "_BinMapper"),
    ("sklearn.ensemble._hist_gradient_boosting.gradient_boosting", "HistGradientBoostingClassifier"),
    ("sklearn.ensemble._hist_gradient_boosting.predictor", "TreePredictor"),
    ("sklearn.feature_extraction.text", "TfidfTransformer"), ("sklearn.feature_extraction.text", "TfidfVectorizer"),
    ("sklearn.linear_model._logistic", "LogisticRegression"), ("sklearn.pipeline", "Pipeline"),
    ("sklearn.preprocessing._data", "StandardScaler"), ("sklearn.preprocessing._label", "LabelEncoder"),
}


class RestrictedUnpickler(NP.NumpyUnpickler):
    def find_class(self, module, name):
        if (module, name) not in ALLOWED:
            raise pickle.UnpicklingError(f"blocked {module}.{name}")
        if (module, name) == ("__main__", "Base"):
            return train_eval.Base
        return super().find_class(module, name)


def restricted_load(path):
    with open(path, "rb") as f:
        with _validate_fileobject_and_memmap(f, str(path), None) as (fobj, _):
            return RestrictedUnpickler(str(path), fobj, True).load()


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", help="another test folder with its own .hasil/rows.jsonl (default: this folder)")
    ap.add_argument("--limit", type=int, help="smoke test: score only the first N pages")
    args = ap.parse_args()
    base_dir = Path(args.dir).resolve() if args.dir else HERE
    rows = [json.loads(line) for line in open(base_dir / ".hasil/rows.jsonl", encoding="utf-8")]
    if args.limit:
        rows = rows[: args.limit]
    base = restricted_load(ALIEF_OUT / "layer3_base.joblib")["base"]
    meta = restricted_load(ALIEF_OUT / "layer3_meta.joblib")
    model = load_model()
    out_path = base_dir / ".hasil/results.jsonl"
    started, n_chunks, BATCH = time.time(), 0, 128
    with open(out_path, "w", encoding="utf-8") as out:
        for i in range(0, len(rows), BATCH):
            batch = rows[i : i + BATCH]
            parts, idx = [], []
            for j, r in enumerate(batch):
                for c in chunks(r):
                    parts.append(c)
                    idx.append(j)
            idx = np.array(idx, dtype=np.int32)
            emb = encode(model, parts)
            n_chunks += len(parts)
            mean = np.zeros((len(batch), emb.shape[1]), dtype=np.float32)
            np.add.at(mean, idx, emb)
            mean /= np.bincount(idx, minlength=len(batch))[:, None]
            scores = base.score(batch, emb, idx, mean)
            side = train_eval.side_matrix(batch)
            with_address = meta["metas"]["with_address"].predict_proba(np.hstack([scores, side]))[:, 1]
            no_address = meta["metas"]["no_address"].predict_proba(np.hstack([scores[:, :4], side[:, meta["no_address_columns"]]]))[:, 1]
            final = (with_address + no_address) / 2
            per_chunk = np.maximum(base.chunk.predict_proba(emb)[:, 1], base.gamble.predict_proba(emb)[:, 1])
            for j, r in enumerate(batch):
                group = "indonesian" if train_eval.is_indonesian(r) else "other"
                limits = meta["thresholds"][group]
                official = bool(r["feats"].get("official"))
                tier = "safe" if official else next((t for t in ("block", "warn", "gate") if final[j] >= limits[t]), "safe")
                evidence = None
                if tier != "safe":
                    ids = np.where(idx == j)[0]
                    evidence = parts[int(ids[np.argmax(per_chunk[ids])])].split("\n", 1)[-1][:240]
                rules = r["baseline"]["score"]
                out.write(json.dumps({
                    "id": r["id"], "dataset": r["dataset"], "label": r["label"], "url": r["url"], "host": r["host"], "title": r["title"][:120],
                    "text_len": len(r["text"]), "text_excerpt": r["text"][:300], "forms": r["feats"]["forms"], "password_field": r["feats"]["passwordField"],
                    "her": {"score": rules, "signals": r["baseline"]["signals"], "caught": rules >= 30},
                    "alief": {"final": round(float(final[j]), 4), "with_address": round(float(with_address[j]), 4), "no_address": round(float(no_address[j]), 4),
                              "base_scores": {n: round(float(v), 3) for n, v in zip(train_eval.Base.NAMES, scores[j])},
                              "tier": tier, "language_group": group, "official": official, "evidence": evidence},
                }, ensure_ascii=False) + "\n")
            print(f"{min(i + BATCH, len(rows))}/{len(rows)} pages, {n_chunks} chunks, {time.time() - started:.0f} s", flush=True)
    json.dump({"pages": len(rows), "chunks": n_chunks, "seconds": round(time.time() - started), "device": str(model.device),
               "base_sha256": sha256(ALIEF_OUT / "layer3_base.joblib"), "meta_sha256": sha256(ALIEF_OUT / "layer3_meta.joblib"),
               "thresholds": meta["thresholds"]}, open(base_dir / ".hasil/score-meta.json", "w"), indent=1)
    print("done")


if __name__ == "__main__":
    main()
