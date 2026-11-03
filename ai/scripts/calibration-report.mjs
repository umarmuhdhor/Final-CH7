// Weekly calibration report (05b K5, X3): how well each signal id separates the domains families and admins labelled
// scam from the ones they labelled safe. Input: the dashboard's intel export (`GET /api/export/intel.jsonl`, scope
// export:read). Output: Markdown with counts and ratios per signal id ONLY. This repo is public and the report lands in a
// PR, so a domain, URL or note never reaches the output (a test checks it). Weights are never changed here: the report
// is material for Team AI, who change weights by hand with an eval before/after (M6).
//
//   node ai/scripts/calibration-report.mjs [--since YYYY-MM-DD] [--out report.md]     (SHOO_ADMIN_URL + CF_ACCESS_* set)
//   node ai/scripts/calibration-report.mjs --input intel.jsonl [--out report.md]      (an export you already have)
//
// Run by .github/workflows/ai-calibration.yml once vars.AI_CALIBRATION_ENABLED is 'true' (off by default).
import { readFileSync, writeFileSync } from "node:fs";
import { isMain } from "../eval/tools/is-main.mjs";
import { dashboardFromEnv, parseJson } from "./dashboard.mjs";

export const LABELS = Object.freeze({ scam_strong: "scam", scam_weak: "scam", safe: "safe" });
/** Below this many domains in the denominator a ratio is shown as "–": a percent of 3 domains misleads. */
export const MIN_DENOMINATOR = 5;
/** A signal id is listed on its own only if it looks like one of ours and was seen on this many labelled domains. */
export const MIN_DOMAINS_PER_ID = 3;
const ID = /^[a-z][a-z0-9_]{1,39}$/;
const OTHER = "(other)";

/**
 * @param {object[]} rows intel.jsonl rows ({ label, signals: { id: count } , ... }); other fields are ignored
 * @returns {{ scam: number, safe: number, unlabelled: number, signals: { id: string, scam: number, safe: number, precision: number|null, recall: number|null, safeRate: number|null }[] }}
 */
export function calibrate(rows) {
    const totals = { scam: 0, safe: 0, unlabelled: 0 };
    const seen = new Map(); // id -> { scam, safe } domains that had it at least once
    for (const r of rows) {
        const side = Object.hasOwn(LABELS, r?.label) ? LABELS[r.label] : null;
        if (!side) {
            totals.unlabelled += 1;
            continue;
        }
        totals[side] += 1;
        const signals = r.signals && typeof r.signals === "object" ? r.signals : {};
        for (const [id, n] of Object.entries(signals)) {
            if (!(Number(n) > 0)) continue;
            const c = seen.get(id) ?? { scam: 0, safe: 0 };
            c[side] += 1;
            seen.set(id, c);
        }
    }
    // Ids come from scans, i.e. from clients: anything that does not look like ours, or that only a couple of domains
    // carry, is folded into one row so a public report cannot be used to publish a string.
    const merged = new Map();
    for (const [id, c] of seen) {
        const key = ID.test(id) && c.scam + c.safe >= MIN_DOMAINS_PER_ID ? id : OTHER;
        const m = merged.get(key) ?? { scam: 0, safe: 0 };
        m.scam += c.scam;
        m.safe += c.safe;
        merged.set(key, m);
    }
    const ratio = (n, d) => (d >= MIN_DENOMINATOR ? n / d : null);
    const signals = [...merged]
        .map(([id, c]) => ({ id, scam: c.scam, safe: c.safe, precision: ratio(c.scam, c.scam + c.safe), recall: ratio(c.scam, totals.scam), safeRate: ratio(c.safe, totals.safe) }))
        .sort((a, b) => (a.id === OTHER) - (b.id === OTHER) || (a.id < b.id ? -1 : 1));
    return { ...totals, signals };
}

const pct = (v) => (v === null ? "–" : `${Math.round(v * 100)}%`);

/** Markdown; numbers and signal ids only. */
export function renderReport(result, { date, since = null }) {
    const look = result.signals.filter((s) => s.id !== OTHER && s.precision !== null && s.precision < 0.5);
    return [
        `# Calibration report ${date}`,
        "",
        `Labelled domains${since ? ` seen since ${since}` : ""}: ${result.scam} scam (strong + weak), ${result.safe} safe; ${result.unlabelled} without a label were skipped.`,
        `Counts are domains, not scans. Ratios need at least ${MIN_DENOMINATOR} domains, else "–".`,
        "",
        "| Signal | Scam domains | Safe domains | Precision | Recall | Safe domains hit |",
        "|---|---:|---:|---:|---:|---:|",
        ...result.signals.map((s) => `| \`${s.id}\` | ${s.scam} | ${s.safe} | ${pct(s.precision)} | ${pct(s.recall)} | ${pct(s.safeRate)} |`),
        "",
        "Precision = scam / (scam + safe) among domains with the signal. Recall = share of scam domains with it. " +
            "Safe domains hit = share of safe domains with it.",
        "",
        look.length
            ? `To look at (precision under 50%): ${look.map((s) => `\`${s.id}\``).join(", ")}. Weights are not changed automatically: change them by hand with an eval before/after (\`node ai/eval/run.mjs\`).`
            : "No signal with precision under 50%.",
        "",
    ].join("\n");
}

function parseArgs(argv) {
    const args = { since: null, out: null, input: null };
    for (let i = 0; i < argv.length; i += 2) {
        const [flag, v] = [argv[i], argv[i + 1]];
        if (flag === "--since" && /^\d{4}-\d{2}-\d{2}$/.test(v ?? "")) args.since = v;
        else if (flag === "--out" && v) args.out = v;
        else if (flag === "--input" && v) args.input = v;
        else throw new Error(`unknown or incomplete option ${flag}`);
    }
    return args;
}

async function main(argv) {
    const args = parseArgs(argv);
    let rows;
    if (args.input) rows = readFileSync(args.input, "utf8").split("\n").filter((l) => l.trim()).map((l) => parseJson(l, args.input));
    else {
        const dash = dashboardFromEnv();
        rows = [];
        for (const label of Object.keys(LABELS)) rows.push(...(await dash.getJsonl("/api/export/intel.jsonl", { label, ...(args.since ? { since: args.since } : {}) })));
    }
    const report = renderReport(calibrate(rows), { date: new Date().toISOString().slice(0, 10), since: args.since });
    if (args.out) writeFileSync(args.out, report);
    else process.stdout.write(report);
    process.stderr.write(`${rows.length} rows read\n`); // a count only
}

if (isMain(import.meta.url)) {
    main(process.argv.slice(2)).catch((e) => {
        process.stderr.write(`calibration-report: ${e.message}\n`);
        process.exit(1);
    });
}
