// POST /analyze and GET /public-blocklist (contracts/api.md). Stateless: nothing from a request is stored or logged.
// The only cache is RDAP domain ages (domain + registration date, TTL in rdap/cache.js).
// Authorization is accepted but never read: the AI service cannot verify device tokens in the MVP.
import { Hono } from "hono";
import { LIMITS } from "./limits.js";
import { HttpError, errorResponse, readTextLimited } from "./http.js";
import { validateRequest } from "./validate.js";
import { analyze } from "./analyze.js";
import { createMemoryCache } from "./rdap/cache.js";
import { createRdapClient } from "./rdap/rdap.js";
import { emptySource } from "./blocklist/source.js";
import { createBlocklist } from "./blocklist/route.js";
import { readConfig } from "./layer4/config.js";
import { createRealityCheck, CLIENT_CALLS_PER_HOUR } from "./layer4/reality.js";
import { clientKey, createRateLimiter } from "./ratelimit.js";

/** Per-IP limit for /analyze. Phones behind one carrier IP share it, so it is generous; over the limit the extension just keeps layers 1-2. */
export const ANALYZE_RATE = Object.freeze({ limit: 300, windowMs: 10 * 60 * 1000 });
/** A GET to /public-blocklist has no body; anything that declares more than this is refused. */
const MAX_GET_BODY_BYTES = 1024;

// Same on every answer, including errors and preflights. The API returns JSON only: nothing here is ever rendered.
const SECURITY_HEADERS = {
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "cache-control": "no-store", // the answer is about one page view
    "strict-transport-security": "max-age=31536000",
    "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
    "cross-origin-resource-policy": "cross-origin", // the extension reads these answers from its own origin
};
// The Safari extension reads answers from another origin. No cookies or credentials exist here, so any origin may read them.
const CORS_HEADERS = {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-max-age": "86400",
};

/** Per-IP limit for /public-blocklist: the extension asks every 6 h, so this is generous for a real client. */
export const BLOCKLIST_RATE = Object.freeze({ limit: 30, windowMs: 10 * 60 * 1000 });

/**
 * @param {{ fetch?: typeof fetch, cache?: object, now?: () => number, rdapTimeoutMs?: number, llm?: object, llmFetch?: typeof fetch, llmClientCallsPerHour?: number, devStats?: boolean, blocklistSource?: object, rateLimit?: { limit: number, windowMs: number }, analyzeRateLimit?: { limit: number, windowMs: number } }} [opts]
 *   fetch: network for RDAP (the Worker entry passes the real one). Without it new_domain is off, so tests never touch the network.
 *   cache: { get, set } for RDAP answers; defaults to an in-memory cache that lives as long as this app (one Worker isolate).
 *   blocklistSource: where /public-blocklist gets its domains (blocklist/source.js). Default: an empty list.
 *   rateLimit: per-IP limit for /public-blocklist.
 *   llm: a layer 4 checker ({ check }) for tests. Otherwise layer 4 is configured from the request's env bindings (LLM_*), using llmFetch (the Worker entry passes the real fetch).
 *   llmClientCallsPerHour: per-IP limit on layer 4 calls (default CLIENT_CALLS_PER_HOUR; Infinity = off, local eval only).
 *   devStats: serve GET /_dev/layer4 (layer 4 outcome counters, no page data). Local dev server only, never the Worker.
 */
export function createApp({ fetch: rdapFetch = null, cache, now = Date.now, rdapTimeoutMs, blocklistSource = emptySource, rateLimit = BLOCKLIST_RATE, analyzeRateLimit = ANALYZE_RATE, llm = null, llmFetch = null, llmClientCallsPerHour = CLIENT_CALLS_PER_HOUR, devStats = false } = {}) {
    let envLlm = { key: "", checker: null }; // built once per distinct configuration, so the daily counter survives requests
    const rdap = rdapFetch ? createRdapClient({ fetch: rdapFetch, cache: cache ?? createMemoryCache({ now }), now, timeoutMs: rdapTimeoutMs }) : null;
    const blocklist = createBlocklist({ source: blocklistSource, now });
    const blocklistLimiter = createRateLimiter({ ...rateLimit, now });
    const analyzeLimiter = createRateLimiter({ ...analyzeRateLimit, now });
    function llmFor(env) {
        if (!llmFetch) return null;
        const config = readConfig(env);
        if (!config) return null;
        const key = JSON.stringify(config);
        if (envLlm.key !== key) envLlm = { key, checker: createRealityCheck({ config, fetch: llmFetch, now, clientCallsPerHour: llmClientCallsPerHour }) };
        return envLlm.checker;
    }
    const app = new Hono();

    app.use("*", async (c, next) => {
        if (c.req.method === "OPTIONS") {
            // Preflight: answered here, so it never touches a handler or a rate limit.
            c.res = new Response(null, { status: 204, headers: CORS_HEADERS });
        } else {
            await next();
            for (const [k, v] of Object.entries(CORS_HEADERS)) c.res.headers.set(k, v);
        }
        for (const [k, v] of Object.entries(SECURITY_HEADERS)) c.res.headers.set(k, v);
    });

    app.post("/analyze", async (c) => {
        // Limit first: a refused request's body is never read.
        const gate = analyzeLimiter(clientKey(c.req.raw));
        if (!gate.ok) return errorResponse(429, "rate_limited", "Too many requests.", { "retry-after": String(gate.retryAfterSec) });
        const text = await readTextLimited(c.req.raw, LIMITS.MAX_BODY_BYTES);
        let body;
        try {
            body = JSON.parse(text);
        } catch {
            throw new HttpError(400, "bad_json", "Body is not valid JSON.");
        }
        const checked = validateRequest(body);
        if ("error" in checked) throw new HttpError(422, "invalid_body", checked.error);
        const checker = llm ?? llmFor(c.env);
        return c.json({ signals: await analyze(checked.snapshot, { rdap, llm: checker, client: clientKey(c.req.raw), localSignals: checked.localSignals }) });
    });

    app.get("/public-blocklist", async (c) => {
        if (Number(c.req.header("content-length")) > MAX_GET_BODY_BYTES) throw new HttpError(413, "too_large", "Request body is too large.");
        // The Bearer token is never read: the AI service cannot verify it, and a token that is not read cannot be logged.
        const verdict = blocklistLimiter(clientKey(c.req.raw));
        if (!verdict.ok) {
            return errorResponse(429, "rate_limited", "Too many requests.", { "retry-after": String(verdict.retryAfterSec) });
        }
        return c.json(await blocklist(c.req.query("since")));
    });

    if (devStats) {
        app.get("/_dev/layer4", (c) => {
            const checker = llm ?? llmFor(c.env);
            return c.json(checker?.stats ? checker.stats() : { off: true });
        });
    }

    app.all("/public-blocklist", () => errorResponse(405, "method_not_allowed", "Use GET.", { allow: "GET" }));
    app.all("/analyze", () => errorResponse(405, "method_not_allowed", "Use POST.", { allow: "POST" }));
    app.notFound(() => errorResponse(404, "not_found", "Not found."));
    app.onError((err) => {
        if (err instanceof HttpError) return errorResponse(err.status, err.code, err.message);
        return errorResponse(500, "internal", "Something went wrong.");
    });
    return app;
}
