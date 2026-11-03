// Freezes the admin dashboard's case library into a versioned layer 4 case set (05b K7, X4; src/layer4/cases.js).
// Run LOCALLY by Team AI / Umar, never in Actions, and only after the PM agreed to learn from family decisions:
//
//   node ai/scripts/build-cases.mjs                 (SHOO_ADMIN_URL + CF_ACCESS_* with scope export:read)
//   node ai/scripts/build-cases.mjs --input cases.json
//
// Writes ai/eval/private/cases-<version>.json (gitignored) and prints the next steps (counts and the version only). It writes nothing to KV itself:
// a set goes live only after an eval with it (CASES_FILE on the dev server) and two explicit wrangler commands.
// Kept per case: id, rule ids, label, category. Dropped: domain, admin note, counters, pins, the dashboard's lessons
// (lessons never reach the prompt automatically, X5). The version is the first 8 hex of SHA-256 over the kept cases, so the
// same library always gives the same version.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { isMain } from "../eval/tools/is-main.mjs";
import { parseCases, ACTIVE_KEY } from "../src/layer4/cases.js";
import { dashboardFromEnv, parseJson } from "./dashboard.mjs";

const AI_DIR = fileURLToPath(new URL("..", import.meta.url));
const PRIVATE_DIR = join(AI_DIR, "eval", "private");
const RULE = /^[a-z][a-z0-9_]{1,39}$/;
const CATEGORY = /^[a-z][a-z0-9_]{0,39}$/;
const LABELS = new Set(["scam_strong", "scam_weak", "safe"]);
const MAX_RULES = 20;
const MAX_CASES = 200;

/**
 * @param {{ cases: object[] }} exported body of GET /api/export/cases.json
 * @returns {{ version: string, cases: { id: number, rules: string[], label: string, category: string | null }[] }}
 */
export function buildCaseSet(exported) {
    if (!exported || !Array.isArray(exported.cases)) throw new Error("cases.json has no cases list");
    const cases = [];
    for (const c of exported.cases) {
        const id = Number(c?.id);
        if (!Number.isInteger(id) || id <= 0 || !LABELS.has(c.label)) continue;
        const counts = c.signals && typeof c.signals === "object" ? c.signals : {};
        const rules = Object.entries(counts)
            .filter(([r, n]) => RULE.test(r) && Number(n) > 0)
            .sort(([a, x], [b, y]) => Number(y) - Number(x) || (a < b ? -1 : 1))
            .slice(0, MAX_RULES)
            .map(([r]) => r)
            .sort();
        if (!rules.length) continue; // nothing to compare a page with
        cases.push({ id, rules, label: c.label, category: typeof c.category === "string" && CATEGORY.test(c.category) ? c.category : null });
        if (cases.length >= MAX_CASES) break;
    }
    // Export order is kept (pinned first, newest next): layer 4 shows the model the first MAX_CASES of them.
    const version = createHash("sha256").update(JSON.stringify(cases)).digest("hex").slice(0, 8);
    const set = { version, cases };
    if (!parseCases(set)) throw new Error("built set does not pass parseCases"); // the Worker would refuse it
    return set;
}

async function main(argv) {
    const inputAt = argv.indexOf("--input");
    const exported =
        inputAt === -1 ? await dashboardFromEnv().getJson("/api/export/cases.json") : parseJson(readFileSync(argv[inputAt + 1], "utf8"), "--input");
    const set = buildCaseSet(exported);
    mkdirSync(PRIVATE_DIR, { recursive: true });
    const file = join(PRIVATE_DIR, `cases-${set.version}.json`);
    writeFileSync(file, JSON.stringify(set, null, 2) + "\n");
    const rel = relative(AI_DIR, file); // commands below run from ai/
    console.log(
        [
            `case set ${set.version}: ${set.cases.length} case(s) -> ${rel}`,
            "",
            "Next, in this order (commands run from ai/):",
            `1. Eval with it: CASES_FILE=${rel} npm run dev   then   node eval/run.mjs --analyze-url http://127.0.0.1:8787`,
            "   and once more without CASES_FILE; paste both tables in the PR or issue.",
            `2. Store it:     npx wrangler kv key put --binding CASES_KV "cases:${set.version}" --path ${rel} --remote`,
            `3. Switch to it: npx wrangler kv key put --binding CASES_KV "${ACTIVE_KEY}" "${set.version}" --remote`,
            "   The Worker reads it only while the secret CASES_ENABLED is \"true\"; isolates pick it up within 10 min.",
        ].join("\n"),
    );
}

if (isMain(import.meta.url)) {
    main(process.argv.slice(2)).catch((e) => {
        console.error(`build-cases: ${e.message}`);
        process.exit(1);
    });
}
