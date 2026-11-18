"""Step 4 (v7): write HASIL.md from the scored pages.

Usage: python3 -I report.py
Reads .hasil/{sample-meta.json, sample-input.jsonl (tags only), rows.jsonl, results.jsonl (Alief, optional), eyecheck.jsonl}
      shoo-impersonation-lab/out/{impersonation,all}/applied-v7*.jsonl, shoo-impersonation-lab/popular.py (Tranco top 1000)
Writes HASIL.md (and detail.csv: one line per page, scores and tiers only, no page text, hosts defanged).
Everything below the ANALISIS marker in an existing HASIL.md is kept.
"""
import collections
import csv
import json
import re
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
H = HERE / ".hasil"
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
sys.path.insert(0, str(LAB))
from popular import Popular  # noqa: E402  (stdlib only)

MARK = "<!-- ANALISIS: tulisan di bawah baris ini tidak ditimpa oleh report.py -->"
# Pages that hold no site of their own: parked, for sale, expired, coming soon, server default, bot check, error.
DEAD = re.compile(
    r"for sale|domain (name )?(has )?expired|registration has expired|has expired|parked|coming soon|under construction|en construction|"
    r"maintenance|checking your browser|verify you.{0,8}re human|confirm you are human|security check|welcome to nginx|apache.{0,20}(default|test) page|"
    r"it works!|dns resolution error|does not exist|not found|404|account (has been )?suspended|domain is suspended|fatal error|"
    r"has been (recently )?registered|registered with|hello world! welcome to wordpress|just another wordpress site|не прилинкован|"
    r"site is undergoing|website is under|this domain|domain name", re.I)


def defang(h):
    return h.replace(".", "[.]")


def auc(y, s):
    """Mann-Whitney AUC with average ranks for ties (no scikit-learn needed)."""
    y = np.asarray(y)
    s = np.asarray(s, dtype=float)
    n1, n0 = int((y == 1).sum()), int((y == 0).sum())
    if not n1 or not n0:
        return float("nan")
    order = np.argsort(s, kind="mergesort")
    sv = s[order]
    ranks = np.empty(len(s))
    i = 0
    while i < len(sv):
        j = i
        while j + 1 < len(sv) and sv[j + 1] == sv[i]:
            j += 1
        ranks[order[i:j + 1]] = (i + j + 2) / 2
        i = j + 1
    return (ranks[y == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0)


def n_(n):
    """Indonesian thousands separator: 12.367"""
    return f"{int(n):,}".replace(",", ".")


def pct(a, b):
    if not b:
        return "-"
    return f"{n_(a)} dari {n_(b)} ({f'{100 * a / b:.1f}'.replace('.', ',')}%)"


def load_applied(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        d = json.loads(line)
        out[d["id"]] = d
    return out


def fresh_section():
    """Section 6: the 1.239 non-Kaggle rows (Alief's feed of 2026-11-09, manual lists), fetched once by fresh.mjs."""
    F = HERE / "fresh/.hasil"
    if not (F / "rows.jsonl").exists():
        return []
    meta = json.load(open(F / "sample-meta.json"))
    tags = {}
    for line in open(F / "sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        tags[d["id"]] = d["tags"]
    rows = [json.loads(line) for line in open(F / "rows.jsonl", encoding="utf-8")]
    ids = [r["id"] for r in rows]
    y = np.array([r["label"] for r in rows])
    grp = np.array(["seen" if tags[i]["group"] in ("train", "dev") else tags[i]["group"] for i in ids])
    rs = np.array([r["baseline"]["score"] for r in rows])
    pipes = {"Rules sekarang": np.where(rs >= 80, "block", np.where(rs >= 30, "warn", "safe"))}
    if (F / "results.jsonl").exists():
        al = {}
        for line in open(F / "results.jsonl", encoding="utf-8"):
            d = json.loads(line)
            al[d["id"]] = d["alief"]["tier"]
        pipes["Alief (bge-m3)"] = np.array([al[i] for i in ids])
    pop = load_applied(LAB / "out/impersonation/applied-v7-fresh-pop1000.jsonl")
    pipes["**Ours, impersonation + popular 1.000**"] = np.array([pop[i]["tier"] for i in ids])
    L = ["## 6. Link segar: feed phishing Alief 2026-11-09 dan daftar manual (diambil ulang hari ini)", "",
         "Baris non-Kaggle di CSV tidak punya snapshot. `fresh.mjs` mengambil tiap link sekali (GET statis, tanpa JavaScript, sama seperti `pages.mjs`). "
         f"Terbuka dengan isi dan tidak pindah host: **{n_(meta['kept'])}** dari 1.239 (kosong {meta['skipped'].get('kosong', 0)}, gagal {meta['skipped'].get('gagal', 0)}, "
         f"pindah host {meta['skipped'].get('moved_to_other_host', 0)}). "
         "Sebagian besar situs feed ini ada di data latih Alief (`seen`), jadi hanya baris `unseen` yang adil.", "",
         "| Kelompok | Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block |",
         "|---|---|---|---|---|---|---|"]
    for g, gname in (("unseen", "unseen"), ("test", "test split Alief"), ("seen", "train/dev Alief")):
        for name, t in pipes.items():
            cells = []
            for lab in (1, 0):
                m = (grp == g) & (y == lab)
                n = int(m.sum())
                cells += [pct(int((t[m] != "safe").sum()), n), pct(int(np.isin(t[m], ("warn", "block")).sum()), n)]
                if lab == 1:
                    cells.append(pct(int((t[m] == "block").sum()), n))
            L.append(f"| {gname} | {name} | " + " | ".join(cells) + " |")
    if (F / "eyecheck.jsonl").exists():
        eye = [json.loads(line) for line in open(F / "eyecheck.jsonl", encoding="utf-8")]
        cats = ("masih_scam", "mati_parkir", "normal", "konten_buruk", "tidak_jelas")
        L += ["", "**Cek mata link segar (unseen, label scam), dibaca Claude dari teks tersimpan**", "",
              "| Kelompok | Ukuran kelompok | Dibaca | " + " | ".join(f"`{c}`" for c in cats) + " |", "|---|---|---|" + "---|" * len(cats)]
        for s, sname in (("S6", "ours safe (semua)"), ("S7", "ours gate/warn/block (acak)")):
            e = [x for x in eye if x["stratum"] == s]
            if e:
                c = collections.Counter(x["cek"] for x in e)
                L.append(f"| {s} {sname} | {e[0]['pool']} | {len(e)} | " + " | ".join(str(c.get(k, 0)) for k in cats) + " |")
    L += ["", "**Link aman manual (`manual_link_aman`) yang ours tandai warn/block**", "", "| host | judul | kelompok | ours (+popular) |", "|---|---|---|---|"]
    for i, r in enumerate(rows):
        if r["label"] == 0 and pop[r["id"]]["tier"] in ("warn", "block"):
            L.append(f"| `{defang(r['host'])}` | `{re.sub(r'[|`]', ' ', r['title'] or '')[:60]}` | {tags[r['id']]['group']} | {pop[r['id']]['final']:.2f} {pop[r['id']]['tier']} |")
    return L + [""]


def main():
    meta = json.load(open(H / "sample-meta.json"))
    rows = [json.loads(line) for line in open(H / "rows.jsonl", encoding="utf-8")]
    tags = {}
    for line in open(H / "sample-input.jsonl", encoding="utf-8"):
        d = json.loads(line)
        tags[d["id"]] = d["tags"]
    ids = [r["id"] for r in rows]
    y = np.array([r["label"] for r in rows])
    P = Popular(1000)
    popular = np.array([P.is_popular(r["host"]) for r in rows])
    dead = np.array([bool(DEAD.search((r["title"] or "") + " " + (r["text"] or "")[:600])) for r in rows])
    pw = np.array([bool(r["feats"]["passwordField"]) for r in rows])
    group = np.array([tags[i]["group"] for i in ids])
    in_v5 = np.array([tags[i]["in_v5"] for i in ids])
    rank3 = np.array([tags[i]["site_rank"] <= 3 for i in ids])

    imp = load_applied(LAB / "out/impersonation/applied-v7.jsonl")
    pop = load_applied(LAB / "out/impersonation/applied-v7-pop1000.jsonl")
    allv = load_applied(LAB / "out/all/applied-v7.jsonl")
    rules_score = np.array([r["baseline"]["score"] for r in rows])
    rules_tier = np.where(rules_score >= 80, "block", np.where(rules_score >= 30, "warn", "safe"))
    BEST = "**Ours, impersonation + popular 1.000**"
    pipes = {"Rules sekarang": (rules_tier, rules_score)}
    alief = None
    if (H / "results.jsonl").exists():
        alief = {}
        for line in open(H / "results.jsonl", encoding="utf-8"):
            d = json.loads(line)
            alief[d["id"]] = d["alief"]
    if alief and all(i in alief for i in ids):  # train-page.jsonl holds 7 ids twice, so compare ids, not counts
        at = np.array([alief[i]["tier"] for i in ids])
        af = np.array([alief[i]["final"] for i in ids])
        pipes["Alief (bge-m3)"] = (at, af)
        pipes["Alief + popular 1.000"] = (np.where(popular, "safe", at), af)
    pipes["Ours, semua tipe scam"] = (np.array([allv[i]["tier"] for i in ids]), np.array([allv[i]["final"] for i in ids]))
    pipes["Ours, impersonation"] = (np.array([imp[i]["tier"] for i in ids]), np.array([imp[i]["final"] for i in ids]))
    pipes[BEST] = (np.array([pop[i]["tier"] for i in ids]), np.array([pop[i]["final"] for i in ids]))

    def table(mask, title):
        L = [f"### {title}", "", f"Scam {n_(int((mask & (y == 1)).sum()))} halaman, legit {n_(int((mask & (y == 0)).sum()))} halaman.", "",
             "| Pipeline | Scam: sampai L4 atau ditandai | Scam: warn atau block | Scam: block | Legit: sampai L4 atau ditandai | Legit: warn atau block | Legit: block | AUC |",
             "|---|---|---|---|---|---|---|---|"]
        for name, (t, s) in pipes.items():
            cells = []
            for lab in (1, 0):
                m = mask & (y == lab)
                n = int(m.sum())
                cells += [pct(int((t[m] != "safe").sum()), n), pct(int(np.isin(t[m], ("warn", "block")).sum()), n), pct(int((t[m] == "block").sum()), n)]
            L.append(f"| {name} | " + " | ".join(cells) + f" | {f'{auc(y[mask], s[mask]):.3f}'.replace('.', ',')} |")
        return L + [""]

    unseen = group == "unseen"
    out = ["# Hasil v7: model impersonation pada data maliciousphish (database-link-label.csv)", "",
           "_Dibuat oleh `report.py` dari `.hasil/`. Host ditulis dengan `[.]`: jangan dibuka. Repo publik: baca sebelum commit._", "",
           "## 0. Cara membaca", "",
           "- **Data:** `test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/database-link-label.csv` (177.648 link, label Kaggle `malicious_phish`). "
           "Halaman tidak dibuka ulang: dipakai snapshot yang sudah tersimpan di `train-page.jsonl` (id sama). Hanya halaman yang terbuka dengan isi dan tidak pindah host.",
           "- **Pipeline:** rules sekarang (`analyzeSnapshot`), Alief (bge-m3), dan model kita. Layer 1, 2, 4 dan umur domain mati, jadi ini hasil layer 3 saja.",
           "- **Unseen** = situs yang tidak ada di train/dev Alief (model kita juga dilatih dari data Alief). Ini perbandingan yang adil.",
           "- **Peringatan besar:** laporan v4 data ini menemukan 92 dari 100 halaman berlabel scam sudah bukan scam lagi. Bagian 3 (cek mata) mengulang pemeriksaan itu. "
           "Angka di bagian 2 memakai label mentah dan **tidak** mengukur kemampuan menangkap scam sungguhan.", ""]
    out += ["## 1. Halaman", "",
            "| Tahap | Jumlah |", "|---|---|",
            f"| Link di CSV | {n_(meta['csv_links'])} (scam {n_(meta['csv_label']['scam'])}, normal {n_(meta['csv_label']['normal'])}) |",
            f"| Halaman `ok` di CSV | {n_(meta['csv_halaman'].get('ok', 0))} |",
            f"| Dibuang: pindah ke host lain | {n_(meta['skipped'].get('moved_to_other_host', 0))} |",
            f"| Dibuang: kosong / tidak ada di CSV | {n_(meta['skipped'].get('empty_page', 0))} / {n_(meta['skipped'].get('not_in_csv', 0))} |",
            f"| **Dinilai** | **{n_(meta['kept'])}** halaman dari {n_(meta['sites'])} situs |"]
    for g in ("unseen", "seen-by-alief"):
        m = group == g
        out.append(f"| {g} | scam {n_(int((m & (y == 1)).sum()))}, legit {n_(int((m & (y == 0)).sum()))} |")
    out.append(f"| Sudah dipakai di v5 (unseen) | {n_(int((in_v5 & unseen).sum()))} |")
    out.append(f"| Domain di Tranco top 1.000 | {n_(int(popular.sum()))} (scam {n_(int((popular & (y == 1)).sum()))}, legit {n_(int((popular & (y == 0)).sum()))}) |")
    out += ["", "## 2. Hasil dengan label mentah", ""]
    out += table(unseen, "Situs unseen (perbandingan adil)")
    out += table(unseen & ~in_v5, "Situs unseen, belum pernah dipakai di v5 (data baru sungguhan)")
    out += table(unseen & rank3, "Situs unseen, maksimal 3 halaman per situs")
    out += table(unseen & pw, "Situs unseen, halaman dengan password field")
    out += table(np.ones(len(rows), dtype=bool), "Semua halaman, termasuk situs yang dilatih Alief")

    eye = [json.loads(line) for line in open(H / "eyecheck.jsonl", encoding="utf-8")]
    names = {"S1": "Label scam, ours warn/block", "S2": "Label legit, ours warn/block", "S3": "Label scam + password field, ours safe",
             "S4": "Label scam, acak", "S5": "Label legit, ours gate"}
    cats = ("masih_scam", "mati_parkir", "normal", "konten_buruk", "tidak_jelas")
    out += ["## 3. Cek mata (dari teks tersimpan, tanpa membuka link)", "",
            "Situs unseen, model ours + popular 1.000, maksimal 1 halaman per situs, seed tetap. Dibaca oleh Claude dari judul, 400 karakter pertama, "
            "dan jenis field form. Belum dicek manusia.", "",
            "| Kelompok | Ukuran kelompok | Dibaca | " + " | ".join(f"`{c}`" for c in cats) + " |", "|---|---|---|" + "---|" * len(cats)]
    for s in names:
        e = [x for x in eye if x["stratum"] == s]
        c = collections.Counter(x["cek"] for x in e)
        out.append(f"| {s} {names[s]} | {n_(e[0]['pool'])} | {len(e)} | " + " | ".join(str(c.get(k, 0)) for k in cats) + " |")
    out += ["", "`mati_parkir`: dijual, kedaluwarsa, diparkir, segera hadir, halaman default server, cek bot, halaman error. "
            "`konten_buruk`: judi atau porno di domain yang diambil alih, bukan peniruan brand.", ""]

    out += ["## 4. Halaman tanpa isi situs (parkir, error, cek bot)", "",
            "Ditandai dengan pola teks sederhana di `report.py` (`DEAD`). Perkiraan kasar: bisa salah ke dua arah.", "",
            "| Situs unseen | Halaman | Bagian dari semua warn/block ours (+popular) di label ini | Ours warn/block di kelompok ini |", "|---|---|---|---|"]
    t = pipes[BEST][0]
    flagged = np.isin(t, ("warn", "block"))
    for lab, name in ((1, "scam"), (0, "legit")):
        allf = unseen & (y == lab) & flagged
        for dm, dn in ((dead, "mirip parkir/error"), (~dead, "lainnya")):
            m = unseen & (y == lab) & dm
            out.append(f"| {name}, {dn} | {n_(int(m.sum()))} | {pct(int((flagged & m).sum()), int(allf.sum()))} | {pct(int((flagged & m).sum()), int(m.sum()))} |")
    out.append("")

    def ex(mask, n=8, rev=True):
        idx = list(np.where(mask)[0])
        idx.sort(key=lambda i: pipes[BEST][1][i], reverse=rev)
        L = ["| id | host | judul | rules | ours (+popular) |", "|---|---|---|---|---|"]
        for i in idx[:n]:
            r = rows[i]
            title = re.sub(r"[|`\n]", " ", r["title"] or "")[:60]
            L.append(f"| `{r['id']}` | `{defang(r['host'])}` | `{title}` | {int(rules_score[i])} | {pop[r['id']]['final']:.2f} {pop[r['id']]['tier']} |")
        return L + [""]

    out += ["## 5. Contoh (situs unseen)", "", "**Legit yang paling yakin di-warn/block ours (bukan parkir/error)**", ""]
    out += ex(unseen & (y == 0) & flagged & ~dead)
    out += ["**Scam dengan password field yang ours anggap aman (skor terendah)**", ""]
    out += ex(unseen & (y == 1) & pw & (t == "safe"), rev=False)

    out += fresh_section()

    old = (HERE / "HASIL.md").read_text(encoding="utf-8") if (HERE / "HASIL.md").exists() else ""
    tail = old.split(MARK, 1)[1] if MARK in old else "\n"
    (HERE / "HASIL.md").write_text("\n".join(out) + "\n" + MARK + tail, encoding="utf-8")

    others = [k for k in pipes if k != "Rules sekarang"]
    with open(HERE / "detail.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "group", "in_v5", "label", "host", "password_field", "popular", "dead_like", "rules"] + [k.strip("*") for k in others])
        for i, r in enumerate(rows):
            w.writerow([r["id"], group[i], int(in_v5[i]), r["label"], defang(r["host"]), int(pw[i]), int(popular[i]), int(dead[i]), int(rules_score[i])]
                       + [pipes[k][0][i] for k in others])
    print("wrote HASIL.md and detail.csv", "with Alief" if "Alief (bge-m3)" in pipes else "(Alief missing)")


if __name__ == "__main__":
    main()
