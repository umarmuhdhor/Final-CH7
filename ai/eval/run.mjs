#!/usr/bin/env node
// M2 eval runner. One command:  node ai/eval/run.mjs
//   --analyze-url <base>   also call POST /analyze (M3/M4). Without it only layers 1-2 (M1) are scored.
//   --dir <path>           sample folder (default: ai/eval/data)
//   --tag <tag>            only samples with this tag
//   --json                 print machine-readable results instead of the table
//   --strict               exit 1 when the MVP targets are not met (only meaningful with 50+ per class and --analyze-url)
import { fileURLToPath } from "node:url";
import { loadSamples, loadDetector, evaluate, summarize, MIN_PER_CLASS, TARGETS } from "./lib.mjs";

function parseArgs(argv) {
    const args = { dir: fileURLToPath(new URL("./data", import.meta.url)), analyzeUrl: null, tag: null, json: false, strict: false };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === "--dir") args.dir = argv[++i];
        else if (a === "--analyze-url") args.analyzeUrl = argv[++i];
        else if (a === "--tag") args.tag = argv[++i];
        else if (a === "--json") args.json = true;
        else if (a === "--strict") args.strict = true;
        else {
            console.error(`unknown option ${a}`);
            process.exit(2);
        }
    }
    return args;
}

const pct = (v) => (v === null ? "n/a" : `${(v * 100).toFixed(0)}%`);
const pad = (s, n) => String(s).padEnd(n).slice(0, n);

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const { samples, errors } = loadSamples(args.dir);
    if (errors.length) {
        console.error(`${errors.length} sample problem(s):\n` + errors.map((e) => `  - ${e}`).join("\n"));
        process.exit(2);
    }
    const chosen = args.tag ? samples.filter((s) => (s.tags || []).includes(args.tag)) : samples;
    if (!chosen.length) {
        console.error("no samples found");
        process.exit(2);
    }

    const detector = loadDetector();
    const rows = [];
    for (const s of chosen) rows.push(await evaluate(s, { detector, analyzeUrl: args.analyzeUrl }));
    const summary = summarize(rows, { remote: !!args.analyzeUrl });

    if (args.json) {
        console.log(JSON.stringify({ summary, rows }, null, 2));
    } else {
        console.log(`${pad("id", 30)} ${pad("label", 6)} ${pad("L2", 4)} ${pad("score", 5)} ${pad("status", 9)} signals`);
        console.log("-".repeat(96));
        for (const r of rows) {
            const sigs = r.signals.map((s) => `${s.id}+${s.weight}`).join(" ") || "-";
            console.log(`${pad(r.id + (r.synthetic ? "*" : ""), 30)} ${pad(r.label, 6)} ${pad(r.localScore, 4)} ${pad(r.score, 5)} ${pad(r.status, 9)} ${sigs}`);
        }
        console.log("\n* = synthetic sample (made up to exercise a rule, not a real page)\n");

        const { counts, scam, legit, checks } = summary;
        console.log(`MODE: ${summary.mode}${args.analyzeUrl ? ` (${args.analyzeUrl})` : "  (no /analyze yet: layer 3-4 columns are empty)"}`);
        console.log(`samples: ${counts.scam} scam, ${counts.legit} legit  (need ${MIN_PER_CLASS}+ of each for the targets to mean anything)\n`);
        console.log(`scam   flagged >=30: ${scam.atLeast30}/${counts.scam}   >=50: ${scam.atLeast50}/${counts.scam}   >=80: ${scam.atLeast80}/${counts.scam}`);
        console.log(`legit  flagged >=30: ${legit.atLeast30}/${counts.legit}   >=50: ${legit.atLeast50}/${counts.legit}   >=80: ${legit.atLeast80}/${counts.legit}`);
        console.log(`\nTARGETS (mandate)            now        target`);
        console.log(`  scam   score >= 50         ${pad(pct(checks.scamAtLeast50.value), 10)} ${pct(TARGETS.scamAtLeast50)}`);
        console.log(`  scam   score >= 80         ${pad(pct(checks.scamAtLeast80.value), 10)} ${pct(TARGETS.scamAtLeast80)}`);
        console.log(`  legit  score >= 30         ${pad(checks.legitAtLeast30.value ?? "n/a", 10)} ${TARGETS.legitAtLeast30} pages`);
        if (summary.targetsMet === null) console.log(`  -> not judged: ${!args.analyzeUrl ? "layer 3-4 missing" : ""}${!summary.enough ? `${!args.analyzeUrl ? " and " : ""}fewer than ${MIN_PER_CLASS} per class` : ""}`);
        else console.log(`  -> targets ${summary.targetsMet ? "MET" : "NOT met"}`);
        const line = (t) => `scam ${t.scam.atLeast50}/${t.scam.n} >=50, ${t.scam.atLeast80}/${t.scam.n} >=80 | legit ${t.legit.atLeast30}/${t.legit.n} flagged`;
        console.log(`\nREAL vs SYNTHETIC (only real samples may back a claim about the targets)`);
        console.log(`  real       ${line(summary.real)}`);
        console.log(`  synthetic  ${line(summary.synthetic)}`);
        console.log(`\nHOLDOUT vs TUNING (holdout is looked at once, at the end of phase 07)`);
        console.log(`  holdout    ${line(summary.bySplit.holdout)}`);
        console.log(`  tuning     ${line(summary.bySplit.tuning)}`);
        console.log(`\nPER CATEGORY`);
        for (const [tag, t] of Object.entries(summary.byTag)) console.log(`  ${pad(tag, 18)} ${line(t)}`);
        if (summary.falsePositives.length) {
            console.log(`\nlegit pages that were flagged (false positives): ${summary.falsePositives.join(", ")}`);
            console.log("  by signal:", JSON.stringify(summary.falsePositiveSignals));
        }
        if (summary.misses.length) console.log(`scam pages under 50: ${summary.misses.join(", ")}`);
        console.log(`\nanalyzeLocal: avg ${summary.timing.analyzeLocalAvgMs.toFixed(2)} ms, max ${summary.timing.analyzeLocalMaxMs.toFixed(2)} ms (target < 50 ms)`);
    }
    if (args.strict && summary.targetsMet === false) process.exit(1);
}

main().catch((e) => {
    console.error(e);
    process.exit(2);
});
