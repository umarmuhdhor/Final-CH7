// node --test ios/ShooExtension/Tests
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/pipeline.js"); // plain script → defines globalThis.ShooPipeline
const P = globalThis.ShooPipeline;

const fixture = (name) =>
    JSON.parse(readFileSync(new URL(`../../../contracts/fixtures/${name}.json`, import.meta.url), "utf8"));

const snapshotFor = (result) => ({ url: result.url, domain: result.domain, title: "", lang: null, text: "", forms: [], imageAlts: [], capturedAt: "" });

/** Runs a scan with fakes; returns every published state and which deps were called. */
async function run({ local = [], remote = [], verdict = null, current = () => true, snapshot } = {}) {
    const states = [];
    const calls = { remote: 0, verdict: [] };
    await P.runScan({
        snapshot: snapshot ?? { url: "https://x.test/", domain: "x.test" },
        analyzeLocal: async () => (typeof local === "function" ? local() : local),
        analyzeRemote: async () => {
            calls.remote++;
            return typeof remote === "function" ? remote() : remote;
        },
        lookupVerdict: async (domain) => {
            calls.verdict.push(domain);
            return typeof verdict === "function" ? verdict() : verdict;
        },
        isCurrent: current,
        publish: (s) => states.push(s),
    });
    return { states, calls, last: states.at(-1) };
}

const sig = (id, layer, weight) => ({
    id, layer, weight,
    label: { en: id, id: id },
    labelSimple: { en: id, id: id },
});

test("thresholds 29/30/49/50/79/80", () => {
    assert.deepEqual([29, 30, 49, 50, 79, 80, 100].map(P.statusFor),
        ["normal", "warning", "warning", "warning", "warning", "blocked", "blocked"]);
});

test("score is capped at 100", () => {
    assert.equal(P.scoreFrom([sig("a", 2, 70), sig("b", 3, 70)]), 100);
});

for (const name of ["blocked-92", "warning-63", "warning-41"]) {
    test(`fixture ${name}: layer 1–2 locally + 3–4 from server reproduces its score`, async () => {
        const f = fixture(name);
        const { states, last } = await run({
            snapshot: snapshotFor(f),
            local: f.signals.filter((s) => s.layer <= 2),
            remote: f.signals.filter((s) => s.layer >= 3),
        });
        assert.equal(last.score, f.score);
        assert.equal(last.status, f.status);
        assert.equal(last.done, true);
        assert.deepEqual(last.layersDone, [1, 2, 3, 4]);
        // Score rises per layer: start at 0, then layer 1–2, then final.
        assert.equal(states[0].score, 0);
        assert.ok(states.map((s) => s.score).every((v, i, a) => i === 0 || v >= a[i - 1]));
        // Highest weight first (schema)
        assert.deepEqual(last.signals.map((s) => s.weight), [...last.signals.map((s) => s.weight)].sort((a, b) => b - a));
    });
}

test("db_match → 100 immediately, server layers skipped", async () => {
    const { last, calls } = await run({ local: [sig("db_match", 1, 0)] });
    assert.equal(last.score, 100);
    assert.equal(last.status, "blocked");
    assert.equal(calls.remote, 0);
});

test("safe verdict → score 0, nothing shown, server layers skipped", async () => {
    const { last, calls } = await run({ local: [sig("cheap_tld", 2, 40)], verdict: { value: "safe" } });
    assert.equal(last.score, 0);
    assert.equal(last.status, "normal");
    assert.equal(last.verdict.value, "safe");
    assert.equal(calls.remote, 0);
});

test("not_safe verdict → blocked 100", async () => {
    const { last } = await run({ local: [sig("cheap_tld", 2, 30)], verdict: { value: "not_safe" } });
    assert.equal(last.score, 100);
    assert.equal(last.status, "blocked");
});

test("verdict is not looked up while score < 30 (browsing stays on the phone)", async () => {
    const { calls } = await run({ local: [sig("cheap_tld", 2, 15)], remote: [sig("urgent_language", 3, 10)] });
    assert.deepEqual(calls.verdict, []);
});

test("verdict looked up once score reaches 30 after server layers", async () => {
    const { calls, last } = await run({ local: [sig("cheap_tld", 2, 15)], remote: [sig("asks_pin", 3, 25)] });
    assert.deepEqual(calls.verdict, ["x.test"]);
    assert.equal(last.score, 40);
});

test("verdict looked up only once per page", async () => {
    const { calls } = await run({ local: [sig("cheap_tld", 2, 30)], remote: [sig("asks_pin", 3, 25)] });
    assert.equal(calls.verdict.length, 1);
});

test("server down or detector throws → page still scanned with what's left", async () => {
    const remoteDown = await run({ local: [sig("cheap_tld", 2, 35)], remote: () => { throw new Error("down"); } });
    assert.equal(remoteDown.last.score, 35);
    assert.equal(remoteDown.last.done, true);

    const detectorBroken = await run({ local: () => { throw new Error("bug"); }, remote: [sig("asks_pin", 3, 25)] });
    assert.equal(detectorBroken.last.score, 25);

    const verdictDown = await run({ local: [sig("cheap_tld", 2, 35)], verdict: () => { throw new Error("down"); } });
    assert.equal(verdictDown.last.score, 35);
});

test("same signal from device and server counts once, higher weight wins", async () => {
    const { last } = await run({ local: [sig("new_domain", 2, 20)], remote: [sig("new_domain", 3, 30)] });
    assert.equal(last.score, 30);
    assert.equal(last.signals.length, 1);
});

test("malformed or wrong-layer signals are dropped", async () => {
    const { last } = await run({
        local: [sig("cheap_tld", 2, 15), sig("asks_pin", 3, 25), { id: "x", layer: 2, weight: "50" }],
        remote: [sig("db_match", 1, 0), { ...sig("urgent_language", 3, 10), label: { en: "only en" } }, sig("asks_otp", 3, 20)],
    });
    assert.deepEqual(last.signals.map((s) => s.id).sort(), ["asks_otp", "cheap_tld"]);
    assert.equal(last.score, 35);
});

test("navigating away mid-scan publishes nothing more", async () => {
    let current = true;
    const { states, calls } = await run({
        local: () => { current = false; return [sig("cheap_tld", 2, 50)]; },
        current: () => current,
    });
    assert.equal(states.length, 1); // only the initial 0
    assert.equal(calls.remote, 0);
});
