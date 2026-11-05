// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createDeviceData, OWNER_KEY } from "../Resources/device-data.js";

function world(stored = {}) {
    const store = { ...stored };
    let wiped = 0;
    const data = createDeviceData({
        storage: {
            get: async (keys) => Object.fromEntries([keys].flat().filter((k) => k in store).map((k) => [k, store[k]])),
            set: async (items) => Object.assign(store, items),
            clear: async () => { for (const key of Object.keys(store)) delete store[key]; },
        },
        onWipe: () => wiped++,
    });
    return { data, store, wipes: () => wiped };
}
const SITES = { "blockMemory.v1": { "scam.site": { domain: "scam.site" } } };

test("an update keeps what the phone already has: no owner yet, a device signed in", async () => {
    const w = world(SITES);
    await w.data.sync("dev_1");
    assert.equal(w.wipes(), 0);
    assert.deepEqual(w.store, { ...SITES, [OWNER_KEY]: "dev_1" });
});

test("same device: nothing happens", async () => {
    const w = world({ ...SITES, [OWNER_KEY]: "dev_1" });
    await w.data.sync("dev_1");
    assert.equal(w.wipes(), 0);
    assert.ok("blockMemory.v1" in w.store);
});

test("account deleted: everything from that device goes, once", async () => {
    const w = world({ ...SITES, [OWNER_KEY]: "dev_1" });
    await w.data.sync(null);
    assert.equal(w.wipes(), 1);
    assert.deepEqual(w.store, { [OWNER_KEY]: "" });
    await w.data.sync(null);
    assert.equal(w.wipes(), 1);
});

test("left over from a delete before this version: no owner and nobody signed in wipes too", async () => {
    const w = world(SITES);
    await w.data.sync(null);
    assert.equal(w.wipes(), 1);
    assert.deepEqual(w.store, { [OWNER_KEY]: "" });
});

test("a new device on this phone never sees the old device's data", async () => {
    const w = world({ ...SITES, [OWNER_KEY]: "dev_1" });
    await w.data.sync("dev_2");
    assert.equal(w.wipes(), 1);
    assert.deepEqual(w.store, { [OWNER_KEY]: "dev_2" });
});

test("two pages at once wipe once", async () => {
    const w = world({ ...SITES, [OWNER_KEY]: "dev_1" });
    await Promise.all([w.data.sync(null), w.data.sync(null), w.data.sync(null)]);
    assert.equal(w.wipes(), 1);
});

test("storage that throws never rejects: a page is not held up by this", async () => {
    const data = createDeviceData({ storage: { get: async () => { throw new Error("gone"); } }, onWipe: () => assert.fail("no wipe on unreadable storage") });
    await data.sync(null);
});
