// Owner: lead. GET /verdicts client (EX-06). ES module, used by background.js.
// Rate limit is 30 requests / 10 s per device. A 429 means "ask again later", never "no verdict"
// (backend/API.md): we keep answering from the last known verdict and don't call again until Retry-After.

const TTL_MS = 60 * 1000;
const TIMEOUT_MS = 3 * 1000;
const DEFAULT_RETRY_MS = 10 * 1000; // one rate-limit window
const MAX_RETRY_MS = 5 * 60 * 1000;

/** Retry-After header (seconds, per backend/API.md; HTTP-date also accepted) → ms to wait, clamped. */
export function retryAfterMs(header, now) {
    const raw = String(header ?? "").trim();
    let ms = /^\d+$/.test(raw) ? Number(raw) * 1000 : Date.parse(raw) - now;
    if (!Number.isFinite(ms)) ms = DEFAULT_RETRY_MS;
    return Math.min(MAX_RETRY_MS, Math.max(1000, ms));
}

/**
 * @param {object} deps
 * @param {() => Promise<object|null>} deps.getSession
 * @param {(url, init) => Promise<object>} deps.fetchJSON  throws an error with `status` / `retryAfter` on HTTP errors
 */
export function createVerdicts({ getSession, fetchJSON, now = () => Date.now() }) {
    const cache = new Map(); // domain → { verdict, at }
    let limitedUntil = 0;

    function rateLimited(cached) {
        return { ok: true, verdict: cached?.verdict ?? null, rateLimited: true, retryAfterMs: limitedUntil - now() };
    }

    /** Never rejects. `fresh` skips the cache (block screen polling). */
    async function lookup(domain, { fresh = false } = {}) {
        const cached = cache.get(domain);
        if (!fresh && cached && now() - cached.at < TTL_MS) return { ok: true, verdict: cached.verdict };
        if (now() < limitedUntil) return rateLimited(cached);

        const session = await getSession();
        if (!session?.apiBaseURL) return { ok: true, verdict: null, skipped: "no_api_url" };
        try {
            const url = session.apiBaseURL.replace(/\/+$/, "") + `/verdicts?domain=${encodeURIComponent(domain)}`;
            const body = await fetchJSON(url, { method: "GET", token: session.token, timeoutMs: TIMEOUT_MS });
            const verdict = body?.verdict ?? null;
            cache.set(domain, { verdict, at: now() });
            return { ok: true, verdict };
        } catch (error) {
            if (error?.status === 429) {
                limitedUntil = now() + retryAfterMs(error.retryAfter, now());
                return rateLimited(cached);
            }
            console.warn("[Shoo] /verdicts failed", error);
            return { ok: true, verdict: null, skipped: "error" };
        }
    }

    return { lookup };
}
