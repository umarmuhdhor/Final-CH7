// POST /analyze (contracts/api.md). Stateless: nothing from a request is stored or logged.
// The only cache is RDAP domain ages (domain + registration date, TTL in rdap/cache.js).
// Authorization is accepted but never read: the AI service cannot verify device tokens in the MVP.
import { Hono } from "hono";
import { LIMITS } from "./limits.js";
import { HttpError, errorResponse, readTextLimited } from "./http.js";
import { validateRequest } from "./validate.js";
import { analyze } from "./analyze.js";
import { createMemoryCache } from "./rdap/cache.js";
import { createRdapClient } from "./rdap/rdap.js";

/**
 * @param {{ fetch?: typeof fetch, cache?: object, now?: () => number, rdapTimeoutMs?: number }} [opts]
 *   fetch: network for RDAP (the Worker entry passes the real one). Without it new_domain is off, so tests never touch the network.
 *   cache: { get, set } for RDAP answers; defaults to an in-memory cache that lives as long as this app (one Worker isolate).
 */
export function createApp({ fetch: rdapFetch = null, cache, now = Date.now, rdapTimeoutMs } = {}) {
    const rdap = rdapFetch ? createRdapClient({ fetch: rdapFetch, cache: cache ?? createMemoryCache({ now }), now, timeoutMs: rdapTimeoutMs }) : null;
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
        if ("error" in checked) throw new HttpError(400, "invalid_body", checked.error);
        return c.json({ signals: await analyze(checked.snapshot, { rdap }) });
    });

    app.all("/analyze", () => errorResponse(405, "method_not_allowed", "Use POST.", { allow: "POST" }));
    app.notFound(() => errorResponse(404, "not_found", "Not found."));
    app.onError((err) => {
        if (err instanceof HttpError) return errorResponse(err.status, err.code, err.message);
        return errorResponse(500, "internal", "Something went wrong.");
    });
    return app;
}
