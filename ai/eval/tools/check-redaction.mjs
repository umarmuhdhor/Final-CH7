#!/usr/bin/env node
// Redaction checker: node ai/eval/tools/check-redaction.mjs [dir]   (default: ai/eval/data)
// Exits 1 when any sample still holds an e-mail, a phone number, a 13-19 digit number (NIK, card, account),
// a token/key, or a URL (page, iframe, form action) with a query value other than REDACTED, a fragment or credentials.
// Look-alike characters (fullwidth, Arabic digits) are folded first. Pure check: reads files, writes nothing.
import { fileURLToPath } from "node:url";
import { loadSamples } from "../lib.mjs";
import { fold, MASKS, SECRETS } from "./patterns.mjs";
import { isMain } from "./is-main.mjs";

const RULES = [...MASKS.map(([name, , re]) => [name, new RegExp(re.source, re.flags.replace("g", ""))]), ...SECRETS];

function urlProblem(raw) {
    try {
        const u = new URL(raw, "https://relative.invalid/");
        if (u.hash) return "has a fragment";
        for (const [k, v] of u.searchParams) if (v !== "REDACTED") return `query value of "${k}" is not REDACTED`;
        if (u.username || u.password) return "has credentials";
        return null;
    } catch {
        return "is not a valid URL";
    }
}

/** @returns {string[]} one line per finding, naming the field; empty = clean */
export function findPersonalData(sample) {
    const out = [];
    const scan = (where, value) => {
        if (typeof value !== "string" || !value) return;
        const text = fold(value);
        for (const [name, re] of RULES) if (re.test(text)) out.push(`${where}: ${name}`);
    };
    const scanUrl = (where, url) => {
        if (typeof url !== "string" || !url) return;
        const p = urlProblem(url);
        if (p) out.push(`${where} (url): ${p}`);
        scan(where, url.replace(/REDACTED/g, ""));
    };
    const snap = sample.snapshot || {};
    scanUrl("snapshot.url", snap.url);
    for (const [i, u] of (sample.meta?.iframes || []).entries()) scanUrl(`meta.iframes[${i}]`, u);
    scan("snapshot.title", snap.title);
    scan("snapshot.text", snap.text);
    for (const [i, a] of (snap.imageAlts || []).entries()) scan(`snapshot.imageAlts[${i}]`, a);
    for (const [i, f] of (snap.forms || []).entries()) {
        scanUrl(`snapshot.forms[${i}].action`, f.action);
        for (const [j, x] of (f.fields || []).entries()) for (const key of ["name", "id", "label", "placeholder", "autocomplete"]) scan(`snapshot.forms[${i}].fields[${j}].${key}`, x[key]);
    }
    scan("notes", sample.notes);
    scan("source", sample.source);
    return out;
}

function main() {
    const dir = process.argv[2] || fileURLToPath(new URL("../data", import.meta.url));
    const { samples, errors } = loadSamples(dir);
    let findings = 0;
    for (const s of samples) {
        for (const f of findPersonalData(s)) {
            console.log(`${s.id}: ${f}`);
            findings++;
        }
    }
    for (const e of errors) console.log(`load error: ${e}`);
    console.log(`${samples.length} samples checked, ${findings} finding(s), ${errors.length} load error(s)`);
    process.exit(findings || errors.length ? 1 : 0);
}

if (isMain(import.meta.url)) main();
