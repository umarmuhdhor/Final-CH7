#!/usr/bin/env node
// Redaction checker: node ai/eval/tools/check-redaction.mjs [dir]   (default: ai/eval/data)
// Exits 1 when any sample still holds an e-mail, an Indonesian phone number, a 13-19 digit number (NIK, card, account),
// a token/key, or a URL with a query value other than REDACTED (or a fragment). Pure check: reads files, writes nothing.
import { fileURLToPath } from "node:url";
import { loadSamples } from "../lib.mjs";

const RULES = [
    ["email", /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i],
    ["phone", /(?<![\d+])\+?(?:62|0)[\s.-]?8[\d\s.-]{7,13}\d(?!\d)/],
    ["long number", /(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)/],
    ["secret (sk-)", /\bsk-[A-Za-z0-9_-]{16,}/],
    ["secret (AKIA)", /\bAKIA[0-9A-Z]{16}\b/],
    ["secret (JWT)", /\beyJ[\w-]+\.eyJ[\w-]+\.[\w-]+/],
    ["secret (token)", /\b(?:ghp|gho|xox[abp]|AIza)[\w-]{16,}/],
];

function urlProblem(raw) {
    try {
        const u = new URL(raw);
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
        for (const [name, re] of RULES) if (re.test(value)) out.push(`${where}: ${name}`);
    };
    const snap = sample.snapshot || {};
    for (const [where, url] of [["snapshot.url", snap.url], ...(sample.meta?.iframes || []).map((u, i) => [`meta.iframes[${i}]`, u])]) {
        if (typeof url !== "string") continue;
        if (!url.startsWith("http")) continue; // relative iframe src: only scan it as text
        const p = urlProblem(url);
        if (p) out.push(`${where} (url): ${p}`);
        scan(where, url.replace(/REDACTED/g, ""));
    }
    for (const [i, u] of (sample.meta?.iframes || []).entries()) if (!String(u).startsWith("http")) scan(`meta.iframes[${i}]`, u);
    scan("snapshot.title", snap.title);
    scan("snapshot.text", snap.text);
    for (const [i, a] of (snap.imageAlts || []).entries()) scan(`snapshot.imageAlts[${i}]`, a);
    for (const [i, f] of (snap.forms || []).entries()) {
        scan(`snapshot.forms[${i}].action`, f.action);
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

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
