// node --test ios/ShooExtension/Tests/*.test.mjs
// #490: what the pill says after POST /analyze answers 200. The whole path runs: background.js `analyze`
// (fake server) → pipeline.js `runScan` → pill.js `decide`. "Low risk" only when layer 3 really answered.
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../Resources/pipeline.js");
await import("../Resources/pill.js"); // view part skips itself outside the browser
const P = globalThis.ShooPipeline;
const { decide } = globalThis.ShooPill;

const SESSION = { ok: true, deviceId: "dev_1", token: "t", mode: "guardian", name: "Rina", apiBaseURL: "https://api.test", aiBaseURL: "https://ai.test" };
const label = { en: "x", id: "x" };
const sig = (id, layer, weight) => ({ id, layer, weight, label, labelSimple: label });

let answer = null; // the raw JSON text /analyze answers with
let generation = 0;
async function boot() {
    let listener;
    const store = {};
    globalThis.browser = {
        storage: {
            local: {
                get: async () => ({}),
                set: async (items) => void Object.assign(store, items),
                remove: async () => {},
                clear: async () => {},
            },
        },
        runtime: {
            sendNativeMessage: async (_app, message) => (message.type === "getSession" ? SESSION : { ok: true }),
            onMessage: { addListener: (fn) => (listener = fn) },
            getURL: (path) => `safari-web-extension://x/${path}`,
        },
        permissions: { contains: async () => true },
    };
    globalThis.fetch = async (url) => {
        if (url.endsWith("/analyze")) return new Response(answer, { status: 200 });
        return new Response(JSON.stringify({ domains: [], nextSince: null, verdict: null }), { status: 200 });
    };
    await import(`../Resources/background.js?boot=${++generation}`);
    return (message) => listener(message);
}
const send = await boot();

/** One page scan with the online check on; returns the last pipeline state and the pill's view of it. */
async function scan(body) {
    answer = JSON.stringify(body);
    let last;
    await P.runScan({
        snapshot: { url: "https://x.test/", domain: "x.test" },
        analyzeLocal: async () => [sig("cheap_tld", 2, 14)],
        analyzeRemote: (snapshot, localSignals) => send({ type: "analyze", snapshot, localSignals }),
        lookupVerdict: async () => null,
        isCurrent: () => true,
        publish: (s) => (last = s),
    });
    return { last, view: decide(null, { scanId: 1, ...last }).view };
}

const UNUSABLE = {
    "empty object": {},
    null: null,
    "error object": { error: "internal", message: "boom" },
    "signals not an array": { signals: { id: "x" } },
    "signals of the wrong shape": { signals: [{ foo: 1 }, "x", null] },
    "weight as a string": { signals: [{ ...sig("new_domain", 3, 20), weight: "20" }] },
    "layer other than 3 or 4": { signals: [sig("new_domain", 2, 20), sig("brand_offsite", 5, 20)] },
};

for (const [name, body] of Object.entries(UNUSABLE)) {
    test(`#490: /analyze 200 with ${name} → not checked, pill says "Online check unavailable"`, async () => {
        const { last, view } = await scan(body);
        assert.equal(last.done, true);
        assert.equal(last.score, 14, "the phone's own layers still count");
        assert.equal(last.onlineChecked, false);
        assert.equal(view.offline, true);
    });
}

test('#490: /analyze 200 with {"signals": []} → checked, nothing found ("Low risk")', async () => {
    const { last, view } = await scan({ signals: [] });
    assert.equal(last.onlineChecked, true);
    assert.equal(view.tone, "safe");
    assert.ok(!("offline" in view));
});

test("#490: a reply with some usable signals is checked; the bad ones are just dropped", async () => {
    const { last } = await scan({ signals: [sig("new_domain", 3, 10), { ...sig("bad", 3, 5), weight: "5" }] });
    assert.equal(last.onlineChecked, true);
    assert.deepEqual(last.signals.map((s) => s.id).sort(), ["cheap_tld", "new_domain"]);
});

test("#490: background marks a body it can't use as skipped bad_body", async () => {
    for (const body of [{}, null, [], "text", 7, { signals: "x" }, { error: "internal" }]) {
        answer = JSON.stringify(body);
        const reply = await send({ type: "analyze", snapshot: { url: "https://x.test/", domain: "x.test" }, localSignals: [] });
        assert.deepEqual(reply, { ok: true, signals: [], skipped: "bad_body" }, JSON.stringify(body));
    }
    answer = JSON.stringify({ signals: [], rdapRegisteredAt: "2026-01-01" });
    const ok = await send({ type: "analyze", snapshot: { url: "https://x.test/", domain: "x.test" }, localSignals: [] });
    assert.deepEqual(ok, { ok: true, signals: [], rdapRegisteredAt: "2026-01-01" });
});
