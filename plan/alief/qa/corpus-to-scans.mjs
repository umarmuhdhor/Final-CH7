// Figma parity QA, test 2a: Imelda's eval corpus with the detector's real results, as app scans.
//
//   node ai/eval/run.mjs --analyze-url http://127.0.0.1:8788 --json --show-holdout > /tmp/corpus-eval.json
//   node plan/alief/qa/corpus-to-scans.mjs /tmp/corpus-eval.json
//
// Writes ios/ShooApp/Data/Fixtures/corpus-scans.json (a ScanPage for `-mock.scenario corpus`) and
// plan/alief/qa/img/figma-parity/corpus-results.json (every sample, also the ones under 30 that the
// extension never sends). Only rows with score >= 30 become scans, as in the real pipeline.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadSamples } from "../../../ai/eval/lib.mjs";

const repo = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const report = JSON.parse(readFileSync(process.argv[2], "utf8"));
const samples = new Map(loadSamples(join(repo, "ai/eval/data")).samples.map((s) => [s.id, s]));

// Same people as MockScenarios.figma, so the Guardian, Pribadi and Protected views all get rows.
const owners = [
    ["dev_syahnaz", "Syahnaz"], ["dev_bayu", "Bayu"], ["dev_renatta", "Renatta"], ["dev_me", "Adhella"], ["dev_maria", "Maria"],
];
const base = Date.parse("2026-10-31T03:42:00Z");

const results = [];
const items = [];
report.rows.forEach((row, i) => {
    const sample = samples.get(row.id);
    const url = new URL(sample.snapshot.url);
    results.push({
        id: row.id, label: row.label, synthetic: row.synthetic, holdout: row.tags.includes("holdout"), url: url.href,
        localScore: row.localScore, score: row.score, status: row.status, remoteOk: row.remoteOk,
        signals: row.signals.map((s) => `${s.id}:L${s.layer}:${s.weight}`),
    });
    if (row.score < 30) return;
    const [ownerDeviceId, ownerName] = owners[items.length % owners.length];
    items.push({
        id: `corpus-${row.id}`,
        url: url.href,
        domain: url.hostname,
        pageTitle: sample.snapshot.title || null,
        faviconUrl: null,
        score: row.score,
        status: row.score >= 80 ? "blocked" : "warning",
        signals: row.signals.map((s) => ({
            id: s.id, layer: s.layer, weight: s.weight,
            label: s.label ?? { en: s.id, id: s.id },
            labelSimple: s.labelSimple ?? s.label ?? { en: s.id, id: s.id },
            ...(s.evidence ? { evidence: s.evidence } : {}),
        })),
        screenshotUrl: null,
        pageReplicaUrl: null,
        ownerDeviceId, ownerName,
        detectedAt: new Date(base - i * 47 * 60_000).toISOString(),
        verdict: null,
    });
});

writeFileSync(join(repo, "ios/ShooApp/Data/Fixtures/corpus-scans.json"), JSON.stringify({ items, nextCursor: null }, null, 2) + "\n");
const out = join(repo, "plan/alief/qa/img/figma-parity");
mkdirSync(out, { recursive: true });
writeFileSync(join(out, "corpus-results.json"), JSON.stringify({ summary: report.summary, results }, null, 2) + "\n");
console.log(`${report.rows.length} samples, ${items.length} scans (score >= 30)`);
