import fs from "node:fs";
import { dissect } from "./dissect-lib.mjs";
const base = "/Users/imelda/Documents/Swift/Final-CH/Final-CH7/ai/eval/data/";
const holdout = JSON.parse(fs.readFileSync(base + "HOLDOUT.json", "utf8"));
const rows = [];
for (const k of ["scam", "legit"]) for (const f of fs.readdirSync(base + k).filter((f) => f.endsWith(".json"))) {
  let j = JSON.parse(fs.readFileSync(`${base}${k}/${f}`, "utf8")); j = Array.isArray(j) ? j : [j];
  for (const s of j) { const r = dissect(s.snapshot.url); rows.push({ k, id: s.id, url: s.snapshot.url, synth: !!s.synthetic, hold: (s.tags||[]).includes("holdout"), score: r.score, why: r.parts.map(p=>p.part).join("+") }); }
}
const stat = (k, pred = () => true) => { const r = rows.filter((x) => x.k === k && pred(x)); const c = (t) => r.filter((x) => x.score >= t).length; return `n=${r.length}  >=15: ${c(15)}  >=30: ${c(30)}  >=50: ${c(50)}`; };
console.log("SCAM  all      ", stat("scam"));
console.log("SCAM  real only", stat("scam", (x) => !x.synth));
console.log("LEGIT all      ", stat("legit"));
console.log("LEGIT real only", stat("legit", (x) => !x.synth));
console.log("\nLEGIT with score >= 10:");
for (const x of rows.filter((x) => x.k === "legit" && x.score >= 10).sort((a,b)=>b.score-a.score)) console.log(`  ${String(x.score).padStart(3)} ${x.synth?"S":"R"} ${x.id}  ${x.url.slice(0,80)}  [${x.why}]`);
console.log("\nSCAM with score < 15 (missed by link-only):");
const miss = rows.filter((x) => x.k === "scam" && x.score < 15);
console.log("  count", miss.length); for (const x of miss.slice(0,8)) console.log(`  ${String(x.score).padStart(3)} ${x.id}  ${x.url.slice(0,80)}`);
console.log("\nSCAM score distribution top:"); for (const x of rows.filter(x=>x.k==="scam").sort((a,b)=>b.score-a.score).slice(0,6)) console.log(`  ${x.score} ${x.url.slice(0,80)} [${x.why}]`);
