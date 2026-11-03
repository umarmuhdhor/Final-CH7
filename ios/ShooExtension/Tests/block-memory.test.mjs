// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createBlockMemory, memoryKey, TTL_MS, MAX_ENTRIES, STORAGE_KEY } from "../Resources/block-memory.js";
import { PSL_RULES } from "../Resources/psl.js";
import { parseRules, registrableDomain } from "../Resources/domain.js";

const rules = parseRules(PSL_RULES);
const domainOf = (host) => registrableDomain(host, rules);

function fakeStorage(initial = {}) {
    const data = structuredClone(initial);
    return {
        data,
        get: async (key) => (key in data ? { [key]: structuredClone(data[key]) } : {}),
        set: async (items) => Object.assign(data, structuredClone(items)),
    };
}

function world({ initial } = {}) {
    let clock = Date.UTC(2026, 10, 3);
    const storage = fakeStorage(initial);
    const memory = createBlockMemory({ storage, registrableDomain: domainOf, now: () => clock });
    return { memory, storage, tick: (ms) => (clock += ms) };
}

const sig = (id, weight) => ({ id, layer: 3, weight, label: { en: id, id }, labelSimple: { en: id, id }, evidence: "page text" });
const BLOCK = { domain: "bca-aman.co.id", score: 92, signals: [sig("asks_pin", 30), sig("new_domain", 30), sig("urgent_language", 15), sig("cheap_tld", 5)] };

test("memoryKey: registrable domain for an ordinary site", () => {
    assert.equal(memoryKey("https://login.bca-aman.co.id/verify?x=1", domainOf), "bca-aman.co.id");
    assert.equal(memoryKey("https://www.bca-aman.co.id/", domainOf), "bca-aman.co.id");
});

test("memoryKey: one scam on a shared platform never stands for the whole platform", () => {
    // the host itself holds everyone's pages: host + path
    assert.equal(memoryKey("https://docs.google.com/forms/d/e/abc/viewform?usp=sf", domainOf), "docs.google.com/forms/d/e/abc/viewform");
    assert.equal(memoryKey("https://sites.google.com/view/bansos-2026/", domainOf), "sites.google.com/view/bansos-2026");
    assert.equal(memoryKey("https://forms.office.com/r/XyZ", domainOf), "forms.office.com/r/XyZ");
    assert.equal(memoryKey("https://medium.com/@scam/post", domainOf), "medium.com/@scam/post");
    // a user's own subdomain: the full host, whether or not the PSL splits it
    assert.equal(memoryKey("https://alice.medium.com/post", domainOf), "alice.medium.com");
    assert.equal(memoryKey("https://contoso.sharepoint.com/sites/x", domainOf), "contoso.sharepoint.com");
    assert.equal(memoryKey("https://bantuan-bansos.blogspot.com/p.html", domainOf), "bantuan-bansos.blogspot.com");
    assert.equal(memoryKey("https://bucket.s3.amazonaws.com/a.html", domainOf), "bucket.s3.amazonaws.com");
});

test("memoryKey: no key for non-web pages or junk", () => {
    for (const url of ["about:blank", "safari-web-extension://x/blocked.html", "not a url", ""]) assert.equal(memoryKey(url, domainOf), null, url);
});

test("remember → recall the same site, on another page of it too", async () => {
    const { memory } = world();
    await memory.remember("https://login.bca-aman.co.id/verify", BLOCK);
    const entry = await memory.recall("https://bca-aman.co.id/other");
    assert.equal(entry.domain, "bca-aman.co.id");
    assert.equal(entry.score, 92);
    assert.equal(entry.recordId, null);
    assert.equal(await memory.recall("https://bca.co.id/"), null);
});

test("only the 3 heaviest reasons are kept, without evidence (no page text in storage)", async () => {
    const { memory, storage } = world();
    await memory.remember("https://bca-aman.co.id/", BLOCK);
    const { signals } = await memory.recall("https://bca-aman.co.id/");
    assert.deepEqual(signals.map((s) => s.id), ["asks_pin", "new_domain", "urgent_language"]);
    assert.ok(!JSON.stringify(storage.data).includes("page text"));
});

test("a page on a shared platform only remembers that page", async () => {
    const { memory } = world();
    await memory.remember("https://docs.google.com/forms/d/e/scam/viewform", { ...BLOCK, domain: "google.com" });
    assert.ok(await memory.recall("https://docs.google.com/forms/d/e/scam/viewform"));
    assert.equal(await memory.recall("https://docs.google.com/document/d/mine/edit"), null);
    assert.equal(await memory.recall("https://google.com/"), null);
});

test("setRecord attaches the backend's scan id to an existing entry only", async () => {
    const { memory } = world();
    await memory.setRecord("https://bca-aman.co.id/", "scan-1");
    assert.equal(await memory.recall("https://bca-aman.co.id/"), null, "nothing created");
    await memory.remember("https://bca-aman.co.id/", BLOCK);
    await memory.setRecord("https://bca-aman.co.id/x", "scan-1");
    assert.equal((await memory.recall("https://bca-aman.co.id/")).recordId, "scan-1");
});

test("forgetDomain (safe verdict) clears every page under that domain", async () => {
    const { memory } = world();
    await memory.remember("https://docs.google.com/forms/d/e/a/viewform", { ...BLOCK, domain: "google.com" });
    await memory.remember("https://sites.google.com/view/b", { ...BLOCK, domain: "google.com" });
    await memory.remember("https://bca-aman.co.id/", BLOCK);
    await memory.forgetDomain("google.com");
    assert.equal(await memory.recall("https://docs.google.com/forms/d/e/a/viewform"), null);
    assert.equal(await memory.recall("https://sites.google.com/view/b"), null);
    assert.ok(await memory.recall("https://bca-aman.co.id/"));
});

test("an entry expires after 14 days and is removed", async () => {
    const { memory, storage, tick } = world();
    await memory.remember("https://bca-aman.co.id/", BLOCK);
    tick(TTL_MS - 1);
    assert.ok(await memory.recall("https://bca-aman.co.id/"));
    tick(1);
    assert.equal(await memory.recall("https://bca-aman.co.id/"), null);
    assert.deepEqual(storage.data[STORAGE_KEY], {});
});

test(`at most ${MAX_ENTRIES} entries, the oldest go first`, async () => {
    const { memory, storage, tick } = world();
    for (let i = 0; i <= MAX_ENTRIES; i++) {
        await memory.remember(`https://scam${i}.test/`, { ...BLOCK, domain: `scam${i}.test` });
        tick(1);
    }
    assert.equal(Object.keys(storage.data[STORAGE_KEY]).length, MAX_ENTRIES);
    assert.equal(await memory.recall("https://scam0.test/"), null);
    assert.ok(await memory.recall(`https://scam${MAX_ENTRIES}.test/`));
});

test("writes at the same time all land (two tabs blocking at once)", async () => {
    const { memory } = world();
    await Promise.all([
        memory.remember("https://a.example/", { ...BLOCK, domain: "a.example" }),
        memory.remember("https://b.example/", { ...BLOCK, domain: "b.example" }),
    ]);
    assert.ok(await memory.recall("https://a.example/"));
    assert.ok(await memory.recall("https://b.example/"));
});

test("broken storage never throws, it just remembers nothing", async () => {
    const storage = { get: async () => { throw new Error("quota"); }, set: async () => { throw new Error("quota"); } };
    const memory = createBlockMemory({ storage, registrableDomain: domainOf });
    await memory.remember("https://bca-aman.co.id/", BLOCK);
    assert.equal(await memory.recall("https://bca-aman.co.id/"), null);
});

test("junk in storage is ignored", async () => {
    const { memory } = world({ initial: { [STORAGE_KEY]: ["junk"] } });
    assert.equal(await memory.recall("https://bca-aman.co.id/"), null);
    await memory.remember("https://bca-aman.co.id/", BLOCK);
    assert.ok(await memory.recall("https://bca-aman.co.id/"));
});
