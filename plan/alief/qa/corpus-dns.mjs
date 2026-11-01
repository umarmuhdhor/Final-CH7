// Checks which corpus hosts still resolve, so the live test (2b) only opens pages that exist.
//   node plan/alief/qa/corpus-dns.mjs plan/alief/qa/img/figma-parity/corpus-results.json plan/alief/qa/img/figma-parity/corpus-dns.json
import { readFileSync, writeFileSync } from "node:fs";
import { lookup } from "node:dns/promises";
const [resultsFile, out] = process.argv.slice(2);
const rows = JSON.parse(readFileSync(resultsFile, "utf8")).results;
const res = [];
for (const r of rows) {
  const host = new URL(r.url).hostname;
  let resolves = false;
  try { await Promise.race([lookup(host), new Promise((_, j) => setTimeout(() => j(new Error("t")), 5000))]); resolves = true; } catch {}
  res.push({ ...r, host, resolves });
}
writeFileSync(out, JSON.stringify(res, null, 2) + "\n");
console.log(res.filter((x) => x.resolves).length, "resolve:", res.filter((x) => x.resolves && x.label === "scam").map((x) => x.id).join(", "));
