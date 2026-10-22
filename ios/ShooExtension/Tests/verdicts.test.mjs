// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createVerdicts, retryAfterMs } from "../Resources/verdicts.js";

const SESSION = { token: "t", apiBaseURL: "https://api.test/" };
const SAFE = { value: "safe", byDeviceId: "g1", byName: "Andi", decidedAt: "2026-10-21T10:00:00.000Z" };
const httpError = (status, retryAfter = null) => Object.assign(new Error(`HTTP ${status}`), { status, retryAfter });

/** Fake server: `responses` is consumed one per call (a value, or an Error to throw). */
function world(responses, { session = SESSION } = {}) {
    let clock = Date.UTC(2026, 9, 22);
    const calls = [];
    const verdicts = createVerdicts({
        getSession: async () => session,
        fetchJSON: async (url, init) => {
            calls.push({ url, token: init.token, method: init.method });
            const next = responses.shift();
            if (next instanceof Error) throw next;
            return next;
        },
        now: () => clock,
    });
    return { verdicts, calls, tick: (ms) => (clock += ms) };
}

test("GET /verdicts with the device token and an encoded domain", async () => {
    const { verdicts, calls } = world([{ verdict: SAFE }]);
    assert.deepEqual(await verdicts.lookup("bansos klaim.example"), { ok: true, verdict: SAFE });
    assert.deepEqual(calls, [{ url: "https://api.test/verdicts?domain=bansos%20klaim.example", token: "t", method: "GET" }]);
});

test("cached for a minute; fresh (block screen) always asks", async () => {
    const { verdicts, calls, tick } = world([{ verdict: null }, { verdict: SAFE }, { verdict: SAFE }]);
    await verdicts.lookup("a.example");
    tick(30_000);
    assert.equal((await verdicts.lookup("a.example")).verdict, null);
    assert.equal(calls.length, 1);
    assert.equal((await verdicts.lookup("a.example", { fresh: true })).verdict.value, "safe");
    tick(61_000);
    await verdicts.lookup("a.example");
    assert.equal(calls.length, 3);
});

test("429 is 'retry later', not verdict null: last known verdict is kept and the server isn't called again", async () => {
    const { verdicts, calls, tick } = world([{ verdict: SAFE }, httpError(429, "7"), { verdict: SAFE }]);
    await verdicts.lookup("a.example");
    const limited = await verdicts.lookup("a.example", { fresh: true });
    assert.deepEqual(limited, { ok: true, verdict: SAFE, rateLimited: true, retryAfterMs: 7000 });

    tick(3000);
    const still = await verdicts.lookup("b.example", { fresh: true }); // limit is per device, not per domain
    assert.equal(still.rateLimited, true);
    assert.equal(still.retryAfterMs, 4000);
    assert.equal(calls.length, 2);

    tick(4000);
    assert.deepEqual(await verdicts.lookup("a.example", { fresh: true }), { ok: true, verdict: SAFE });
    assert.equal(calls.length, 3);
});

test("429 never overwrites the cache with null", async () => {
    const { verdicts, tick } = world([{ verdict: SAFE }, httpError(429, "2")]);
    await verdicts.lookup("a.example");
    await verdicts.lookup("a.example", { fresh: true });
    tick(2000);
    assert.equal((await verdicts.lookup("a.example")).verdict.value, "safe"); // cache still valid, still safe
});

test("other errors and missing session → null, never throws", async () => {
    assert.deepEqual(await world([httpError(500)]).verdicts.lookup("a.example"), { ok: true, verdict: null, skipped: "error" });
    assert.deepEqual(await world([], { session: null }).verdicts.lookup("a.example"), { ok: true, verdict: null, skipped: "no_api_url" });
});

test("Retry-After: seconds or HTTP-date, clamped to 1 s … 5 min, default one window", () => {
    const now = Date.UTC(2026, 9, 22);
    assert.equal(retryAfterMs("3", now), 3000);
    assert.equal(retryAfterMs(new Date(now + 20_000).toUTCString(), now), 20_000);
    assert.equal(retryAfterMs(null, now), 10_000);
    assert.equal(retryAfterMs("soon", now), 10_000);
    assert.equal(retryAfterMs("0", now), 1000);
    assert.equal(retryAfterMs("9999", now), 300_000);
});
