// POST /analyze and GET /public-blocklist (contracts/api.md). Stateless: nothing from a request is stored or logged.
// The only cache is RDAP domain ages (domain + registration date, TTL in rdap/cache.js): memory, plus Workers KV
// when the RDAP_KV binding exists (D-imelda-40).
// Authorization is accepted but never read: the AI service cannot verify device tokens in the MVP.
import { Hono } from "hono";
import { LIMITS } from "./limits.js";
import { HttpError, errorResponse, readTextLimited } from "./http.js";
import { validateRequest } from "./validate.js";
import { analyze, SERVER_DEADLINE_MS } from "./analyze.js";
import { createMemoryCache, createKvCache, createKvBudget, createTieredCache } from "./rdap/cache.js";
import { createRdapClient } from "./rdap/rdap.js";
import { emptySource } from "./blocklist/source.js";
import { createBlocklist } from "./blocklist/route.js";
import { createKvBlocklist } from "./blocklist/kv.js";
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
// The extension calls us from background.js with <all_urls> host permission, so it needs no CORS. Only an extension
// origin is ever echoed back: a web page must not be able to use its visitors' browsers to run (and pay for) /analyze.
const EXTENSION_ORIGIN = "safari-web-extension://";
const CORS_HEADERS = {
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
    "access-control-expose-headers": "retry-after",
    "access-control-max-age": "86400",
    vary: "origin",
};
const KNOWN_PATHS = new Set(["/analyze", "/public-blocklist"]);
/** Retry-After for a 429 from the Workers Rate Limiting binding (its period is 60 s). */
const BINDING_RETRY_SEC = 60;

function corsFor(origin) {
    return typeof origin === "string" && origin.startsWith(EXTENSION_ORIGIN) ? { ...CORS_HEADERS, "access-control-allow-origin": origin } : null;
}

/**
 * Workers Rate Limiting binding (wrangler.toml [[ratelimits]]): shared across isolates, works on workers.dev.
 * Absent in tests and the dev server; then only the in-memory limiter applies. A binding error never blocks a request.
 */
async function bindingAllows(binding, key) {
    if (!binding || typeof binding.limit !== "function") return true;
    try {
        return (await binding.limit({ key })).success !== false;
    } catch {
        return true;
    }
}

/** KV writes outlive the answer through the Worker's waitUntil; tests and the dev server have no execution context. */
function waitUntilOf(c) {
    try {
        const ctx = c.executionCtx;
        return (p) => ctx.waitUntil(p);
    } catch {
        return undefined;
    }
}

/** Per-IP limit for /public-blocklist: the extension asks every 6 h, so this is generous for a real client. */
export const BLOCKLIST_RATE = Object.freeze({ limit: 30, windowMs: 10 * 60 * 1000 });

/**
 * @param {{ fetch?: typeof fetch, cache?: object, now?: () => number, rdapTimeoutMs?: number, llm?: object, llmFetch?: typeof fetch, llmClientCallsPerHour?: number, devStats?: boolean, blocklistSource?: object, rateLimit?: { limit: number, windowMs: number }, analyzeRateLimit?: { limit: number, windowMs: number } }} [opts]
 *   fetch: network for RDAP (the Worker entry passes the real one). Without it new_domain is off, so tests never touch the network.
 *   cache: { get, set } for RDAP answers; defaults to an in-memory cache that lives as long as this app (one Worker isolate).
 *     With an RDAP_KV binding in the request's env, Workers KV is a second tier behind it (rdap/cache.js createTieredCache).
 *   blocklistSource: where /public-blocklist gets its domains (blocklist/source.js). Default: an empty list.
 *     When the Worker has a BLOCKLIST_KV binding, the pre-built list in KV is served instead (blocklist/kv.js, D-imelda-38).
 *   rateLimit: per-IP limit for /public-blocklist.
 *   llm: a layer 4 checker ({ check }) for tests. Otherwise layer 4 is configured from the request's env bindings (LLM_*), using llmFetch (the Worker entry passes the real fetch).
 *   llmClientCallsPerHour: per-IP limit on layer 4 calls (default CLIENT_CALLS_PER_HOUR; Infinity = off, local eval only).
 *   devStats: serve GET /_dev/layer4 (layer 4 outcome counters, no page data). Local dev server only, never the Worker.
 */
export function createApp({ fetch: rdapFetch = null, cache, now = Date.now, rdapTimeoutMs, blocklistSource = emptySource, rateLimit = BLOCKLIST_RATE, analyzeRateLimit = ANALYZE_RATE, llm = null, llmFetch = null, llmClientCallsPerHour = CLIENT_CALLS_PER_HOUR, devStats = false } = {}) {
    let envLlm = { key: "", checker: null }; // built once per distinct configuration, so the daily counter survives requests
    const memoryCache = cache ?? createMemoryCache({ now });
    const rdap = rdapFetch ? createRdapClient({ fetch: rdapFetch, cache: memoryCache, now, timeoutMs: rdapTimeoutMs }) : null;
    const kvBudget = createKvBudget({ now }); // lives with the isolate, like the memory cache
    /** The RDAP client for one request: memory only, or memory + KV when the Worker has the RDAP_KV binding. */
    function rdapFor(c) {
        const kv = c.env?.RDAP_KV;
        if (!rdap || typeof kv?.get !== "function" || typeof kv?.put !== "function") return rdap;
        const requestCache = createTieredCache({ memory: memoryCache, kv: createKvCache(kv), budget: kvBudget, waitUntil: waitUntilOf(c) });
        return { lookupAgeDays: (host) => rdap.lookupAgeDays(host, { cache: requestCache }) };
    }
    const blocklist = createBlocklist({ source: blocklistSource, now });
    const kvBlocklist = createKvBlocklist({ now });
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
        const cors = corsFor(c.req.header("origin"));
        if (c.req.method === "OPTIONS" && KNOWN_PATHS.has(c.req.path)) {
            // Preflight: answered here, so it never touches a handler or a rate limit.
            c.res = new Response(null, { status: 204, headers: cors ?? { vary: "origin" } });
        } else {
            await next();
            if (cors) for (const [k, v] of Object.entries(cors)) c.res.headers.set(k, v);
        }
        for (const [k, v] of Object.entries(SECURITY_HEADERS)) c.res.headers.set(k, v);
    });

    app.post("/analyze", async (c) => {
        const startedAt = now(); // the deadline counts body upload too: the extension's 8 s clock is already running
        // Limit first: a refused request's body is never read.
        const client = clientKey(c.req.raw);
        if (!(await bindingAllows(c.env?.ANALYZE_LIMITER, client))) return errorResponse(429, "rate_limited", "Too many requests.", { "retry-after": String(BINDING_RETRY_SEC) });
        const gate = analyzeLimiter(client);
        if (!gate.ok) return errorResponse(429, "rate_limited", "Too many requests.", { "retry-after": String(gate.retryAfterSec) });
        // JSON only. A text/plain POST is a CORS "simple" request (no preflight): refusing it keeps web pages out.
        const type = (c.req.header("content-type") ?? "").split(";")[0].trim().toLowerCase();
        if (type !== "application/json") throw new HttpError(422, "invalid_body", "Content-Type must be application/json.");
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
        return c.json({ signals: await analyze(checked.snapshot, { rdap: rdapFor(c), llm: checker, client, localSignals: checked.localSignals, deadline: startedAt + SERVER_DEADLINE_MS, now }) });
    });

    app.get("/public-blocklist", async (c) => {
        if (Number(c.req.header("content-length")) > MAX_GET_BODY_BYTES) throw new HttpError(413, "too_large", "Request body is too large.");
        // The Bearer token is never read: the AI service cannot verify it, and a token that is not read cannot be logged.
        const client = clientKey(c.req.raw);
        if (!(await bindingAllows(c.env?.BLOCKLIST_LIMITER, client))) return errorResponse(429, "rate_limited", "Too many requests.", { "retry-after": String(BINDING_RETRY_SEC) });
        const verdict = blocklistLimiter(client);
        if (!verdict.ok) {
            return errorResponse(429, "rate_limited", "Too many requests.", { "retry-after": String(verdict.retryAfterSec) });
        }
        const kv = c.env?.BLOCKLIST_KV;
        if (!kv) return c.json(await blocklist(c.req.query("since")));
        const answer = await kvBlocklist(kv, c.req.query("since"));
        return "stream" in answer ? c.body(answer.stream, 200, { "content-type": "application/json; charset=UTF-8" }) : c.json(answer.json);
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
