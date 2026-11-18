// Parity: Shoo's JS port of model v2 (Final-CH7-l3model/ai/src/layer3/model/impersonation.js) vs sklearn, on the 100 rows
// that export_js.py wrote to out/impersonation-v2/parity-fixture.json (page text: stays in this lab, never in Shoo's repo).
// The rows' own feats and rule ids are fed in, so this checks tokenizers, TF-IDF, logistic regression, trees and the
// language rule. The feats themselves are computed by the same JS as build-rows.mjs.
// Usage: node parity_js.mjs [path to ai/src/layer3/model/impersonation.js]
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const mod = resolve(process.argv[2] ?? new URL("../Final-CH7-l3model/ai/src/layer3/model/impersonation.js", import.meta.url).pathname);
const { modelScores, isIndonesian } = await import(pathToFileURL(mod).href);
const rows = JSON.parse(readFileSync(new URL("./out/impersonation-v2/parity-fixture.json", import.meta.url), "utf8"));

let worst = { words: 0, address: 0, final: 0 };
let langDiff = 0;
const flips = [];
for (const r of rows) {
    const row = { host: r.host, url: r.url, title: r.title, text: r.text, feats: r.feats };
    const s = modelScores(row, r.signals);
    for (const k of ["words", "address", "final"]) worst[k] = Math.max(worst[k], Math.abs(s[k] - r[k]));
    if (isIndonesian(row) !== r.indonesian) langDiff++;
    if (Math.abs(s.final - r.final) > 0.01) flips.push({ host: r.host.replace(/\./g, "[.]"), py: r.final.toFixed(4), js: s.final.toFixed(4) });
}
console.log(`rows ${rows.length} | max |diff| words ${worst.words.toFixed(5)} address ${worst.address.toFixed(5)} final ${worst.final.toFixed(5)} | language differs ${langDiff}`);
if (flips.length) console.log("final differs by more than 0.01:", flips);
process.exitCode = worst.final > 0.05 || langDiff ? 1 : 0;
