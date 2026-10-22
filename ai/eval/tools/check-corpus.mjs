#!/usr/bin/env node
// Is the corpus complete?  node ai/eval/tools/check-corpus.mjs   (exit 1 with the list of problems)
// Checks: 50+ per class, composition per category (inside each class, one category tag per sample), label/source/collectedAt/
// redacted, redaction patterns, holdout vs seed, and 60% real legit (D-imelda-22). Real scam count is only reported: see WARNING.
import { fileURLToPath } from "node:url";
import { loadSamples, MIN_PER_CLASS } from "../lib.mjs";
import { validateCorpus, COMPOSITION, HOLDOUT_TAG } from "../corpus.mjs";
import { readSeed } from "./assign-holdout.mjs";

const dir = process.argv[2] || fileURLToPath(new URL("../data", import.meta.url));
const { samples, errors } = loadSamples(dir);
const problems = [...errors, ...validateCorpus(samples, { seed: readSeed(), composition: COMPOSITION, minRealShare: { legit: 0.6 } })];
const n = (f) => samples.filter(f).length;
const realScam = n((s) => s.label === "scam" && !s.synthetic);
console.log(`scam ${n((s) => s.label === "scam")} (real ${realScam}), legit ${n((s) => s.label === "legit")} (real ${n((s) => s.label === "legit" && !s.synthetic)}), holdout ${n((s) => (s.tags || []).includes(HOLDOUT_TAG))}`);
for (const [label, tags] of Object.entries(COMPOSITION)) for (const [tag, min] of Object.entries(tags)) console.log(`  ${label.padEnd(5)} ${tag.padEnd(16)} ${n((s) => s.label === label && (s.tags || []).includes(tag))}/${min}`);
for (const p of problems) console.log(`PROBLEM ${p}`);
if (realScam < MIN_PER_CLASS) console.log(`WARNING only ${realScam} real scam sample(s): the mandate targets cannot be judged until there are ${MIN_PER_CLASS} real ones (D-imelda-19, D-imelda-22)`);
console.log(problems.length ? `${problems.length} problem(s)` : "corpus complete");
process.exit(problems.length ? 1 : 0);
