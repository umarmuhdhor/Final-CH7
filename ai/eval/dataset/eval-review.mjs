#!/usr/bin/env node
// Layer 5 eval: does the LLM's suggestion (POST /review) beat the plain rule? Reads the JSON lines that
// `seed-dummy.sh --export` writes (admin.ai_dataset, one row per Guardian decision) and prints precision / recall for
//   (a) the rule  families_not_safe >= 2 && domain_avg_score >= 50  -> approve
//   (b) the LLM   review_suggestion === "approve"
// Truth, per domain (a `truth` function returns true = scam, false = not scam, null = leave the domain out):
//   default       final_label scam_strong / scam_weak = scam, safe = not scam. Fine for real data once an admin decided.
//   --dummy-truth the name of the dummy domain: scam-*.shoo-dummy.test = scam, legit-*.shoo-dummy.test = not scam, the rest out.
//                 Needed on dummy data: final_label is computed from the families' votes, so `legit-05` (2 N + 2 Y, built to
//                 be legit) gets scam_weak and a rule that approves it would count as right.
// Counted on domains that have a truth, are not shared hosts and were reviewed, so both sides are scored on the same domains.
// With dummy data the numbers prove nothing: the decision "use the LLM or not" needs real Guardian data.
//
//   node eval/dataset/eval-review.mjs out.jsonl [--dummy-truth]
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const RULE_MIN_FAMILIES = 2;
const RULE_MIN_AVG_SCORE = 50;

const ruleApproves = (d) => d.families_not_safe >= RULE_MIN_FAMILIES && d.domain_avg_score >= RULE_MIN_AVG_SCORE;
const llmApproves = (d) => d.review_suggestion === "approve";
const isScam = (d) => d.final_label === "scam_strong" || d.final_label === "scam_weak";

/** Default truth: the label the Guardians' votes produced. */
export const labelTruth = (d) => (isScam(d) ? true : d.final_label === "safe" ? false : null);

/** Dummy truth: what the dummy generator meant the domain to be (`ai/eval/dataset/dummy.mjs`). */
export const dummyTruth = (d) => (/^scam-/.test(d.domain) ? true : /^legit-/.test(d.domain) ? false : null);

function score(domains, predict, truthOf) {
    const c = { tp: 0, fp: 0, fn: 0, tn: 0 };
    for (const d of domains) {
        const said = predict(d);
        const truth = truthOf(d);
        if (said && truth) c.tp++;
        else if (said) c.fp++;
        else if (truth) c.fn++;
        else c.tn++;
    }
    // null = undefined (nothing predicted / nothing to find), not 0
    return { ...c, precision: c.tp + c.fp ? c.tp / (c.tp + c.fp) : null, recall: c.tp + c.fn ? c.tp / (c.tp + c.fn) : null };
}

/**
 * @param {object[]} rows admin.ai_dataset rows (several per domain)
 * @param {{ truth?: (d: object) => boolean | null }} [options] truth: true scam, false not scam, null leave the domain out
 */
export function evalReview(rows, { truth = labelTruth } = {}) {
    const byDomain = new Map();
    for (const r of rows) if (!byDomain.has(r.domain)) byDomain.set(r.domain, r); // domain-level fields repeat per family row
    const domains = [...byDomain.values()].filter((d) => !d.shared_host && truth(d) !== null && d.review_result !== null && d.review_result !== undefined);
    return { n: domains.length, rule: score(domains, ruleApproves, truth), llm: score(domains, llmApproves, truth) };
}

const pct = (v) => (v === null ? "n/a" : v.toFixed(2));

export function formatEval(result) {
    const line = (name, s) => `| ${name} | ${s.tp} | ${s.fp} | ${s.fn} | ${s.tn} | ${pct(s.precision)} | ${pct(s.recall)} |`;
    return [
        `Domains scored: ${result.n} (labelled, not shared hosts, reviewed)`,
        "",
        "| Approach | TP | FP | FN | TN | Precision | Recall |",
        "|---|---|---|---|---|---|---|",
        line("(a) rule: >= 2 families N and avg score >= 50", result.rule),
        line("(b) LLM suggestion = approve", result.llm),
    ].join("\n");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
    const args = process.argv.slice(2);
    const file = args.find((a) => !a.startsWith("--"));
    const unknown = args.filter((a) => a.startsWith("--") && a !== "--dummy-truth");
    if (!file || unknown.length) {
        console.error("usage: node eval/dataset/eval-review.mjs out.jsonl [--dummy-truth]");
        process.exit(2);
    }
    const rows = readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
    console.log(formatEval(evalReview(rows, { truth: args.includes("--dummy-truth") ? dummyTruth : labelTruth })));
}
