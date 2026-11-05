// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createReportLog, STORAGE_KEY, DOMAIN_TTL_MS, ID_TTL_MS, MAX_DOMAINS, MAX_IDS } from "../Resources/report-log.js";

function world() {
    const store = {};
    let clock = Date.UTC(2026, 10, 5);
    const make = () =>
        createReportLog({
            storage: {
                get: async (keys) => Object.fromEntries([keys].flat().filter((k) => k in store).map((k) => [k, structuredClone(store[k])])),
                set: async (items) => Object.assign(store, structuredClone(items)),
            },
            now: () => clock,
        });
    return { log: make(), restart: make, store, tick: (ms) => (clock += ms) };
}

test("the record id outlives the background page", async () => {
    const { log, restart } = world();
    assert.equal(await log.recordId("k1"), null);
    await log.saveRecord("k1", "scan_1");
    assert.equal(await restart().recordId("k1"), "scan_1");
});

test("an old record id goes; the list never grows past its cap", async () => {
    const { log, tick, store } = world();
    await log.saveRecord("old", "scan_0");
    tick(ID_TTL_MS);
    assert.equal(await log.recordId("old"), null);
    for (let i = 0; i < MAX_IDS + 5; i++) await log.saveRecord(`k${i}`, `s${i}`);
    assert.equal(Object.keys(store[STORAGE_KEY].ids).length, MAX_IDS);
    assert.equal(await log.recordId(`k${MAX_IDS + 4}`), `s${MAX_IDS + 4}`);
});

test("a domain counts as sent for 24 hours, on this device only by name", async () => {
    const { log, restart, tick } = world();
    assert.equal(await log.sentRecently("scam.site"), false);
    await log.markSent("scam.site");
    assert.equal(await restart().sentRecently("scam.site"), true);
    assert.equal(await log.sentRecently("other.site"), false);
    tick(DOMAIN_TTL_MS);
    assert.equal(await log.sentRecently("scam.site"), false);
});

test("the domain list keeps the newest", async () => {
    const { log, store, tick } = world();
    for (let i = 0; i < MAX_DOMAINS + 3; i++) {
        tick(1000);
        await log.markSent(`d${i}.site`);
    }
    assert.equal(Object.keys(store[STORAGE_KEY].domains).length, MAX_DOMAINS);
    assert.equal(await log.sentRecently("d0.site"), false);
    assert.equal(await log.sentRecently(`d${MAX_DOMAINS + 2}.site`), true);
});

test("parallel writes both land", async () => {
    const { log } = world();
    await Promise.all([log.saveRecord("a", "1"), log.saveRecord("b", "2"), log.markSent("x.site")]);
    assert.equal(await log.recordId("a"), "1");
    assert.equal(await log.recordId("b"), "2");
    assert.equal(await log.sentRecently("x.site"), true);
});

test("storage that throws: nothing rejects, the report just goes in full", async () => {
    const log = createReportLog({ storage: { get: async () => { throw new Error("gone"); }, set: async () => { throw new Error("gone"); } } });
    await log.saveRecord("a", "1");
    await log.markSent("x.site");
    assert.equal(await log.recordId("a"), null);
    assert.equal(await log.sentRecently("x.site"), false);
});
