// node --test chrome/test/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRouter } from "../extension/router.js";

function router({ session = null } = {}) {
    const calls = { verdict: [], analyze: [], match: [] };
    const route = createRouter({
        getSession: async () => session,
        lists: { match: async (hostname) => (calls.match.push(hostname), null) },
        verdicts: { lookup: async (domain, opts) => (calls.verdict.push([domain, opts]), { ok: true, verdict: null }) },
        domainFor: (hostname) => hostname.replace(/^www\./, ""),
        analyze: async (snapshot, localSignals) => (calls.analyze.push(localSignals), { ok: true, signals: [] }),
    });
    return { route: (message) => Promise.resolve(route(message)), calls };
}

test("profile without a session: not onboarded", async () => {
    assert.deepEqual(await router().route({ type: "profile" }), { ok: true, onboarded: false, mode: null, guardianName: null });
});

test("profile never carries the token or base URLs", async () => {
    const session = { ok: true, token: "secret", apiBaseURL: "https://api.test", aiBaseURL: "https://ai.test", mode: "protected", guardianName: "Rina" };
    const reply = await router({ session }).route({ type: "profile" });
    assert.deepEqual(reply, { ok: true, onboarded: true, mode: "protected", guardianName: "Rina" });
    assert.doesNotMatch(JSON.stringify(reply), /secret|api\.test|ai\.test/);
});

test("heartbeat and report are answered without an app", async () => {
    const { route } = router();
    assert.deepEqual(await route({ type: "heartbeat" }), { ok: true, skipped: "no_app" });
    assert.deepEqual(await route({ type: "report", key: "k" }), { ok: false, skipped: "not_supported" });
    assert.deepEqual(await route({ type: "recordId", key: "k" }), { ok: true, recordId: null });
});

test("domain, listMatch, analyze and verdict reach their modules", async () => {
    const { route, calls } = router();
    assert.deepEqual(await route({ type: "domain", hostname: "www.bca.co.id" }), { ok: true, domain: "bca.co.id" });
    assert.deepEqual(await route({ type: "listMatch", hostname: "scam.test" }), { ok: true, match: null });
    await route({ type: "analyze", snapshot: {} });
    await route({ type: "verdict", domain: "scam.test", fresh: true });
    await route({ type: "verdict", domain: "scam.test" });
    assert.deepEqual(calls.match, ["scam.test"]);
    assert.deepEqual(calls.analyze, [[]]);
    assert.deepEqual(calls.verdict, [["scam.test", { fresh: true }], ["scam.test", { fresh: false }]]);
});

test("unknown message types are refused", async () => {
    assert.deepEqual(await router().route({ type: "getToken" }), { ok: false, error: "unknown_type" });
    assert.deepEqual(await router().route(null), { ok: false, error: "unknown_type" });
});
