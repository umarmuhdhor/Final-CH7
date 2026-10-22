#!/usr/bin/env node
// Writes the "holdout" tag into the sample files from data/HOLDOUT.json (seed + fraction). Nobody picks by hand.
//   node ai/eval/tools/assign-holdout.mjs --init   create HOLDOUT.json with a fresh random seed (refuses if it exists)
//   node ai/eval/tools/assign-holdout.mjs          re-apply the recorded seed to every sample file
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { join, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { holdoutOf, HOLDOUT_FRACTION, HOLDOUT_TAG } from "../corpus.mjs";

const dataDir = fileURLToPath(new URL("../data", import.meta.url));
const seedFile = join(dataDir, "HOLDOUT.json");

export function readSeed() {
    return JSON.parse(readFileSync(seedFile, "utf8")).seed;
}

function* jsonFiles(dir) {
    for (const name of readdirSync(dir).sort()) {
        const p = join(dir, name);
        if (statSync(p).isDirectory()) yield* jsonFiles(p);
        else if (extname(name) === ".json" && name !== "HOLDOUT.json") yield p;
    }
}

function main() {
    if (process.argv.includes("--init")) {
        if (existsSync(seedFile)) {
            console.error("HOLDOUT.json already exists: the seed is fixed once recorded (changing it would leak the holdout into tuning)");
            process.exit(2);
        }
        writeFileSync(seedFile, JSON.stringify({ seed: randomBytes(8).toString("hex"), fraction: HOLDOUT_FRACTION, createdAt: new Date().toISOString() }, null, 2) + "\n");
        console.log(`wrote ${seedFile}`);
    }
    const seed = readSeed();
    let changed = 0;
    for (const file of jsonFiles(dataDir)) {
        const parsed = JSON.parse(readFileSync(file, "utf8"));
        const list = Array.isArray(parsed) ? parsed : [parsed];
        let dirty = false;
        for (const s of list) {
            const tags = (s.tags || []).filter((t) => t !== HOLDOUT_TAG);
            if (holdoutOf(s.id, seed)) tags.push(HOLDOUT_TAG);
            if (JSON.stringify(tags) !== JSON.stringify(s.tags || [])) {
                s.tags = tags;
                dirty = true;
            }
        }
        if (dirty) {
            writeFileSync(file, JSON.stringify(parsed, null, 2) + "\n");
            changed++;
        }
    }
    console.log(`seed ${seed}: ${changed} file(s) updated`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
