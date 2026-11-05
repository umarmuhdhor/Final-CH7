#!/usr/bin/env node
// Layer 5 eval: does the LLM's suggestion (POST /review) beat the plain rule? Reads the JSON lines that
// `seed-dummy.sh --export` writes (admin.ai_dataset, one row per Guardian decision) and prints precision / recall for
//   (a) the rule  families_not_safe >= 2 && domain_avg_score >= 50  -> approve
//   (b) the LLM   review_suggestion === "approve"
// Truth: final_label scam_strong / scam_weak = scam, safe = not scam. Counted per domain, on domains that have a label,
// are not shared hosts and were reviewed, so both sides are scored on the same domains.
// With dummy data the numbers prove nothing: the decision "use the LLM or not" needs real Guardian data.
//
//   node eval/dataset/eval-review.mjs out.jsonl
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const RULE_MIN_FAMILIES = 2;
const RULE_MIN_AVG_SCORE = 50;

const ruleApproves = (d) => d.families_not_safe >= RULE_MIN_FAMILIES && d.domain_avg_score >= RULE_MIN_AVG_SCORE;
const llmApproves = (d) => d.review_suggestion === "approve";
const isScam = (d) => d.final_label === "scam_strong" || d.final_label === "scam_weak";

function score(domains, predict) {
    const c = { tp: 0, fp: 0, fn: 0, tn: 0 };
    for (const d of domains) {
        const said = predict(d);
        const truth = isScam(d);
        if (said && truth) c.tp++;
        else if (said) c.fp++;
        else if (truth) c.fn++;
        else c.tn++;
    }
    // null = undefined (nothing predicted / nothing to find), not 0
    return { ...c, precision: c.tp + c.fp ? c.tp / (c.tp + c.fp) : null, recall: c.tp + c.fn ? c.tp / (c.tp + c.fn) : null };
}

/** @param {object[]} rows admin.ai_dataset rows (several per domain) */
export function evalReview(rows) {
    const byDomain = new Map();
    for (const r of rows) if (!byDomain.has(r.domain)) byDomain.set(r.domain, r); // domain-level fields repeat per family row
    const domains = [...byDomain.values()].filter((d) => !d.shared_host && (d.final_label === "safe" || isScam(d)) && d.review_result !== null && d.review_result !== undefined);
    return { n: domains.length, rule: score(domains, ruleApproves), llm: score(domains, llmApproves) };
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
    const file = process.argv[2];
    if (!file) {
        console.error("usage: node eval/dataset/eval-review.mjs out.jsonl");
        process.exit(2);
    }
    const rows = readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
    console.log(formatEval(evalReview(rows)));
}
