// Step 2: sample-input.jsonl (PageSnapshots) -> rows in the exact shape Alief's model reads (feats + baseline).
// Usage: node build-rows.mjs            reads .hasil/sample-input.jsonl, writes .hasil/rows.jsonl
//
// addressFacts() and rowFromSnapshot() are copied from shoo-layer3-lab/src/build_snapshots.mjs (commit c29f2b2), which
// only accepts raw HTML. Nothing else changed: same brand list, same feature names, same current-layer-3 call.
// "baseline" is this repo's real layer 3 (analyzeSnapshot) on the snapshot: no layer 1, 2, 4, no domain age.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const AI = join(HERE, "../..");
// Optional first argument: another test folder (it holds its own .hasil/sample-input.jsonl). Default: this folder.
const BASE = process.argv[2] ? resolve(process.argv[2]) : HERE;
const { analyzeSnapshot } = await import(join(AI, "src/analyze.js"));
const { isOfficialHost } = await import(join(AI, "src/layer3/official.js"));
const { SHARED_HOSTS } = await import(join(AI, "src/blocklist/allowlist.js"));
const brandData = JSON.parse(readFileSync(join(AI, "../detector/data/brands.json"), "utf8"));

const BRAND_NAMES = brandData.brands.map((b) => [...new Set([b.name, ...(b.names || []), ...(b.commonNames || [])].map((n) => n.toLowerCase()))]);
const CHEAP_TLDS = new Set((brandData.cheapTlds || []).map((t) => t.replace(/^\./, "").toLowerCase()));
const URL_KEYWORDS = (brandData.keywords || []).map((k) => String(k).toLowerCase());
const esc = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const BRAND_WORD = BRAND_NAMES.map((names) => new RegExp(`(^|[^a-z0-9])(${names.map(esc).join("|")})([^a-z0-9]|$)`, "i"));
const SECOND_LEVEL = /^(co|go|ac|or|web|sch|my|biz|net|com|org|gov|edu|mil|desa|ponpes)\.[a-z]{2}$/;
const site = (host) => {
    const p = host.replace(/^www\./, "").split(".");
    return p.slice(SECOND_LEVEL.test(p.slice(-2).join(".")) ? -3 : -2).join(".");
};
const hostOf = (u) => {
    try {
        return new URL(u).hostname.toLowerCase();
    } catch {
        return "";
    }
};

function addressFacts(snap, host, url) {
    const official = isOfficialHost(host);
    const count = (text) => BRAND_WORD.filter((re) => re.test(text)).length;
    const inTitle = count(snap.title || "");
    const inText = count((snap.text || "").slice(0, 6000));
    const pieces = host.split(/[.\-_0-9]+/).filter(Boolean);
    const inHost = BRAND_NAMES.some((names) => names.some((n) => (n.length >= 5 ? host.includes(n.replace(/\s+/g, "")) : pieces.includes(n))));
    let path = "";
    try {
        path = new URL(url).pathname;
    } catch {}
    const labels = host.split(".");
    const shared = [...SHARED_HOSTS].some((h) => host === h || host.endsWith("." + h));
    const lowered = (host + path).toLowerCase();
    return {
        official,
        brandsInTitle: inTitle,
        brandsInText: inText,
        brandOffsite: !official && inTitle > 0,
        brandTextOffsite: !official && inText > 0,
        brandInHost: !official && inHost,
        cheapTld: CHEAP_TLDS.has(labels[labels.length - 1]),
        sharedHost: shared,
        hostLen: host.length,
        hostDigits: (host.match(/[0-9]/g) || []).length,
        hostHyphens: (host.match(/-/g) || []).length,
        subdomains: Math.max(0, labels.length - site(host).split(".").length),
        pathLen: path.length,
        pathDepth: path.split("/").filter(Boolean).length,
        ipHost: /^[0-9.]+$/.test(host),
        punycode: host.includes("xn--"),
        urlKeywords: URL_KEYWORDS.filter((k) => lowered.includes(k)).length,
    };
}

function rowFromSnapshot(snap, host, url) {
    const signals = analyzeSnapshot(snap);
    const forms = snap.forms || [];
    const fields = forms.flatMap((x) => x.fields || []);
    const noBanner = (t) => (t || "").replace(/The Wayback Machine - \S+\s*/g, "");
    const text = noBanner(snap.text);
    const offsite = forms.some((f) => /^https?:\/\//i.test(f.action || "") && site(hostOf(f.action)) !== site(host));
    return {
        host,
        title: noBanner(snap.title),
        text,
        baseline: { score: signals.reduce((s, x) => s + (x.weight ?? 0), 0), signals: signals.map((s) => s.id) },
        feats: {
            textLen: text.length,
            fields: fields.length,
            passwordField: fields.some((x) => x.type === "password"),
            forms: forms.length,
            imageAlts: (snap.imageAlts || []).length,
            formActionOffsite: offsite,
            ...addressFacts({ title: noBanner(snap.title), text }, host, url),
        },
    };
}

const input = readFileSync(join(BASE, ".hasil/sample-input.jsonl"), "utf8").split("\n").filter(Boolean);
const out = [];
let failed = 0, mismatch = 0, compared = 0, slow = 0;
for (const line of input) {
    const r = JSON.parse(line);
    const host = hostOf(r.url);
    if (!host) {
        failed++;
        continue;
    }
    try {
        const t0 = Date.now();
        const row = rowFromSnapshot(r.snapshot, host, r.url);
        if (Date.now() - t0 > 2000) slow++;
        if (r.her_stored) {
            compared++;
            if (r.her_stored.scoreNoAge !== row.baseline.score) mismatch++;
        }
        out.push({ id: r.id, dataset: r.dataset, label: r.label, url: r.url, ...row });
    } catch {
        failed++;
    }
}
writeFileSync(join(BASE, ".hasil/rows.jsonl"), out.map((r) => JSON.stringify(r)).join("\n") + "\n");
console.log(`rows ${out.length} of ${input.length} | failed ${failed} | slower than 2 s ${slow}`);
console.log(`sanity: stored scoreNoAge vs recomputed baseline on ${compared} phishing-url pages: ${mismatch} differ`);
