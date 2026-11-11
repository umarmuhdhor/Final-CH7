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
async function run({ local = [], remote = [], rdap, skipped, verdict = null, current = () => true, snapshot, previous, memory } = {}) {
    const states = [];
    const calls = { remote: 0, verdict: [], local: 0, fresh: [] };
    await P.runScan({
        snapshot: snapshot ?? { url: "https://x.test/", domain: "x.test" },
        analyzeLocal: async () => {
            calls.local++;
            return typeof local === "function" ? local() : local;
        },
        analyzeRemote: async () => {
            calls.remote++;
            if (remote === "throw") throw new Error("down");
            return { signals: typeof remote === "function" ? remote() : remote, rdapRegisteredAt: rdap, ...(skipped ? { skipped } : {}) };
        },
        lookupVerdict: async (domain, options) => {
            calls.verdict.push(domain);
            calls.fresh.push(Boolean(options?.fresh));
            return typeof verdict === "function" ? verdict() : verdict;
        },
        ...(memory === undefined ? {} : { recallBlock: async () => (typeof memory === "function" ? memory() : memory) }),
        isCurrent: current,
        publish: (s) => states.push(s),
        previous,
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

const settled = (signals) => ({ score: P.scoreFrom(signals), status: P.statusFor(P.scoreFrom(signals)), signals, layersDone: [1, 2, 3, 4] });

test("re-check: nothing new on the page → server asked again, publishes nothing", async () => {
    const before = settled([sig("cheap_tld", 2, 10), sig("asks_otp", 3, 20)]);
    const { states, calls } = await run({ previous: before, local: [sig("cheap_tld", 2, 10)], remote: [sig("asks_otp", 3, 20)] });
    assert.equal(states.length, 0);
    assert.equal(calls.remote, 1);
});

test("re-check: only the server finds something new (page text changed) → score climbs", async () => {
    const before = settled([sig("cheap_tld", 2, 10)]);
    const { states, last } = await run({ previous: before, local: [sig("cheap_tld", 2, 10)], remote: [sig("asks_pin", 3, 30)] });
    assert.equal(states.length, 1);
    assert.equal(last.score, 40);
    assert.equal(last.status, "warning");
    assert.equal(last.done, true);
});

test("re-check: new local signal → score climbs from where it was, earlier server signals kept", async () => {
    const before = settled([sig("cheap_tld", 2, 10), sig("asks_otp", 3, 20)]);
    const { states, calls, last } = await run({
        previous: before,
        local: [sig("cheap_tld", 2, 10), sig("asks_pin", 2, 25)],
        remote: [sig("urgent_language", 3, 5)],
    });
    assert.ok(states.every((s) => s.score >= before.score), "never drops below the earlier score");
    assert.equal(states[0].done, false);
    assert.equal(calls.remote, 1);
    assert.deepEqual(last.signals.map((s) => s.id).sort(), ["asks_otp", "asks_pin", "cheap_tld", "urgent_language"]);
    assert.equal(last.score, 60);
    assert.equal(last.done, true);
});

test("re-check: a heavier copy of a known signal counts as new", async () => {
    const before = settled([sig("asks_pin", 2, 10)]);
    const { last } = await run({ previous: before, local: [sig("asks_pin", 2, 30)] });
    assert.equal(last.score, 30);
});

// ---------- block memory (#231) ----------
const REMEMBERED = { score: 92, recordId: "scan-1", signals: [sig("asks_pin", 3, 30), sig("unreasonable_request", 4, 50)] };

test("memory: a site blocked before is blocked again with no layer run (no /analyze, no LLM)", async () => {
    const { last, calls } = await run({ memory: REMEMBERED, local: [sig("cheap_tld", 2, 5)] });
    assert.equal(last.status, "blocked");
    assert.equal(last.score, 92);
    assert.equal(last.remembered, true);
    assert.equal(last.recordId, "scan-1");
    assert.deepEqual(last.signals.map((s) => s.id), ["asks_pin", "unreasonable_request"]);
    assert.equal(last.done, true);
    assert.equal(calls.local, 0);
    assert.equal(calls.remote, 0);
});

test("memory: the verdict is asked once, fresh, even below 30", async () => {
    const { calls } = await run({ memory: REMEMBERED });
    assert.deepEqual(calls.verdict, ["x.test"]);
    assert.deepEqual(calls.fresh, [true]);
});

test("memory: a safe verdict opens the page (score 0)", async () => {
    const { last, calls } = await run({ memory: REMEMBERED, verdict: { value: "safe" } });
    assert.equal(last.status, "normal");
    assert.equal(last.score, 0);
    assert.equal(last.remembered, undefined);
    assert.equal(calls.remote, 0);
});

test("memory: not_safe stays blocked at 100, still remembered (no second report)", async () => {
    const { last } = await run({ memory: REMEMBERED, verdict: { value: "not_safe" } });
    assert.deepEqual(last.signals, REMEMBERED.signals, "the block screen still has its reasons");
    assert.equal(last.status, "blocked");
    assert.equal(last.score, 100);
    assert.equal(last.remembered, true);
});

test("memory: server down stays blocked", async () => {
    const { last } = await run({ memory: REMEMBERED, verdict: () => { throw new Error("offline"); } });
    assert.equal(last.status, "blocked");
    assert.equal(last.score, 92);
});

test("memory: nothing remembered, or the memory breaks → the usual scan", async () => {
    for (const memory of [null, () => { throw new Error("storage"); }]) {
        const { last, calls } = await run({ memory, local: [sig("cheap_tld", 2, 5)] });
        assert.equal(last.status, "normal");
        assert.equal(calls.local, 1);
        assert.equal(calls.remote, 1);
        assert.equal(last.remembered, undefined);
    }
});

test("memory: a re-check (previous) never reads the memory", async () => {
    let asked = 0;
    const previous = { signals: [sig("cheap_tld", 2, 5)], score: 5, status: "normal", layersDone: [1, 2, 3, 4] };
    await run({ previous, memory: () => (asked++, REMEMBERED) });
    assert.equal(asked, 0);
});

test("memory: user navigated away while recalling → nothing published after", async () => {
    let current = true;
    const { states } = await run({ memory: () => ((current = false), REMEMBERED), current: () => current });
    assert.ok(states.every((s) => s.status !== "blocked"));
});

test("memory: stored signals that fail the schema are dropped, the block stays", async () => {
    const { last } = await run({ memory: { score: 85, recordId: null, signals: [{ id: "x" }, sig("asks_otp", 3, 30)] } });
    assert.equal(last.status, "blocked");
    assert.deepEqual(last.signals.map((s) => s.id), ["asks_otp"]);
});

test("#270: the RDAP date from /analyze stays on the state", async () => {
    const { last } = await run({ remote: [sig("asks_otp", 3, 35)], rdap: "2026-10-30" });
    assert.equal(last.rdapRegisteredAt, "2026-10-30");
});

test("#270: no date when /analyze has none, fails or answers nothing", async () => {
    assert.equal((await run({ remote: [sig("asks_otp", 3, 35)] })).last.rdapRegisteredAt, null);
    assert.equal((await run({ remote: [sig("asks_otp", 3, 35)], rdap: null })).last.rdapRegisteredAt, null);
    const failed = await run({ remote: () => { throw new Error("down"); } });
    assert.equal(failed.last.rdapRegisteredAt, null);
});

test("#270: a re-check keeps the date when RDAP fails the second time", async () => {
    const first = await run({ remote: [sig("asks_otp", 3, 35)], rdap: "2026-10-30" });
    const again = await run({ remote: [sig("asks_otp", 3, 35), sig("asks_pin", 3, 35)], rdap: null, previous: first.last });
    assert.equal(again.last.rdapRegisteredAt, "2026-10-30");
});

test("urlChurn: a few route changes are normal, a page that keeps changing its address is not", () => {
    const churn = globalThis.ShooPipeline.urlChurn();
    assert.deepEqual([0, 2000, 4000].map((at) => churn(at)), [false, false, false]);
    assert.equal(churn(4490), true);
    assert.equal(churn(4980), true);
    assert.equal(churn(30_000), false, "quiet again after the window");
});

test("#379: onlineChecked says whether /analyze really ran", async () => {
    assert.equal((await run({ local: [sig("cheap_tld", 2, 14)] })).last.onlineChecked, true);
    assert.equal((await run({ local: [sig("cheap_tld", 2, 14)], skipped: "error" })).last.onlineChecked, false);
    assert.equal((await run({ local: [sig("cheap_tld", 2, 14)], skipped: "no_ai_url" })).last.onlineChecked, false);
    assert.equal((await run({ local: [sig("cheap_tld", 2, 14)], remote: "throw" })).last.onlineChecked, false);
});
