"""v7 extra: eye-check 50 pages that model v2 flags (warn/block) without an LLM: 25 labelled legit, 25 labelled scam.

Usage (lab environment):
  cd ~/Documents/Swift/Final-CH/shoo-impersonation-lab
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/eyecheck50.py pick     -> .hasil/eyecheck50/pick.jsonl
  node <this folder>/eyecheck50_shot.mjs                                                          -> .hasil/eyecheck50/ss/<id>.png
  (write .hasil/eyecheck50/verdict.json by hand after looking at every screenshot)
  uv run --python 3.12 --project ../shoo-layer3-lab python <this folder>/eyecheck50.py report   -> .hasil/eyecheck50/laporan.html
Legit: all flagged manual safe links, then flagged Indonesian legit and Kaggle legit (seeded random). Scam: flagged fresh-feed unseen
scams, half warn and half block where possible. Everything stays under .hasil/ (gitignored): the report holds full URLs.
"""
import ast
import html
import json
import random
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = Path.home() / "Documents/Swift/Final-CH/shoo-impersonation-lab"
sys.path.insert(0, str(LAB))
sys.path.insert(0, str(HERE))
import links_measure as LM  # noqa: E402
import train as T1  # noqa: E402
import train2 as T2  # noqa: E402

OUT = HERE / ".hasil/eyecheck50"
SEED = 50


def load(p):
    return [json.loads(line) for line in open(p, encoding="utf-8")]


def feats(r):
    f = r["feats"]
    return f if isinstance(f, dict) else ast.literal_eval(f)


def pick():
    from popular import Popular
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "pick.jsonl"
    if out.exists():
        raise SystemExit("pick.jsonl exists: not overwriting")
    P = Popular(1000)
    th = json.load(open(LAB / "out/impersonation-v2/thresholds-idcal.json"))["final"]
    app = {}
    for t in ("v2-v7-fresh", "v2-v7", "v2-idcal-v4", "v2-idcal-alieftest"):
        app.update({d["id"]: d for d in load(LAB / f"out/impersonation-v2/applied-{t}.jsonl")})
    links = {d["id"]: d for d in load(HERE / ".hasil/links.jsonl")}
    fit_rows = [r for r in T1.load_rows() if r["split"] in ("train", "dev")]
    a_sites, a_hosts = {T1.site(r["host"]) for r in fit_rows}, {r["host"] for r in fit_rows}

    def info(r, group):
        f = feats(r)
        r = dict(r, feats=f)
        indo = T2.is_indonesian(r)
        off = bool(f.get("official")) or P.is_popular(r["host"])
        a = app[r["id"]]
        tier = T1.tier_names([a["final"]], [indo], [off], th)[0]
        lk = links.get(r["id"], {})
        return {"id": r["id"], "group": group, "label": int(r["label"]), "url": r["url"], "host": r["host"],
                "title": r.get("title") or "", "text": (r.get("text") or "")[:400], "tier": tier, "final": a["final"],
                "words": a["words"], "address": a["address"], "indonesian": indo, "sharedHost": bool(f.get("sharedHost")),
                "chat": lk.get("msg") or {}, "passwordField": bool(f.get("passwordField")), "forms": f.get("forms", 0)}

    G = LM.groups()
    rnd = random.Random(SEED)
    legit = []
    for group, cap in (("legit_manual", 25), ("legit_indonesian", 8), ("legit_kaggle", 25)):
        rows = [x for x in (info(r, group) for r in G[group]) if x["tier"] in ("warn", "block")]
        rnd.shuffle(rows)
        legit += rows[:min(cap, 25 - len(legit))]
    scam_rows = []
    for r in G["scam_fresh"]:
        f = feats(r)
        uns = (r["host"] not in a_hosts) if f.get("sharedHost") else (T1.site(r["host"]) not in a_sites)
        if uns:
            x = info(r, "scam_fresh_unseen")
            if x["tier"] in ("warn", "block"):
                scam_rows.append(x)
    rnd.shuffle(scam_rows)
    blocks = [x for x in scam_rows if x["tier"] == "block"][:13]
    warns = [x for x in scam_rows if x["tier"] == "warn"][:25 - len(blocks)]
    picked = legit + blocks + warns
    with open(out, "w", encoding="utf-8") as f:
        for x in picked:
            f.write(json.dumps(x, ensure_ascii=False) + "\n")
    print("picked", len(picked), dict(Counter((x["group"], x["tier"]) for x in picked)))


def defang(u):
    return u.replace(".", "[.]").replace("http", "hxxp", 1)


def report():
    rows = load(OUT / "pick.jsonl")
    shots = {d["id"]: d for d in load(OUT / "shots.jsonl")} if (OUT / "shots.jsonl").exists() else {}
    verdict = json.load(open(OUT / "verdict.json")) if (OUT / "verdict.json").exists() else {}
    V = {"benar": ("Benar ditandai", "ok"), "salah": ("Salah tanda", "bad"), "ragu": ("Ragu / tak terbaca", "meh")}

    def summary(label):
        rs = [r for r in rows if r["label"] == label]
        return len(rs), {k: sum(1 for r in rs if verdict.get(r["id"], {}).get("v") == k) for k in V}

    nl, cl = summary(0)
    ns, cs = summary(1)
    trs = []
    for i, r in enumerate(rows):
        v = verdict.get(r["id"], {})
        vt, vc = V.get(v.get("v"), ("Belum dicek", "meh"))
        s = shots.get(r["id"], {})
        img = (f'<img loading="lazy" src="ss/{r["id"]}.png" alt="Screenshot halaman {html.escape(r["host"])}">'
               if s.get("ok") else f'<span class="noshot">Tidak ada screenshot: {html.escape(s.get("why", "belum diambil"))}</span>')
        chat = ", ".join(f"{h} ×{n}" for h, n in r["chat"].items()) or "-"
        trs.append(f"""
<tr data-label="{r['label']}" data-v="{v.get('v', '')}">
  <td class="num">{i + 1}</td>
  <td class="shot">{img}</td>
  <td><span class="lab l{r['label']}">{'Legit' if r['label'] == 0 else 'Scam'}</span></td>
  <td><span class="tier t-{r['tier']}">{r['tier']}</span></td>
  <td><span class="verd {vc}">{vt}</span></td>
  <td class="page"><b>{html.escape(r['title'][:120]) or '<i>(tanpa judul)</i>'}</b><code>{html.escape(defang(r['url'])[:160])}</code></td>
  <td class="num">{r['final']:.3f}<br><small>kata {r['words']:.2f} · alamat {r['address']:.2f}</small></td>
  <td>{'Indonesia' if r['indonesian'] else 'lain'}{'<br><small>hosting bersama</small>' if r['sharedHost'] else ''}</td>
  <td>{r['forms']}{'<br><small>password</small>' if r['passwordField'] else ''}</td>
  <td>{html.escape(chat)}</td>
  <td class="note">{html.escape(v.get('why', ''))}</td>
</tr>""")

    def line(n, c):
        return f"{c['benar']} benar · {c['salah']} salah · {c['ragu']} ragu (dari {n})"

    taken = next(iter(shots.values()), {}).get("at", "-")
    page = f"""<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cek Mata v2</title><style>
:root{{--bg:#f7f7f5;--card:#fff;--fg:#1b1b1b;--mut:#666;--line:#e3e3df;--ok:#1f7a3f;--bad:#b42318;--meh:#8a6d00;--warn:#b25e00;--block:#b42318}}
@media (prefers-color-scheme:dark){{:root{{--bg:#151515;--card:#1f1f1f;--fg:#eee;--mut:#aaa;--line:#333;--ok:#5cc489;--bad:#ff7b72;--meh:#e3c25a;--warn:#ffa657;--block:#ff7b72}}}}
body{{background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:24px 16px}}
main{{max-width:1100px;margin:auto}} h1{{font-size:24px;margin:0 0 6px}} .sub{{color:var(--mut);margin:0 0 18px}}
.sum{{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:16px}} .sum div{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 14px}}
.filters{{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px}} .filters button{{border:1px solid var(--line);background:var(--card);color:var(--fg);border-radius:999px;padding:6px 12px;cursor:pointer}}
.filters button[aria-pressed=true]{{background:var(--fg);color:var(--bg)}}
.wrap{{overflow-x:auto;background:var(--card);border:1px solid var(--line);border-radius:10px}}
table{{border-collapse:collapse;width:100%;min-width:1100px;font-size:13px}}
th,td{{text-align:left;vertical-align:top;padding:8px 10px;border-bottom:1px solid var(--line)}}
th{{position:sticky;top:0;background:var(--card);font-size:12px;color:var(--mut);font-weight:600;z-index:1}}
td.num{{font-variant-numeric:tabular-nums;white-space:nowrap}} small{{color:var(--mut)}}
td.shot{{width:110px}} .shot img{{width:100px;height:180px;object-fit:cover;object-position:top;display:block;border:1px solid var(--line);border-radius:4px;cursor:zoom-in}}
.noshot{{display:block;width:100px;font-size:11px;color:var(--mut)}}
td.page{{max-width:280px}} td.page b{{display:block;overflow-wrap:anywhere}} td.page code{{display:block;font-size:11px;color:var(--mut);overflow-wrap:anywhere;margin-top:4px}}
td.note{{max-width:260px}} .lab,.tier,.verd{{font-size:12px;font-weight:600;white-space:nowrap}}
.lab.l0{{color:var(--ok)}} .lab.l1{{color:var(--bad)}} .t-warn{{color:var(--warn)}} .t-block{{color:var(--block)}}
.verd.ok{{color:var(--ok)}} .verd.bad{{color:var(--bad)}} .verd.meh{{color:var(--meh)}}
dialog{{max-width:min(95vw,600px);max-height:92vh;padding:0;border:0}} dialog img{{width:100%;display:block}}
</style></head><body><main>
<h1>Cek mata model v2: 50 halaman yang ditandai</h1>
<p class="sub">Model v2 tanpa LLM, popular 1.000 aktif. Hanya halaman warn/block. Screenshot diambil {html.escape(taken)} dengan Chrome headless,
layar iPhone 390×844, tanpa klik/ketik. URL disamarkan (hxxp, [.]). <b>Jangan buka link scam.</b> Klik gambar untuk memperbesar.</p>
<div class="sum"><div><b>Legit ditandai</b><br>{line(nl, cl)}</div><div><b>Scam ditandai</b><br>{line(ns, cs)}</div></div>
<div class="filters" role="group" aria-label="Filter">
<button aria-pressed="true" data-f="all">Semua</button><button aria-pressed="false" data-f="l0">Legit</button>
<button aria-pressed="false" data-f="l1">Scam</button><button aria-pressed="false" data-f="salah">Salah tanda</button><button aria-pressed="false" data-f="ragu">Ragu</button></div>
<div class="wrap"><table><thead><tr><th>#</th><th>Screenshot</th><th>Label</th><th>Tingkat</th><th>Cek mata</th><th>Halaman</th>
<th>Skor final</th><th>Bahasa</th><th>Form</th><th>Link chat</th><th>Catatan</th></tr></thead><tbody>{''.join(trs)}</tbody></table></div></main>
<dialog id="dlg"><img alt=""></dialog>
<script>
const bs=document.querySelectorAll('.filters button');
bs.forEach(b=>b.onclick=()=>{{bs.forEach(x=>x.setAttribute('aria-pressed',x===b));const f=b.dataset.f;
document.querySelectorAll('tbody tr').forEach(c=>{{c.hidden=!(f==='all'||(f==='l0'&&c.dataset.label==='0')||(f==='l1'&&c.dataset.label==='1')||c.dataset.v===f)}})}});
const d=document.getElementById('dlg');document.querySelectorAll('.shot img').forEach(i=>i.onclick=()=>{{d.querySelector('img').src=i.src;d.showModal()}});
d.onclick=()=>d.close();
</script></body></html>"""
    (OUT / "laporan.html").write_text(page, encoding="utf-8")
    print("wrote", OUT / "laporan.html", "| legit", line(nl, cl), "| scam", line(ns, cs))


if __name__ == "__main__":
    {"pick": pick, "report": report}[sys.argv[1]]()
