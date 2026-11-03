// node --test ios/ShooExtension/Tests/*.test.mjs
// Dashboard phase 05b X1: score thresholds from GET /config/public (Safari only).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createThresholds, toThresholds, DEFAULTS, REFRESH_EVERY, MAX_AGE } from "../Resources/thresholds.js";

const HOUR = 3600_000;
const SESSION = { token: "t", apiBaseURL: "https://api.test/" };
const body = (warnAt, blockAt, version) => ({ warnAt, blockAt, version, updatedAt: "2026-11-03T08:00:00.000000Z" });

/** Fake world: storage, one server answer (or error), clock. */
function world({ session = SESSION, answer = body(30, 80, 0), stored = {} } = {}) {
    let clock = Date.UTC(2026, 10, 3);
    const store = { ...stored };
    const calls = [];
    let reply = answer;
    const t = createThresholds({
        storage: { get: async (keys) => Object.fromEntries([keys].flat().filter((k) => k in store).map((k) => [k, structuredClone(store[k])])),
                   set: async (items) => Object.assign(store, structuredClone(items)) },
        getSession: async () => session,
        fetchJSON: async (url, init) => {
            calls.push({ url, token: init.token, method: init.method });
            if (reply instanceof Error) throw reply;
            return structuredClone(reply);
        },
        now: () => clock,
    });
    return { t, store, calls, tick: (ms) => (clock += ms), answer: (r) => (reply = r) };
}

test("toThresholds: server body → pipeline thresholds, secondWarning = clamp(50, warnAt, blockAt)", () => {
    assert.deepEqual(toThresholds(body(30, 80, 0)), { firstWarning: 30, secondWarning: 50, blocked: 80, version: 0 });
    assert.deepEqual(toThresholds(body(35, 70, 7)), { firstWarning: 35, secondWarning: 50, blocked: 70, version: 7 });
    assert.deepEqual(toThresholds(body(55, 90, 8)), { firstWarning: 55, secondWarning: 55, blocked: 90, version: 8 });
});

test("toThresholds: anything outside the fence is refused (null)", () => {
    for (const b of [body(29, 80, 1), body(61, 90, 1), body(30, 49, 1), body(30, 96, 1), body(50, 60, 1), body(30, 80, -1),
                     body("30", 80, 1), body(30.5, 80, 1), null, {}, []]) {
        assert.equal(toThresholds(b), null, JSON.stringify(b));
    }
});

test("first use: built-in values right away, then the server's after the refresh", async () => {
    const w = world({ answer: body(35, 70, 7) });
    assert.deepEqual(await w.t.current(), DEFAULTS); // a page never waits for the download
    await w.t.refresh();
    assert.deepEqual(await w.t.current(), { firstWarning: 35, secondWarning: 50, blocked: 70, version: 7 });
    assert.deepEqual(w.calls, [{ url: "https://api.test/config/public", token: "t", method: "GET" }]);
});

test("cached for an hour, then asked again; a new version replaces the values", async () => {
    const w = world({ answer: body(35, 70, 7) });
    await w.t.refresh();
    w.answer(body(35, 75, 8));
    w.tick(REFRESH_EVERY - 1);
    await w.t.refresh();
    assert.equal(w.calls.length, 1);
    assert.equal((await w.t.current()).blocked, 70);
    w.tick(1);
    await w.t.refresh();
    assert.equal(w.calls.length, 2);
    assert.deepEqual(await w.t.current(), { firstWarning: 35, secondWarning: 50, blocked: 75, version: 8 });
});

test("a failed or invalid answer keeps the last good value", async () => {
    const w = world({ answer: body(35, 70, 7) });
    await w.t.refresh();
    for (const bad of [Object.assign(new Error("HTTP 404"), { status: 404 }), new Error("timeout"), body(10, 99, 9)]) {
        w.answer(bad);
        w.tick(REFRESH_EVERY);
        await w.t.refresh();
        assert.equal((await w.t.current()).version, 7);
    }
});

test("no stored value and the server down → built-in 30/50/80", async () => {
    const w = world({ answer: new Error("HTTP 500") });
    await w.t.refresh();
    assert.deepEqual(await w.t.current(), DEFAULTS);
});

test("not onboarded → nothing is fetched, built-in values", async () => {
    const w = world({ session: null });
    await w.t.refresh();
    assert.equal(w.calls.length, 0);
    assert.deepEqual(await w.t.current(), DEFAULTS);
});

test("survives a restart through storage; older than MAX_AGE is not trusted", async () => {
    const w = world({ answer: body(35, 70, 7) });
    await w.t.refresh();
    const again = world({ stored: w.store, answer: new Error("offline") });
    assert.equal((await again.t.current()).version, 7);
    again.tick(MAX_AGE + 1);
    assert.deepEqual(await again.t.current(), DEFAULTS);
});

test("one download at a time", async () => {
    const w = world();
    await Promise.all([w.t.refresh(), w.t.refresh(), w.t.refresh()]);
    assert.equal(w.calls.length, 1);
});

test("the reply carries only numbers, never the token or the URL", async () => {
    const w = world();
    await w.t.refresh();
    assert.deepEqual(Object.keys(await w.t.current()).sort(), ["blocked", "firstWarning", "secondWarning", "version"]);
});

test("thresholds-client.js applies the background's numbers to ShooPipeline.THRESHOLD", async () => {
    let asked = null;
    globalThis.browser = { runtime: { sendMessage: async (m) => ((asked = m), { ok: true, thresholds: { firstWarning: 35, secondWarning: 50, blocked: 70, version: 7 } }) } };
    await import("../Resources/pipeline.js");
    await import("../Resources/thresholds-client.js");
    await new Promise((r) => setTimeout(r, 0));
    assert.deepEqual(asked, { type: "thresholds" });
    assert.deepEqual({ ...globalThis.ShooPipeline.THRESHOLD }, { firstWarning: 35, secondWarning: 50, blocked: 70 });
    assert.equal(globalThis.ShooPipeline.statusFor(72), "blocked");
    assert.equal(globalThis.ShooPipeline.statusFor(34), "normal");
});

test("Safari loads thresholds-client.js right after pipeline.js; Chrome does not share either new file", () => {
    const manifest = JSON.parse(readFileSync(new URL("../Resources/manifest.json", import.meta.url)));
    const js = manifest.content_scripts[0].js;
    assert.equal(js.indexOf("thresholds-client.js"), js.indexOf("pipeline.js") + 1);
    const shared = readFileSync(new URL("../../../chrome/scripts/shared-files.txt", import.meta.url), "utf8");
    assert.doesNotMatch(shared, /thresholds/);
});
