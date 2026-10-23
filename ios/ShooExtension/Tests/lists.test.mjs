// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createLists, candidates, due, applyPage, SOURCES, FULL_EVERY, MAX_AGE, MAX_ENTRIES } from "../Resources/lists.js";
import { PSL_RULES } from "../Resources/psl.js";
import { parseRules, registrableDomain } from "../Resources/domain.js";

const rules = parseRules(PSL_RULES);
const regDomain = (h) => registrableDomain(h, rules);
const HOUR = 3600_000;
const SESSION = { token: "t", apiBaseURL: "https://api.test", aiBaseURL: "https://ai.test/" };

/** Fake world: storage, server responses per source, clock. */
function world({ session = SESSION, server = {}, stored = {} } = {}) {
    let clock = Date.UTC(2026, 9, 21);
    const store = { ...stored };
    const calls = [];
    const lists = createLists({
        storage: { get: async (keys) => Object.fromEntries(keys.filter((k) => k in store).map((k) => [k, structuredClone(store[k])])),
                   set: async (items) => Object.assign(store, structuredClone(items)) },
        getSession: async () => session,
        fetchJSON: async (url, init) => {
            calls.push({ url, token: init.token });
            const handler = Object.entries(server).find(([prefix]) => url.startsWith(prefix))?.[1];
            if (!handler) throw new Error("HTTP 404");
            return handler(new URL(url).searchParams.get("since"));
        },
        registrableDomain: regDomain,
        now: () => clock,
    });
    return { lists, store, calls, tick: (ms) => (clock += ms), now: () => clock };
}

const page = (domains, nextSince, removed) => ({ domains: domains.map((domain) => ({ domain, addedAt: "2026-10-20T00:00:00Z" })), nextSince, ...(removed ? { removed: removed.map((domain) => ({ domain, removedAt: "x" })) } : {}) });

test("candidates: hostname down to the registrable domain, never above", () => {
    assert.deepEqual(candidates("a.b.scam.site", "scam.site"), ["a.b.scam.site", "b.scam.site", "scam.site"]);
    assert.deepEqual(candidates("login.bca-x.vercel.app", "bca-x.vercel.app"), ["login.bca-x.vercel.app", "bca-x.vercel.app"]);
    assert.deepEqual(candidates("WWW.Shop.co.id.", "shop.co.id"), ["www.shop.co.id", "shop.co.id"]);
});

test("due: full first, then incremental per source interval, full again after 24 h", () => {
    const shoo = SOURCES[0];
    assert.equal(due({}, shoo, 0), "full");
    assert.equal(due({ fullAt: 0, fetchedAt: 0 }, shoo, HOUR - 1), null);
    assert.equal(due({ fullAt: 0, fetchedAt: 0 }, shoo, HOUR), "incremental");
    assert.equal(due({ fullAt: 0, fetchedAt: FULL_EVERY - 1 }, shoo, FULL_EVERY), "full");
});

test("applyPage adds, lowercases and removes", () => {
    const map = applyPage(new Map(), page(["Scam.site", "b.xyz"], "c1"));
    applyPage(map, page([], "c2", ["b.xyz"]));
    assert.deepEqual([...map.keys()], ["scam.site"]);
});

/** A map already at MAX_ENTRIES: full0.site … full{N-1}.site, addedAt from `at(i)`. */
function fullMap(at = () => "2026-10-01T00:00:00Z") {
    const map = new Map();
    for (let i = 0; i < MAX_ENTRIES; i++) map.set(`full${i}.site`, at(i));
    return map;
}

test("applyPage on a full map keeps the new delta domains, evicting the oldest", () => {
    const map = fullMap((i) => (i === 7 ? "2026-09-01T00:00:00Z" : i === 3 ? null : "2026-10-01T00:00:00Z"));
    applyPage(map, page(["new1.site", "new2.site"], "c1"));
    assert.equal(map.size, MAX_ENTRIES);
    assert.ok(map.has("new1.site") && map.has("new2.site"));
    assert.ok(!map.has("full3.site"), "null addedAt counts as oldest");
    assert.ok(!map.has("full7.site"), "then the oldest addedAt");
    assert.ok(map.has("full0.site"));
});

test("applyPage on a full map breaks addedAt ties by insertion order (first in goes first)", () => {
    const map = fullMap();
    applyPage(map, { domains: [{ domain: "same-time.site", addedAt: "2026-10-01T00:00:00Z" }] });
    assert.ok(map.has("same-time.site"));
    assert.ok(!map.has("full0.site"));
    assert.ok(map.has("full1.site"));
});

test("applyPage applies removed[] first, so it frees room for the page's new domains", () => {
    const map = fullMap((i) => (i === 0 ? "2026-09-01T00:00:00Z" : "2026-10-01T00:00:00Z"));
    applyPage(map, page(["new.site"], "c1", ["full5.site"]));
    assert.equal(map.size, MAX_ENTRIES);
    assert.ok(map.has("new.site"));
    assert.ok(!map.has("full5.site"));
    assert.ok(map.has("full0.site"), "nothing evicted: the removal made room");
});

test("applyPage re-adding a domain already in a full map never evicts", () => {
    const map = fullMap();
    applyPage(map, { domains: [{ domain: "FULL9.site", addedAt: "2026-10-22T00:00:00Z" }] });
    assert.equal(map.size, MAX_ENTRIES);
    assert.equal(map.get("full9.site"), "2026-10-22T00:00:00Z");
    assert.ok(map.has("full0.site"));
});

test("applyPage into an empty map (full download) keeps every domain in server order", () => {
    const domains = Array.from({ length: 1000 }, (_, i) => `d${i}.site`);
    const map = applyPage(new Map(), page(domains, "c1"));
    assert.deepEqual([...map.keys()], domains);
});

test("applyPage stays fast at the cap (200,000 entries + a delta page)", () => {
    const map = fullMap((i) => `2026-10-${String(1 + (i % 28)).padStart(2, "0")}T00:00:00Z`);
    const delta = page(Array.from({ length: 5000 }, (_, i) => `delta${i}.site`), "c1");
    const start = performance.now();
    applyPage(map, delta);
    const took = performance.now() - start;
    assert.equal(map.size, MAX_ENTRIES);
    assert.ok(map.has("delta0.site") && map.has("delta4999.site"));
    assert.ok(took < 1000, `took ${took.toFixed(0)} ms`); // generous for slow CI; expect well under 200 ms
});

test("not set up → no download, no match (layer 2 still runs elsewhere)", async () => {
    const w = world({ session: null });
    await w.lists.refresh();
    assert.equal(w.calls.length, 0);
    assert.equal(await w.lists.match("scam.site"), null);
});

test("downloads both lists with the device token, then matches host and parents", async () => {
    const w = world({ server: {
        "https://api.test/blocklist": () => page(["bca-verifikasi.site"], "s1"),
        "https://ai.test/public-blocklist": () => page(["promo-undian.click", "evil.github.io"], "p1"),
    } });
    await w.lists.refresh();
    assert.ok(w.calls.every((c) => c.token === "t"));
    assert.ok(w.calls.some((c) => c.url === "https://ai.test/public-blocklist")); // trailing slash on base handled
    assert.deepEqual(await w.lists.match("login.bca-verifikasi.site"), { source: "shoo", domain: "bca-verifikasi.site", addedAt: "2026-10-20T00:00:00Z" });
    assert.equal((await w.lists.match("www.promo-undian.click")).source, "public");
    assert.equal((await w.lists.match("evil.github.io")).domain, "evil.github.io");
    assert.equal(await w.lists.match("good.github.io"), null); // never matches above the registrable domain
    assert.equal(await w.lists.match("tokopedia.com"), null);
});

test("incremental refresh uses since, applies removed[]; nothing else is sent", async () => {
    let shooCalls = 0;
    const w = world({ server: {
        "https://api.test/blocklist": (since) => {
            shooCalls++;
            if (!since) return page(["a.site", "b.site"], "s1");
            if (since === "s1") return page(["c.site"], "s2", ["a.site"]);
            return page([], since);
        },
        "https://ai.test/public-blocklist": () => page([], "p1"),
    } });
    await w.lists.refresh();
    w.tick(HOUR);
    await w.lists.refresh();
    assert.equal(await w.lists.match("a.site"), null);
    assert.ok(await w.lists.match("b.site"));
    assert.ok(await w.lists.match("c.site"));
    assert.ok(w.calls.every((c) => !/[?&](url|domain|host)=/.test(c.url)), "no browsing data in requests");
    assert.ok(shooCalls >= 3);
});

test("lists survive a background restart (storage.local)", async () => {
    const first = world({ server: { "https://api.test/blocklist": () => page(["scam.site"], "s1"), "https://ai.test/public-blocklist": () => page([], "p1") } });
    await first.lists.refresh();
    const second = world({ session: null, stored: first.store }); // offline + not reachable now
    assert.ok(await second.lists.match("scam.site"));
});

test("a copy older than 7 days is not trusted", async () => {
    const w = world({ server: { "https://api.test/blocklist": () => page(["scam.site"], "s1"), "https://ai.test/public-blocklist": () => page([], "p1") } });
    await w.lists.refresh();
    const offline = world({ session: null, stored: w.store });
    offline.tick(MAX_AGE + 1);
    assert.equal(await offline.lists.match("scam.site"), null);
});

test("server down → keeps the old copy, match never rejects", async () => {
    let up = true;
    const w = world({ server: {
        "https://api.test/blocklist": () => { if (!up) throw new Error("down"); return page(["scam.site"], "s1"); },
        "https://ai.test/public-blocklist": () => { throw new Error("down"); },
    } });
    await w.lists.refresh();
    up = false;
    w.tick(FULL_EVERY);
    await w.lists.refresh();
    assert.ok(await w.lists.match("scam.site"));
});

test("paging stops when caught up (empty page or same cursor)", async () => {
    let n = 0;
    const w = world({ server: {
        "https://api.test/blocklist": (since) => { n++; return since === "s2" ? page([], "s2") : page([`d${n}.site`], since ? "s2" : "s1"); },
        "https://ai.test/public-blocklist": () => page([], null),
    } });
    await w.lists.refresh();
    assert.equal(n, 3); // full → s1 → s2 → empty
    assert.ok(await w.lists.match("d1.site"));
    assert.ok(await w.lists.match("d2.site"));
});
