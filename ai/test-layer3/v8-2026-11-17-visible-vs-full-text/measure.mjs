#!/usr/bin/env node
// v8: does reading only the VISIBLE text (what the iPhone extension sends: innerText) instead of the whole DOM text
// (what the model's training/eval snapshots used: parseHtml) change layer 3 answers?
// Each sampled page is loaded once in headless Chrome (iPhone user agent, no clicks, no typing). Both texts are taken from the
// same load, then scored with the real layer 3 rules + the impersonation model. HTML and page text are never stored:
// .hasil/results.jsonl keeps ids, labels and numbers only (.hasil/ is gitignored).
//   node measure.mjs [scam=60] [legit=40]
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync, createReadStream, existsSync } from "node:fs";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";
import { parseHtml } from "../../eval/tools/snapshot.mjs";
import { analyzeSnapshot } from "../../src/analyze.js";
import { scoreImpersonation, MODEL_WEIGHTS } from "../../src/layer3/model/impersonation.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, ".hasil");
const OUT = join(OUT_DIR, "results.jsonl");
const V7 = "/Users/imelda/Documents/Swift/Final-CH/Final-CH7/ai/test-layer3/v7-2026-11-16-impersonation-new-data";
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
const N_SCAM = Number(process.argv[2] ?? 60), N_LEGIT = Number(process.argv[3] ?? 40);
const WORKERS = 4, LOAD_MS = 20000, SETTLE_MS = 4000, MAX_TEXT = 20000;

// ---- sample (fixed seed, so a rerun picks the same pages) ----
let seed = 1234567;
const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
const shuffle = (a) => { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const slim = (o) => ({ id: o.id, label: o.label, url: o.url });
const fresh = readFileSync(join(V7, "fresh/.hasil/sample-input.jsonl"), "utf8").trim().split("\n").map((l) => slim(JSON.parse(l)));
const scam = shuffle(fresh.filter((r) => r.label === 1)).slice(0, N_SCAM);
const legit = [];
for await (const line of createInterface({ input: createReadStream(join(V7, ".hasil/sample-input.jsonl")) })) {
    let o;
    try { o = JSON.parse(line); } catch { continue; } // a few rows are split mid-record (readline cuts at CR): skip them
    if (o.label === 0) legit.push(slim(o));
}
const sample = [...scam, ...shuffle(legit).slice(0, N_LEGIT)];

// ---- Chrome over the DevTools protocol (Node's own WebSocket) ----
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function render(url, port) {
    const profile = mkdtempSync(join(tmpdir(), "v8-"));
    const chrome = spawn(CHROME, ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--disable-extensions",
        "--mute-audio", "--deny-permission-prompts", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, `--user-agent=${UA}`,
        "--window-size=390,844", "about:blank"], { stdio: "ignore" });
    try {
        let target;
        for (let i = 0; i < 40 && !target; i++) {
            await sleep(250);
            try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === "page"); } catch { /* not up yet */ }
        }
        if (!target) return null;
        const ws = new WebSocket(target.webSocketDebuggerUrl);
        await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
        let id = 0, loaded;
        const waiting = new Map();
        const loadedP = new Promise((r) => (loaded = r));
        ws.onmessage = (e) => {
            const m = JSON.parse(e.data);
            if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
            if (m.method === "Page.loadEventFired") loaded();
        };
        const send = (method, params = {}) => new Promise((res) => { waiting.set(++id, res); ws.send(JSON.stringify({ id, method, params })); });
        await send("Page.enable");
        await send("Page.navigate", { url });
        await Promise.race([loadedP, sleep(LOAD_MS)]);
        await sleep(SETTLE_MS);
        const r = await send("Runtime.evaluate", {
            expression: "JSON.stringify({ vis: document.body ? document.body.innerText : '', html: document.documentElement.outerHTML })",
            returnByValue: true,
        });
        ws.close();
        return r.result?.result?.value ? JSON.parse(r.result.result.value) : null;
    } finally {
        chrome.kill("SIGKILL");
        rmSync(profile, { recursive: true, force: true });
    }
}

// ---- scoring: the real rules + the model, as /analyze does (rule ids go to the model) ----
function score(snapshot) {
    const rules = analyzeSnapshot(snapshot);
    const model = scoreImpersonation(snapshot, { ruleIds: rules.map((s) => s.id) });
    const modelW = model.tier === "warn" || model.tier === "block" ? MODEL_WEIGHTS[model.tier] : 0;
    const ruleSum = rules.reduce((a, s) => a + (s.weight || 0), 0);
    return { tier: model.tier, final: +model.final.toFixed(4), total: ruleSum + modelW };
}

mkdirSync(OUT_DIR, { recursive: true });
if (existsSync(OUT)) throw new Error("results.jsonl exists: not overwriting");
const results = [];
let next = 0;
async function worker(slot) {
    while (next < sample.length) {
        const r = sample[next++];
        const rec = { id: r.id, label: r.label, ok: false };
        try {
            await assertPublicUrl(r.url);
            const page = await render(r.url, 9300 + slot);
            if (page && page.html.length > 200) {
                const full = parseHtml(page.html, { url: r.url, domain: new URL(r.url).hostname }).snapshot;
                const vis = { ...full, text: page.vis.slice(0, MAX_TEXT) };
                Object.assign(rec, { ok: true, lenFull: full.text.length, lenVis: vis.text.length, full: score(full), vis: score(vis) });
            }
        } catch { /* not public, DNS failed, load failed: stays ok=false */ }
        results.push(rec);
    }
}
await Promise.all(Array.from({ length: WORKERS }, (_, i) => worker(i)));
writeFileSync(OUT, results.map((x) => JSON.stringify(x)).join("\n") + "\n");

// ---- counts only ----
const band = (t) => (t >= 80 ? "block(>=80)" : t >= 30 ? "warn(30-79)" : "quiet(<30)");
for (const label of [1, 0]) {
    const ok = results.filter((x) => x.ok && x.label === label);
    const moved = ok.filter((x) => band(x.full.total) !== band(x.vis.total));
    const m = {};
    for (const x of ok) { const k = `${band(x.full.total)} -> ${band(x.vis.total)}`; m[k] = (m[k] || 0) + 1; }
    const tierMoved = ok.filter((x) => x.full.tier !== x.vis.tier).length;
    const shorter = ok.filter((x) => x.lenVis < x.lenFull * 0.8).length;
    console.log(`${label ? "scam" : "legit"}: loaded ${ok.length}/${results.filter((x) => x.label === label).length}, visible text >20% shorter ${shorter}, model tier changed ${tierMoved}, layer-3 band changed ${moved.length}`);
    console.log("  ", JSON.stringify(m));
}
