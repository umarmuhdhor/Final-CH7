// ADM-09 (shoo-dashboard plan, phase 10a K4/K12): what the old hand-written lists answer for ~1500
// hosts, per reader, so the admin.domain_lists seed can be proven to behave the same. Imports the old
// code itself (Node 24 strips the types of allowlist.ts). Run once, while that code still exists:
//   node backend/db/scripts/domain-lists-golden.mjs
// Writes backend/api/test/fixtures/domain-lists-golden.json (old answers), domain-lists-expected-diff.json
// (cases where the seed answers differently on purpose, each with its K12 category) and
// backend/db/scripts/domain-lists-diff.md (summary for the PR). A difference without a category fails
// the run: fix the seed mapping, not the list. The files are committed and not regenerated later.
//
// Readers (old → new):
//   backend     neverQueue(host)                         → domain_match(host).protected
//   build       isAllowlisted(toRegistrable(host))       → domain_match(toRegistrable(host)).protected
//   official    isOfficialHost(host)                     → domain_match(host).trusted
//   blockMemory memoryKey(url) mode (Safari)             → recorded for phase 10c, not tested here
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { neverQueue } from "../../api/src/data/allowlist.ts";
import { isAllowlisted } from "../../../ai/src/blocklist/build.js";
import { toRegistrable } from "../../../ai/src/blocklist/domains.js";
import { isOfficialHost } from "../../../ai/src/layer3/official.js";
import { memoryKey } from "../../../ios/ShooExtension/Resources/block-memory.js";
import {
  AC4, L1, L1_L2, L2, L4, L4_ONLY, L4_SHARED, L4_SHARED_ONLY, buildSeed, match, protectingRow,
} from "./domain-lists-seed.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(HERE, "../../api/test/fixtures");
// backend/api/src/http/validate.ts:81: what POST /scans accepts as a domain (the backend reader's input).
const DOMAIN = /^(?!www\.)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;

const rows = buildSeed();
const byDomain = new Map(rows.map((r) => [r.domain, r]));

const NEGATIVE = ["bca.co.id.evil.com", "notgoogle.com", "klikbca-login.com", "go-id.com", "example.com", "x.example.com", "id-bca.com"];
const hosts = new Set(NEGATIVE);
for (const d of byDomain.keys()) {
  for (const h of [d, `www.${d}`, `x.${d}`, `a.b.${d}`]) hosts.add(h);
  const labels = d.split(".");
  for (let i = 1; i < labels.length - 1; i++) hosts.add(labels.slice(i).join(".")); // dotted parents (co.id)
}

const memoryMode = (host) => {
  const key = memoryKey(`https://${host}/p`, () => "\u0000registrable");
  if (key === "\u0000registrable") return "registrable";
  return key === host.replace(/^www\./, "") ? "host" : "host_path";
};
const newMemoryMode = (host) => {
  const h = host.replace(/^www\./, "");
  const labels = h.split(".");
  const hostingAt = (i) => byDomain.get(labels.slice(i).join("."))?.hosting ?? "none";
  if (hostingAt(0) !== "none") return "host_path";
  return labels.slice(1).some((_, i) => hostingAt(i + 1) !== "none") ? "host" : "registrable";
};

const under = (set, d) => [...set].some((s) => d === s || d.endsWith(`.${s}`));

/** K12 category of one difference, or null (= the seed is wrong). */
function category(reader, host, d, oldV, newV) {
  if (reader === "official") return null;
  const row = protectingRow(byDomain, d);
  if (reader === "backend") {
    if (!oldV && newV) {
      if (row.src.includes("multi-tenant")) return "g";
      if (row.src.some((s) => ["L1", "L2", "brands", "brands suffix"].includes(s))) return "a";
      return null;
    }
    return under(AC4, d) ? "c" : null;
  }
  // build: d is the registrable domain the old build looked up.
  if (oldV && !newV) return under(L1_L2, d) ? "d" : null;
  if (row.src.includes("multi-tenant")) return "g";
  if (L4_ONLY.has(row.domain)) return "b";
  if (L4_SHARED_ONLY.has(row.domain)) return "e";
  return null;
}

const REASON = {
  a: "backend now protects L1, L2 apex, brands and suffix rows it did not list",
  b: "L4-only domain: protect only (trusted = false) until X10",
  c: "ac.id/sch.id/mil.id/desa.id are apex: names under them can be queued (D-dash-22 #3)",
  d: "L1 ∩ L2 are apex: tenants under them can be published after 10c (D-dash-22 #2)",
  e: "platform apex only the backend listed (shared roots) is now protected in the ai/ build (after 10c)",
  g: "multi-tenant host row is protected as apex (D-dash-22 #7)",
};

const cases = [];
const diffs = [];
const uncategorized = [];
for (const host of [...hosts].sort()) {
  const backendOld = DOMAIN.test(host) ? neverQueue(host) : null;
  const buildDomain = toRegistrable(host);
  const buildOld = buildDomain ? isAllowlisted(buildDomain) : null;
  const officialOld = isOfficialHost(host);
  const memOld = memoryMode(host);
  cases.push({ host, backend: backendOld, build: buildOld, buildDomain, official: officialOld, blockMemory: memOld });

  const checks = [
    ["backend", host, backendOld, backendOld === null ? null : match(byDomain, host).protected],
    ["build", buildDomain, buildOld, buildOld === null ? null : match(byDomain, buildDomain).protected],
    ["official", host, officialOld, match(byDomain, host).trusted],
  ];
  for (const [reader, d, oldV, newV] of checks) {
    if (oldV === null || oldV === newV) continue;
    const cat = category(reader, host, d, oldV, newV);
    const diff = { host, reader, old: oldV, new: newV, category: cat, reason: cat ? REASON[cat] : "UNCATEGORIZED" };
    (cat ? diffs : uncategorized).push(diff);
  }
  const memNew = newMemoryMode(host);
  if (memNew !== memOld) diffs.push({ host, reader: "blockMemory", old: memOld, new: memNew, category: "blockMemory-10c",
    reason: "Safari block-memory key mode differs (L6 is narrower than L2/L4); decided and tested in 10c" });
}

if (uncategorized.length) {
  console.error(`${uncategorized.length} differences without a K12 category (fix the seed):`);
  for (const d of uncategorized.slice(0, 40)) console.error(`  ${d.reader} ${d.host}: ${d.old} -> ${d.new}`);
  process.exit(1);
}

const source = "origin/main ce137f9 (7 Nov 2026)";
writeFileSync(join(FIXTURES, "domain-lists-golden.json"),
  JSON.stringify({ source, readers: ["backend", "build", "official", "blockMemory"], cases }, null, 1) + "\n");
writeFileSync(join(FIXTURES, "domain-lists-expected-diff.json"), JSON.stringify({ source, diffs }, null, 1) + "\n");

const byCat = Object.groupBy(diffs, (d) => `${d.reader} (${d.category})`);
const lines = [
  "# Domain lists: seed vs old lists",
  "",
  `Golden: ${cases.length} hosts from ${source}. Seed: ${rows.length} rows. Differences: ${diffs.length}, all categorized (K12).`,
  "",
  "| Reader (category) | Cases | Reason | Examples |",
  "|---|---|---|---|",
  ...Object.entries(byCat).sort().map(([k, v]) =>
    `| ${k} | ${v.length} | ${v[0].reason} | ${v.slice(0, 6).map((d) => `\`${d.host}\` ${d.old}→${d.new}`).join(", ")} |`),
  "",
  `Old lists: L1 ${L1.size}, L2 ${L2.size}, L4 ${L4.size} + ${L4_SHARED.size} shared roots.`,
];
writeFileSync(join(HERE, "domain-lists-diff.md"), lines.join("\n") + "\n");
console.log(lines.join("\n"));
