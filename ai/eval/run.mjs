#!/usr/bin/env node
// M2 eval runner. One command:  node ai/eval/run.mjs
//   --analyze-url <base>   also call POST /analyze (M3/M4). Without it only layers 1-2 (M1) are scored.
//   --dir <path>           sample folder (default: ai/eval/data)
//   --tag <tag>            only samples with this tag
//   --json                 print machine-readable results instead of the table
//   --show-holdout         also list holdout samples one by one (default: only their totals; look at them once, at the end of phase 07)
//   --strict               exit 0 only when the targets were judged (50+ real per class, --analyze-url, no /analyze failure) AND met; 1 = not met, 2 = not judged
import { fileURLToPath } from "node:url";
import { loadSamples, loadDetector, evaluate, summarize, probeAnalyze, layer4Stats, layer4Delta, strictExitCode, visibleRows, jsonReport, normalizeSnapshot, MIN_PER_CLASS, TARGETS } from "./lib.mjs";

function parseArgs(argv) {
    const args = { dir: fileURLToPath(new URL("./data", import.meta.url)), analyzeUrl: null, tag: null, json: false, strict: false, showHoldout: false };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        const value = () => {
            const v = argv[++i];
            if (v === undefined || v.startsWith("--")) {
                console.error(`${a} needs a value`);
                process.exit(2);
            }
            return v;
        };
        if (a === "--dir") args.dir = value();
        else if (a === "--analyze-url") args.analyzeUrl = value();
        else if (a === "--tag") args.tag = value();
        else if (a === "--show-holdout") args.showHoldout = true;
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

    if (args.analyzeUrl) await probeAnalyze(args.analyzeUrl);
    const l4Before = args.analyzeUrl ? await layer4Stats(args.analyzeUrl) : null;
    const detector = loadDetector();
    const rows = [];
    await detector.analyzeLocal(normalizeSnapshot(chosen[0].snapshot)); // warm-up: the first call is slow and would skew the max timing
    for (const s of chosen) rows.push(await evaluate(s, { detector, analyzeUrl: args.analyzeUrl }));
    const summary = summarize(rows, { remote: !!args.analyzeUrl });
    const layer4 = args.analyzeUrl ? layer4Delta(l4Before, await layer4Stats(args.analyzeUrl)) : null;

    if (args.json) {
        console.log(JSON.stringify({ ...jsonReport(rows, summary, args), layer4 }, null, 2));
    } else {
        console.log(`${pad("id", 30)} ${pad("label", 6)} ${pad("L2", 4)} ${pad("score", 5)} ${pad("status", 9)} signals`);
        console.log("-".repeat(96));
        const shown = visibleRows(rows, args);
        for (const r of shown) {
            const sigs = r.signals.map((s) => `${s.id}+${s.weight}`).join(" ") || "-";
            console.log(`${pad(r.id + (r.synthetic ? "*" : ""), 30)} ${pad(r.label, 6)} ${pad(r.localScore, 4)} ${pad(r.score, 5)} ${pad(r.status, 9)} ${sigs}`);
        }
        console.log(`\n* = synthetic sample (made up to exercise a rule, not a real page)${shown.length < rows.length ? `\n${rows.length - shown.length} holdout row(s) not listed (use --show-holdout)` : ""}\n`);

        const { counts, scam, legit, checks } = summary;
        console.log(`MODE: ${summary.mode}${args.analyzeUrl ? ` (${args.analyzeUrl})` : "  (no /analyze yet: layer 3-4 columns are empty)"}`);
        console.log(`samples: ${counts.scam} scam, ${counts.legit} legit  (need ${MIN_PER_CLASS}+ of each for the targets to mean anything)\n`);
        console.log(`scam   flagged >=30: ${scam.atLeast30}/${counts.scam}   >=50: ${scam.atLeast50}/${counts.scam}   >=80: ${scam.atLeast80}/${counts.scam}`);
        console.log(`legit  flagged >=30: ${legit.atLeast30}/${counts.legit}   >=50: ${legit.atLeast50}/${counts.legit}   >=80: ${legit.atLeast80}/${counts.legit}`);
        const realN = summary.real;
        console.log(`\nTARGETS (mandate)            real only   all samples  target     (real: ${realN.scam.n} scam, ${realN.legit.n} legit)`);
        const all = summary.checksAll;
        console.log(`  scam   score >= 50         ${pad(pct(checks.scamAtLeast50.value), 11)} ${pad(pct(all.scamAtLeast50.value), 12)} ${pct(TARGETS.scamAtLeast50)}`);
        console.log(`  scam   score >= 80         ${pad(pct(checks.scamAtLeast80.value), 11)} ${pad(pct(all.scamAtLeast80.value), 12)} ${pct(TARGETS.scamAtLeast80)}`);
        console.log(`  legit  score >= 30         ${pad(checks.legitAtLeast30.value ?? "n/a", 11)} ${pad(all.legitAtLeast30.value ?? "n/a", 12)} ${TARGETS.legitAtLeast30} pages`);
        if (summary.targetsMet === null) {
            const why = [];
            if (!args.analyzeUrl) why.push("layer 3-4 missing");
            if (!summary.realEnough) why.push(`fewer than ${MIN_PER_CLASS} real samples per class (synthetic samples cannot back a claim)`);
            if (summary.remoteFailures) why.push(`/analyze failed for ${summary.remoteFailures} page(s)`);
            console.log(`  -> not judged: ${why.join("; ")}`);
        } else console.log(`  -> targets ${summary.targetsMet ? "MET" : "NOT met"}`);
        if (summary.remoteFailures) console.log(`  WARNING /analyze failed for ${summary.remoteFailures} page(s): those rows have no layer 3-4 result`);
        const line = (t) => `scam ${t.scam.atLeast50}/${t.scam.n} >=50, ${t.scam.atLeast80}/${t.scam.n} >=80 | legit ${t.legit.atLeast30}/${t.legit.n} flagged`;
        console.log(`\nREAL vs SYNTHETIC (only real samples may back a claim about the targets)`);
        console.log(`  real       ${line(summary.real)}`);
        console.log(`  synthetic  ${line(summary.synthetic)}`);
        console.log(`\nHOLDOUT vs TUNING (holdout is looked at once, at the end of phase 07)`);
        console.log(`  holdout    ${line(summary.bySplit.holdout)}`);
        console.log(`  tuning     ${line(summary.bySplit.tuning)}`);
        console.log(`\nPER CATEGORY`);
        for (const [tag, t] of Object.entries(summary.byTag)) console.log(`  ${pad(tag, 18)} ${line(t)}`);
        const shownIds = new Set(shown.map((r) => r.id));
        const listed = (ids) => `${ids.filter((id) => shownIds.has(id)).join(", ")}${ids.some((id) => !shownIds.has(id)) ? ` (+${ids.filter((id) => !shownIds.has(id)).length} holdout, hidden)` : ""}`;
        if (summary.falsePositives.length) {
            console.log(`\nlegit pages that were flagged (false positives): ${listed(summary.falsePositives)}`);
            console.log("  by signal (all rows):", JSON.stringify(summary.falsePositiveSignals));
        }
        if (summary.misses.length) console.log(`scam pages under 50: ${listed(summary.misses)}`);
        if (args.analyzeUrl) {
            const flagged = (label) => rows.filter((r) => r.label === label && r.signals.some((x) => x.id === "unreasonable_request")).length;
            console.log(`\nLAYER 4 (unreasonable_request): scam ${flagged("scam")}/${summary.counts.scam}, legit ${flagged("legit")}/${summary.counts.legit}`);
            if (layer4) {
                console.log(`  ${layer4.promptVersion} · model ${layer4.model}`);
                console.log(`  outcomes: ${Object.entries(layer4.outcomes).map(([k, v]) => `${k} ${v}`).join(", ")}`);
                const broken = layer4.outcomes.http_error + layer4.outcomes.timeout + layer4.outcomes.bad_schema + layer4.outcomes.capped;
                if (broken) console.log(`  WARNING ${broken} layer 4 call(s) gave no verdict (http_error/timeout/bad_schema/capped): layer 4 numbers are incomplete`);
            } else console.log("  outcomes: n/a (layer 4 off, or not the local dev server)");
        }
        console.log(`\nanalyzeLocal: avg ${summary.timing.analyzeLocalAvgMs.toFixed(2)} ms, max ${summary.timing.analyzeLocalMaxMs.toFixed(2)} ms (target < 50 ms)`);
        if (summary.timing.analyzeRemoteP95Ms !== null) console.log(`/analyze: p95 ${Math.round(summary.timing.analyzeRemoteP95Ms)} ms (target < 8000 ms; the server cuts layer 4 at 6500 ms, D-imelda-38)`);
    }
    if (args.strict) process.exit(strictExitCode(summary));
}

main().catch((e) => {
    console.error(e);
    process.exit(2);
});
