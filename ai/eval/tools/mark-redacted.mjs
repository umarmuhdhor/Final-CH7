#!/usr/bin/env node
// For the OWNER, after reading the sample files:  node ai/eval/tools/mark-redacted.mjs --confirm-read --ids a,b,c   (or --all)
//   --dir <path>   another sample folder (default ai/eval/data), e.g. ai/eval/private from import-dashboard.mjs
// Sets "redacted": true on real samples. Refuses a sample that still has a finding from check-redaction. An agent must not run this.
import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isMain } from "./is-main.mjs";
import { findPersonalData } from "./check-redaction.mjs";

const defaultDir = fileURLToPath(new URL("../data", import.meta.url));

/** `--dir <path>` or the default folder; exits on a flag without a value. */
export function dirArg(argv, fallback) {
    const at = argv.indexOf("--dir");
    if (at === -1) return fallback;
    const v = argv[at + 1];
    if (!v || v.startsWith("--")) {
        console.error("--dir needs a folder");
        process.exit(2);
    }
    return resolve(v);
}

/** @returns {{marked: string[], refused: string[]}} mutates the samples that qualify */
export function markRedacted(samples, ids /* null = all */) {
    const marked = [];
    const refused = [];
    for (const s of samples) {
        if (s.synthetic === true || s.redacted === true) continue;
        if (ids && !ids.includes(s.id)) continue;
        if (findPersonalData(s).length) refused.push(s.id);
        else {
            s.redacted = true;
            marked.push(s.id);
        }
    }
    return { marked, refused };
}

function* jsonFiles(dir) {
    for (const name of readdirSync(dir).sort()) {
        const p = join(dir, name);
        if (statSync(p).isDirectory()) yield* jsonFiles(p);
        else if (extname(name) === ".json" && name !== "HOLDOUT.json") yield p;
    }
}

function main() {
    const argv = process.argv.slice(2);
    if (!argv.includes("--confirm-read") || (!argv.includes("--all") && !argv.includes("--ids"))) {
        console.error("usage: mark-redacted.mjs --confirm-read (--all | --ids a,b,c)   (only after you have read the files)");
        process.exit(2);
    }
    const idArg = argv.includes("--ids") ? argv[argv.indexOf("--ids") + 1] : null;
    if (argv.includes("--ids") && (!idArg || idArg.startsWith("--"))) {
        console.error("--ids needs a comma-separated list");
        process.exit(2);
    }
    const ids = idArg ? idArg.split(",") : null;
    const dataDir = dirArg(argv, defaultDir);
    let total = 0;
    for (const file of jsonFiles(dataDir)) {
        const parsed = JSON.parse(readFileSync(file, "utf8"));
        const list = Array.isArray(parsed) ? parsed : [parsed];
        const { marked, refused } = markRedacted(list, ids);
        if (refused.length) console.log(`refused (still has personal data): ${refused.join(", ")}`);
        if (marked.length) {
            writeFileSync(file, JSON.stringify(parsed, null, 2) + "\n");
            total += marked.length;
        }
    }
    console.log(`${total} sample(s) marked redacted`);
}

if (isMain(import.meta.url)) main();
