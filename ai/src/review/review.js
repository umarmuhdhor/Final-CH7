// POST /review (layer 5, D-imelda-52/53): suggests approve / reject for queued blocklist domains from counts only.
// Stateless: it reads no database. The dashboard cron sends admin.review_due() rows and stores the answer.
// Contract: Alief's proposal in #241. The model only labels (result, confidence, reason). The suggestion is computed
// here from result + confidence, so a domain name or a model that says "approve" cannot decide anything.
// Nothing in this module logs: not the request, not the answer, not the secret.
import { HttpError } from "../http.js";
import { createProvider } from "../layer4/provider.js";
import { SHARED_HOSTS } from "../blocklist/allowlist.js";
import { USER_CONTENT } from "../layer3/official.js";
import { REVIEW_PROMPT_VERSION, buildReviewMessages } from "../../prompts/review.js";

export const MAX_DOMAINS = 25;
export const DEFAULT_DAILY_CAP = 20; // requests per UTC day per isolate; each one costs one LLM call (a few retries at most)
const ATTEMPTS = 3;
const ATTEMPT_TIMEOUT_MS = 15_000;
const MAX_TOKENS = 2000; // 25 answers of about 60 tokens
const SUGGEST_MIN_CONFIDENCE = 0.7;
const MAX_REASON = 500;

const DOMAIN_RE = /^[a-z0-9.-]{1,253}$/;
const SIGNAL_KEY_RE = /^[a-z_]{1,40}$/;
const RESULTS = new Set(["scam", "legit", "unsure"]);
const SHARED = [...new Set([...SHARED_HOSTS, ...USER_CONTENT])];

const isInt = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;
const isShared = (domain) => SHARED.some((h) => domain === h || domain.endsWith(`.${h}`));

/**
 * @param {unknown} body
 * @returns {{ domains: object[] } | { error: string }} domains are rebuilt from the six known fields: anything else is dropped
 */
export function validateReviewRequest(body) {
    if (!body || typeof body !== "object" || Array.isArray(body) || !Array.isArray(body.domains)) return { error: "domains must be an array." };
    if (body.domains.length < 1 || body.domains.length > MAX_DOMAINS) return { error: `domains must hold 1 to ${MAX_DOMAINS} items.` };
    const domains = [];
    for (const d of body.domains) {
        if (!d || typeof d !== "object" || Array.isArray(d)) return { error: "each domain must be an object." };
        if (typeof d.domain !== "string" || !DOMAIN_RE.test(d.domain) || d.domain.startsWith("www.")) return { error: "invalid domain." };
        const counts = d.signal_counts;
        if (!counts || typeof counts !== "object" || Array.isArray(counts)) return { error: "signal_counts must be an object." };
        const entries = Object.entries(counts);
        if (entries.length > 30) return { error: "signal_counts has too many keys." };
        for (const [k, v] of entries) if (!SIGNAL_KEY_RE.test(k) || !isInt(v, 0, 1_000_000)) return { error: "invalid signal_counts." };
        for (const k of ["avg_score", "max_score"]) if (d[k] !== null && !isInt(d[k], 0, 100)) return { error: `invalid ${k}.` };
        for (const k of ["families_safe", "families_not_safe"]) if (!isInt(d[k], 0, 10_000)) return { error: `invalid ${k}.` };
        domains.push({
            domain: d.domain,
            signal_counts: Object.fromEntries(entries), // fromEntries: an own "__proto__" key stays data
            avg_score: d.avg_score,
            max_score: d.max_score,
            families_safe: d.families_safe,
            families_not_safe: d.families_not_safe,
        });
    }
    return { domains };
}

/** scam and sure enough -> approve, legit and sure enough -> reject, anything else -> none. */
export function suggestionFor(result, confidence) {
    if (typeof confidence !== "number" || !(confidence >= SUGGEST_MIN_CONFIDENCE)) return "none";
    if (result === "scam") return "approve";
    if (result === "legit") return "reject";
    return "none";
}

async function sha256(text) {
    return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

/** Compares the Bearer token with the secret over two SHA-256 digests (fixed length), so timing says nothing about either. */
export async function bearerMatches(header, secret) {
    const given = /^Bearer (.*)$/i.exec(header ?? "")?.[1] ?? "";
    const [a, b] = await Promise.all([sha256(given), sha256(secret)]);
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff === 0;
}

const failed = (index) => ({ index, result: null, confidence: null, reason: null, suggestion: "none" });
const sharedAnswer = (index) => ({ index, result: "unsure", confidence: null, reason: "shared_host", suggestion: "none" });

function cleanReason(reason) {
    if (typeof reason !== "string") return null;
    return reason.replace(/[<>]/g, "").slice(0, MAX_REASON).trim() || null;
}

/** One model answer -> one result. Model output is untrusted: unknown values become null, the suggestion is recomputed. */
function toResult(index, a) {
    const result = RESULTS.has(a?.result) ? a.result : null;
    if (!result) return failed(index);
    const confidence = typeof a.confidence === "number" && a.confidence >= 0 && a.confidence <= 1 ? Math.round(a.confidence * 100) / 100 : null;
    return { index, result, confidence, reason: cleanReason(a.reason), suggestion: suggestionFor(result, confidence) };
}

/**
 * @param {{ config: object, fetch: typeof fetch, now?: () => number, dailyCap?: number }} deps config is layer4/config.js readConfig()
 */
export function createReviewer({ config, fetch, now = Date.now, dailyCap = DEFAULT_DAILY_CAP }) {
    const provider = createProvider({ config, fetch });
    let day = "";
    let used = 0;

    /** The model's results array, or null after ATTEMPTS failed attempts (http error, timeout, not JSON, wrong shape). */
    async function askModel(items) {
        const messages = buildReviewMessages(items);
        for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), ATTEMPT_TIMEOUT_MS);
            try {
                const r = await provider(messages, controller.signal, { maxTokens: MAX_TOKENS });
                if (!r.ok) continue;
                let parsed;
                try {
                    parsed = JSON.parse(r.content);
                } catch {
                    continue;
                }
                if (Array.isArray(parsed?.results)) return parsed.results;
            } finally {
                clearTimeout(timer);
            }
        }
        return null;
    }

    return {
        /** @param {object[]} domains from validateReviewRequest */
        async review(domains) {
            const results = domains.map((_, i) => failed(i));
            const asked = []; // positions in `domains` that go to the model
            domains.forEach((d, i) => {
                if (isShared(d.domain)) results[i] = sharedAnswer(i);
                else asked.push(i);
            });
            if (asked.length) {
                const today = new Date(now()).toISOString().slice(0, 10);
                if (today !== day) {
                    day = today;
                    used = 0;
                }
                if (used >= dailyCap) throw new HttpError(429, "rate_limited", "Daily review limit reached.");
                used++;
                const answers = await askModel(asked.map((pos, k) => ({ index: k, ...domains[pos] })));
                if (answers) {
                    // An index answered twice is ambiguous: both answers are dropped. Out-of-range or missing ones are ignored.
                    const byIndex = new Map();
                    for (const a of answers) {
                        if (a && typeof a === "object" && isInt(a.index, 0, asked.length - 1)) byIndex.set(a.index, byIndex.has(a.index) ? null : a);
                    }
                    asked.forEach((pos, k) => {
                        results[pos] = toResult(pos, byIndex.get(k));
                    });
                }
            }
            return { model: config.model, prompt: REVIEW_PROMPT_VERSION, results };
        },
    };
}
