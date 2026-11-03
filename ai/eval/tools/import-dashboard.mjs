#!/usr/bin/env node
// For Team AI, run LOCALLY (never in Actions):  node ai/eval/tools/import-dashboard.mjs [--since YYYY-MM-DD]
// Pulls `GET /api/export/eval-samples.json` from the admin dashboard (scam_strong domains backed by enough families, as
// URL-only samples, admin dashboard 05b K6) into ai/eval/private/ (gitignored: real domains never go into this public
// repo, and the folder is outside ai/eval/data/, so the default eval and its tests never read it).
// Needs SHOO_ADMIN_URL, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET (service token, scope export:read) in the env.
//
// Every imported sample has redacted: false, whatever the export says. A person reads the file, then the owner runs
//   node ai/eval/tools/mark-redacted.mjs --dir ai/eval/private --confirm-read --ids …
//   node ai/eval/tools/assign-holdout.mjs --dir ai/eval/private
//   node ai/eval/run.mjs --dir ai/eval/private
// Prints counts only, never a domain.
import { mkdirSync, writeFileSync, readdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { isMain } from "./is-main.mjs";
import { validateSample } from "../lib.mjs";
import { dashboardFromEnv } from "../../scripts/dashboard.mjs";

export const PRIVATE_DIR = fileURLToPath(new URL("../private", import.meta.url));
const ID = /^dash-[0-9a-f]{12}$/;
const TAGS = new Set(["bank", "e-wallet", "prize", "other"]);

/**
 * Keeps only the fields of the export's sample shape, with redacted forced to false. A sample is dropped when it has
 * anything else in it, so a changed export cannot slip page text or a note into the folder.
 * @returns {{ samples: object[], dropped: number }}
 */
export function toSamples(exported, known = new Set()) {
    if (!Array.isArray(exported)) throw new Error("eval-samples.json is not a list");
    const samples = [];
    let dropped = 0;
    for (const s of exported) {
        const url = s?.snapshot?.url;
        const tags = Array.isArray(s?.tags) ? s.tags : [];
        const ok =
            s && typeof s === "object" &&
            ID.test(s.id) && s.label === "scam" &&
            tags.length === 2 && TAGS.has(tags[0]) && tags[1] === "url-only" &&
            typeof s.source === "string" && s.source.length <= 80 &&
            typeof s.collectedAt === "string" && !Number.isNaN(Date.parse(s.collectedAt)) &&
            typeof url === "string" && /^https:\/\/[a-z0-9.-]+\/$/.test(url) &&
            Object.keys(s.snapshot).length === 1;
        if (!ok || known.has(s.id)) {
            dropped += ok ? 0 : 1;
            continue;
        }
        samples.push({ id: s.id, label: "scam", tags: [...tags], synthetic: false, redacted: false, source: s.source, collectedAt: s.collectedAt, snapshot: { url } });
    }
    return { samples, dropped };
}

/** Ids already in the folder, so a second import only adds new domains (and never undoes a sample a person already marked redacted). */
export function knownIds(dir) {
    if (!existsSync(dir)) return new Set();
    const ids = new Set();
    for (const name of readdirSync(dir)) {
        if (!name.endsWith(".json") || name === "HOLDOUT.json") continue;
        const parsed = JSON.parse(readFileSync(join(dir, name), "utf8"));
        for (const s of Array.isArray(parsed) ? parsed : [parsed]) if (typeof s?.id === "string") ids.add(s.id);
    }
    return ids;
}

async function main(argv) {
    const sinceAt = argv.indexOf("--since");
    const since = sinceAt === -1 ? null : argv[sinceAt + 1];
    if (since !== null && !/^\d{4}-\d{2}-\d{2}$/.test(since)) throw new Error("--since needs YYYY-MM-DD");
    const exported = await dashboardFromEnv().getJson(`/api/export/eval-samples.json${since ? `?since=${since}` : ""}`);
    const { samples, dropped } = toSamples(exported, knownIds(PRIVATE_DIR));
    // validateSample refuses a real scam sample until a person marks it redacted, which is the point: run.mjs stops until a person checked
    const pending = samples.filter((s) => validateSample(s).length).length;
    if (samples.length) {
        mkdirSync(PRIVATE_DIR, { recursive: true });
        writeFileSync(join(PRIVATE_DIR, `dashboard-${new Date().toISOString().slice(0, 10)}-${process.pid}.json`), JSON.stringify(samples, null, 2) + "\n");
    }
    console.log(`${samples.length} new sample(s) in ai/eval/private/ (${pending} wait for a person to check them), ${dropped} dropped (unexpected shape)`);
}

if (isMain(import.meta.url)) {
    main(process.argv.slice(2)).catch((e) => {
        console.error(`import-dashboard: ${e.message}`);
        process.exit(1);
    });
}
