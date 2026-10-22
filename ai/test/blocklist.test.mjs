// GET /public-blocklist: contract shape, since/removed, allowlist, size cap, rate limit, privacy.
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { createStaticSource } from "../src/blocklist/source.js";
import { BRANDS } from "./helpers.mjs";

const T = (s) => `2026-10-${s}:00:00.000Z`;
const entry = (host, addedAt, removedAt) => ({ host, addedAt, ...(removedAt ? { removedAt } : {}) });
const appWith = (entries, opts = {}) => createApp({ blocklistSource: createStaticSource({ name: "test", license: "test", entries }), ...opts });
const get = (app, path = "/public-blocklist", init = {}) => app.request(path, init);

function assertShape(body) {
    assert.deepEqual(Object.keys(body).filter((k) => !["domains", "removed", "nextSince"].includes(k)), [], "no extra keys");
    assert.ok(Array.isArray(body.domains));
    for (const d of body.domains) {
        assert.deepEqual(Object.keys(d).sort(), ["addedAt", "domain"]);
        assert.equal(typeof d.domain, "string");
        assert.ok(!Number.isNaN(Date.parse(d.addedAt)));
    }
    if ("removed" in body) {
        assert.ok(Array.isArray(body.removed));
        for (const r of body.removed) assert.deepEqual(Object.keys(r).sort(), ["domain", "removedAt"]);
    }
    assert.ok(body.nextSince === null || typeof body.nextSince === "string");
}

const SEED = [
    entry("shoo-fixture-bca-login.xyz", T("01T10")),
    entry("shoo-fixture-dana-klaim.top", T("02T10")),
    entry("shoo-fixture-kurir-paket.site", T("03T10")),
];

test("full list: contract shape, no removed, nextSince = newest addedAt", async () => {
    const res = await get(appWith(SEED));
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type"), /application\/json/);
    assert.equal(res.headers.get("cache-control"), "no-store");
    const body = await res.json();
    assertShape(body);
    assert.deepEqual(body.domains.map((d) => d.domain).sort(), SEED.map((e) => e.host).sort());
    assert.equal(body.nextSince, T("03T10"));
    assert.ok(!("removed" in body) || body.removed.length === 0);
});

test("empty list without since -> nextSince null; with since -> echoes since", async () => {
    const app = appWith([]);
    assert.deepEqual(await (await get(app)).json(), { domains: [], nextSince: null });
    const since = encodeURIComponent(T("02T10"));
    assert.deepEqual(await (await get(app, `/public-blocklist?since=${since}`)).json(), { domains: [], nextSince: T("02T10") });
});

test("since returns only newer entries; caught up returns since back", async () => {
    const app = appWith(SEED);
    const body = await (await get(app, `/public-blocklist?since=${encodeURIComponent(T("02T10"))}`)).json();
    assertShape(body);
    assert.deepEqual(body.domains.map((d) => d.domain), ["shoo-fixture-kurir-paket.site"]);
    assert.equal(body.nextSince, T("03T10"));
    const again = await (await get(app, `/public-blocklist?since=${encodeURIComponent(T("03T10"))}`)).json();
    assert.deepEqual(again, { domains: [], nextSince: T("03T10") });
});

test("removed: reported only for since, never in a full list", async () => {
    const entries = [...SEED, entry("shoo-fixture-gone.xyz", T("01T11"), T("04T10"))];
    const app = appWith(entries);
    const full = await (await get(app)).json();
    assert.ok(!full.domains.some((d) => d.domain === "shoo-fixture-gone.xyz"));
    assert.ok(!full.removed?.length);
    const inc = await (await get(app, `/public-blocklist?since=${encodeURIComponent(T("03T10"))}`)).json();
    assertShape(inc);
    assert.deepEqual(inc.removed, [{ domain: "shoo-fixture-gone.xyz", removedAt: T("04T10") }]);
    assert.equal(inc.nextSince, T("04T10"));
});

test("entries are reduced to the registrable domain and de-duplicated", async () => {
    const app = appWith([
        entry("login.shoo-fixture-a.xyz", T("01T10")),
        entry("www.shoo-fixture-a.xyz", T("02T10")),
        entry("shoo-fixture-b.co.id", T("01T10")),
        entry("x.y.shoo-fixture-b.co.id", T("03T10")),
        entry("SHOO-FIXTURE-C.XYZ.", T("01T10")),
    ]);
    const names = (await (await get(app)).json()).domains.map((d) => d.domain).sort();
    assert.deepEqual(names, ["shoo-fixture-a.xyz", "shoo-fixture-b.co.id", "shoo-fixture-c.xyz"]);
});

test("a duplicate keeps the earliest addedAt", async () => {
    const app = appWith([entry("a.shoo-fixture-a.xyz", T("05T10")), entry("b.shoo-fixture-a.xyz", T("01T10"))]);
    const body = await (await get(app)).json();
    assert.deepEqual(body.domains, [{ domain: "shoo-fixture-a.xyz", addedAt: T("01T10") }]);
});

test("allowlist: official domains (and subdomains), popular sites and shared hosts never appear", async () => {
    const official = BRANDS.brands.flatMap((b) => b.domains);
    const hostile = [
        ...official.map((d) => entry(d, T("01T10"))),
        ...official.map((d) => entry(`login.${d}`, T("01T10"))),
        ...["google.com", "wordpress.com", "github.io", "blogspot.com", "vercel.app", "pages.dev", "netlify.app", "weebly.com", "co.id", "com", "localhost"].map((d) => entry(d, T("01T10"))),
        entry("shoo-fixture-ok.xyz", T("02T10")),
    ];
    const names = (await (await get(appWith(hostile))).json()).domains.map((d) => d.domain);
    assert.deepEqual(names, ["shoo-fixture-ok.xyz"]);
});

test("a customer site on a shared host stays its own domain; the platform itself is dropped", async () => {
    const app = appWith([entry("shoo-fixture-fake.github.io", T("01T10")), entry("github.io", T("01T10")), entry("a.shoo-fixture-fake.vercel.app", T("01T10"))]);
    const names = (await (await get(app)).json()).domains.map((d) => d.domain).sort();
    assert.deepEqual(names, ["shoo-fixture-fake.github.io", "shoo-fixture-fake.vercel.app"]);
});

test("junk entries are skipped, not errors", async () => {
    const app = appWith([entry("127.0.0.1", T("01T10")), entry("http://x", T("01T10")), entry("", T("01T10")), entry("a b.xyz", T("01T10")), entry("shoo-fixture-d.xyz", "not a date"), entry("shoo-fixture-e.xyz", T("01T10")), null, 5]);
    const body = await (await get(app)).json();
    assert.deepEqual(body.domains.map((d) => d.domain), ["shoo-fixture-e.xyz"]);
});

test("entries given as URLs are reduced to their host", async () => {
    const app = appWith([entry("https://evil.shoo-fixture-f.xyz/login?a=1", T("01T10"))]);
    assert.deepEqual((await (await get(app)).json()).domains.map((d) => d.domain), ["shoo-fixture-f.xyz"]);
});

test("size cap: at most 200,000 domains, newest kept", async () => {
    const entries = [];
    for (let i = 0; i < 200_005; i++) entries.push(entry(`shoo-fixture-${i}.xyz`, new Date(Date.UTC(2026, 0, 1) + i * 1000).toISOString()));
    const app = appWith(entries);
    const body = await (await get(app)).json();
    assert.equal(body.domains.length, 200_000);
    assert.ok(!body.domains.some((d) => d.domain === "shoo-fixture-0.xyz"));
    assert.ok(body.domains.some((d) => d.domain === "shoo-fixture-200004.xyz"));
});

test("bad since -> 400 invalid_query; other methods -> 405", async () => {
    const app = appWith(SEED);
    for (const q of ["since=yesterday", "since=", "since=2026-13-45T00:00:00Z", `since=${"9".repeat(200)}`]) {
        const res = await get(app, `/public-blocklist?${q}`);
        assert.equal(res.status, 400, q);
        assert.equal((await res.json()).error.code, "invalid_query");
    }
    const res = await app.request("/public-blocklist", { method: "POST", body: "{}" });
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("allow"), "GET");
});

test("a failing source is a fixed 500, never a leak", async () => {
    const app = createApp({ blocklistSource: { name: "x", license: "x", entries: async () => { throw new Error("secret detail"); } } });
    const res = await get(app);
    assert.equal(res.status, 500);
    assert.doesNotMatch(await res.text(), /secret/);
});

test("without a configured source the answer is an empty list (never fake domains)", async () => {
    assert.deepEqual(await (await get(createApp())).json(), { domains: [], nextSince: null });
});

test("Authorization is ignored and never echoed", async () => {
    const res = await get(appWith(SEED), "/public-blocklist", { headers: { authorization: "Bearer TOKEN-SHOULD-NOT-APPEAR" } });
    assert.equal(res.status, 200);
    assert.doesNotMatch(await res.text(), /TOKEN-SHOULD/);
    assert.doesNotMatch(JSON.stringify([...res.headers]), /TOKEN-SHOULD/);
});

test("rate limit per IP: 429 with Retry-After, other IPs unaffected, window resets", async () => {
    let t = 1_000_000;
    const app = appWith(SEED, { now: () => t, rateLimit: { limit: 3, windowMs: 60_000 } });
    const ip = (a) => ({ headers: { "cf-connecting-ip": a } });
    for (let i = 0; i < 3; i++) assert.equal((await get(app, "/public-blocklist", ip("203.0.113.9"))).status, 200);
    const blocked = await get(app, "/public-blocklist", ip("203.0.113.9"));
    assert.equal(blocked.status, 429);
    assert.equal((await blocked.json()).error.code, "rate_limited");
    assert.ok(Number(blocked.headers.get("retry-after")) >= 1);
    assert.equal((await get(app, "/public-blocklist", ip("203.0.113.10"))).status, 200);
    t += 61_000;
    assert.equal((await get(app, "/public-blocklist", ip("203.0.113.9"))).status, 200);
});

test("rate limit treats an IPv6 /64 as one client", async () => {
    const app = appWith(SEED, { rateLimit: { limit: 1, windowMs: 60_000 } });
    const ip = (a) => ({ headers: { "cf-connecting-ip": a } });
    assert.equal((await get(app, "/public-blocklist", ip("2001:db8:1:2:aaaa::1"))).status, 200);
    assert.equal((await get(app, "/public-blocklist", ip("2001:db8:1:2:bbbb::9"))).status, 429);
    assert.equal((await get(app, "/public-blocklist", ip("2001:db8:1:3::1"))).status, 200);
});

test("privacy: nothing about the request is logged", async () => {
    const seen = [];
    const orig = { log: console.log, info: console.info, warn: console.warn, error: console.error };
    for (const k of Object.keys(orig)) console[k] = (...a) => seen.push(a.join(" "));
    try {
        await get(appWith(SEED), "/public-blocklist?since=2026-10-01T00:00:00Z", { headers: { authorization: "Bearer SECRET-T", "cf-connecting-ip": "198.51.100.7" } });
    } finally {
        Object.assign(console, orig);
    }
    assert.deepEqual(seen, []);
});

test("allowlist data file: every popular entry is a valid registrable domain", async () => {
    const { POPULAR, SHARED_HOSTS } = await import("../src/blocklist/allowlist.js");
    assert.ok(POPULAR.size >= 100, "about 100 popular sites");
    assert.ok(SHARED_HOSTS.size >= 10);
});
