// RDAP cache in Workers KV (D-imelda-40): memory first, KV second, every KV problem = memory only.
// Fake KV bindings and a mock fetch only: no real KV, RDAP or network.
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { createMemoryCache, createKvCache, createKvBudget, createTieredCache, KV_SUCCESS_TTL_MS, KV_WRITES_PER_DAY, KV_READS_PER_DAY, KV_WRITE_PAUSE_MS } from "../src/rdap/cache.js";
import { BOOTSTRAP_URL } from "../src/rdap/rdap.js";
import { page, field, ids } from "./helpers.mjs";

const NOW = Date.parse("2026-10-22T00:00:00Z");
const DAY = 86_400_000;
const Y2020 = Date.parse("2020-01-01T00:00:00Z");
const iso = (daysAgo) => new Date(NOW - daysAgo * DAY).toISOString();
const BOOTSTRAP = { services: [[["com"], ["https://rdap.registry-a.example/com/v1/"]]] };
const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });
const SCAM = "https://login.bca-verifikasi.com/akun?token=abc";
const body = (url = SCAM) => JSON.stringify({ snapshot: page(url, [field({ name: "pin" })], { text: "PRIVATE-TEXT", title: "PRIVATE-TITLE" }), localSignals: [] });

function mockFetch({ rdap = () => json({ events: [{ eventAction: "registration", eventDate: iso(3) }] }) } = {}) {
    const calls = [];
    const fn = async (url) => {
        calls.push(String(url));
        return String(url) === BOOTSTRAP_URL ? json(BOOTSTRAP) : rdap(String(url));
    };
    fn.rdapCalls = () => calls.filter((u) => u !== BOOTSTRAP_URL);
    return fn;
}

/** Fake RDAP_KV binding: records every get/put. `get`/`put` can be replaced to fail or hang. */
function fakeKv(entries = {}, over = {}) {
    const store = new Map(Object.entries(entries));
    const kv = {
        store,
        gets: [],
        puts: [],
        async get(key) {
            kv.gets.push(key);
            return store.get(key) ?? null;
        },
        async put(key, value, opts) {
            kv.puts.push({ key, value, opts });
            store.set(key, value);
        },
        ...over,
    };
    return kv;
}

/** Execution context like the Worker's: waitUntil promises are collected so a test can wait for background writes. */
function fakeCtx() {
    const pending = [];
    return { pending, waitUntil: (p) => pending.push(p), passThroughOnException() {}, settle: () => Promise.all(pending) };
}

const call = (app, env, ctx, url) => app.request("/analyze", { method: "POST", headers: { "content-type": "application/json" }, body: body(url) }, env, ctx);
const newDomain = async (res) => (await res.json()).signals.find((s) => s.id === "new_domain");

// ---- through POST /analyze ----------------------------------------------------

test("RDAP_KV hit: no RDAP call, age from the stored date, and the hit is kept in memory (no second KV read)", async () => {
    const f = mockFetch();
    const kv = fakeKv({ "rdap:bca-verifikasi.com": JSON.stringify({ registeredAt: NOW - 2 * DAY }) });
    const app = createApp({ fetch: f, now: () => NOW });
    const ctx = fakeCtx();
    const res = await call(app, { RDAP_KV: kv }, ctx);
    assert.equal(res.status, 200);
    assert.equal((await newDomain(res)).label.en, "Domain age 2 days");
    assert.equal(f.rdapCalls().length, 0);
    await call(app, { RDAP_KV: kv }, ctx);
    assert.deepEqual(kv.gets, ["rdap:bca-verifikasi.com"]);
    await ctx.settle();
    assert.equal(kv.puts.length, 0, "a KV hit is never written back");
});

test("RDAP_KV miss: RDAP lookup, then one background write of the registrable domain + date only, 7-day TTL", async () => {
    const f = mockFetch();
    const kv = fakeKv();
    const ctx = fakeCtx();
    const res = await call(createApp({ fetch: f, now: () => NOW }), { RDAP_KV: kv }, ctx);
    assert.equal((await newDomain(res)).weight, 30);
    assert.equal(f.rdapCalls().length, 1);
    assert.equal(ctx.pending.length, 1, "the write goes through waitUntil, the answer does not wait for it");
    await ctx.settle();
    assert.deepEqual(kv.puts, [{ key: "rdap:bca-verifikasi.com", value: JSON.stringify({ registeredAt: Date.parse(iso(3)) }), opts: { expirationTtl: KV_SUCCESS_TTL_MS / 1000 } }]);
    // a second app (another isolate) reads it back instead of calling RDAP
    const f2 = mockFetch();
    const res2 = await call(createApp({ fetch: f2, now: () => NOW }), { RDAP_KV: kv }, fakeCtx());
    assert.equal((await newDomain(res2)).weight, 30);
    assert.equal(f2.rdapCalls().length, 0);
});

test("RDAP_KV: a failed lookup is not written to KV (memory only, 10 min)", async () => {
    const kv = fakeKv();
    const ctx = fakeCtx();
    const app = createApp({ fetch: mockFetch({ rdap: () => json({}, 404) }), now: () => NOW });
    const res = await call(app, { RDAP_KV: kv }, ctx);
    assert.deepEqual(ids((await res.json()).signals), ["asks_pin"]);
    await ctx.settle();
    assert.equal(kv.puts.length, 0);
});

test("RDAP_KV throws on read and write: still 200 with new_domain, nothing thrown, writes pause", async () => {
    let puts = 0;
    const kv = fakeKv({}, { get: async () => { throw new Error("KV GET failed: 429"); }, put: async () => { puts++; throw new Error("KV put() limit exceeded for the day"); } });
    const ctx = fakeCtx();
    const app = createApp({ fetch: mockFetch(), now: () => NOW });
    const res = await call(app, { RDAP_KV: kv }, ctx);
    assert.equal(res.status, 200);
    assert.equal((await newDomain(res)).weight, 30);
    await ctx.settle();
    assert.equal(puts, 1);
    // another new domain in the same isolate: the write is skipped while paused
    await call(app, { RDAP_KV: kv }, ctx, "https://other-new.com/");
    await ctx.settle();
    assert.equal(puts, 1);
});

test("RDAP_KV synchronous throw or junk value: treated as a miss", async () => {
    for (const kv of [fakeKv({}, { get() { throw new Error("sync"); } }), fakeKv({ "rdap:bca-verifikasi.com": "{not json" }), fakeKv({ "rdap:bca-verifikasi.com": JSON.stringify({ registeredAt: NOW + 30 * DAY }) })]) {
        const f = mockFetch();
        const res = await call(createApp({ fetch: f, now: () => NOW }), { RDAP_KV: kv }, fakeCtx());
        assert.equal((await newDomain(res)).weight, 30);
        assert.equal(f.rdapCalls().length, 1);
    }
});

test("RDAP_KV hanging read: falls back to RDAP inside the same 1.5 s lookup budget", async () => {
    const f = mockFetch();
    const kv = fakeKv({}, { get: () => new Promise(() => {}) });
    const t0 = performance.now();
    const res = await call(createApp({ fetch: f, now: Date.now }), { RDAP_KV: kv }, fakeCtx());
    const ms = performance.now() - t0;
    assert.equal(res.status, 200);
    assert.equal(f.rdapCalls().length, 1);
    assert.ok(ms < 1500, `took ${ms} ms`);
});

test("RDAP_KV hanging read + hanging RDAP: the whole lookup still ends at the RDAP deadline", async () => {
    const kv = fakeKv({}, { get: () => new Promise(() => {}) });
    const app = createApp({ fetch: mockFetch({ rdap: () => new Promise(() => {}) }), now: Date.now, rdapTimeoutMs: 300 });
    const t0 = performance.now();
    const res = await call(app, { RDAP_KV: kv }, fakeCtx());
    const ms = performance.now() - t0;
    assert.deepEqual(ids((await res.json()).signals), ["asks_pin"]);
    assert.ok(ms < 600, `took ${ms} ms (cache read + RDAP share one 300 ms budget)`);
});

test("no RDAP_KV binding (local dev, tests) or a broken one: memory cache only, normal answer", async () => {
    for (const env of [undefined, {}, { RDAP_KV: null }, { RDAP_KV: {} }, { RDAP_KV: { get: async () => null } }]) {
        const f = mockFetch();
        const app = createApp({ fetch: f, now: () => NOW });
        assert.equal((await newDomain(await call(app, env))).weight, 30);
        await call(app, env);
        assert.equal(f.rdapCalls().length, 1, "second lookup is a memory hit");
    }
});

test("RDAP_KV without an execution context (no waitUntil): the write still happens and never throws", async () => {
    const kv = fakeKv();
    const res = await createApp({ fetch: mockFetch(), now: () => NOW }).request("/analyze", { method: "POST", headers: { "content-type": "application/json" }, body: body() }, { RDAP_KV: kv });
    assert.equal(res.status, 200);
    await new Promise((r) => setTimeout(r, 0));
    assert.equal(kv.puts.length, 1);
});

test("RDAP_KV privacy: keys and values hold only the registrable domain and its date; nothing is logged", async () => {
    const names = ["log", "info", "debug", "warn", "error"];
    const logged = [];
    const originals = Object.fromEntries(names.map((n) => [n, console[n]]));
    names.forEach((n) => (console[n] = (...a) => logged.push(a)));
    const kv = fakeKv();
    try {
        const ctx = fakeCtx();
        await call(createApp({ fetch: mockFetch(), now: () => NOW }), { RDAP_KV: kv }, ctx);
        await ctx.settle();
        const broken = fakeKv({}, { get: async () => { throw new Error("x"); }, put: async () => { throw new Error("y"); } });
        const ctx2 = fakeCtx();
        await call(createApp({ fetch: mockFetch(), now: () => NOW }), { RDAP_KV: broken }, ctx2);
        await ctx2.settle();
    } finally {
        names.forEach((n) => (console[n] = originals[n]));
    }
    assert.deepEqual(logged, []);
    const written = JSON.stringify([...kv.store]);
    for (const needle of ["login.", "akun", "token", "PRIVATE", "https"]) assert.ok(!written.includes(needle), needle);
    assert.deepEqual(Object.keys(JSON.parse(kv.store.get("rdap:bca-verifikasi.com"))), ["registeredAt"]);
});

test("official domains never touch RDAP_KV", async () => {
    const kv = fakeKv();
    await call(createApp({ fetch: mockFetch(), now: () => NOW }), { RDAP_KV: kv }, fakeCtx(), "https://www.bca.co.id/");
    assert.equal(kv.gets.length + kv.puts.length, 0);
});

// ---- budget and tiered cache ----------------------------------------------------

test("KV budget: at most KV_WRITES_PER_DAY writes and KV_READS_PER_DAY reads per isolate per UTC day", () => {
    let t = NOW + 3_600_000;
    const budget = createKvBudget({ now: () => t });
    for (let i = 0; i < KV_WRITES_PER_DAY; i++) assert.equal(budget.write(), true);
    assert.equal(budget.write(), false);
    for (let i = 0; i < KV_READS_PER_DAY; i++) assert.equal(budget.read(), true);
    assert.equal(budget.read(), false);
    t = NOW + DAY; // 00:00 UTC next day: the KV quota resets, so does the budget
    assert.equal(budget.write(), true);
    assert.equal(budget.read(), true);
});

test("KV budget: a failed write pauses writes for KV_WRITE_PAUSE_MS, reads go on", () => {
    let t = NOW;
    const budget = createKvBudget({ now: () => t });
    budget.writeFailed();
    assert.equal(budget.write(), false);
    assert.equal(budget.read(), true);
    t += KV_WRITE_PAUSE_MS;
    assert.equal(budget.write(), true);
});

test("tiered cache: spent budget means memory only (no KV call at all)", async () => {
    const kv = fakeKv({ "rdap:a.com": JSON.stringify({ registeredAt: Y2020 }) });
    const budget = createKvBudget({ readsPerDay: 0, writesPerDay: 0, now: () => NOW });
    const cache = createTieredCache({ memory: createMemoryCache({ now: () => NOW }), kv: createKvCache(kv), budget });
    assert.equal(await cache.get("a.com"), null);
    await cache.set("b.com", { registeredAt: Y2020 }, 1000);
    assert.equal(kv.gets.length + kv.puts.length, 0);
    assert.deepEqual(await cache.get("b.com"), { registeredAt: Y2020 }, "memory still works");
});

test("tiered cache: KV read slower than readTimeoutMs is a miss", async () => {
    const kv = fakeKv({}, { get: () => new Promise((r) => setTimeout(() => r(JSON.stringify({ registeredAt: Y2020 })), 200)) });
    const cache = createTieredCache({ memory: createMemoryCache({ now: () => NOW }), kv: createKvCache(kv), budget: createKvBudget({ now: () => NOW }), readTimeoutMs: 20 });
    const t0 = performance.now();
    assert.equal(await cache.get("a.com"), null);
    assert.ok(performance.now() - t0 < 150);
});
