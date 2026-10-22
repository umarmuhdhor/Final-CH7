#!/usr/bin/env node
// Is the corpus complete?  node ai/eval/tools/check-corpus.mjs   (exit 1 with the list of problems)
// Checks: 50+ per class, composition per category, label/source/collectedAt/redacted, redaction patterns, holdout vs seed.
import { fileURLToPath } from "node:url";
import { loadSamples } from "../lib.mjs";
import { validateCorpus, COMPOSITION, HOLDOUT_TAG } from "../corpus.mjs";
import { readSeed } from "./assign-holdout.mjs";

const dir = process.argv[2] || fileURLToPath(new URL("../data", import.meta.url));
const { samples, errors } = loadSamples(dir);
const problems = [...errors, ...validateCorpus(samples, { seed: readSeed(), minPerTag: COMPOSITION })];
const n = (f) => samples.filter(f).length;
console.log(`scam ${n((s) => s.label === "scam")} (real ${n((s) => s.label === "scam" && !s.synthetic)}), legit ${n((s) => s.label === "legit")} (real ${n((s) => s.label === "legit" && !s.synthetic)}), holdout ${n((s) => (s.tags || []).includes(HOLDOUT_TAG))}`);
for (const [tag, min] of Object.entries(COMPOSITION)) console.log(`  ${tag.padEnd(16)} ${n((s) => (s.tags || []).includes(tag))}/${min}`);
for (const p of problems) console.log(`PROBLEM ${p}`);
console.log(problems.length ? `${problems.length} problem(s)` : "corpus complete");
process.exit(problems.length ? 1 : 0);
