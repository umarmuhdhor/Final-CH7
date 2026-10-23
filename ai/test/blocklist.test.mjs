// GET /public-blocklist: contract shape, since/removed, allowlist, size cap, rate limit, privacy; Phishing.Database source and the pre-built KV list.
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { createStaticSource } from "../src/blocklist/source.js";
import { BLOCKLIST_LIMITS } from "../src/blocklist/route.js";
import { BRANDS } from "./helpers.mjs";
import { gzipSync, gunzipSync } from "node:zlib";
import { PHISHING_DATABASE, parseHostList, trackFirstSeen, createPhishingDatabaseSource } from "../src/blocklist/phishing-database.js";
import { PREBUILT, buildArtifacts, deltaKey } from "../src/blocklist/prebuilt.js";
import { runBuild, createKvRest } from "../scripts/build-blocklist.mjs";
import { MAX_ENTRIES, applyPage } from "../../ios/ShooExtension/Resources/lists.js";

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

test("size cap: at most MAX_DOMAINS, newest kept", async () => {
    const entries = [];
    for (let i = 0; i < 200_005; i++) entries.push(entry(`shoo-fixture-${i}.xyz`, new Date(Date.UTC(2026, 0, 1) + i * 1000).toISOString()));
    const app = appWith(entries);
    const body = await (await get(app)).json();
    assert.equal(body.domains.length, BLOCKLIST_LIMITS.MAX_DOMAINS);
    assert.ok(!body.domains.some((d) => d.domain === "shoo-fixture-0.xyz"));
    assert.ok(body.domains.some((d) => d.domain === "shoo-fixture-200004.xyz"));
});

test("bad since -> 422 invalid_body; other methods -> 405", async () => {
    const app = appWith(SEED);
    for (const q of ["since=yesterday", "since=", "since=2026-13-45T00:00:00Z", `since=${"9".repeat(200)}`]) {
        const res = await get(app, `/public-blocklist?${q}`);
        assert.equal(res.status, 422, q);
        assert.equal((await res.json()).error.code, "invalid_body");
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

test("review fixes: platform CDNs are allowlisted", async () => {
    const hosts = ["x.sharepoint.com", "storage.googleapis.com", "youtu.be", "t.me", "wa.me", "linktr.ee", "mega.nz"];
    const names = (await (await get(appWith(hosts.map((h) => entry(h, T("01T10")))))).json()).domains;
    assert.deepEqual(names, []);
});

test("review fixes: dates in the future or before 2000 are skipped (cursor cannot be parked)", async () => {
    const app = appWith([entry("a.shoo-fixture-g.xyz", "9999-01-01T00:00:00Z"), entry("shoo-fixture-h.xyz", "+010000-01-01T00:00:00Z"), entry("shoo-fixture-i.xyz", "1999-12-31T00:00:00Z"), entry("shoo-fixture-ok2.xyz", T("01T10"))], { now: () => Date.UTC(2026, 9, 22) });
    const body = await (await get(app)).json();
    assert.deepEqual(body.domains.map((d) => d.domain), ["shoo-fixture-ok2.xyz"]);
    assert.equal(body.nextSince, T("01T10"));
});

test("review fixes: since must be strict ISO 8601 UTC", async () => {
    const app = appWith(SEED);
    for (const q of ["2026-10-22 garbage", "2026-10-22", "2026-10-22T08:00:00+08:00", "2026-10-22T08:00:00"]) {
        assert.equal((await get(app, `/public-blocklist?since=${encodeURIComponent(q)}`)).status, 422, q);
    }
    assert.equal((await get(app, "/public-blocklist?since=2026-10-22T08:00:00Z")).status, 200);
    assert.equal((await get(app, "/public-blocklist?since=2026-10-22T08:00:00.5Z")).status, 200);
});

test("review fixes: a failing source is not retried on every request", async () => {
    let calls = 0;
    let t = 5_000_000_000_000;
    const app = createApp({ now: () => t, blocklistSource: { name: "x", license: "x", entries: async () => { calls++; throw new Error("down"); } } });
    for (let i = 0; i < 5; i++) assert.equal((await get(app)).status, 500);
    assert.equal(calls, 1);
    t += 61_000;
    await get(app);
    assert.equal(calls, 2);
});

test("review fixes: IPv4-mapped IPv6 shares the IPv4 bucket", async () => {
    const app = appWith(SEED, { rateLimit: { limit: 1, windowMs: 60_000 } });
    assert.equal((await get(app, "/public-blocklist", { headers: { "cf-connecting-ip": "203.0.113.50" } })).status, 200);
    assert.equal((await get(app, "/public-blocklist", { headers: { "cf-connecting-ip": "::ffff:203.0.113.50" } })).status, 429);
});

// ---- Phishing.Database source + pre-built list in Workers KV (M5-A, D-imelda-38) ----

const B = (h) => `2026-10-20T${h}:00:00.000Z`; // build timestamps
const DAY = 24 * 60 * 60 * 1000;
const hostsOf = (entries) => entries.map((e) => e.host).sort();

test("phishing-database: the source declares its feed URL and MIT licence", () => {
    assert.match(PHISHING_DATABASE.url, /^https:\/\/raw\.githubusercontent\.com\/Phishing-Database\/Phishing\.Database\/master\/phishing-domains-ACTIVE\.txt$/);
    assert.match(PHISHING_DATABASE.license, /MIT/);
    const source = createPhishingDatabaseSource({ fetchText: async () => "", builtAt: B("00") });
    assert.equal(source.name, PHISHING_DATABASE.name);
    assert.equal(source.license, PHISHING_DATABASE.license);
    assert.equal(typeof source.entries, "function");
});

test("phishing-database: parseHostList keeps one hostname per line, skips blanks, comments and junk", () => {
    const text = "# comment\r\n\r\nshoo-fixture-a.xyz\r\n  login.shoo-fixture-b.top  \n! adblock comment\n0.0.0.0 shoo-fixture-c.xyz\nshoo-fixture-d.site\n";
    assert.deepEqual(parseHostList(text), ["shoo-fixture-a.xyz", "login.shoo-fixture-b.top", "shoo-fixture-d.site"]);
    assert.deepEqual(parseHostList(""), []);
});

test("phishing-database: first sight sets addedAt = build time; later builds keep it", () => {
    const first = trackFirstSeen([], ["a.shoo-fixture-a.xyz", "shoo-fixture-a.xyz", "shoo-fixture-b.top"], B("00"));
    assert.deepEqual(first, [
        { host: "shoo-fixture-a.xyz", addedAt: B("00") },
        { host: "shoo-fixture-b.top", addedAt: B("00") },
    ]);
    const second = trackFirstSeen(first, ["shoo-fixture-a.xyz", "shoo-fixture-b.top", "shoo-fixture-c.site"], B("06"));
    assert.deepEqual(second, [
        { host: "shoo-fixture-a.xyz", addedAt: B("00") },
        { host: "shoo-fixture-b.top", addedAt: B("00") },
        { host: "shoo-fixture-c.site", addedAt: B("06") },
    ]);
});

test("phishing-database: a domain that leaves the feed gets removedAt; it comes back as new", () => {
    const state = [{ host: "shoo-fixture-a.xyz", addedAt: B("00") }, { host: "shoo-fixture-b.top", addedAt: B("00") }];
    const gone = trackFirstSeen(state, ["shoo-fixture-a.xyz"], B("06"));
    assert.deepEqual(gone, [
        { host: "shoo-fixture-a.xyz", addedAt: B("00") },
        { host: "shoo-fixture-b.top", addedAt: B("00"), removedAt: B("06") },
    ]);
    const stillGone = trackFirstSeen(gone, ["shoo-fixture-a.xyz"], B("12"));
    assert.deepEqual(stillGone[1], { host: "shoo-fixture-b.top", addedAt: B("00"), removedAt: B("06") }, "removedAt is not moved forward");
    const back = trackFirstSeen(gone, ["shoo-fixture-a.xyz", "shoo-fixture-b.top"], B("12"));
    assert.deepEqual(back[1], { host: "shoo-fixture-b.top", addedAt: B("12") });
});

test("phishing-database: removed domains are forgotten after the retention window", () => {
    const removedAt = "2026-10-01T00:00:00.000Z";
    const state = [{ host: "shoo-fixture-old.xyz", addedAt: "2026-09-01T00:00:00.000Z", removedAt }];
    const builtAt = new Date(Date.parse(removedAt) + PREBUILT.KEEP_REMOVED_MS + 1000).toISOString();
    assert.deepEqual(trackFirstSeen(state, [], builtAt), []);
    const early = new Date(Date.parse(removedAt) + PREBUILT.KEEP_REMOVED_MS - 1000).toISOString();
    assert.equal(trackFirstSeen(state, [], early).length, 1);
});

test("phishing-database: junk in the previous state or the feed is dropped", () => {
    const out = trackFirstSeen([null, 5, { host: "co.id", addedAt: B("00") }, { host: "shoo-fixture-a.xyz", addedAt: "bad" }], ["127.0.0.1", "http://x", "shoo-fixture-a.xyz", "shoo-fixture-b.top"], B("06"));
    assert.deepEqual(hostsOf(out), ["shoo-fixture-a.xyz", "shoo-fixture-b.top"]);
    assert.equal(out.find((e) => e.host === "shoo-fixture-a.xyz").addedAt, B("06"), "a bad stored date counts as new");
});

test("phishing-database: entries() fetches the feed URL and refuses a suspiciously small feed", async () => {
    const asked = [];
    const source = createPhishingDatabaseSource({ fetchText: async (url) => (asked.push(url), "shoo-fixture-a.xyz\nshoo-fixture-b.top\n"), builtAt: B("00"), minHosts: 2 });
    assert.deepEqual(hostsOf(await source.entries()), ["shoo-fixture-a.xyz", "shoo-fixture-b.top"]);
    assert.deepEqual(asked, [PHISHING_DATABASE.url]);
    const tiny = createPhishingDatabaseSource({ fetchText: async () => "shoo-fixture-a.xyz\n", builtAt: B("00"), minHosts: 2 });
    await assert.rejects(tiny.entries(), /too small/);
});

test("prebuilt: full list has the contract shape and still applies the allowlist", () => {
    const official = BRANDS.brands.flatMap((b) => b.domains);
    const entries = [
        ...official.map((d) => ({ host: d, addedAt: B("00") })),
        ...["wordpress.com", "github.io", "google.com"].map((d) => ({ host: d, addedAt: B("00") })),
        { host: "shoo-fixture-ok.xyz", addedAt: B("00") },
    ];
    const { full, deltas, meta } = buildArtifacts({ entries, builtAt: B("00"), previousMeta: null, source: { name: "t", license: "t" } });
    assertShape(full);
    assert.deepEqual(full, { domains: [{ domain: "shoo-fixture-ok.xyz", addedAt: B("00") }], nextSince: B("00") });
    assert.deepEqual(deltas, []);
    assert.deepEqual(meta.builds, [B("00")]);
    assert.equal(meta.active, 1);
});

test("prebuilt: one delta per earlier build, equal to what since would return", () => {
    const entries = [
        { host: "shoo-fixture-a.xyz", addedAt: B("00") },
        { host: "shoo-fixture-b.top", addedAt: B("06") },
        { host: "shoo-fixture-c.site", addedAt: B("00"), removedAt: B("12") },
        { host: "shoo-fixture-d.xyz", addedAt: B("12") },
    ];
    const previousMeta = { builds: [B("06"), B("00")] };
    const { full, deltas, meta } = buildArtifacts({ entries, builtAt: B("12"), previousMeta, source: { name: "t", license: "t" } });
    assert.deepEqual(meta.builds, [B("12"), B("06"), B("00")]);
    assert.deepEqual(full.domains.map((d) => d.domain), ["shoo-fixture-a.xyz", "shoo-fixture-b.top", "shoo-fixture-d.xyz"]);
    assert.equal(full.nextSince, B("12"));
    assert.deepEqual(deltas.map((d) => d.since), [B("06"), B("00")]);
    for (const d of deltas) assertShape(d.body);
    assert.deepEqual(deltas[0].body, { domains: [{ domain: "shoo-fixture-d.xyz", addedAt: B("12") }], removed: [{ domain: "shoo-fixture-c.site", removedAt: B("12") }], nextSince: B("12") });
    assert.deepEqual(deltas[1].body.domains.map((d) => d.domain), ["shoo-fixture-b.top", "shoo-fixture-d.xyz"]);
    assert.equal(deltaKey(B("06")), `delta:${B("06")}`);
});

test("prebuilt: builds older than the retention window get no delta", () => {
    const builtAt = B("12");
    const old = new Date(Date.parse(builtAt) - PREBUILT.RETENTION_MS - 1000).toISOString();
    const { deltas, meta } = buildArtifacts({ entries: [], builtAt, previousMeta: { builds: [B("06"), old, "junk"] }, source: { name: "t", license: "t" } });
    assert.deepEqual(deltas.map((d) => d.since), [B("06")]);
    assert.deepEqual(meta.builds, [builtAt, B("06")]);
});

test("size cap leaves the extension room for deltas (lists.js MAX_ENTRIES)", () => {
    assert.ok(BLOCKLIST_LIMITS.MAX_DOMAINS <= MAX_ENTRIES - BLOCKLIST_LIMITS.DELTA_HEADROOM);
    assert.ok(BLOCKLIST_LIMITS.DELTA_HEADROOM >= 10_000);
});

test("prebuilt: a phone holding the full list still takes the next build's new domains", () => {
    const source = { name: "t", license: "t" };
    const entries = [];
    for (let i = 0; i < 200_003; i++) entries.push({ host: `shoo-fixture-${i}.xyz`, addedAt: B("06") });
    const first = buildArtifacts({ entries, builtAt: B("06"), previousMeta: null, source });
    const phone = applyPage(new Map(), first.full);
    const fresh = ["shoo-fixture-new-a.xyz", "shoo-fixture-new-b.xyz"];
    for (const host of fresh) entries.push({ host, addedAt: B("12") });
    const second = buildArtifacts({ entries, builtAt: B("12"), previousMeta: first.meta, source });
    const delta = second.deltas.find((d) => d.since === first.full.nextSince);
    assert.ok(delta, "a delta exists for the cursor the phone holds");
    applyPage(phone, delta.body);
    for (const host of fresh) assert.ok(phone.has(host), `${host} reached the phone`);
});

test("prebuilt: at most MAX_DOMAINS, newest kept", () => {
    const entries = [];
    for (let i = 0; i < 200_003; i++) entries.push({ host: `shoo-fixture-${i}.xyz`, addedAt: i < 3 ? B("00") : B("06") });
    const { full, meta } = buildArtifacts({ entries, builtAt: B("06"), previousMeta: null, source: { name: "t", license: "t" } });
    assert.equal(full.domains.length, BLOCKLIST_LIMITS.MAX_DOMAINS);
    assert.equal(meta.active, BLOCKLIST_LIMITS.MAX_DOMAINS);
    assert.ok(!full.domains.some((d) => d.addedAt === B("00")));
});

// A Workers KV binding as the Worker sees it: get(key, "json" | "stream" | "text").
function fakeKvBinding(values, { fail = false } = {}) {
    const reads = [];
    return {
        reads,
        async get(key, type) {
            reads.push(key);
            if (fail) throw new Error("kv secret detail");
            const v = values[key];
            if (v === undefined) return null;
            const text = typeof v === "string" ? v : JSON.stringify(v);
            if (type === "json") return JSON.parse(text);
            if (type === "stream") return new Response(text).body;
            return text;
        },
    };
}

function kvWorld() {
    const full = { domains: [{ domain: "shoo-fixture-a.xyz", addedAt: B("00") }, { domain: "shoo-fixture-b.top", addedAt: B("12") }], nextSince: B("12") };
    const d06 = { domains: [{ domain: "shoo-fixture-b.top", addedAt: B("12") }], removed: [{ domain: "shoo-fixture-c.site", removedAt: B("12") }], nextSince: B("12") };
    const d00 = { domains: [{ domain: "shoo-fixture-b.top", addedAt: B("12") }], nextSince: B("12") };
    return {
        full, d06, d00,
        values: { [PREBUILT.META_KEY]: { v: 1, builtAt: B("12"), builds: [B("12"), B("06"), B("00")] }, [PREBUILT.FULL_KEY]: full, [deltaKey(B("06"))]: d06, [deltaKey(B("00"))]: d00 },
    };
}
const kvGet = async (app, kv, query = "") => {
    const res = await app.request(`/public-blocklist${query}`, {}, { BLOCKLIST_KV: kv });
    return { res, body: res.status === 200 ? await res.json() : null };
};
const q = (since) => `?since=${encodeURIComponent(since)}`;

test("kv: without since the pre-built full list is served as JSON", async () => {
    const w = kvWorld();
    const { res, body } = await kvGet(createApp(), fakeKvBinding(w.values));
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type"), /application\/json/);
    assert.equal(res.headers.get("cache-control"), "no-store");
    assertShape(body);
    assert.deepEqual(body, w.full);
});

test("kv: since = a build time serves that build's delta; between builds the older build's delta", async () => {
    const w = kvWorld();
    const app = createApp();
    assert.deepEqual((await kvGet(app, fakeKvBinding(w.values), q(B("06")))).body, w.d06);
    assert.deepEqual((await kvGet(app, fakeKvBinding(w.values), q("2026-10-20T07:30:00Z"))).body, w.d06);
    assert.deepEqual((await kvGet(app, fakeKvBinding(w.values), q("2026-10-20T03:00:00Z"))).body, w.d00);
});

test("kv: caught up (since >= newest build) -> empty list, nextSince = since, no list read", async () => {
    const w = kvWorld();
    const kv = fakeKvBinding(w.values);
    assert.deepEqual((await kvGet(createApp(), kv, q(B("12")))).body, { domains: [], nextSince: B("12") });
    assert.deepEqual(kv.reads, [PREBUILT.META_KEY]);
});

test("kv: since older than every kept build -> the full list", async () => {
    const w = kvWorld();
    assert.deepEqual((await kvGet(createApp(), fakeKvBinding(w.values), q("2026-10-01T00:00:00Z"))).body, w.full);
});

test("kv: a missing delta falls back to the full list", async () => {
    const w = kvWorld();
    delete w.values[deltaKey(B("06"))];
    assert.deepEqual((await kvGet(createApp(), fakeKvBinding(w.values), q(B("06")))).body, w.full);
});

test("kv: nothing built yet -> honest empty list", async () => {
    const app = createApp();
    assert.deepEqual((await kvGet(app, fakeKvBinding({}))).body, { domains: [], nextSince: null });
    assert.deepEqual((await kvGet(app, fakeKvBinding({}), q(B("06")))).body, { domains: [], nextSince: B("06") });
});

test("kv: a KV failure is a fixed 500, never a leak", async () => {
    const { res } = await kvGet(createApp(), fakeKvBinding({}, { fail: true }));
    assert.equal(res.status, 500);
    assert.doesNotMatch(await res.text(), /secret/);
});

test("kv: bad since is still 422 and the rate limit still applies", async () => {
    const w = kvWorld();
    const app = createApp({ rateLimit: { limit: 1, windowMs: 60_000 } });
    const kv = fakeKvBinding(w.values);
    const bad = await app.request("/public-blocklist?since=yesterday", { headers: { "cf-connecting-ip": "203.0.113.1" } }, { BLOCKLIST_KV: kv });
    assert.equal(bad.status, 422);
    assert.deepEqual(kv.reads, [], "a bad request never reads KV");
    const limited = await app.request("/public-blocklist", { headers: { "cf-connecting-ip": "203.0.113.1" } }, { BLOCKLIST_KV: kv });
    assert.equal(limited.status, 429);
});

test("kv: the build list is cached per isolate (one meta read per refresh window)", async () => {
    let t = 1_000_000;
    const w = kvWorld();
    const kv = fakeKvBinding(w.values);
    const app = createApp({ now: () => t });
    await kvGet(app, kv);
    await kvGet(app, kv);
    assert.equal(kv.reads.filter((k) => k === PREBUILT.META_KEY).length, 1);
    t += PREBUILT.META_CACHE_MS + 1;
    await kvGet(app, kv);
    assert.equal(kv.reads.filter((k) => k === PREBUILT.META_KEY).length, 2);
});

// The build script's KV side: get(key) -> bytes | null, putMany([{ key, value, expirationTtl? }]).
function fakeKvStore(initial = {}) {
    const values = new Map(Object.entries(initial));
    const batches = [];
    return {
        values,
        batches,
        async get(key) {
            const v = values.get(key);
            return v === undefined ? null : typeof v === "string" ? new TextEncoder().encode(v) : v;
        },
        async putMany(items) {
            batches.push(items.map((i) => i.key));
            for (const i of items) values.set(i.key, i.value);
        },
    };
}
const feed = (...hosts) => async () => hosts.join("\n") + "\n";

test("build script: first run writes state, full and meta (meta last), no deltas", async () => {
    const kv = fakeKvStore();
    const meta = await runBuild({ kv, fetchText: feed("shoo-fixture-a.xyz", "shoo-fixture-b.top", "google.com"), now: () => Date.parse(B("00")), minHosts: 1 });
    assert.equal(meta.active, 2);
    assert.equal(meta.source, PHISHING_DATABASE.name);
    assert.deepEqual(kv.batches.at(-1), [PREBUILT.META_KEY], "meta is written alone, after everything else");
    assert.deepEqual(kv.batches[0].sort(), [PREBUILT.FULL_KEY, PREBUILT.STATE_KEY].sort());
    const full = JSON.parse(kv.values.get(PREBUILT.FULL_KEY));
    assertShape(full);
    assert.deepEqual(full.domains.map((d) => d.domain), ["shoo-fixture-a.xyz", "shoo-fixture-b.top"]);
    const state = JSON.parse(gunzipSync(kv.values.get(PREBUILT.STATE_KEY)).toString("utf8"));
    assert.ok(state.every((e) => e.addedAt === B("00")));
});

test("build script: second run keeps first-seen dates and writes a delta for the first build", async () => {
    const kv = fakeKvStore();
    // Four domains, so one new one stays within PREBUILT.MAX_NEW_SHARE.
    const kept = ["shoo-fixture-a.xyz", "shoo-fixture-d.xyz", "shoo-fixture-e.xyz"];
    await runBuild({ kv, fetchText: feed(...kept, "shoo-fixture-b.top"), now: () => Date.parse(B("00")), minHosts: 1 });
    await runBuild({ kv, fetchText: feed(...kept, "shoo-fixture-c.site"), now: () => Date.parse(B("06")), minHosts: 1 });
    const delta = JSON.parse(kv.values.get(deltaKey(B("00"))));
    assert.deepEqual(delta, { domains: [{ domain: "shoo-fixture-c.site", addedAt: B("06") }], removed: [{ domain: "shoo-fixture-b.top", removedAt: B("06") }], nextSince: B("06") });
    const full = JSON.parse(kv.values.get(PREBUILT.FULL_KEY));
    assert.deepEqual(full.domains, [...kept.map((domain) => ({ domain, addedAt: B("00") })), { domain: "shoo-fixture-c.site", addedAt: B("06") }]);
    assert.deepEqual(JSON.parse(kv.values.get(PREBUILT.META_KEY)).builds, [B("06"), B("00")]);
});

test("build script: a big drop in the list aborts before anything is written", async () => {
    const kv = fakeKvStore();
    const many = Array.from({ length: 10 }, (_, i) => `shoo-fixture-${i}.xyz`);
    await runBuild({ kv, fetchText: feed(...many), now: () => Date.parse(B("00")), minHosts: 1 });
    const before = kv.batches.length;
    await assert.rejects(runBuild({ kv, fetchText: feed(...many.slice(0, 4)), now: () => Date.parse(B("06")), minHosts: 1 }), /drop/);
    assert.equal(kv.batches.length, before);
});

test("build script: a flood of new domains aborts before anything is written", async () => {
    const kv = fakeKvStore();
    const many = Array.from({ length: 10 }, (_, i) => `shoo-fixture-${i}.xyz`);
    await runBuild({ kv, fetchText: feed(...many), now: () => Date.parse(B("00")), minHosts: 1 });
    const before = kv.batches.length;
    const flood = Array.from({ length: Math.floor(10 * PREBUILT.MAX_NEW_SHARE) + 1 }, (_, i) => `shoo-flood-${i}.top`);
    await assert.rejects(runBuild({ kv, fetchText: feed(...many, ...flood), now: () => Date.parse(B("06")), minHosts: 1 }), /new domains/);
    assert.equal(kv.batches.length, before);
    assert.equal(JSON.parse(kv.values.get(PREBUILT.META_KEY)).builtAt, B("00"), "the last good build keeps being served");
});

test("build script: normal growth is published", async () => {
    const kv = fakeKvStore();
    const many = Array.from({ length: 10 }, (_, i) => `shoo-fixture-${i}.xyz`);
    await runBuild({ kv, fetchText: feed(...many), now: () => Date.parse(B("00")), minHosts: 1 });
    const grown = Array.from({ length: Math.floor(10 * PREBUILT.MAX_NEW_SHARE) }, (_, i) => `shoo-new-${i}.top`);
    const meta = await runBuild({ kv, fetchText: feed(...many, ...grown), now: () => Date.parse(B("06")), minHosts: 1 });
    assert.equal(meta.active, 10 + grown.length);
    assert.equal(JSON.parse(kv.values.get(PREBUILT.META_KEY)).builtAt, B("06"));
});

test("build script: the first build is exempt from the growth guard", async () => {
    const kv = fakeKvStore();
    const many = Array.from({ length: 50 }, (_, i) => `shoo-fixture-${i}.xyz`);
    const meta = await runBuild({ kv, fetchText: feed(...many), now: () => Date.parse(B("00")), minHosts: 1 });
    assert.equal(meta.active, 50);
});

test("build script: a broken feed or stored state never writes", async () => {
    const kv = fakeKvStore({ [PREBUILT.STATE_KEY]: gzipSync("not json") });
    await assert.rejects(runBuild({ kv, fetchText: feed("shoo-fixture-a.xyz"), now: () => Date.parse(B("00")), minHosts: 1 }));
    await assert.rejects(runBuild({ kv: fakeKvStore(), fetchText: async () => { throw new Error("feed down"); }, now: () => Date.parse(B("00")) }), /feed down/);
    assert.equal(kv.batches.length, 0);
});

test("build script: KV REST client uses the bulk API, base64 for bytes, and never prints the token", async () => {
    const calls = [];
    const fetchFake = async (url, init = {}) => {
        calls.push({ url, init });
        if (init.method === "PUT") return Response.json({ success: true, result: { successful_key_count: 2, unsuccessful_keys: [] } });
        return url.endsWith("/values/missing") ? new Response("", { status: 404 }) : new Response(new Uint8Array([1, 2, 3]));
    };
    const kv = createKvRest({ accountId: "acc", namespaceId: "ns", token: "TOKEN-XYZ", fetch: fetchFake });
    assert.equal(await kv.get("missing"), null);
    assert.deepEqual([...(await kv.get("state"))], [1, 2, 3]);
    await kv.putMany([{ key: "full", value: "{}" }, { key: "state", value: new Uint8Array([1, 2]), expirationTtl: 120 }]);
    const put = calls.at(-1);
    assert.equal(put.url, "https://api.cloudflare.com/client/v4/accounts/acc/storage/kv/namespaces/ns/bulk");
    assert.equal(put.init.headers.authorization, "Bearer TOKEN-XYZ");
    assert.deepEqual(JSON.parse(put.init.body), [{ key: "full", value: "{}" }, { key: "state", value: "AQI=", base64: true, expiration_ttl: 120 }]);
    const failing = createKvRest({ accountId: "acc", namespaceId: "ns", token: "TOKEN-XYZ", fetch: async () => new Response("nope TOKEN-XYZ", { status: 403 }) });
    await assert.rejects(failing.putMany([{ key: "a", value: "b" }]), (err) => !String(err.message).includes("TOKEN-XYZ") && /403/.test(err.message));
    const partial = createKvRest({ accountId: "acc", namespaceId: "ns", token: "t", fetch: async () => Response.json({ success: true, result: { unsuccessful_keys: ["a"] } }) });
    await assert.rejects(partial.putMany([{ key: "a", value: "b" }]), /a/);
});
