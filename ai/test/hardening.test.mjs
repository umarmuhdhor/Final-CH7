// Phase 08: rate limit and body limit on both endpoints, security headers on every answer, CORS, no logging.
import test from "node:test";
import assert from "node:assert/strict";
import { createApp, ANALYZE_RATE } from "../src/app.js";
import { createStaticSource } from "../src/blocklist/source.js";
import { field, page, SCAM_URL } from "./helpers.mjs";

const ip = (a) => ({ "cf-connecting-ip": a });
const analyzeBody = () => JSON.stringify({ snapshot: page(SCAM_URL, [field({ name: "pin" })]), localSignals: [] });
const postAnalyze = (app, headers = {}, body = analyzeBody()) => app.request("/analyze", { method: "POST", headers: { "content-type": "application/json", ...headers }, body });
const SOURCE = createStaticSource({ name: "t", license: "t", entries: [{ host: "shoo-fixture-a.xyz", addedAt: "2026-10-01T00:00:00Z" }] });

const REQUIRED = {
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "cache-control": "no-store",
    "cross-origin-resource-policy": "cross-origin",
};

function assertHeaders(res, label) {
    for (const [k, v] of Object.entries(REQUIRED)) assert.equal(res.headers.get(k), v, `${label}: ${k}`);
    assert.match(res.headers.get("strict-transport-security") ?? "", /max-age=\d{7,}/, `${label}: hsts`);
    assert.match(res.headers.get("content-security-policy") ?? "", /default-src 'none'/, `${label}: csp`);
    assert.match(res.headers.get("content-security-policy") ?? "", /frame-ancestors 'none'/, `${label}: frame-ancestors`);
    assert.equal(res.headers.get("x-powered-by"), null);
    assert.equal(res.headers.get("server"), null);
}

test("security headers on 200, 400, 404, 405, 413 and 429, for both endpoints", async () => {
    const app = createApp({ blocklistSource: SOURCE, rateLimit: { limit: 1, windowMs: 60_000 }, analyzeRateLimit: { limit: 1, windowMs: 60_000 } });
    assertHeaders(await postAnalyze(app, ip("203.0.113.1")), "analyze 200");
    assertHeaders(await postAnalyze(app, ip("203.0.113.1")), "analyze 429");
    assertHeaders(await postAnalyze(app, ip("203.0.113.2"), "{nope"), "analyze 400");
    assertHeaders(await postAnalyze(app, ip("203.0.113.3"), "x".repeat(250_000)), "analyze 413");
    assertHeaders(await app.request("/analyze", { method: "GET", headers: ip("203.0.113.4") }), "analyze 405");
    assertHeaders(await app.request("/public-blocklist", { headers: ip("203.0.113.5") }), "blocklist 200");
    assertHeaders(await app.request("/public-blocklist", { headers: ip("203.0.113.5") }), "blocklist 429");
    assertHeaders(await app.request("/public-blocklist?since=x", { headers: ip("203.0.113.6") }), "blocklist 400");
    assertHeaders(await app.request("/nowhere"), "404");
});

test("/analyze rate limit per IP: 429 + Retry-After, other IPs fine, window resets", async () => {
    let t = 1_000_000;
    const app = createApp({ now: () => t, analyzeRateLimit: { limit: 3, windowMs: 60_000 } });
    for (let i = 0; i < 3; i++) assert.equal((await postAnalyze(app, ip("203.0.113.9"))).status, 200);
    const blocked = await postAnalyze(app, ip("203.0.113.9"));
    assert.equal(blocked.status, 429);
    assert.equal((await blocked.json()).error.code, "rate_limited");
    assert.ok(Number(blocked.headers.get("retry-after")) >= 1);
    assert.equal((await postAnalyze(app, ip("203.0.113.10"))).status, 200);
    t += 61_000;
    assert.equal((await postAnalyze(app, ip("203.0.113.9"))).status, 200);
});

test("/analyze: a rate-limited request is refused before its body is read or parsed", async () => {
    const app = createApp({ analyzeRateLimit: { limit: 1, windowMs: 60_000 } });
    await postAnalyze(app, ip("203.0.113.20"));
    let read = false;
    const body = new ReadableStream({ pull(c) { read = true; c.enqueue(new TextEncoder().encode("{}")); c.close(); } }, { highWaterMark: 0 }); // 0: nothing is pulled until someone reads
    const res = await app.request("/analyze", { method: "POST", headers: { ...ip("203.0.113.20"), "content-type": "application/json" }, body, duplex: "half" });
    assert.equal(res.status, 429);
    assert.equal(read, false);
});

test("default /analyze limit is generous for a real client and finite", () => {
    assert.ok(ANALYZE_RATE.limit >= 60 && ANALYZE_RATE.limit <= 1000);
    assert.ok(ANALYZE_RATE.windowMs >= 60_000);
});

test("/public-blocklist: a request that carries a body is refused with 413", async () => {
    const app = createApp({ blocklistSource: SOURCE });
    const res = await app.request("/public-blocklist", { method: "GET", headers: { ...ip("203.0.113.30"), "content-length": "100000" } });
    assert.equal(res.status, 413);
    assert.equal((await res.json()).error.code, "too_large");
});

test("the two endpoints limit independently", async () => {
    const app = createApp({ blocklistSource: SOURCE, rateLimit: { limit: 1, windowMs: 60_000 }, analyzeRateLimit: { limit: 1, windowMs: 60_000 } });
    assert.equal((await app.request("/public-blocklist", { headers: ip("203.0.113.40") })).status, 200);
    assert.equal((await postAnalyze(app, ip("203.0.113.40"))).status, 200);
});

test("CORS: preflight answered without touching limits or handlers; actual answers carry the allow headers", async () => {
    const app = createApp({ blocklistSource: SOURCE, rateLimit: { limit: 1, windowMs: 60_000 }, analyzeRateLimit: { limit: 1, windowMs: 60_000 } });
    for (let i = 0; i < 3; i++) {
        const pre = await app.request("/analyze", { method: "OPTIONS", headers: { origin: "safari-web-extension://abc", "access-control-request-method": "POST", "access-control-request-headers": "authorization, content-type", ...ip("203.0.113.50") } });
        assert.equal(pre.status, 204);
        assert.equal(pre.headers.get("access-control-allow-origin"), "*");
        assert.match(pre.headers.get("access-control-allow-methods"), /POST/);
        assert.match(pre.headers.get("access-control-allow-headers").toLowerCase(), /authorization/);
        assert.match(pre.headers.get("access-control-allow-headers").toLowerCase(), /content-type/);
        assertHeaders(pre, "preflight");
    }
    const real = await app.request("/public-blocklist", { headers: { origin: "safari-web-extension://abc", ...ip("203.0.113.50") } });
    assert.equal(real.status, 200, "preflights did not use up the limit");
    assert.equal(real.headers.get("access-control-allow-origin"), "*");
    assert.equal(real.headers.get("access-control-allow-credentials"), null);
});

test("no logging of the request on any path (IP, token, body, URL)", async () => {
    const seen = [];
    const orig = { log: console.log, info: console.info, warn: console.warn, error: console.error, debug: console.debug };
    for (const k of Object.keys(orig)) console[k] = (...a) => seen.push(a.join(" "));
    try {
        const app = createApp({ blocklistSource: SOURCE, rateLimit: { limit: 1, windowMs: 1000 }, analyzeRateLimit: { limit: 1, windowMs: 1000 } });
        const h = { ...ip("198.51.100.77"), authorization: "Bearer SECRET-TOKEN" };
        await postAnalyze(app, h);
        await postAnalyze(app, h);
        await postAnalyze(app, h, "{broken");
        await app.request("/public-blocklist?since=bad", { headers: h });
        await app.request("/public-blocklist", { headers: h });
        await app.request("/public-blocklist", { headers: h });
    } finally {
        Object.assign(console, orig);
    }
    assert.deepEqual(seen, []);
});

test("errors never echo input or the Authorization header", async () => {
    const app = createApp({ analyzeRateLimit: { limit: 1, windowMs: 60_000 } });
    const h = { ...ip("203.0.113.60"), authorization: "Bearer SECRET-TOKEN" };
    const texts = [];
    texts.push(await (await postAnalyze(app, h, "{ \"SECRET-BODY\": ")).text());
    texts.push(await (await postAnalyze(app, h)).text());
    texts.push(await (await app.request("/SECRET-PATH", { headers: h })).text());
    for (const t of texts) assert.doesNotMatch(t, /SECRET/);
});
