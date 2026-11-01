// Turns every page of Imelda's eval corpus (ai/eval/data) into a local HTML page, so anyone can open
// what the detector saw next to how it scored it (Test 2a) and what Safari showed live (Test 2b).
//   node plan/alief/qa/corpus-view.mjs   ->   open plan/alief/qa/corpus-view/index.html
// The corpus keeps a snapshot, not the real page: URL, title, text, form fields, image alt texts.
// The view draws that snapshot as a simple page. Everything is escaped, scam URLs are never links,
// and a CSP blocks scripts, network and images from outside this folder.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../..");
const dataDir = join(root, "ai/eval/data");
const outDir = join(here, "corpus-view");
const results = Object.fromEntries(JSON.parse(readFileSync(join(here, "img/figma-parity/corpus-results.json"), "utf8")).results.map((r) => [r.id, r]));
const liveFile = join(here, "img/figma-parity/live/live-results.json");
const live = existsSync(liveFile) ? Object.fromEntries(JSON.parse(readFileSync(liveFile, "utf8")).rows.map((r) => [r.id, r])) : {};

const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
// Same rules as the report: contracts/README.md thresholds.
const expected = (s) => (s.label === "scam" ? "≥ 80 % · scam, block it" : "< 30 % · not scam, show nothing");
const right = (s, r) => !r ? "not scored" : s.label === "scam" ? (r.score >= 80 ? "✅ blocked" : r.score >= 30 ? "⚠️ only warned" : "❌ missed") : r.score < 30 ? "✅ left alone" : "❌ wrongly flagged";
const isWrong = (s, r) => r && ((s.label === "scam" && r.score < 30) || (s.label === "legit" && r.score >= 30));
const signal = (g) => g.replace(/^(.*):L(\d):(\d+)$/, "$1 (L$2, +$3)");
const safeName = (id) => id.replace(/[^a-z0-9._-]/gi, "_");

// Every sample, with the file and line it comes from (for the GitHub link in the report).
const samples = [];
for (const label of ["scam", "legit"])
    for (const file of readdirSync(join(dataDir, label)).filter((f) => f.endsWith(".json")).sort()) {
        const rel = `ai/eval/data/${label}/${file}`;
        const raw = readFileSync(join(root, rel), "utf8");
        const lines = raw.split("\n");
        for (const s of JSON.parse(raw)) {
            const line = lines.findIndex((l) => l.includes(`"id": "${s.id}"`) || l.includes(`"id":"${s.id}"`)) + 1;
            samples.push({ ...s, file: rel, line });
        }
    }

const CSS = `
:root{--bg:#f5f7fa;--card:#fff;--ink:#1a1c2e;--muted:#6a717e;--line:#e3e7ee;--red:#c62828;--amber:#b26a00;--green:#1b7f4b}
@media (prefers-color-scheme:dark){:root{--bg:#12141a;--card:#1c1f27;--ink:#eef0f4;--muted:#9aa1ad;--line:#2c313c}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 -apple-system,system-ui,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px}a{color:#0367b6}h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:28px 0 8px}
.muted{color:var(--muted)}.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin:12px 0}
table{width:100%;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{font-size:13px;color:var(--muted)}code{font:13px ui-monospace,Menlo,monospace}
.grid{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,1fr);gap:16px}@media (max-width:820px){.grid{grid-template-columns:1fr}}
.browser{border:1px solid var(--line);border-radius:14px;overflow:hidden;background:#fff;color:#1a1c2e}
.bar{background:#eceff3;padding:8px 12px;font:13px ui-monospace,Menlo,monospace;color:#444;word-break:break-all}
.page{padding:18px}.page h3{margin:0 0 10px;font-size:20px}.page p{white-space:pre-wrap;margin:0 0 12px}
.alt{display:inline-block;border:1px dashed #9aa1ad;border-radius:8px;padding:10px 12px;margin:4px;font-size:13px;color:#555;background:#f3f5f8}
.form{border:1px solid #d6dbe3;border-radius:10px;padding:12px;margin:12px 0}label{display:block;font-size:13px;margin:8px 0 2px;color:#444}
input{width:100%;padding:8px 10px;border:1px solid #c9d0da;border-radius:8px;font:inherit;background:#fafbfc}
.pill{display:inline-block;padding:1px 8px;border-radius:99px;font-size:12px;border:1px solid var(--line)}
.scam{color:var(--red)}.legit{color:var(--green)}pre{white-space:pre-wrap;word-break:break-word;font:12px ui-monospace,Menlo,monospace;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px;max-height:480px;overflow:auto}
img.shot{width:100%;max-width:300px;border-radius:12px;border:1px solid var(--line)}
`;
const page = (title, body) =>
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
    `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'self'">` +
    `<title>${esc(title)}</title><style>${CSS}</style></head><body><main>${body}</main></body></html>\n`;

function snapshotHTML(snap) {
    const parts = [`<div class="bar">${esc(snap.url)}</div><div class="page">`];
    const empty = !snap.title && !snap.text && !(snap.forms ?? []).length && !(snap.imageAlts ?? []).length;
    if (snap.title) parts.push(`<h3>${esc(snap.title)}</h3>`);
    if (snap.text) parts.push(`<p>${esc(snap.text)}</p>`);
    for (const a of snap.imageAlts ?? []) parts.push(`<span class="alt">image: ${esc(a)}</span>`);
    for (const f of snap.forms ?? []) {
        parts.push(`<div class="form"><div class="muted" style="font-size:12px">form → ${esc(f.action ?? "(no action)")}</div>`);
        for (const fl of f.fields ?? []) {
            parts.push(`<label>${esc(fl.label ?? fl.name ?? fl.id ?? fl.type)} <span class="muted">(${esc(fl.type)}${fl.autocomplete ? `, ${esc(fl.autocomplete)}` : ""})</span></label>`);
            parts.push(`<input disabled type="text" placeholder="${esc(fl.placeholder ?? "")}">`);
        }
        parts.push(`</div>`);
    }
    if (empty) parts.push(`<p class="muted">No page content in this sample: only the URL. The detector sees the link name (L1–2) and nothing else.</p>`);
    parts.push(`</div>`);
    return parts.join("");
}

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

for (const s of samples) {
    const r = results[s.id];
    const l = live[s.id];
    const shot = `../img/figma-parity/live/safari-${s.id}.jpg`;
    const facts = [
        ["Type", `<span class="${s.label}">${s.label === "scam" ? "scam" : "normal (legit)"}</span>`],
        ["Source", `${s.synthetic ? "made up by Team AI" : "real page"}${s.tags?.includes("holdout") ? " · held back (never used for tuning)" : ""}`],
        ["Should get", esc(expected(s))],
        ["Got (Test 2a)", r ? `L1–2: ${r.localScore} · final: <b>${r.score}</b> (${esc(r.status)}) · ${right(s, r)}` : "not in this run"],
        ["Why", r?.signals.length ? r.signals.map((g) => `<code>${esc(signal(g))}</code>`).join("<br>") : "no signal"],
        ["Live (Test 2b)", l ? `${esc(l.live).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")}<br><span class="muted">sent to server: ${esc(l.scan)} · push: ${esc(l.push)}</span>` : "not opened live (host gone or not checked)"],
        ["Tags", (s.tags ?? []).map((t) => `<span class="pill">${esc(t)}</span>`).join(" ")],
        ["Where it comes from", esc(s.source)],
        ["Note", esc(s.notes) || "none"],
        ["File", `<code>${esc(s.file)}</code>, line ${s.line}`],
    ];
    const body =
        `<p><a href="index.html">← all pages</a></p><h1><code>${esc(s.id)}</code></h1>` +
        `<p class="muted">What the detector saw, drawn as a page. Not the real site: the corpus keeps only this snapshot.</p>` +
        `<div class="grid"><div class="browser">${snapshotHTML(s.snapshot ?? {})}</div>` +
        `<div><table>${facts.map(([k, v]) => `<tr><th>${k}</th><td>${v}</td></tr>`).join("")}</table>` +
        (existsSync(join(here, shot.replace("../", ""))) ? `<h2>Safari, live</h2><img class="shot" src="${shot}" alt="Safari screenshot of ${esc(s.id)}">` : "") +
        `</div></div><h2>Raw sample (JSON)</h2><pre>${esc(JSON.stringify(Object.fromEntries(Object.entries(s).filter(([k]) => k !== "file" && k !== "line")), null, 2))}</pre>`;
    writeFileSync(join(outDir, `${safeName(s.id)}.html`), page(s.id, body));
}

const row = (s) => {
    const r = results[s.id];
    return `<tr><td><a href="${safeName(s.id)}.html"><code>${esc(s.id)}</code></a></td><td class="${s.label}">${s.label === "scam" ? "scam" : "normal"}</td>` +
        `<td>${s.synthetic ? "made up" : "real"}${s.tags?.includes("holdout") ? ", held back" : ""}</td><td>${esc(expected(s))}</td>` +
        `<td>${r ? r.score : "n/a"}</td><td>${right(s, r)}</td><td>${live[s.id] ? "yes" : ""}</td></tr>`;
};
const head = `<tr><th>Page</th><th>Type</th><th>Source</th><th>Should get</th><th>Got</th><th>Right?</th><th>Opened live</th></tr>`;
const wrong = samples.filter((s) => isWrong(s, results[s.id]));
const index =
    `<h1>Test pages: Imelda's corpus</h1>` +
    `<p class="muted">${samples.length} pages from <code>ai/eval/data</code>. Click a page to see what the detector saw, its score, and the live Safari screenshot if there is one. Rebuild with <code>node plan/alief/qa/corpus-view.mjs</code>.</p>` +
    `<div class="card">Score: 0 to 29 nothing shown · 30 to 79 warning · 80 to 100 blocked. A scam should get 80 or more; a normal page under 30.</div>` +
    `<h2>Scored wrong (${wrong.length})</h2><table>${head}${wrong.map(row).join("")}</table>` +
    `<h2>All pages (${samples.length})</h2><table>${head}${samples.map(row).join("")}</table>`;
writeFileSync(join(outDir, "index.html"), page("Test pages", index));
writeFileSync(join(outDir, "index.json"), JSON.stringify(Object.fromEntries(samples.map((s) => [s.id, { file: s.file, line: s.line, view: `${safeName(s.id)}.html` }])), null, 2) + "\n");
console.log(`${samples.length} pages written to ${outDir}`);
