#!/usr/bin/env node
// Re-run layer 3 on saved snapshots. No network.
import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeSnapshot } from "../src/analyze.js";
import { buildNewDomainSignal } from "../src/layer3/signals.js";

const dir = join(dirname(fileURLToPath(import.meta.url)), "snapshots");
const files = (await readdir(dir)).filter((f) => f.endsWith(".json")).sort();

const rows = [];
for (const file of files) {
    const rec = JSON.parse(await readFile(join(dir, file), "utf8"));
    const rules = rec.snapshot ? analyzeSnapshot(rec.snapshot) : [];
    const domain = rec.rdapAgeDays == null ? null : buildNewDomainSignal(rec.rdapAgeDays);
    const all = domain ? [...rules, domain] : rules;
    const scoreRules = Math.min(100, rules.reduce((s, x) => s + x.weight, 0));
    const scoreAll = Math.min(100, all.reduce((s, x) => s + x.weight, 0));
    const sig = all.map((x) => `${x.id}:${x.weight}:${x.evidence ?? "-"}`).join(" ");
    rows.push({
        id: rec.id,
        label: rec.label,
        scoreAll,
        scoreRules,
        sig: sig || "-",
        caught: scoreAll >= 30,
    });
}

const pad = (v, n) => String(v).padEnd(n);
console.log(
    `${pad("id", 6)} ${pad("label", 10)} ${pad("skor L3", 8)} ${pad("tanpa new_domain", 16)} sinyal`,
);
for (const r of rows) {
    console.log(`${pad(r.id, 6)} ${pad(r.label, 10)} ${pad(r.scoreAll, 8)} ${pad(r.scoreRules, 16)} ${r.sig}`);
}
const scam = rows.filter((r) => r.label !== "legit");
const caught = scam.filter((r) => r.caught).length;
console.log(`---`);
console.log(`scam ${caught}/${scam.length} tertangkap (>=30)`);
