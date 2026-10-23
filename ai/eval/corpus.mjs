// Corpus rules for the M2 set (phase 04): size, required fields, redaction, and the seeded holdout split.
import { createHash } from "node:crypto";
import { validateSample, MIN_PER_CLASS } from "./lib.mjs";
import { findPersonalData } from "./tools/check-redaction.mjs";

export const HOLDOUT_FRACTION = 0.3;
export const HOLDOUT_TAG = "holdout";

/** Stable per id and seed: adding samples never moves an old one in or out of the holdout. */
export function holdoutOf(id, seed, fraction = HOLDOUT_FRACTION) {
    const h = createHash("sha256").update(`${seed}:${id}`).digest();
    return h.readUInt32BE(0) / 2 ** 32 < fraction;
}

/**
 * @param {object} opts
 *   seed: holdout seed; composition: {scam: {tag: min}, legit: {tag: min}} counted inside each class, and every sample
 *   must carry exactly one of those category tags; minRealShare: {legit: 0.6} minimum share of non-synthetic samples.
 * @returns {string[]} problems; empty = the corpus is complete
 */
export function validateCorpus(samples, { seed, minPerClass = MIN_PER_CLASS, composition = null, minRealShare = {} } = {}) {
    const bad = [];
    for (const label of ["scam", "legit"]) {
        const inClass = samples.filter((s) => s.label === label);
        if (inClass.length < minPerClass) bad.push(`${label}: ${inClass.length} samples, need ${minPerClass}`);
        const share = minRealShare[label];
        if (share !== undefined && inClass.length) {
            const real = inClass.filter((s) => s.synthetic !== true).length;
            if (real / inClass.length < share) bad.push(`${label}: ${real}/${inClass.length} real samples, need ${Math.round(share * 100)}% real`);
        }
        for (const [tag, min] of Object.entries(composition?.[label] || {})) {
            const n = inClass.filter((s) => (s.tags || []).includes(tag)).length;
            if (n < min) bad.push(`${label} tag ${tag}: ${n} samples, need ${min}`);
        }
    }
    const categories = new Set(Object.values(composition || {}).flatMap((o) => Object.keys(o)));
    for (const s of samples) {
        const add = (m) => bad.push(`${s.id}: ${m}`);
        for (const p of validateSample(s)) add(p);
        if (!s.collectedAt || Number.isNaN(Date.parse(s.collectedAt))) add("collectedAt must be an ISO date");
        if (s.synthetic !== true && s.redacted !== true) add("real sample must set redacted: true after a manual read");
        for (const p of findPersonalData(s)) add(`personal data left (${p})`);
        if (composition) {
            const own = Object.keys(composition[s.label] || {});
            const mine = (s.tags || []).filter((t) => categories.has(t));
            if (mine.length !== 1 || !own.includes(mine[0])) add(`needs exactly one ${s.label} category tag (${own.join(", ")}), has: ${mine.join(", ") || "none"}`);
        }
        if (seed !== undefined) {
            const want = holdoutOf(s.id, seed);
            const has = (s.tags || []).includes(HOLDOUT_TAG);
            if (want !== has) add(`holdout tag ${has ? "present" : "missing"} but the seed says ${want ? "holdout" : "tuning"} (run tools/assign-holdout.mjs)`);
        }
    }
    return bad;
}

/** Minimum samples per category tag, inside each class (plan/imelda D-imelda-20). A sample carries exactly one category tag. */
export const COMPOSITION = {
    scam: { bank: 10, "e-wallet": 8, courier: 8, prize: 8, government: 8, apple: 4, other: 4 }, // 50
    legit: { "bank-login": 8, checkout: 11, "official-gov": 8, popular: 10, "lookalike-trap": 12 }, // 49; checkout back to 12 once real checkout pages land (README "Known limits")
};
