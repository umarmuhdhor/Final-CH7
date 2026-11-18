"""v7 extra: is "the page sends you to t.me / wa.me" a useful no-LLM signal next to model v2?

Usage (lab environment):
  cd ~/Documents/Swift/Final-CH/shoo-impersonation-lab
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/links_measure.py prep     -> .hasil/links-todo.jsonl
  node <this folder>/links_fetch.mjs                                                                -> .hasil/links.jsonl
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/links_measure.py report   -> LINKS.md
Pages: fresh feed (scam, plus the manual safe links), Kaggle unseen legit (the same 1,500 sites as RDAP.md), legit Indonesian pages of
the iteration-1 calibration set (phishing-url v4 train+dev and Alief test). Model: v2 (out/impersonation-v2) with its outside-calibrated
cut-offs, popular top 1000 on. No LLM: only warn/block count as flagged.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(HERE))
import rdap_measure as R  # noqa: E402
import train as T1  # noqa: E402
import train2 as T2  # noqa: E402

CLAIM = re.compile(r"klaim|hadiah|bansos|bantuan sosial|undian|pencairan|refund|pembatalan|verifikasi|aktivasi|diblokir|blokir|call center|"
                   r"customer service|\bcs\b|pinjaman|investasi|profit|saldo dana|dana gratis|menang", re.I)


def load(p):
    return [json.loads(line) for line in open(p, encoding="utf-8")]


def groups():
    fresh = load(HERE / "fresh/.hasil/rows.jsonl")
    cal = {r["id"]: r for r in load(LAB / "iter1-idcal/.hasil/rows.jsonl") + load(LAB / "iter1-idcal/alief-test-indo.jsonl")}
    return {
        "scam_fresh": [r for r in fresh if r["label"] == 1],
        "legit_manual": [r for r in fresh if r["label"] == 0],
        "legit_kaggle": R.sets()["legit_kaggle_sample"],
        "legit_indonesian": [r for r in cal.values() if r["label"] == 0 and T2.is_indonesian(r)],
    }


def prep():
    out = HERE / ".hasil/links-todo.jsonl"
    if out.exists():
        raise SystemExit(".hasil/links-todo.jsonl exists: not overwriting")
    n = 0
    with open(out, "w", encoding="utf-8") as f:
        for name, rows in groups().items():
            for r in rows:
                url = r["url"] if "//" in r["url"] else "http://" + r["url"]
                f.write(json.dumps({"id": r["id"], "url": url, "set": name, "label": r["label"]}) + "\n")
                n += 1
    print("pages", n)


def report():
    from popular import Popular
    P = Popular(1000)
    th = json.load(open(LAB / "out/impersonation-v2/thresholds-idcal.json"))["final"]
    fin = {}
    for t in ("v2-v7-fresh", "v2-v7", "v2-idcal-v4", "v2-idcal-alieftest"):
        fin.update({d["id"]: d["final"] for d in load(LAB / f"out/impersonation-v2/applied-{t}.jsonl")})
    links = {d["id"]: d for d in load(HERE / ".hasil/links.jsonl")}
    fit_rows = [r for r in T1.load_rows() if r["split"] in ("train", "dev")]
    a_sites, a_hosts = {T1.site(r["host"]) for r in fit_rows}, {r["host"] for r in fit_rows}

    def unseen(r):
        return (r["host"] not in a_hosts) if r["feats"]["sharedHost"] else (T1.site(r["host"]) not in a_sites)

    def tier(r):
        off = bool(r["feats"].get("official")) or P.is_popular(r["host"])
        return T1.tier_names([fin[r["id"]]], [T2.is_indonesian(r)], [off], th)[0]

    G = groups()
    G["scam_fresh_unseen"] = [r for r in G["scam_fresh"] if unseen(r)]
    order = ["scam_fresh_unseen", "scam_fresh", "legit_kaggle", "legit_indonesian", "legit_manual"]
    L = ["# Link keluar ke aplikasi chat (t.me, wa.me, ...) sebagai sinyal tanpa LLM", "",
         "_Dibuat oleh `links_measure.py report`. Halaman diambil ulang sekali (GET statis, tanpa JavaScript) hanya untuk menghitung link; "
         "HTML tidak disimpan. Model: v2, ambang kalibrasi luar, popular 1.000 aktif._", "",
         "## Seberapa sering ada link chat", "",
         "| Kelompok | Halaman | Terbuka lagi | Ada link chat (href) | Link chat hanya di script/onclick | Paling sering |", "|---|---|---|---|---|---|"]
    for name in order:
        rows = G[name]
        ok = [links[r["id"]] for r in rows if links.get(r["id"], {}).get("keadaan") == "ok"]
        href = [d for d in ok if d["msg"]]
        script_only = [d for d in ok if not d["msg"] and d["msg_in_script"]]
        top = {}
        for d in href:
            for h in d["msg"]:
                top[h] = top.get(h, 0) + 1
        tops = ", ".join(f"`{h}` {c}" for h, c in sorted(top.items(), key=lambda x: -x[1])[:3])
        n = len(ok)
        L.append(f"| {name} | {len(rows)} | {n} | {len(href)} ({round(100 * len(href) / n) if n else 0}%) | {len(script_only)} | {tops or '-'} |")
    L += ["", "## Aturan yang dicoba", "",
          "- **Model**: warn/block dari model v2 saja.",
          "- **R1**: ada link chat (href atau script) langsung warn.",
          "- **R2**: ada link chat **dan** kata klaim/CS/bansos/verifikasi di judul atau teks.",
          "- **R3**: ada link chat **dan** model minimal `gate`.",
          "- **R4**: ada link chat **dan** halaman sedikit link (paling banyak 15) atau minimal 30% link-nya ke chat (halaman yang isinya mengarahkan ke chat).",
          "", "Halaman yang gagal dibuka lagi dihitung tanpa link (model saja).", "",
          "| Aturan | " + " | ".join(order) + " |", "|---|" + "---|" * len(order)]

    def flagged(rule):
        cells = []
        for name in order:
            rows = G[name]
            k = 0
            for r in rows:
                d = links.get(r["id"], {})
                has = d.get("keadaan") == "ok" and (bool(d["msg"]) or d["msg_in_script"])
                t = tier(r)
                claim = bool(CLAIM.search((r["title"] or "") + " " + (r["text"] or "")[:4000]))
                funnel = has and (d.get("links_total", 0) <= 15 or sum(d["msg"].values()) / max(1, d.get("links_total", 0)) >= 0.3)
                extra = {"Model": False, "R1": has, "R2": has and claim, "R3": has and t != "safe", "R4": funnel}[rule]
                k += bool(t in ("warn", "block") or extra)
            cells.append(f"{k}/{len(rows)} ({f'{100 * k / len(rows):.1f}'.replace('.', ',')}%)" if rows else "-")
        return cells

    for rule in ("Model", "R1", "R2", "R3", "R4"):
        L.append(f"| {rule} | " + " | ".join(flagged(rule)) + " |")
    L.append("")
    (HERE / "LINKS.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("\n".join(L))


if __name__ == "__main__":
    {"prep": prep, "report": report}[sys.argv[1]]()
