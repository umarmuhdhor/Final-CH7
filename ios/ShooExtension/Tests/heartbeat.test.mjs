// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHeartbeat } from "../Resources/heartbeat.js";

const INTERVAL = 60 * 1000;

/** `contains` is what browser.permissions.contains resolves to, a function, or null for "no API". */
function world({ contains = true } = {}) {
    let clock = Date.UTC(2026, 9, 22);
    const sent = [];
    const asked = [];
    const permissions =
        contains === null
            ? undefined
            : {
                  contains: async (query) => {
                      asked.push(query);
                      if (typeof contains === "function") return contains();
                      return contains;
                  },
              };
    const heartbeat = createHeartbeat({
        permissions,
        sendNative: async (message) => {
            sent.push(message);
            return { ok: true };
        },
        intervalMs: INTERVAL,
        now: () => clock,
    });
    return { heartbeat, sent, asked, tick: (ms) => (clock += ms) };
}

test("access to every website → allSites: true, asked as every http(s) host", async () => {
    const { heartbeat, sent, asked } = world({ contains: true });
    assert.deepEqual(await heartbeat.beat(), { ok: true });
    assert.deepEqual(sent, [{ type: "heartbeat", allSites: true }]);
    // Never <all_urls>: Safari's "Allow" grant (*://*/*) doesn't cover it, so it read false with full access.
    assert.deepEqual(asked, [{ origins: ["*://*/*"] }]);
});

test("access narrowed to some sites → allSites: false", async () => {
    const { heartbeat, sent } = world({ contains: false });
    await heartbeat.beat();
    assert.deepEqual(sent, [{ type: "heartbeat", allSites: false }]);
});

test("no permissions API → plain heartbeat, no allSites (app keeps the old rule)", async () => {
    const { heartbeat, sent } = world({ contains: null });
    await heartbeat.beat();
    assert.deepEqual(sent, [{ type: "heartbeat" }]);
});

test("permissions.contains throws → plain heartbeat, never a false Off", async () => {
    const { heartbeat, sent } = world({
        contains: () => {
            throw new Error("unsupported");
        },
    });
    await heartbeat.beat();
    assert.deepEqual(sent, [{ type: "heartbeat" }]);
});

test("throttled to one per interval", async () => {
    const { heartbeat, sent, tick } = world();
    await heartbeat.beat();
    assert.deepEqual(await heartbeat.beat(), { ok: true, throttled: true });
    tick(INTERVAL - 1);
    assert.equal((await heartbeat.beat()).throttled, true);
    tick(1);
    await heartbeat.beat();
    assert.equal(sent.length, 2);
});

test("force skips the throttle (permission just changed)", async () => {
    let granted = true;
    const { heartbeat, sent } = world({ contains: () => granted });
    await heartbeat.beat();
    granted = false;
    await heartbeat.beat({ force: true });
    assert.deepEqual(sent, [
        { type: "heartbeat", allSites: true },
        { type: "heartbeat", allSites: false },
    ]);
});
