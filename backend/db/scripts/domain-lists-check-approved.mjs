// ADM-09 (shoo-dashboard plan, phase 10a LANGKAH MANUAL 0b): which approved blocklist domains the
// admin.domain_lists seed would protect. Reads the committed domain-lists-seed.sql (the migration's seed),
// so it runs without the old lists. Input: one domain per line, e.g. the output of
//   select domain from blocklist_entries where approved_at is not null and removed_at is null;
//   node backend/db/scripts/domain-lists-check-approved.mjs approved.txt
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { match, protectingRow } from "./domain-lists-match.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const sql = readFileSync(join(HERE, "domain-lists-seed.sql"), "utf8");
// Each seed line: ('domain', 'protect', trusted, 'hosting', public_suffix, ...
const rows = [...sql.matchAll(/^  \('([^']+)', '(subtree|apex|none)', (true|false), '(none|subdomains|host_path)'/gm)]
  .map(([, domain, protect, trusted, hosting]) => ({ domain, protect, trusted: trusted === "true", hosting }));
if (rows.length < 200) throw new Error(`only ${rows.length} seed rows parsed`);
const byDomain = new Map(rows.map((r) => [r.domain, r]));

const file = process.argv[2];
if (!file) throw new Error("usage: domain-lists-check-approved.mjs <file with one domain per line>");
const approved = readFileSync(file, "utf8").split(/\s+/).map((s) => s.trim().toLowerCase()).filter(Boolean);
const hit = approved.filter((d) => match(byDomain, d).protected);
console.log(`${hit.length} of ${approved.length} approved domains become protected by the seed:`);
for (const d of hit) console.log(`  ${d}  (row ${protectingRow(byDomain, d).domain})`);
