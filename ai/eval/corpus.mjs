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

/** @returns {string[]} problems; empty = the corpus is complete */
export function validateCorpus(samples, { seed, minPerClass = MIN_PER_CLASS, minPerTag = {} } = {}) {
    const bad = [];
    for (const label of ["scam", "legit"]) {
        const n = samples.filter((s) => s.label === label).length;
        if (n < minPerClass) bad.push(`${label}: ${n} samples, need ${minPerClass}`);
    }
    for (const [tag, min] of Object.entries(minPerTag)) {
        const n = samples.filter((s) => (s.tags || []).includes(tag)).length;
        if (n < min) bad.push(`tag ${tag}: ${n} samples, need ${min}`);
    }
    for (const s of samples) {
        const add = (m) => bad.push(`${s.id}: ${m}`);
        for (const p of validateSample(s)) add(p);
        if (!s.collectedAt || Number.isNaN(Date.parse(s.collectedAt))) add("collectedAt must be an ISO date");
        if (s.synthetic !== true && s.redacted !== true) add("real sample must set redacted: true after a manual read");
        for (const p of findPersonalData(s)) add(`personal data left (${p})`);
        if (seed !== undefined) {
            const want = holdoutOf(s.id, seed);
            const has = (s.tags || []).includes(HOLDOUT_TAG);
            if (want !== has) add(`holdout tag ${has ? "present" : "missing"} but the seed says ${want ? "holdout" : "tuning"} (run tools/assign-holdout.mjs)`);
        }
    }
    return bad;
}

/** Minimum samples per category tag (docs: plan/imelda D-imelda-20). A sample carries exactly one category tag. */
export const COMPOSITION = {
    bank: 10, "e-wallet": 8, courier: 8, prize: 8, government: 8, apple: 4, other: 4, // scam: 50
    "bank-login": 8, checkout: 12, "official-gov": 8, popular: 10, "lookalike-trap": 12, // legit: 50
};
