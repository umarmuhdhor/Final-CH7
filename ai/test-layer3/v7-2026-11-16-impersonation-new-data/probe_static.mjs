#!/usr/bin/env node
// v7 extra (probe, step 1): "where does the page send what the user types?" measured WITHOUT typing or clicking anything.
// Re-fetches the labelled fresh rows once (static GET, no JavaScript, no cookies, redirects checked by assertPublicUrl, at most
// 500 kB) and looks at the RAW html for data-collector endpoints and form wiring. Pages are attacker data: never run, never followed
// further. Stores only ids and booleans, prints only counts, never URLs, hosts, tokens or chat ids.
// Rows with keadaan "kosong" (little text, usually JS-only) are kept on purpose: that is where collector scripts hide.
//   node probe_static.mjs        writes .hasil/probe/static.jsonl (new file; refuses to overwrite)
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
// Optional: --in <pages.jsonl> --out <name> --sample <N per label>  (deterministic: every k-th row, no randomness).
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const IN = arg("in") ? join(process.cwd(), arg("in")) : join(HERE, "fresh/.hasil/pages.jsonl");
const OUT_DIR = join(HERE, ".hasil/probe");
const OUT = join(OUT_DIR, `${arg("out", "static")}.jsonl`);
const SAMPLE = Number(arg("sample", 0));
const MAX_BYTES = 500_000, MAX_REDIRECTS = 3, TIMEOUT_MS = 15000, WORKERS = 8;
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

if (existsSync(OUT)) throw new Error("static.jsonl already exists: not overwriting");

// Endpoints that only exist to hand a visitor's input to someone else. A real site has its own backend.
const COLLECTORS = {
    telegram: /api\.telegram\.org\/bot/i,
    discord: /discord(?:app)?\.com\/api\/webhooks\//i,
    slack: /hooks\.slack\.com\/services\//i,
    gas: /script\.google\.com\/macros\/s\//i,
    gform: /docs\.google\.com\/forms\/[^"']*formResponse/i,
    formservice: /(?:formspree\.io|formsubmit\.co|getform\.io|web3forms\.com|formspark\.io|usebasin\.com|api\.emailjs\.com)/i,
    firebase: /(?:firebaseio\.com|firestore\.googleapis\.com)/i,
};
const siteKey = (h) => h.toLowerCase().replace(/^www\./, "");

async function fetchHtml(startUrl) {
    const signal = AbortSignal.timeout(TIMEOUT_MS);
    let url = startUrl, res;
    for (let hop = 0; ; hop++) {
        await assertPublicUrl(url);
        res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html" }, redirect: "manual", credentials: "omit", signal });
        const location = res.headers.get("location");
        if (res.status >= 300 && res.status < 400 && location) {
            await res.body?.cancel();
            if (hop >= MAX_REDIRECTS) throw new Error("redirect");
            url = new URL(location, url).href;
            continue;
        }
        break;
    }
    if (!res.ok) { await res.body?.cancel(); throw new Error(`http_${res.status}`); }
    if (!/html/i.test(res.headers.get("content-type") || "")) { await res.body?.cancel(); throw new Error("bukan_html"); }
    const reader = res.body.getReader();
    const chunks = [];
    let size = 0;
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > MAX_BYTES) { await reader.cancel(); break; }
        chunks.push(value);
    }
    return { html: Buffer.concat(chunks).toString("utf8"), finalUrl: url };
}

function features(html, finalUrl) {
    const host = siteKey(new URL(finalUrl).hostname);
    const forms = [...html.matchAll(/<form\b[^>]*>/gi)].map((m) => m[0]);
    const inputs = [...html.matchAll(/<input\b[^>]*>/gi)].map((m) => m[0]);
    const typeOf = (t) => (/\btype\s*=\s*["']?([a-z]+)/i.exec(t)?.[1] ?? "text").toLowerCase();
    const sensitive = inputs.filter((t) => ["password", "tel", "email"].includes(typeOf(t)) || /\b(otp|pin|kode|code|nik|password|sandi)\b/i.test(t)).length;
    const hasPassword = inputs.some((t) => typeOf(t) === "password");
    const f = { forms: forms.length, inputs: inputs.length, sensitive, hasPassword };
    // Every collector endpoint named anywhere in the raw html (inline script, attribute, form action).
    for (const [k, re] of Object.entries(COLLECTORS)) f[k] = re.test(html);
    f.collector = Object.keys(COLLECTORS).some((k) => f[k]);
    // A form whose action leaves the page's own site.
    f.offsiteAction = forms.some((t) => {
        const a = /\baction\s*=\s*["']?([^"'\s>]+)/i.exec(t)?.[1];
        if (!a || a.startsWith("#") || /^javascript:/i.test(a)) return false;
        try { return siteKey(new URL(a, finalUrl).hostname) !== host; } catch { return false; }
    });
    // Sensitive inputs with no <form> at all: submission has to be done by script.
    f.scriptOnlyCollect = forms.length === 0 && sensitive > 0;
    // Script that reads a field value AND sends it somewhere.
    f.jsSends = /\.value/.test(html) && /(?:fetch\s*\(|XMLHttpRequest|sendBeacon|\$\.(?:post|ajax)\s*\()/.test(html);
    f.strongExfil = f.collector && sensitive > 0;
    return f;
}

let rows = readFileSync(IN, "utf8").trim().split("\n").map((l) => JSON.parse(l)).filter((r) => r.keadaan !== "gagal" && r.url);
if (SAMPLE > 0) {
    const kept = [];
    for (const label of [...new Set(rows.map((r) => r.label))]) {
        const g = rows.filter((r) => r.label === label);
        const step = Math.max(1, Math.floor(g.length / SAMPLE));
        kept.push(...g.filter((_, i) => i % step === 0).slice(0, SAMPLE));
    }
    rows = kept;
}
mkdirSync(OUT_DIR, { recursive: true });
const results = [];
let next = 0;
async function worker() {
    while (next < rows.length) {
        const r = rows[next++];
        const base = { id: r.id, label: r.label, sumber: r.sumber, kategori: r.kategori };
        try {
            const got = await Promise.race([fetchHtml(r.url), new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), TIMEOUT_MS + 5000))]);
            results.push({ ...base, ok: true, ...features(got.html, got.finalUrl) });
        } catch (e) {
            results.push({ ...base, ok: false, alasan: String(e?.message ?? "jaringan").slice(0, 20) });
        }
        if (results.length % 100 === 0) console.log(`${results.length}/${rows.length}`);
    }
}
await Promise.all(Array.from({ length: WORKERS }, worker));
writeFileSync(OUT, results.map((x) => JSON.stringify(x)).join("\n") + "\n");

const FLAGS = ["collector", "strongExfil", "telegram", "discord", "gas", "gform", "formservice", "firebase", "offsiteAction", "scriptOnlyCollect", "jsSends"];
const by = {};
for (const x of results) {
    const g = (by[x.label] ??= { n: 0, ok: 0 });
    g.n++;
    if (!x.ok) continue;
    g.ok++;
    for (const k of FLAGS) if (x[k]) g[k] = (g[k] ?? 0) + 1;
}
console.log(JSON.stringify(by, null, 1));
