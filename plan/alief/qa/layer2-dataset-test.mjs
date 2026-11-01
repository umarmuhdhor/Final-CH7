// Test 3a: the link datasets in ai/test-layer2 (dataset.md scam, dataset-legit.md legit) through layers 1–4,
// offline, the same way as Test 2a. The datasets are URLs only, so every sample is a URL with no page text:
//   L1  public blocklist of the local AI Worker (GET /public-blocklist), matched like the extension does
//       (ios/ShooExtension/Resources lists.js candidates + domain.js registrableDomain + psl.js)
//   L2  the real detector (ai/eval/lib.mjs loadDetector = the script the extension runs)
//   L3–4 POST /analyze with the URL-only snapshot (nothing to read on the page, so mostly the URL)
// No link is opened. Reads ai/test-layer2/*.md, never writes there (Team AI / lead folder).
//   npx --prefix ai wrangler dev --cwd ai --port 8788 &
//   node plan/alief/qa/layer2-dataset-test.mjs [http://127.0.0.1:8788]
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadDetector, evaluate, scoreOf, statusOf } from "../../../ai/eval/lib.mjs";
import { PSL_RULES } from "../../../ios/ShooExtension/Resources/psl.js";
import { parseRules, registrableDomain } from "../../../ios/ShooExtension/Resources/domain.js";
import { candidates } from "../../../ios/ShooExtension/Resources/lists.js";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../..");
const base = process.argv[2] || "http://127.0.0.1:8788";

const parse = (file, expect) =>
    readFileSync(join(root, "ai/test-layer2", file), "utf8").split("\n")
        .filter((l) => /^\|\s*\d+\s*\|/.test(l))
        .map((l) => l.split("|").slice(1, -1).map((c) => c.trim()))
        .map(([n, url, label, batch, note]) => ({ id: `${expect}-${n}`, file: `ai/test-layer2/${file}`, url, label: expect, datasetLabel: label, batch, note }));
const rows = [...parse("dataset.md", "scam"), ...parse("dataset-legit.md", "legit")];

// L1: every page of the public blocklist.
const blocked = new Set();
for (let since = "", page = 0; page < 50; page++) {
    const r = await fetch(new URL(`/public-blocklist${since ? `?since=${encodeURIComponent(since)}` : ""}`, base));
    if (!r.ok) throw new Error(`/public-blocklist ${r.status}`);
    const body = await r.json();
    for (const d of body.domains ?? []) blocked.add(d.domain.toLowerCase());
    if (!body.nextSince || body.nextSince === since || !(body.domains ?? []).length) break;
    since = body.nextSince;
}
const psl = parseRules(PSL_RULES);
const onBlocklist = (host) => candidates(host, registrableDomain(host, psl)).find((d) => blocked.has(d)) ?? null;

const detector = loadDetector();
const results = [];
for (const r of rows) {
    const host = new URL(r.url).hostname.toLowerCase();
    const sample = { id: r.id, label: r.label, snapshot: { url: r.url, title: "", lang: null, text: "", forms: [], imageAlts: [] } };
    const e = await evaluate(sample, { detector, analyzeUrl: base });
    const hit = onBlocklist(host);
    const signals = hit ? [{ id: "db_match", layer: 1, weight: 100, evidence: "public" }, ...e.signals] : e.signals;
    const score = scoreOf(signals);
    results.push({
        ...r, host, blocklist: hit, localScore: e.localScore, score, status: statusOf(score), remoteOk: e.remoteOk, remoteMs: Math.round(e.remoteMs ?? 0),
        signals: signals.map((g) => `${g.id}:L${g.layer}:${g.weight}`),
    });
    process.stdout.write(".");
}
const of = (label, f) => results.filter((x) => x.label === label && f(x)).length;
const summary = {
    run: new Date().toISOString(), base, blocklistSize: blocked.size,
    counts: { scam: of("scam", () => true), legit: of("legit", () => true) },
    scam: { blocklist: of("scam", (x) => x.blocklist), l2Any: of("scam", (x) => x.localScore > 0), atLeast30: of("scam", (x) => x.score >= 30), atLeast50: of("scam", (x) => x.score >= 50), atLeast80: of("scam", (x) => x.score >= 80) },
    legit: { atLeast30: of("legit", (x) => x.score >= 30), anySignal: of("legit", (x) => x.signals.length > 0) },
    remoteFailures: results.filter((x) => x.remoteOk === false).length,
};
const out = join(here, "img/figma-parity/layer2-dataset-results.json");
writeFileSync(out, JSON.stringify({ summary, results }, null, 2) + "\n");
console.log("\n" + JSON.stringify(summary));
