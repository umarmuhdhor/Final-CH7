// Versioned case library for layer 4 (admin dashboard 05b K7, X4). OFF unless the Worker secret CASES_ENABLED is "true"
// and the CASES_KV binding exists. A snapshot is frozen by ai/scripts/build-cases.mjs as KV key `cases:<sha8>`; the key
// `cases:active` names the one in use, so a new set goes live only after an eval (`run.mjs --analyze-url`) and an
// explicit switch. Pinning or deleting a case in the dashboard never changes layer 4 by itself.
// A snapshot holds rule ids, a label and a category per case: no domain, no admin note, no page text. Cases reach the
// model as DATA inside the user message (like page words), never as instructions. PROMPT_VERSION does not change;
// the snapshot's version travels as `casesVersion` (stats(), ai_usage blob2).

export const ACTIVE_KEY = "cases:active";
export const MAX_CASES = 20; // what the model sees; the snapshot may hold more
const MAX_STORED = 200;
const VERSION = /^[0-9a-f]{8}$/;
const RULE = /^[a-z][a-z0-9_]{1,39}$/;
const CATEGORY = /^[a-z][a-z0-9_]{0,39}$/;
const LABELS = new Set(["scam_strong", "scam_weak", "safe"]);
/** A loaded set is kept this long per isolate, so a request costs a KV read at most once per window. */
export const CASES_TTL_MS = 10 * 60 * 1000;

/** Checks a snapshot; anything off makes the whole set unusable (null), never half a set. */
export function parseCases(raw) {
    const s = typeof raw === "string" ? safeJson(raw) : raw;
    if (!s || typeof s !== "object" || !VERSION.test(s.version) || !Array.isArray(s.cases) || s.cases.length > MAX_STORED) return null;
    const cases = [];
    for (const c of s.cases) {
        if (!c || typeof c !== "object" || !Number.isInteger(c.id) || c.id <= 0 || !LABELS.has(c.label)) return null;
        if (!Array.isArray(c.rules) || c.rules.length > 20 || !c.rules.every((r) => typeof r === "string" && RULE.test(r))) return null;
        if (c.category !== null && !(typeof c.category === "string" && CATEGORY.test(c.category))) return null;
        cases.push({ id: c.id, rules: [...c.rules], label: c.label, category: c.category });
    }
    return { version: s.version, cases };
}

function safeJson(text) {
    try {
        return JSON.parse(text);
    } catch {
        return null;
    }
}

/** What goes into the model input: label folded to scam/safe, at most MAX_CASES. */
export function casesForModel(set) {
    return set.cases.slice(0, MAX_CASES).map((c) => ({ rules: c.rules, label: c.label === "safe" ? "safe" : "scam", category: c.category }));
}

/**
 * @param {{ now?: () => number }} [deps]
 * @returns {(env: object) => Promise<{ version: string, cases: object[] } | null>} null = no cases (off, missing, broken)
 */
export function createCasesLoader({ now = Date.now } = {}) {
    let cached = { at: -Infinity, set: null };
    let inflight = null;
    return async function load(env) {
        const kv = env?.CASES_KV;
        if (env?.CASES_ENABLED !== "true" || typeof kv?.get !== "function") return null;
        if (now() - cached.at < CASES_TTL_MS) return cached.set;
        inflight ??= (async () => {
            let set = null;
            try {
                const version = await kv.get(ACTIVE_KEY);
                if (typeof version === "string" && VERSION.test(version.trim())) {
                    set = parseCases(await kv.get(`cases:${version.trim()}`));
                    if (set && set.version !== version.trim()) set = null; // the key and the content must agree
                }
            } catch {
                set = null; // KV down: no cases, layer 4 runs as without them
            }
            cached = { at: now(), set };
            return set;
        })().finally(() => (inflight = null));
        return inflight;
    };
}
