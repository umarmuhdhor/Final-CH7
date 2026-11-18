#!/usr/bin/env node
// Training data from this run: links + labels (all links) and pages (the PageSnapshot of every page layer 3 could read),
// split into train / dev / test BY SITE: a site (and a phishing kit that spans several hosts) is in exactly one part.
// No network. The console prints numbers only, never a URL or a host.
//
//   node dataset.mjs                 writes dataset/links.csv, dataset/pages-{train,dev,test}.jsonl, dataset/summary.json
// Opts: --dev 0.1 --test 0.1         share of rows per label (default 0.1 and 0.1; the rest is train)
//       --dengan-kosong              also keep pages with almost no text and no field (default: dropped)
//       --dengan-resmi               also keep official hosts (layer 3 is silent there; default: dropped)
//
// Label: scam = 1, legit = 0.
// "Site" = ai/test-regresi/fitur.mjs `domainKey` (registrable domain; the whole host on a free host such as blogspot or vercel).
// Scam pages with the same title and the same field layout (one kit on many hosts) are tied to one group; legit pages are not
// (generic "Sign in" pages would tie unrelated legit sites into one giant group).
// Pages dropped: not read (`gagal`), `kosong`, official host, same content twice (one kept), same content with both labels (all dropped).
// dataset/ holds live phishing URLs and the repo is public: it is gitignored. Never commit it.
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { domainKey } from "../../test-regresi/fitur.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, "dataset");
const arg = (n, d) => {
    const i = process.argv.indexOf(n);
    return i > -1 ? process.argv[i + 1] : d;
};
const flag = (n) => process.argv.includes(n);
const log = (s) => process.stderr.write(`${s}\n`);
const DEV = Number(arg("--dev", 0.1));
const TEST = Number(arg("--test", 0.1));
const RATIO = { train: 1 - DEV - TEST, dev: DEV, test: TEST };
const SPLITS = ["train", "dev", "test"];
const hash = (s) => createHash("sha1").update(s).digest("hex").slice(0, 16);
const unit = (s) => parseInt(hash(s).slice(0, 8), 16) / 0xffffffff; // deterministic number in [0, 1]

// ---- links.csv (same rules as run.mjs and probe.mjs: same refang, same dedupe, same ids) -------------------------
function parseCsv(text) {
    const rows = [];
    let row = [], cell = "", q = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (q) {
            if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') q = false; else cell += c;
        } else if (c === '"') q = true;
        else if (c === ",") { row.push(cell); cell = ""; }
        else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(cell); if (row.some((x) => x !== "")) rows.push(row); row = []; cell = ""; }
        else cell += c;
    }
    row.push(cell);
    if (row.some((x) => x !== "")) rows.push(row);
    return rows;
}
const hasScheme = (raw) => /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
const refang = (raw) => String(raw).trim().replace(/^hxxp/i, "http").replace(/\[\.\]|\(\.\)/g, ".").replace(/\[:\]/g, ":");
function toUrl(raw) {
    try {
        const u = new URL(hasScheme(raw) ? raw : `https://${raw}`);
        if (u.protocol !== "http:" && u.protocol !== "https:") return null;
        return u.hostname.includes(".") ? u : null;
    } catch { return null; }
}
const csvCell = (v) => (/[",\n\r]/.test(String(v ?? "")) ? `"${String(v).replaceAll('"', '""')}"` : String(v ?? ""));

const rows = parseCsv(readFileSync(join(here, "links.csv"), "utf8").replace(/^﻿/, ""));
const head = rows[0].map((h) => h.trim().toLowerCase());
const [iId, iUrl, iLab] = ["id", "url", "label"].map((h) => head.indexOf(h));
const seen = new Set();
const links = [];
for (const r of rows.slice(1)) {
    const raw = refang(r[iUrl] ?? "");
    const u = raw && toUrl(raw);
    if (!u || seen.has(raw)) continue;
    seen.add(raw);
    links.push({ id: String(r[iId]).trim(), url: raw, label: /^(legit|normal|benign|safe|aman)/i.test(r[iLab] ?? "") ? 0 : 1, site: domainKey(u.hostname) });
}
log(`links: ${links.length}`);

// ---- probe result (is the link alive) ------------------------------------------------------------------------
const loadJsonl = (f) => (existsSync(f) ? readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l)) : []);
const httpRes = new Map(loadJsonl(join(here, ".probe/http.jsonl")).map((r) => [r.id, r]));
const aliveIds = new Set();
for (const l of links) {
    const r = httpRes.get(l.id);
    if (r && ((r.st >= 300 && r.st < 400) || (r.st >= 200 && r.st < 300 && /html/.test(r.ct ?? "")))) aliveIds.add(l.id);
}

// ---- pages ---------------------------------------------------------------------------------------------------
const drop = {};
const count = (k, label) => { drop[k] = drop[k] ?? { scam: 0, legit: 0 }; drop[k][label === 1 ? "scam" : "legit"]++; };
const linkById = new Map(links.map((l) => [l.id, l]));
const kept = [];
for (const f of readdirSync(join(here, "snapshots"))) {
    const id = f.replace(".json", "");
    const link = linkById.get(id);
    if (!link) continue;
    const r = JSON.parse(readFileSync(join(here, "snapshots", f), "utf8"));
    if (r.status === "gagal" || !r.snapshot) { count("gagal (halaman tidak terbaca)", link.label); continue; }
    if (r.status === "kosong" && !flag("--dengan-kosong")) { count("kosong (teks < 200 karakter, tanpa kolom)", link.label); continue; }
    if (r.l3?.official && !flag("--dengan-resmi")) { count("host resmi (layer 3 diam di sana)", link.label); continue; }
    const s = r.snapshot;
    const fields = (s.forms ?? []).flatMap((fm) => fm.fields ?? []);
    const fieldSig = fields.map((x) => `${x.type}:${String(x.name || x.id || "").toLowerCase()}`).join(",");
    const title = String(s.title ?? "");
    kept.push({
        id, label: link.label, site: link.site, original_url: link.url,
        page: { url: s.url, title, lang: s.lang ?? null, text: s.text ?? "", forms: s.forms ?? [], imageAlts: s.imageAlts ?? [] },
        kit: link.label === 1 && title.trim() && fields.length ? hash(`${title.trim().toLowerCase()}|${fieldSig}`) : null,
        content: hash(`${title}|${String(s.text ?? "").slice(0, 2000)}|${fieldSig}`),
    });
}
// same content twice: keep one; same content with both labels: the label cannot be trusted, drop all
const byContent = new Map();
for (const p of kept) (byContent.get(p.content) ?? byContent.set(p.content, []).get(p.content)).push(p);
const pages = [];
for (const group of byContent.values()) {
    const labels = new Set(group.map((p) => p.label));
    if (labels.size > 1) { for (const p of group) count("isi sama persis tapi label bertentangan", p.label); continue; }
    group.sort((a, b) => a.id.localeCompare(b.id));
    pages.push(group[0]);
    for (const p of group.slice(1)) count("isi sama persis (duplikat, satu disimpan)", p.label);
}
log(`halaman dipakai: ${pages.length} (scam ${pages.filter((p) => p.label === 1).length}, legit ${pages.filter((p) => p.label === 0).length})`);

// ---- groups: one site, plus one scam kit across hosts --------------------------------------------------------
const parent = new Map();
const find = (k) => {
    if (!parent.has(k)) parent.set(k, k);
    let r = k;
    while (parent.get(r) !== r) r = parent.get(r);
    for (let c = k; parent.get(c) !== r; ) { const n = parent.get(c); parent.set(c, r); c = n; }
    return r;
};
for (const l of links) find(`d:${l.site}`);
for (const p of pages) if (p.kit) parent.set(find(`d:${p.site}`), find(`k:${p.kit}`));

// ---- assign groups to splits (balanced per label on the PAGE rows; groups without pages by hash) -----------
const comp = new Map();
for (const p of pages) {
    const k = find(`d:${p.site}`);
    const c = comp.get(k) ?? comp.set(k, { n: [0, 0] }).get(k);
    c.n[p.label]++;
}
const total = [pages.filter((p) => p.label === 0).length, pages.filter((p) => p.label === 1).length];
const target = Object.fromEntries(SPLITS.map((s) => [s, total.map((t) => t * RATIO[s])]));
const cur = Object.fromEntries(SPLITS.map((s) => [s, [0, 0]]));
const splitOfComp = new Map();
for (const [k, c] of [...comp].sort((a, b) => b[1].n[0] + b[1].n[1] - (a[1].n[0] + a[1].n[1]) || (a[0] < b[0] ? -1 : 1))) {
    let best = "train", bestScore = -Infinity;
    for (const s of SPLITS) {
        let score = 0;
        for (const l of [0, 1]) if (c.n[l] > 0) score += target[s][l] > 0 ? (target[s][l] - cur[s][l]) / target[s][l] : -1e9;
        if (score > bestScore) { bestScore = score; best = s; }
    }
    splitOfComp.set(k, best);
    for (const l of [0, 1]) cur[best][l] += c.n[l];
}
const splitOfSite = (site) => {
    const k = find(`d:${site}`);
    if (splitOfComp.has(k)) return splitOfComp.get(k);
    const u = unit(k);
    return u < RATIO.train ? "train" : u < RATIO.train + RATIO.dev ? "dev" : "test";
};

// ---- write ---------------------------------------------------------------------------------------------------
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, "links.csv"), "id,url,label,split,site,hidup,halaman\n");
const pageIds = new Set(pages.map((p) => p.id));
let buf = [];
const flushLinks = () => { if (buf.length) appendFileSync(join(outDir, "links.csv"), buf.join("\n") + "\n"); buf = []; };
for (const l of links) {
    buf.push([l.id, csvCell(l.url), l.label, splitOfSite(l.site), csvCell(l.site), aliveIds.has(l.id) ? 1 : 0, pageIds.has(l.id) ? 1 : 0].join(","));
    if (buf.length >= 5000) flushLinks();
}
flushLinks();
for (const s of SPLITS) writeFileSync(join(outDir, `pages-${s}.jsonl`), "");
const out = Object.fromEntries(SPLITS.map((s) => [s, []]));
const flushPages = (s) => { if (out[s].length) appendFileSync(join(outDir, `pages-${s}.jsonl`), out[s].join("\n") + "\n"); out[s] = []; };
pages.sort((a, b) => a.id.localeCompare(b.id));
for (const p of pages) {
    const s = splitOfSite(p.site);
    out[s].push(JSON.stringify({ id: p.id, split: s, site: p.site, label: p.label, url: p.page.url, original_url: p.original_url, title: p.page.title, lang: p.page.lang, text: p.page.text, forms: p.page.forms, imageAlts: p.page.imageAlts }));
    if (out[s].length >= 300) flushPages(s);
}
for (const s of SPLITS) flushPages(s);

// ---- checks (numbers only) -----------------------------------------------------------------------------------
const stats = Object.fromEntries(SPLITS.map((s) => [s, { links: [0, 0], pages: [0, 0], sites: new Set(), kits: new Set() }]));
const siteSplit = new Map(), kitSplit = new Map();
let siteLeak = 0, kitLeak = 0;
for (const l of links) { const s = splitOfSite(l.site); stats[s].links[l.label]++; stats[s].sites.add(l.site); if (siteSplit.has(l.site) && siteSplit.get(l.site) !== s) siteLeak++; siteSplit.set(l.site, s); }
for (const p of pages) { const s = splitOfSite(p.site); stats[s].pages[p.label]++; if (p.kit) { stats[s].kits.add(p.kit); if (kitSplit.has(p.kit) && kitSplit.get(p.kit) !== s) kitLeak++; kitSplit.set(p.kit, s); } }
const summary = {
    ratio: RATIO, linksTotal: links.length, pagesTotal: pages.length, dropped: drop,
    splits: Object.fromEntries(SPLITS.map((s) => [s, { linksLegit: stats[s].links[0], linksScam: stats[s].links[1], pagesLegit: stats[s].pages[0], pagesScam: stats[s].pages[1], sites: stats[s].sites.size, kits: stats[s].kits.size }])),
    checks: { siteInTwoSplits: siteLeak, kitInTwoSplits: kitLeak },
};
writeFileSync(join(outDir, "summary.json"), JSON.stringify(summary, null, 2));
log(JSON.stringify(summary.splits));
log(`dibuang: ${JSON.stringify(drop)}`);
log(`cek: situs di dua bagian = ${siteLeak}, kit di dua bagian = ${kitLeak}`);
