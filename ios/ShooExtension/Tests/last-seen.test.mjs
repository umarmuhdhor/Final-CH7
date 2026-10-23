// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createLastSeen, INTERVAL_MS } from "../Resources/last-seen.js";

const SESSION = { token: "t0k", apiBaseURL: "https://api.shoo.test/" };

/** Fake world: storage, session, server reply, clock. `fail` makes the server throw. */
function world({ session = SESSION, store = {}, fail = null } = {}) {
    let clock = Date.UTC(2026, 9, 22, 12);
    const calls = [];
    const server = { fail };
    const make = () =>
        createLastSeen({
            storage: {
                get: async (keys) => Object.fromEntries(keys.filter((k) => k in store).map((k) => [k, store[k]])),
                set: async (items) => Object.assign(store, items),
            },
            getSession: async () => session,
            fetchJSON: async (url, init) => {
                calls.push({ url, ...init, body: JSON.parse(init.body) });
                if (server.fail) throw server.fail;
                return { ok: true };
            },
            now: () => clock,
        });
    return { lastSeen: make(), restart: make, calls, store, server, tick: (ms) => (clock += ms), at: () => clock };
}

test("sends PATCH /devices/me with the current ISO time and the device token", async () => {
    const { lastSeen, calls, at } = world();
    assert.deepEqual(await lastSeen.report(), { ok: true, sent: true });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, "https://api.shoo.test/devices/me");
    assert.equal(calls[0].method, "PATCH");
    assert.equal(calls[0].token, "t0k");
    assert.deepEqual(calls[0].body, { extensionLastSeenAt: new Date(at()).toISOString() });
});

test("at most once per hour", async () => {
    const { lastSeen, calls, tick } = world();
    await lastSeen.report();
    tick(INTERVAL_MS - 1);
    assert.deepEqual(await lastSeen.report(), { ok: true, throttled: true });
    tick(1);
    await lastSeen.report();
    assert.equal(calls.length, 2);
});

test("the hour survives a background restart (storage.local)", async () => {
    const { lastSeen, restart, calls, tick } = world();
    await lastSeen.report();
    tick(10 * 60 * 1000);
    assert.equal((await restart().report()).throttled, true);
    assert.equal(calls.length, 1);
});

test("not onboarded → nothing leaves the phone", async () => {
    const { lastSeen, calls } = world({ session: null });
    assert.deepEqual(await lastSeen.report(), { ok: true, skipped: "no_api_url" });
    assert.equal(calls.length, 0);
});

test("failure (server down, 429) never rejects and retries on the next heartbeat", async () => {
    const { lastSeen, calls, store, server } = world({ fail: Object.assign(new Error("HTTP 429"), { status: 429 }) });
    assert.deepEqual(await lastSeen.report(), { ok: true, skipped: "error" });
    assert.deepEqual(store, {});
    server.fail = null;
    assert.deepEqual(await lastSeen.report(), { ok: true, sent: true });
    assert.equal(calls.length, 2);
});

test("overlapping heartbeats share one request", async () => {
    const { lastSeen, calls } = world();
    await Promise.all([lastSeen.report(), lastSeen.report(), lastSeen.report()]);
    assert.equal(calls.length, 1);
});

test("unreadable storage → still sends (never stuck silent)", async () => {
    const calls = [];
    const lastSeen = createLastSeen({
        storage: {
            get: async () => {
                throw new Error("quota");
            },
            set: async () => {
                throw new Error("quota");
            },
        },
        getSession: async () => SESSION,
        fetchJSON: async (url, init) => calls.push(url),
    });
    assert.deepEqual(await lastSeen.report(), { ok: true, sent: true });
    assert.equal((await lastSeen.report()).throttled, true);
    assert.equal(calls.length, 1);
});
