// ADM-09 (shoo-dashboard plan, phase 10a K3): the admin.domain_lists seed, built from the hand-written
// lists it replaces. Run while the old lists still exist; the SQL it writes is pasted into the migration
// and committed. It is not re-run after phase 10a/10c delete those lists.
//   L1 ai/src/blocklist/allowlist.js POPULAR       L2 same file, SHARED_HOSTS
//   L3 ai/src/layer3/official.js USER_CONTENT + USER_SUBDOMAINS
//   L4 backend/api/src/data/allowlist.ts ALLOWLIST + SHARED_ROOTS      brands detector/data/brands.json
//
//   node backend/db/scripts/domain-lists-seed.mjs                         writes domain-lists-seed.sql
//   node backend/db/scripts/domain-lists-seed.mjs --check-approved <file> approved domains (one per line)
//                                                                         the seed would protect (LM 0b)
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "../../..");
const read = (p) => readFileSync(join(ROOT, p), "utf8");

/** String literals of `const <name> = new Set([...])` or `const <name> = [...]` in a source file. */
function literalList(src, name, expected) {
  const start = src.search(new RegExp(`const ${name} = (new Set\\()?\\[`));
  if (start < 0) throw new Error(`${name} not found`);
  const body = src.slice(start, src.indexOf("]", start));
  const items = [...body.matchAll(/"([^"]+)"/g)].map((m) => m[1].toLowerCase());
  if (items.length !== expected) throw new Error(`${name}: ${items.length} entries, expected ${expected}`);
  return items;
}

const aiAllow = read("ai/src/blocklist/allowlist.js");
const official = read("ai/src/layer3/official.js");
const backend = read("backend/api/src/data/allowlist.ts");
const brands = JSON.parse(read("detector/data/brands.json"));

export const L1 = new Set(literalList(aiAllow, "POPULAR", 122));
export const L2 = new Set(literalList(aiAllow, "SHARED_HOSTS", 72));
export const L3 = new Set(literalList(official, "USER_CONTENT", 20));
const L3_SUBDOMAINS = literalList(official, "USER_SUBDOMAINS", 1);
export const L4 = new Set(literalList(backend, "ALLOWLIST", 98));
export const L4_SHARED = new Set(literalList(backend, "SHARED_ROOTS", 61));
const BRAND_OF = new Map(brands.brands.flatMap((b) => b.domains.map((d) => [d.toLowerCase(), b.id])));
const BRAND_SUFFIXES = new Set(brands.suffixes);

// K3 rows that are named, not derived.
export const AC4 = new Set(["ac.id", "sch.id", "mil.id", "desa.id"]);                               // D-dash-22 #3
const L1_NOT_TRUSTED = new Set(["go.id", "tokopedia.link"]);                                  // suffix, shortener
const L2_L3_APEX = new Set(["firebaseapp.com", "web.app", "sharepoint.com"]);
const L2_L3_UNDER_OFFICIAL = new Set(["docs.google.com", "drive.google.com", "sites.google.com"]);
const MULTI_TENANT = new Set(["storage.googleapis.com", "firebasestorage.googleapis.com", "1drv.ms", "cloud.microsoft"]); // D-dash-22 #7
// Country second-level suffixes in SHARED_ROOTS (co.id, com.au, ...): public suffixes, not platforms.
const SECOND_LEVEL = new Set(["co", "com", "or", "web", "my", "biz", "net", "ponpes", "in", "org", "ac", "go", "sch", "mil", "desa"]);
const isCountrySuffix = (d) => { const l = d.split("."); return l.length === 2 && l[1].length === 2 && SECOND_LEVEL.has(l[0]); };

export const L1_L2 = new Set([...L1].filter((d) => L2.has(d)));
export const L4_ONLY = new Set([...L4].filter((d) => !L1.has(d) && !BRAND_OF.has(d) && !AC4.has(d)));
export const L4_SHARED_ONLY = new Set([...L4_SHARED].filter((d) => !L2.has(d) && !isCountrySuffix(d)));
const PUBLIC_SUFFIX = new Set([...BRAND_SUFFIXES, ...[...L4_SHARED].filter(isCountrySuffix), "go.id", ...AC4]);

function check(cond, msg) {
  if (!cond) throw new Error(msg);
}
check(L4_ONLY.size === 18, `L4-only: ${L4_ONLY.size}, expected 18`);
check([...L1_L2].sort().join() === "amazonaws.com,googleapis.com,googleusercontent.com,gstatic.com", "L1 ∩ L2 changed");
check([...L2].filter((d) => L3.has(d)).sort().join() === [...L2_L3_APEX, ...L2_L3_UNDER_OFFICIAL].sort().join(), "L2 ∩ L3 changed");
check(L3_SUBDOMAINS.join() === "medium.com", "USER_SUBDOMAINS changed");

/** K3: one row per domain, highest rule first. `src` names the old lists, for the note and K12. */
function classify(d) {
  const src = [
    BRAND_OF.has(d) && "brands", L1.has(d) && "L1", L2.has(d) && "L2", L3.has(d) && "L3",
    L4.has(d) && "L4", L4_SHARED.has(d) && "L4 shared", BRAND_SUFFIXES.has(d) && "brands suffix",
    MULTI_TENANT.has(d) && "multi-tenant",
  ].filter(Boolean);
  const row = (protect, trusted, hosting, extra = {}) => ({
    domain: d, protect, trusted, hosting, public_suffix: PUBLIC_SUFFIX.has(d), brand_id: BRAND_OF.get(d) ?? null,
    hard_locked: false, src, ...extra,
  });
  if (MULTI_TENANT.has(d)) return row("apex", false, "host_path");
  if (d === "medium.com") return row("subtree", true, "subdomains");
  if (BRAND_OF.has(d)) return row("subtree", true, "none", { hard_locked: true });
  if (L1_L2.has(d)) return row("apex", false, "subdomains");
  if (L2_L3_APEX.has(d)) return row("apex", false, "subdomains");
  if (L2_L3_UNDER_OFFICIAL.has(d)) return row("none", false, "host_path");
  if (L1_NOT_TRUSTED.has(d)) return row("subtree", false, "none");
  if (L1.has(d)) return row("subtree", true, "none");
  if (AC4.has(d)) return row("apex", false, "none");
  if (L4_ONLY.has(d)) return row("subtree", false, "none", { hard_locked: true });
  if (L2.has(d) || L4_SHARED_ONLY.has(d)) return row("apex", false, "subdomains");
  if (PUBLIC_SUFFIX.has(d)) return row("apex", false, "none");
  if (L3.has(d)) return row("none", false, "host_path");
  throw new Error(`no K3 rule for ${d}`);
}

const parents = (host) => host.split(".").map((_, i, l) => l.slice(i).join(".")); // host first, then each parent

/** Same rules as the table checks and admin.domain_set (K1, K6, D-dash-24). */
export function validate(rows) {
  const byDomain = new Map(rows.map((r) => [r.domain, r]));
  for (const r of rows) {
    check(!(r.hosting === "host_path" && r.trusted), `${r.domain}: host_path cannot be trusted`);
    check(!(r.public_suffix && r.trusted), `${r.domain}: public suffix cannot be trusted`);
    check(r.protect !== "none" || r.trusted || r.hosting !== "none", `${r.domain}: empty row`);
    if (r.hosting !== "none" && r.protect === "none") {
      const up = parents(r.domain).slice(1).map((p) => byDomain.get(p)).filter(Boolean);
      check(up.some((p) => p.protect === "subtree" || (p.protect !== "none" && p.hosting === "host_path")),
        `${r.domain}: hosting row without protect needs a subtree or multi-tenant parent`);
    }
  }
}

export function buildSeed() {
  const all = new Set([...L1, ...L2, ...L3, ...L4, ...L4_SHARED, ...BRAND_OF.keys(), ...BRAND_SUFFIXES, ...MULTI_TENANT]);
  const rows = [...all].sort().map(classify);
  validate(rows);
  return rows;
}

/** K2 in JS, the reference admin.domain_match is tested against (golden). */
export function match(byDomain, host) {
  const chain = parents(host).map((d, depth) => ({ depth, r: byDomain.get(d) })).filter((x) => x.r);
  const isProtected = chain.some(({ depth, r }) => r.protect === "subtree" || (r.protect === "apex" && depth === 0));
  const isWww = (depth) => depth === 1 && host.startsWith("www.");
  let trusted;
  if (chain.some(({ r }) => r.hosting === "host_path")) trusted = false;
  else if (chain.some(({ depth, r }) => r.hosting === "subdomains" && depth > 0 && !isWww(depth))) trusted = false;
  else trusted = chain.some(({ r }) => r.trusted);
  const hosting = chain.find(({ r }) => r.hosting !== "none")?.r.hosting ?? "none";
  return { protected: isProtected, trusted, hosting };
}

/** The row that makes `host` protected (nearest first), for K12 labels. */
export function protectingRow(byDomain, host) {
  return parents(host).map((d, depth) => ({ depth, r: byDomain.get(d) }))
    .find(({ depth, r }) => r && (r.protect === "subtree" || (r.protect === "apex" && depth === 0)))?.r ?? null;
}

const sqlText = (s) => (s === null ? "null" : `'${s.replaceAll("'", "''")}'`);

export function seedSql(rows) {
  const values = rows.map((r) =>
    `  (${sqlText(r.domain)}, ${sqlText(r.protect)}, ${r.trusted}, ${sqlText(r.hosting)}, ${r.public_suffix}, ` +
    `${sqlText(r.brand_id)}, true, ${r.hard_locked}, ${sqlText(`seed: ${r.src.join(", ")}`)}, 'seed')`);
  return `-- Generated by backend/db/scripts/domain-lists-seed.mjs (${rows.length} rows). Do not edit by hand.\n` +
    "insert into admin.domain_lists (domain, protect, trusted, hosting, public_suffix, brand_id, locked, hard_locked, note, updated_by) values\n" +
    values.join(",\n") + ";\n";
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const rows = buildSeed();
  const i = process.argv.indexOf("--check-approved");
  if (i > 0) {
    const byDomain = new Map(rows.map((r) => [r.domain, r]));
    const approved = readFileSync(process.argv[i + 1], "utf8").split(/\s+/).map((s) => s.trim().toLowerCase()).filter(Boolean);
    const hit = approved.filter((d) => match(byDomain, d).protected);
    console.log(`${hit.length} of ${approved.length} approved domains become protected:`);
    for (const d of hit) console.log(`  ${d}  (row ${protectingRow(byDomain, d).domain})`);
  } else {
    writeFileSync(join(HERE, "domain-lists-seed.sql"), seedSql(rows));
    const count = (f) => rows.filter(f).length;
    console.log(`${rows.length} rows: subtree ${count((r) => r.protect === "subtree")}, apex ${count((r) => r.protect === "apex")}, ` +
      `trusted ${count((r) => r.trusted)}, hosting ${count((r) => r.hosting !== "none")}, public_suffix ${count((r) => r.public_suffix)}, ` +
      `hard_locked ${count((r) => r.hard_locked)}`);
  }
}
