#!/usr/bin/env node
// Measure how long it takes to find "sends data to Telegram" in saved HTML, and which pages hit.
// Read-only: saved HTML from .html/ and snapshots from snapshots/. No network, no page JS is run,
// no <script src> is fetched. Usage: node ukur-telegram.mjs [--reps 200] [--json out.json]
// Bot tokens are never printed: only true/false per column.
import { readdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeSnapshot } from "../src/analyze.js";
import "./ukur-safari/pola.js";

const { KOLOM, scanTeks } = globalThis.ShooPola;
const here = dirname(fileURLToPath(import.meta.url));
const htmlDir = join(here, ".html");
const snapDir = join(here, "snapshots");

const arg = (name, fallback) => {
    const i = process.argv.indexOf(name);
    return i > -1 ? process.argv[i + 1] : fallback;
};
const REPS = Number(arg("--reps", 200));
const RUNS = 5;

const SCRIPT_RE = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
const FORM_ACTION_RE = /<form\b[^>]*?\baction\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi;
const SRC_RE = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i;

// Inline <script> bodies and form action attributes joined into one string; <script src> is only counted.
function extract(html, siteHost) {
    const parts = [];
    let inlineBytes = 0;
    let ownSrc = 0;
    let otherSrc = 0;
    for (const m of html.matchAll(SCRIPT_RE)) {
        const src = SRC_RE.exec(m[1]);
        if (!src) {
            parts.push(m[2]);
            inlineBytes += m[2].length;
            continue;
        }
        if (isOwnSrc(src[1] ?? src[2] ?? src[3], siteHost)) ownSrc++;
        else otherSrc++;
    }
    for (const m of html.matchAll(FORM_ACTION_RE)) parts.push(m[1] ?? m[2] ?? m[3]);
    return { teks: parts.join("\n"), inlineBytes, ownSrc, otherSrc };
}

// "Own" = relative path, or same host / a subdomain of the page's host (www. ignored).
function isOwnSrc(src, siteHost) {
    if (!src) return false;
    let host;
    try {
        host = new URL(src, `https://${siteHost}/`).hostname;
    } catch {
        return false;
    }
    const base = siteHost.replace(/^www\./, "");
    return host === siteHost || host === base || host.endsWith(`.${base}`);
}

function scanHtml(html, siteHost) {
    const ex = extract(html, siteHost);
    return { ...ex, hit: scanTeks(ex.teks) };
}

function median(xs) {
    const s = [...xs].sort((a, b) => a - b);
    const mid = s.length >> 1;
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

// RUNS runs, first one dropped as warm-up; each run is the mean of `reps` calls.
function timeIt(fn, reps) {
    const runs = [];
    for (let r = 0; r < RUNS; r++) {
        const t0 = performance.now();
        for (let i = 0; i < reps; i++) fn();
        runs.push((performance.now() - t0) / reps);
    }
    const kept = runs.slice(1);
    return { median: median(kept), max: Math.max(...kept) };
}

async function siteHostOf(id, ua) {
    const meta = await readFile(join(htmlDir, `${id}-${ua}.meta`), "utf8").catch(() => "");
    const final = /^curl=\S+\t(\S+)/m.exec(meta)?.[1];
    const requested = /^requested=(\S+)/m.exec(meta)?.[1];
    try {
        return new URL(final || requested).hostname;
    } catch {
        return new URL(requested).hostname;
    }
}

const ids = (await readdir(htmlDir))
    .map((f) => /^(L?\d+)-desktop\.html$/.exec(f)?.[1])
    .filter(Boolean)
    .sort();

const rows = [];
for (const id of ids) {
    const row = { id, legit: id.startsWith("L") };
    for (const ua of ["desktop", "iphone"]) {
        const html = await readFile(join(htmlDir, `${id}-${ua}.html`), "utf8").catch(() => "");
        const siteHost = await siteHostOf(id, ua);
        const res = scanHtml(html, siteHost);
        const full = timeIt(() => scanHtml(html, siteHost), REPS);
        const once = timeIt(() => scanHtml(html, siteHost), 1);
        row[ua] = {
            htmlKB: html.length / 1024,
            empty: html.length === 0,
            inlineKB: res.inlineBytes / 1024,
            ownSrc: res.ownSrc,
            otherSrc: res.otherSrc,
            hit: res.hit,
            medianMs: full.median,
            maxMs: full.max,
            onceMedianMs: once.median,
        };
    }
    rows.push(row);
}

// Comparison: rules layer 3 (analyzeSnapshot) on the same machine, same timing scheme.
const l3 = {};
for (const f of (await readdir(snapDir)).filter((f) => f.endsWith(".json")).sort()) {
    const rec = JSON.parse(await readFile(join(snapDir, f), "utf8"));
    if (!rec.snapshot) continue;
    l3[rec.id] = timeIt(() => analyzeSnapshot(rec.snapshot), REPS);
}

const f2 = (n) => n.toFixed(3);
const yn = (b) => (b ? "ya" : "-");
const anyHit = (h) => KOLOM.some((k) => h[k]);

console.log(`versi kode: ${process.env.UKUR_REV ?? "?"}  node ${process.version}  reps/run=${REPS}  runs=${RUNS} (run 1 dibuang)`);
console.log("\nScam (HTML desktop):");
console.log("| id | html KB | skrip inline KB | script src sendiri | median ms | maks ms | sekali ms | host | token | method | L3 rules median ms |");
console.log("|---|---:|---:|---:|---:|---:|---:|:-:|:-:|:-:|---:|");
for (const r of rows.filter((r) => !r.legit)) {
    const d = r.desktop;
    console.log(
        `| ${r.id} | ${d.htmlKB.toFixed(1)} | ${d.inlineKB.toFixed(1)} | ${d.ownSrc} | ${f2(d.medianMs)} | ${f2(d.maxMs)} | ${f2(d.onceMedianMs)} | ${yn(d.hit.host)} | ${yn(d.hit.token)} | ${yn(d.hit.method)} | ${l3[r.id] ? f2(l3[r.id].median) : "-"} |`,
    );
}
console.log("\nLegit (HTML desktop):");
console.log("| id | html KB | skrip inline KB | script src sendiri | median ms | host | token | method |");
console.log("|---|---:|---:|---:|---:|:-:|:-:|:-:|");
for (const r of rows.filter((r) => r.legit)) {
    const d = r.desktop;
    console.log(
        `| ${r.id} | ${d.empty ? "kosong" : d.htmlKB.toFixed(1)} | ${d.inlineKB.toFixed(1)} | ${d.ownSrc} | ${f2(d.medianMs)} | ${yn(d.hit.host)} | ${yn(d.hit.token)} | ${yn(d.hit.method)} |`,
    );
}

// Detection counts: desktop, iPhone, and either UA.
const list = (group, pick) => group.filter(pick).map((r) => r.id);
function summary(group, label) {
    console.log(`\n${label} (${group.length} situs)`);
    for (const k of KOLOM) {
        const dsk = list(group, (r) => r.desktop.hit[k]);
        const iph = list(group, (r) => r.iphone.hit[k]);
        const both = list(group, (r) => r.desktop.hit[k] || r.iphone.hit[k]);
        console.log(`  ${k}: desktop ${dsk.length} [${dsk}] | iphone ${iph.length} [${iph}] | salah satu ${both.length} [${both}]`);
    }
    const any = (ua) => list(group, (r) => anyHit(r[ua].hit));
    const anyUa = list(group, (r) => anyHit(r.desktop.hit) || anyHit(r.iphone.hit));
    console.log(`  gabungan (>=1 kolom): desktop ${any("desktop").length} | iphone ${any("iphone").length} | salah satu ${anyUa.length} [${anyUa}]`);
    const hostMethod = list(group, (r) => (r.desktop.hit.host && r.desktop.hit.method) || (r.iphone.hit.host && r.iphone.hit.method));
    console.log(`  host+method sekaligus (salah satu UA): ${hostMethod.length} [${hostMethod}]`);
    const own = list(group, (r) => r.desktop.ownSrc > 0 || r.iphone.ownSrc > 0);
    console.log(`  punya <script src> sendiri ("tidak terbaca"): ${own.length} [${own}]`);
    const none = list(group, (r) => r.desktop.empty || r.iphone.empty);
    if (none.length) console.log(`  HTML kosong (tidak bisa dipindai): [${none}]`);
}
summary(rows.filter((r) => !r.legit), "Scam");
summary(rows.filter((r) => r.legit), "Legit");

const scanned = rows.filter((r) => !r.desktop.empty);
const med = scanned.map((r) => r.desktop.medianMs);
const big = [...scanned].sort((a, b) => b.desktop.inlineKB - a.desktop.inlineKB)[0];
console.log(`\nSemua situs ber-HTML (desktop, ${scanned.length}): median ${f2(median(med))} ms, maks ${f2(Math.max(...med))} ms`);
console.log(`Skrip inline terbesar: ${big.id} ${big.desktop.inlineKB.toFixed(1)} KB, ${f2(big.desktop.medianMs)} ms`);
const l3m = Object.values(l3).map((x) => x.median);
console.log(`L3 rules (analyzeSnapshot) median antar snapshot ${f2(median(l3m))} ms, maks ${f2(Math.max(...l3m))} ms`);

const out = arg("--json");
if (out) await writeFile(out, JSON.stringify({ node: process.version, reps: REPS, runs: RUNS, rows, l3 }, null, 2));
