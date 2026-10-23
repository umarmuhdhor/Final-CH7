// Phase 03: new_domain via RDAP. No real network: fetch is a mock. Only a validated registrable domain may leave.
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { registrableDomain } from "../src/rdap/domain.js";
import { createMemoryCache, createKvCache } from "../src/rdap/cache.js";
import { createRdapClient, BOOTSTRAP_URL, TIMEOUT_MS } from "../src/rdap/rdap.js";
import { page, post, ids, field } from "./helpers.mjs";

const NOW = Date.parse("2026-10-22T00:00:00Z");
const DAY = 86_400_000;
const Y2020 = Date.parse("2020-01-01T00:00:00Z");
const iso = (daysAgo) => new Date(NOW - daysAgo * DAY).toISOString();
const BOOTSTRAP = { services: [[["com", "net"], ["https://rdap.registry-a.example/com/v1/"]], [["xyz"], ["https://rdap.registry-b.example/"]]] };
const json = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });

/** Mock fetch: records every call; `rdap(url)` decides the RDAP answer. */
function mockFetch({ rdap = () => json({ events: [{ eventAction: "registration", eventDate: iso(3) }] }), bootstrap = () => json(BOOTSTRAP) } = {}) {
    const calls = [];
    const fn = async (url, init = {}) => {
        calls.push({ url: String(url), init });
        if (String(url) === BOOTSTRAP_URL) return bootstrap();
        return rdap(String(url), init);
    };
    fn.calls = calls;
    fn.rdapCalls = () => calls.filter((c) => c.url !== BOOTSTRAP_URL);
    return fn;
}
const client = (over = {}) => createRdapClient({ fetch: over.fetch ?? mockFetch(), cache: over.cache ?? createMemoryCache({ now: () => NOW }), now: () => NOW, ...over });

// ---- registrableDomain --------------------------------------------------------
test("registrableDomain: normal hosts and multi-label suffixes", () => {
    assert.equal(registrableDomain("verif-akun.example.xyz"), "example.xyz");
    assert.equal(registrableDomain("a.b.example.com"), "example.com");
    assert.equal(registrableDomain("login.bca-aman.co.id"), "bca-aman.co.id");
    assert.equal(registrableDomain("EXAMPLE.com."), "example.com");
});

test("registrableDomain: rejects everything that is not a public domain name", () => {
    for (const bad of ["127.0.0.1", "10.0.0.5", "[::1]", "::1", "0x7f.1", "2130706433", "localhost", "printer.local", "db.internal", "x.localhost", "intranet", "a@b.com", "a b.com", "exa_mple.com", "-bad.com", "bad-.com", "xn--.com", "xn--a", "a..com", ".com", "com", "", "x.onion", "a.b.c.d.e.f".padEnd(260, "a") + ".com", "a".repeat(64) + ".com", "foo.c0m1"]) {
        assert.equal(registrableDomain(bad), null, JSON.stringify(bad));
    }
    assert.equal(registrableDomain(("a".repeat(60) + ".").repeat(5) + "com"), null, "> 253 characters");
});

// ---- RDAP client --------------------------------------------------------------
test("rdap success: age in days from the registration event", async () => {
    assert.equal(await client().lookupAgeDays("login.example.com"), 3);
});

test("rdap sends only the registrable domain: no path, query, or full URL; host comes from the IANA bootstrap", async () => {
    const f = mockFetch();
    await client({ fetch: f }).lookupAgeDays("secret-path.sub.example.com");
    const urls = f.calls.map((c) => c.url);
    assert.deepEqual(urls, [BOOTSTRAP_URL, "https://rdap.registry-a.example/com/v1/domain/example.com"]);
    for (const c of f.calls) {
        assert.equal(c.init.method ?? "GET", "GET");
        assert.equal(c.init.redirect, "manual");
        assert.ok(c.init.signal, "has an abort signal");
        assert.equal(c.init.body, undefined);
        assert.ok(!("credentials" in c.init) || c.init.credentials === "omit");
    }
    assert.ok(!urls.join().includes("secret-path"));
});

test("rdap: old domain -> age is returned (the signal builder decides there is none)", async () => {
    const f = mockFetch({ rdap: () => json({ events: [{ eventAction: "registration", eventDate: iso(4000) }] }) });
    assert.equal(await client({ fetch: f }).lookupAgeDays("example.com"), 4000);
});

test("rdap failure modes all give null, never throw", async () => {
    const cases = {
        "http 500": mockFetch({ rdap: () => json({}, 500) }),
        "http 404": mockFetch({ rdap: () => json({}, 404) }),
        "http 429": mockFetch({ rdap: () => json({}, 429) }),
        "redirect": mockFetch({ rdap: () => new Response(null, { status: 302, headers: { location: "http://169.254.169.254/" } }) }),
        "not json": mockFetch({ rdap: () => new Response("<html>", { status: 200 }) }),
        "no events": mockFetch({ rdap: () => json({ events: [] }) }),
        "bad date": mockFetch({ rdap: () => json({ events: [{ eventAction: "registration", eventDate: "not a date" }] }) }),
        "future date": mockFetch({ rdap: () => json({ events: [{ eventAction: "registration", eventDate: iso(-30) }] }) }),
        "network error": mockFetch({ rdap: () => { throw new TypeError("fetch failed"); } }),
        "bootstrap down": mockFetch({ bootstrap: () => json({}, 503) }),
        "bootstrap garbage": mockFetch({ bootstrap: () => json({ services: "nope" }) }),
        "tld not in bootstrap": mockFetch({ bootstrap: () => json({ services: [[["org"], ["https://rdap.x.example/"]]] }) }),
        "huge body": mockFetch({ rdap: () => new Response("x".repeat(2_000_000), { status: 200 }) }),
    };
    for (const [name, f] of Object.entries(cases)) {
        assert.equal(await client({ fetch: f }).lookupAgeDays("example.com"), null, name);
    }
});

test("rdap bootstrap entries with unsafe servers are never contacted", async () => {
    for (const server of ["http://rdap.registry-a.example/", "https://127.0.0.1/", "https://localhost/", "https://10.1.2.3/", "https://user:pw@rdap.x.example/", "https://rdap.corp.internal/", "https://[::1]/", "ftp://rdap.x.example/", "https://rdap.x.example:8443/"]) {
        const f = mockFetch({ bootstrap: () => json({ services: [[["com"], [server]]] }) });
        assert.equal(await client({ fetch: f }).lookupAgeDays("example.com"), null, server);
        assert.equal(f.rdapCalls().length, 0, `must not contact ${server}`);
    }
});

test("rdap timeout: a hanging server gives null after the 1.5 s budget", async () => {
    assert.equal(TIMEOUT_MS, 1500);
    const hang = (_u, init) => new Promise((_res, rej) => init.signal.addEventListener("abort", () => rej(new DOMException("aborted", "AbortError"))));
    const t0 = performance.now();
    const age = await createRdapClient({ fetch: mockFetch({ rdap: hang }), cache: createMemoryCache({ now: () => NOW }), now: () => NOW, timeoutMs: 80 }).lookupAgeDays("example.com");
    assert.equal(age, null);
    assert.ok(performance.now() - t0 < 500);
});

test("rdap timeout also stops a fetch that ignores the abort signal", async () => {
    const f = mockFetch({ rdap: () => new Promise(() => {}) });
    const t0 = performance.now();
    assert.equal(await createRdapClient({ fetch: f, cache: createMemoryCache({ now: () => NOW }), now: () => NOW, timeoutMs: 80 }).lookupAgeDays("example.com"), null);
    assert.ok(performance.now() - t0 < 500);
});

test("rdap invalid domains never reach fetch", async () => {
    const f = mockFetch();
    const c = client({ fetch: f });
    for (const h of ["127.0.0.1", "localhost", "a.local", "a.internal", "a@b", "xn--", "x".repeat(300), "[::1]", ""]) assert.equal(await c.lookupAgeDays(h), null, h);
    assert.equal(f.calls.length, 0);
});

// ---- cache --------------------------------------------------------------------
test("cache hit: second lookup of the same domain does not call RDAP again", async () => {
    const f = mockFetch();
    const c = client({ fetch: f });
    assert.equal(await c.lookupAgeDays("a.example.com"), 3);
    assert.equal(await c.lookupAgeDays("b.example.com"), 3);
    assert.equal(f.rdapCalls().length, 1);
});

test("cache stores only domain and registration date; age follows the clock", async () => {
    const cache = createMemoryCache({ now: () => NOW });
    await client({ cache }).lookupAgeDays("example.com");
    const entry = await cache.get("example.com");
    assert.deepEqual(Object.keys(entry).sort(), ["registeredAt"]);
    let later = NOW + 2 * DAY;
    const c2 = createRdapClient({ fetch: mockFetch(), cache, now: () => later });
    assert.equal(await c2.lookupAgeDays("example.com"), 5);
});

test("failed lookup is cached briefly (10 min) then retried; success lasts 24 h", async () => {
    let t = NOW;
    const cache = createMemoryCache({ now: () => t });
    let fail = true;
    const f = mockFetch({ rdap: () => (fail ? json({}, 500) : json({ events: [{ eventAction: "registration", eventDate: iso(3) }] })) });
    const c = createRdapClient({ fetch: f, cache, now: () => t });
    assert.equal(await c.lookupAgeDays("example.com"), null);
    assert.equal(await c.lookupAgeDays("example.com"), null);
    assert.equal(f.rdapCalls().length, 1, "failure cached");
    t += 11 * 60_000;
    fail = false;
    assert.equal(await c.lookupAgeDays("example.com"), 3);
    assert.equal(f.rdapCalls().length, 2, "retried after 10 min");
    t += 23 * 3_600_000;
    await c.lookupAgeDays("example.com");
    assert.equal(f.rdapCalls().length, 2, "success still cached at 23 h");
    t += 2 * 3_600_000;
    await c.lookupAgeDays("example.com");
    assert.equal(f.rdapCalls().length, 3, "expired after 24 h");
});

test("memory cache keeps at most `max` entries and drops the oldest", async () => {
    const cache = createMemoryCache({ max: 3, now: () => NOW });
    for (const d of ["a.com", "b.com", "c.com", "d.com"]) await cache.set(d, { registeredAt: Y2020 }, 60_000);
    assert.equal(await cache.get("a.com"), null);
    assert.deepEqual(await cache.get("d.com"), { registeredAt: Y2020 });
});

test("bootstrap: a thrown/aborted download is remembered, and concurrent requests share one download", async () => {
    const f = mockFetch({ bootstrap: () => { throw new TypeError("fetch failed"); } });
    const c = client({ fetch: f, cache: createMemoryCache({ now: () => NOW, max: 0 }) });
    assert.equal(await c.lookupAgeDays("a.example.com"), null);
    assert.equal(await c.lookupAgeDays("b.example.net"), null);
    assert.equal(f.calls.filter((x) => x.url === BOOTSTRAP_URL).length, 1, "failure remembered");
    const g = mockFetch();
    const c2 = client({ fetch: g });
    await Promise.all(["a.example.com", "b.example.net", "c.example.com"].map((d) => c2.lookupAgeDays(d)));
    assert.equal(g.calls.filter((x) => x.url === BOOTSTRAP_URL).length, 1, "one shared download");
});

test("bootstrap: one request's deadline does not kill the shared download, and the miss is not cached per domain", async () => {
    let release;
    const gate = new Promise((resolve) => (release = resolve));
    const f = mockFetch({ bootstrap: async () => { await gate; return json(BOOTSTRAP); } });
    const cache = createMemoryCache({ now: () => NOW });
    const c = client({ fetch: f, cache, timeoutMs: 20 });
    assert.equal(await c.lookupAgeDays("a.example.com"), null, "request hit its own deadline while the bootstrap was slow");
    assert.equal(await cache.get("example.com"), null, "a missing bootstrap must not be cached as a domain failure");
    release();
    assert.equal(await c.lookupAgeDays("a.example.com"), 3, "same domain works as soon as the bootstrap is back");
    assert.equal(f.calls.filter((x) => x.url === BOOTSTRAP_URL).length, 1, "the download was not aborted and restarted");
});

test("KV adapter ignores a poisoned entry (future or ancient date)", async () => {
    const store = new Map([["rdap:a.com", JSON.stringify({ registeredAt: Date.now() + 10 * DAY })], ["rdap:b.com", JSON.stringify({ registeredAt: 5 })]]);
    const cache = createKvCache({ get: async (k) => store.get(k) ?? null, put: async () => {} });
    assert.equal(await cache.get("a.com"), null);
    assert.equal(await cache.get("b.com"), null);
});

test("KV adapter (not enabled in phase 03) works against a fake binding and sets a TTL", async () => {
    const store = new Map();
    const puts = [];
    const kv = { get: async (k) => store.get(k) ?? null, put: async (k, v, o) => { puts.push([k, o]); store.set(k, v); } };
    const cache = createKvCache(kv);
    await cache.set("example.com", { registeredAt: Y2020 }, 600_000);
    assert.deepEqual(await cache.get("example.com"), { registeredAt: Y2020 });
    assert.equal(puts[0][1].expirationTtl, 600);
    assert.equal(await cache.get("nope.com"), null);
});

// ---- through POST /analyze ----------------------------------------------------
const SCAM = "https://bca-verifikasi.example.com/login";
const body = (url = SCAM, over = {}) => ({ snapshot: page(url, [field({ name: "pin" })], over), localSignals: [] });

test("analyze: 3-day-old domain -> new_domain 30, layer 3, bilingual label, no evidence", async () => {
    const app = createApp({ fetch: mockFetch(), now: () => NOW });
    const res = await post(app, body());
    assert.equal(res.status, 200);
    const s = (await res.json()).signals.find((x) => x.id === "new_domain");
    assert.ok(s);
    assert.equal(s.layer, 3);
    assert.equal(s.weight, 30);
    assert.equal("evidence" in s, false);
    assert.equal(s.label.en, "Domain age 3 days");
    assert.equal(s.label.id, "Umur domain 3 hari");
    assert.equal(s.labelSimple.en, "This site was made 3 days ago");
    assert.equal(s.labelSimple.id, "Situs ini baru dibuat 3 hari lalu");
});

test("analyze: singular label for 1 day", async () => {
    const f = mockFetch({ rdap: () => json({ events: [{ eventAction: "registration", eventDate: iso(1) }] }) });
    const s = (await (await post(createApp({ fetch: f, now: () => NOW }), body())).json()).signals.find((x) => x.id === "new_domain");
    assert.equal(s.label.en, "Domain age 1 day");
    assert.equal(s.labelSimple.en, "This site was made 1 day ago");
});

test("analyze: weight table 6->30, 7->20, 30->20, 31->10, 90->10, 91->none", async () => {
    for (const [days, weight] of [[0, 30], [6, 30], [7, 20], [30, 20], [31, 10], [90, 10], [91, undefined], [4000, undefined]]) {
        const f = mockFetch({ rdap: () => json({ events: [{ eventAction: "registration", eventDate: iso(days) }] }) });
        const app = createApp({ fetch: f, now: () => NOW });
        const s = (await (await post(app, body())).json()).signals.find((x) => x.id === "new_domain");
        assert.equal(s?.weight, weight, `${days} days`);
    }
});

test("analyze: RDAP down -> still 200 with the other layer-3 signals, no new_domain", async () => {
    const app = createApp({ fetch: mockFetch({ rdap: () => { throw new Error("boom"); } }), now: () => NOW });
    const res = await post(app, body());
    assert.equal(res.status, 200);
    assert.deepEqual(ids((await res.json()).signals), ["asks_pin"]);
});

test("analyze: RDAP hanging -> answer comes back within the budget, other signals intact", async () => {
    const f = mockFetch({ rdap: () => new Promise(() => {}) });
    const app = createApp({ fetch: f, now: () => NOW, rdapTimeoutMs: 100 });
    const t0 = performance.now();
    const res = await post(app, body());
    assert.ok(performance.now() - t0 < 600);
    assert.deepEqual(ids((await res.json()).signals), ["asks_pin"]);
});

test("analyze: official, IP and localhost URLs never trigger an RDAP call", async () => {
    const f = mockFetch();
    const app = createApp({ fetch: f, now: () => NOW });
    for (const url of ["https://www.bca.co.id/", "http://127.0.0.1/login", "http://localhost:3000/", "http://[::1]/", "http://printer.local/"]) {
        assert.equal((await post(app, body(url))).status, 200);
    }
    assert.equal(f.calls.length, 0);
});

test("analyze: the request body never reaches fetch (no url, text, title, alts in outgoing calls)", async () => {
    const f = mockFetch();
    const app = createApp({ fetch: f, now: () => NOW });
    await post(app, body("https://a.example.com/secret/path?token=abc", { text: "PRIVATE-TEXT", title: "PRIVATE-TITLE", imageAlts: ["PRIVATE-ALT"] }));
    const sent = JSON.stringify(f.calls);
    for (const needle of ["secret", "token", "PRIVATE", "path"]) assert.ok(!sent.includes(needle), needle);
});

test("analyze: nothing is logged (console spy) on RDAP success, failure and timeout", async () => {
    const names = ["log", "info", "debug", "warn", "error"];
    const calls = [];
    const originals = Object.fromEntries(names.map((n) => [n, console[n]]));
    names.forEach((n) => (console[n] = (...a) => calls.push([n, a])));
    try {
        for (const f of [mockFetch(), mockFetch({ rdap: () => { throw new Error("boom"); } }), mockFetch({ rdap: () => new Promise(() => {}) })]) {
            await post(createApp({ fetch: f, now: () => NOW, rdapTimeoutMs: 50 }), body("https://a.example.com/", { text: "klaim sekarang" }));
        }
    } finally {
        names.forEach((n) => (console[n] = originals[n]));
    }
    assert.deepEqual(calls, []);
});

test("analyze: rules run in parallel with RDAP (total time is about one RDAP delay, not the sum)", async () => {
    const slow = mockFetch({ rdap: async () => { await new Promise((r) => setTimeout(r, 120)); return json({ events: [{ eventAction: "registration", eventDate: iso(3) }] }); } });
    const app = createApp({ fetch: slow, now: () => NOW });
    const t0 = performance.now();
    const signals = (await (await post(app, body())).json()).signals;
    const took = performance.now() - t0;
    assert.ok(ids(signals).includes("new_domain") && ids(signals).includes("asks_pin"));
    assert.ok(took < 400, `took ${took}`);
});
