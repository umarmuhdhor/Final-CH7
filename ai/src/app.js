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
import { createRealityCheck } from "./layer4/reality.js";
import { clientKey, createRateLimiter } from "./ratelimit.js";

/** Per-IP limit for /public-blocklist: the extension asks every 6 h, so this is generous for a real client. */
export const BLOCKLIST_RATE = Object.freeze({ limit: 30, windowMs: 10 * 60 * 1000 });

/**
 * @param {{ fetch?: typeof fetch, cache?: object, now?: () => number, rdapTimeoutMs?: number, llm?: object, llmFetch?: typeof fetch, blocklistSource?: object, rateLimit?: { limit: number, windowMs: number } }} [opts]
 *   fetch: network for RDAP (the Worker entry passes the real one). Without it new_domain is off, so tests never touch the network.
 *   cache: { get, set } for RDAP answers; defaults to an in-memory cache that lives as long as this app (one Worker isolate).
 *   blocklistSource: where /public-blocklist gets its domains (blocklist/source.js). Default: an empty list.
 *   rateLimit: per-IP limit for /public-blocklist.
 *   llm: a layer 4 checker ({ check }) for tests. Otherwise layer 4 is configured from the request's env bindings (LLM_*), using llmFetch (the Worker entry passes the real fetch).
 */
export function createApp({ fetch: rdapFetch = null, cache, now = Date.now, rdapTimeoutMs, blocklistSource = emptySource, rateLimit = BLOCKLIST_RATE, llm = null, llmFetch = null } = {}) {
    let envLlm = { key: "", checker: null }; // built once per distinct configuration, so the daily counter survives requests
    const rdap = rdapFetch ? createRdapClient({ fetch: rdapFetch, cache: cache ?? createMemoryCache({ now }), now, timeoutMs: rdapTimeoutMs }) : null;
    const blocklist = createBlocklist({ source: blocklistSource, now });
    const blocklistLimiter = createRateLimiter({ ...rateLimit, now });
    function llmFor(env) {
        if (!llmFetch) return null;
        const config = readConfig(env);
        if (!config) return null;
        const key = JSON.stringify(config);
        if (envLlm.key !== key) envLlm = { key, checker: createRealityCheck({ config, fetch: llmFetch, now }) };
        return envLlm.checker;
    }
    const app = new Hono();

    // The answer is about one page view: never let a cache keep it.
    app.use("*", async (c, next) => {
        await next();
        c.res.headers.set("cache-control", "no-store");
    });

    app.post("/analyze", async (c) => {
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
        return c.json({ signals: await analyze(checked.snapshot, { rdap, llm: checker, localSignals: checked.localSignals }) });
    });

    app.get("/public-blocklist", async (c) => {
        // The Bearer token is never read: the AI service cannot verify it, and a token that is not read cannot be logged.
        const verdict = blocklistLimiter(clientKey(c.req.raw));
        if (!verdict.ok) {
            return errorResponse(429, "rate_limited", "Too many requests.", { "retry-after": String(verdict.retryAfterSec) });
        }
        return c.json(await blocklist(c.req.query("since")));
    });

    app.all("/public-blocklist", () => errorResponse(405, "method_not_allowed", "Use GET.", { allow: "GET" }));
    app.all("/analyze", () => errorResponse(405, "method_not_allowed", "Use POST.", { allow: "POST" }));
    app.notFound(() => errorResponse(404, "not_found", "Not found."));
    app.onError((err) => {
        if (err instanceof HttpError) return errorResponse(err.status, err.code, err.message);
        return errorResponse(500, "internal", "Something went wrong.");
    });
    return app;
}
