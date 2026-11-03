// Versioned case library for layer 4 (admin dashboard 05b K7, X4). OFF unless the Worker secret CASES_ENABLED is "true"
// and the CASES_KV binding exists. A snapshot is frozen by ai/scripts/build-cases.mjs as KV key `cases:<sha8>`; the key
// `cases:active` names the one in use, so a new set goes live only after an eval (`run.mjs --analyze-url`) and an
// explicit switch. Pinning or deleting a case in the dashboard never changes layer 4 by itself.
// A snapshot holds rule ids (only ids Shoo emits, src/signal-ids.js), a label and a category per case: no domain, no
// admin note, no page text. Cases reach the model as DATA inside the user message (like page words), never as
// instructions. PROMPT_VERSION does not change; the snapshot's version travels as `casesVersion` (ai_usage blob2).
import { isKnownSignal } from "../signal-ids.js";

export const ACTIVE_KEY = "cases:active";
export const MAX_CASES = 20; // what the model sees; the snapshot may hold more
export const MAX_RULES_FOR_MODEL = 8;
export const MAX_STORED = 200;
export const MAX_RULES = 20;
const VERSION = /^[0-9a-f]{8}$/;
const CATEGORY = /^[a-z][a-z0-9_]{0,39}$/;
const LABELS = new Set(["scam_strong", "scam_weak", "safe"]);
/** The model input never carries new_domain (analyze.js keeps the domain age from the model), so cases do not either. */
const NOT_FOR_MODEL = new Set(["new_domain"]);
/** A loaded set (or a clear "none") is kept this long per isolate. */
export const CASES_TTL_MS = 10 * 60 * 1000;
/** After a KV error the last good set stays in use and KV is asked again after this long. */
export const CASES_RETRY_MS = 30 * 1000;
/** /analyze never waits longer than this for a cold load; the load goes on and fills the cache for later requests. */
export const CASES_WAIT_MS = 300;
const STUCK_MS = 10 * 1000;

/** First 8 hex of SHA-256 over the cases in their canonical shape. build-cases.mjs and the Worker use the same function. */
export async function versionOf(cases) {
    const canonical = JSON.stringify(cases.map((c) => ({ id: c.id, rules: c.rules, label: c.label, category: c.category })));
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical)));
    return [...digest.slice(0, 4)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Checks a snapshot's shape; anything off makes the whole set unusable (null), never half a set. Empty = null. */
export function parseCases(raw) {
    const s = typeof raw === "string" ? safeJson(raw) : raw;
    if (!s || typeof s !== "object" || !VERSION.test(s.version) || !Array.isArray(s.cases) || s.cases.length === 0 || s.cases.length > MAX_STORED) return null;
    const cases = [];
    const ids = new Set();
    for (const c of s.cases) {
        if (!c || typeof c !== "object" || !Number.isInteger(c.id) || c.id <= 0 || ids.has(c.id) || !LABELS.has(c.label)) return null;
        if (!Array.isArray(c.rules) || c.rules.length === 0 || c.rules.length > MAX_RULES || !c.rules.every(isKnownSignal)) return null;
        if (c.category !== null && !(typeof c.category === "string" && CATEGORY.test(c.category))) return null;
        ids.add(c.id);
        cases.push({ id: c.id, rules: [...c.rules], label: c.label, category: c.category });
    }
    return { version: s.version, cases };
}

/** parseCases plus the content hash: a set whose cases do not hash to its version is refused. */
export async function verifyCases(raw) {
    const set = parseCases(raw);
    return set && (await versionOf(set.cases)) === set.version ? set : null;
}

function safeJson(text) {
    try {
        return JSON.parse(text);
    } catch {
        return null;
    }
}

/** What goes into the model input: label folded to scam/safe, at most MAX_CASES cases of MAX_RULES_FOR_MODEL rules. */
export function casesForModel(set) {
    return set.cases
        .map((c) => ({ rules: c.rules.filter((r) => !NOT_FOR_MODEL.has(r)).slice(0, MAX_RULES_FOR_MODEL), label: c.label === "safe" ? "safe" : "scam", category: c.category }))
        .filter((c) => c.rules.length)
        .slice(0, MAX_CASES);
}

/**
 * @param {{ now?: () => number, waitMs?: number }} [deps]
 * @returns {(env: object) => Promise<{ version: string, cases: object[] } | null>} null = no cases (off, missing, broken, slow)
 */
export function createCasesLoader({ now = Date.now, waitMs = CASES_WAIT_MS } = {}) {
    let cached = { until: -Infinity, set: null };
    let inflight = null; // { promise, at }: one KV load at a time, shared by concurrent requests
    async function refresh(kv) {
        try {
            const pointer = await kv.get(ACTIVE_KEY);
            const version = typeof pointer === "string" ? pointer.trim() : "";
            // No pointer, or one that names a missing / broken / mismatched set: a clear "no cases" for the full TTL.
            const set = VERSION.test(version) ? await verifyCases(await kv.get(`cases:${version}`)) : null;
            cached = { until: now() + CASES_TTL_MS, set: set && set.version === version ? set : null };
        } catch {
            cached = { until: now() + CASES_RETRY_MS, set: cached.set }; // KV down: keep the last good set, ask again soon
        }
        return cached.set;
    }
    /** `waitUntil` (the Worker's ctx.waitUntil) keeps a load that outlives this request's answer running. */
    return async function load(env, waitUntil) {
        const kv = env?.CASES_KV;
        if (env?.CASES_ENABLED !== "true" || typeof kv?.get !== "function") return null;
        if (now() < cached.until) return cached.set;
        // A load the runtime dropped with an old request would never settle: after STUCK_MS a new one starts.
        if (!inflight || now() - inflight.at > STUCK_MS) {
            const promise = refresh(kv).finally(() => {
                if (inflight?.promise === promise) inflight = null;
            });
            inflight = { promise, at: now() };
            waitUntil?.(promise);
        }
        let timer;
        const slow = new Promise((resolve) => (timer = setTimeout(() => resolve(cached.set), waitMs)));
        try {
            return await Promise.race([inflight.promise, slow]);
        } finally {
            clearTimeout(timer);
        }
    };
}
