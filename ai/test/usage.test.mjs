// ai_usage (05b K4): one Analytics Engine point per /analyze, with a FAKE binding and a FAKE provider. No network.
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { createRealityCheck } from "../src/layer4/reality.js";
import { createProvider } from "../src/layer4/provider.js";
import { NO_CASES, tokenUsage } from "../src/usage.js";
import { PROMPT_VERSION } from "../prompts/reality-check.js";
import { field, page, SCAM_URL } from "./helpers.mjs";

const CONFIG = { apiKey: "test-key-NOT-REAL", model: "fake-model", baseUrl: "https://llm.test/v1", timeoutMs: 400, dailyCap: 1000 };
const VERDICT = { page_type: "prize", asks: ["pin"], reasonable: false, confidence: 0.9, evidence: null };
const reply = (usage) =>
    new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify(VERDICT) } }], ...(usage === undefined ? {} : { usage }) }), {
        status: 200,
        headers: { "content-type": "application/json" },
    });
const PIN = () => page(SCAM_URL, [field({ name: "pin", label: "PIN" })], { title: "Cek hadiah anda" });

/** A fake AI_USAGE binding that keeps every point. */
function dataset() {
    const points = [];
    return { points, writeDataPoint: (p) => points.push(p) };
}
const send = (app, env, body = { snapshot: PIN(), localSignals: [] }, headers = {}) =>
    app.request("/analyze", { method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) }, env);
const llmApp = (fetch, opts = {}) => createApp({ llm: createRealityCheck({ config: CONFIG, fetch }), ...opts });

test("flagged call -> one point: prompt version, cases, outcome, tokens in/out, layer 4 ms, RDAP ok", async () => {
    const ds = dataset();
    const res = await send(llmApp(async () => reply({ prompt_tokens: 412, completion_tokens: 37, total_tokens: 449 })), { AI_USAGE: ds });
    assert.equal(res.status, 200);
    assert.equal(ds.points.length, 1);
    const [p] = ds.points;
    assert.deepEqual(p.blobs, [PROMPT_VERSION, NO_CASES, "flagged"]);
    assert.equal(p.doubles.length, 4);
    assert.deepEqual(p.doubles.slice(0, 2), [412, 37]);
    assert.ok(Number.isFinite(p.doubles[2]) && p.doubles[2] >= 0, "layer 4 ms");
    assert.equal(p.doubles[3], 0, "no RDAP client: nothing failed");
    assert.deepEqual(Object.keys(p).sort(), ["blobs", "doubles"], "no indexes");
});

test("the point never carries page data, the IP or the domain", async () => {
    const ds = dataset();
    const snapshot = PIN();
    await send(llmApp(async () => reply({ prompt_tokens: 1, completion_tokens: 1 })), { AI_USAGE: ds }, { snapshot, localSignals: [] }, { "cf-connecting-ip": "203.0.113.9" });
    const raw = JSON.stringify(ds.points);
    for (const s of ["203.0.113.9", "example.xyz", "verif-akun", "PIN", "hadiah", "fake-model", "test-key"]) assert.ok(!raw.includes(s), s);
});

test("provider without usage -> tokens 0; reasonable / gated outcomes by their OUTCOMES name", async () => {
    const ds = dataset();
    const app = createApp({
        llm: createRealityCheck({
            config: CONFIG,
            fetch: async () => new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ ...VERDICT, reasonable: true }) } }] }), { status: 200 }),
        }),
    });
    await send(app, { AI_USAGE: ds });
    await send(app, { AI_USAGE: ds }, { snapshot: page(SCAM_URL, [], { title: "Cek hadiah" }), localSignals: [] }); // total 0 -> gated
    assert.deepEqual(ds.points.map((p) => p.blobs[2]), ["reasonable", "gated"]);
    assert.deepEqual(ds.points.map((p) => p.doubles.slice(0, 2)), [[0, 0], [0, 0]]);
    assert.equal(ds.points[1].doubles[2], 0, "gated: no LLM call, 0 ms");
});

test("timeout and http_error are named, tokens 0", async () => {
    const ds = dataset();
    const slow = createApp({ llm: createRealityCheck({ config: { ...CONFIG, timeoutMs: 20 }, fetch: (u, init) => new Promise((_, no) => init.signal.addEventListener("abort", () => no(new Error("abort")))) }) });
    await send(slow, { AI_USAGE: ds });
    await send(llmApp(async () => new Response("no", { status: 500 })), { AI_USAGE: ds });
    assert.deepEqual(ds.points.map((p) => p.blobs[2]), ["timeout", "http_error"]);
    assert.deepEqual(ds.points.map((p) => p.doubles.slice(0, 2)), [[0, 0], [0, 0]]);
});

test("no layer 4 configured -> outcome off, ms 0", async () => {
    const ds = dataset();
    await send(createApp(), { AI_USAGE: ds });
    assert.equal(ds.points.length, 1);
    assert.deepEqual(ds.points[0].blobs, [PROMPT_VERSION, NO_CASES, "off"]);
    assert.deepEqual(ds.points[0].doubles, [0, 0, 0, 0]);
});

test("RDAP without an answer -> rdapFailed 1; an official host is never looked up -> 0", async () => {
    const ds = dataset();
    const app = createApp({ fetch: async () => new Response("down", { status: 503 }), rdapTimeoutMs: 200 });
    await send(app, { AI_USAGE: ds });
    await send(app, { AI_USAGE: ds }, { snapshot: page("https://www.bca.co.id/login", [field({ name: "pin", label: "PIN" })]), localSignals: [] });
    assert.deepEqual(ds.points.map((p) => p.doubles[3]), [1, 0]);
});

test("no binding, a binding without writeDataPoint, or one that throws: the answer is unchanged", async () => {
    const make = () => llmApp(async () => reply({ prompt_tokens: 3, completion_tokens: 4 }));
    const plain = await (await send(make(), {})).json();
    for (const env of [undefined, { AI_USAGE: {} }, { AI_USAGE: { writeDataPoint: () => { throw new Error("quota"); } } }]) {
        const res = await send(make(), env);
        assert.equal(res.status, 200);
        assert.deepEqual(await res.json(), plain);
    }
});

test("refused requests write nothing (bad JSON, wrong content type, invalid body)", async () => {
    const ds = dataset();
    const app = createApp();
    await app.request("/analyze", { method: "POST", headers: { "content-type": "application/json" }, body: "{" }, { AI_USAGE: ds });
    await app.request("/analyze", { method: "POST", headers: { "content-type": "text/plain" }, body: "{}" }, { AI_USAGE: ds });
    await send(app, { AI_USAGE: ds }, { snapshot: { url: 1 } });
    assert.equal(ds.points.length, 0);
});

test("provider returns usage on success; junk usage counts as 0", async () => {
    const ask = createProvider({ config: CONFIG, fetch: async () => reply({ prompt_tokens: 10, completion_tokens: 2 }) });
    const ok = await ask([], new AbortController().signal);
    assert.equal(ok.ok, true);
    assert.deepEqual(ok.usage, { in: 10, out: 2 });
    assert.deepEqual(tokenUsage(undefined), { in: 0, out: 0 });
    assert.deepEqual(tokenUsage({ prompt_tokens: -1, completion_tokens: "9" }), { in: 0, out: 0 });
    assert.deepEqual(tokenUsage({ prompt_tokens: 1.7, completion_tokens: 1e12 }), { in: 1, out: 1e7 });
});

test("stats() adds token totals per isolate", async () => {
    const checker = createRealityCheck({ config: CONFIG, fetch: async () => reply({ prompt_tokens: 5, completion_tokens: 6 }) });
    const app = createApp({ llm: checker });
    await send(app, {});
    await send(app, {});
    assert.deepEqual(checker.stats().tokens, { in: 10, out: 12 });
});

test("concurrent requests on one shared checker each get their own point", async () => {
    const ds = dataset();
    let n = 0;
    const checker = createRealityCheck({
        config: { ...CONFIG, timeoutMs: 60 },
        clientCallsPerHour: Infinity,
        // first call answers late (timeout), second at once with its own usage
        fetch: (u, init) => (n++ === 0 ? new Promise((_, no) => init.signal.addEventListener("abort", () => no(new Error("abort")))) : Promise.resolve(reply({ prompt_tokens: 7, completion_tokens: 8 }))),
    });
    const app = createApp({ llm: checker });
    await Promise.all([send(app, { AI_USAGE: ds }), send(app, { AI_USAGE: ds })]);
    const byOutcome = Object.fromEntries(ds.points.map((p) => [p.blobs[2], p.doubles.slice(0, 2)]));
    assert.deepEqual(byOutcome, { flagged: [7, 8], timeout: [0, 0] });
});

test("capped, bad_schema with usage, a throwing checker: named outcome, billed tokens kept", async () => {
    const ds = dataset();
    await send(createApp({ llm: createRealityCheck({ config: { ...CONFIG, dailyCap: 0 }, fetch: async () => reply({}) }) }), { AI_USAGE: ds });
    const noContent = async () => new Response(JSON.stringify({ choices: [], usage: { prompt_tokens: 9, completion_tokens: 0 } }), { status: 200 });
    await send(llmApp(noContent), { AI_USAGE: ds });
    await send(createApp({ llm: { check: async () => { throw new Error("boom"); } } }), { AI_USAGE: ds });
    assert.deepEqual(ds.points.map((p) => [p.blobs[2], ...p.doubles.slice(0, 2)]), [["capped", 0, 0], ["bad_schema", 9, 0], ["http_error", 0, 0]]);
});

test("layer 4 ms is the LLM call time on the injected clock", async () => {
    const ds = dataset();
    let t = 1_000;
    const now = () => t;
    const checker = createRealityCheck({ config: CONFIG, now, fetch: async () => { t += 250; return reply({}); } });
    await send(createApp({ llm: checker, now }), { AI_USAGE: ds });
    assert.equal(ds.points[0].doubles[2], 250);
});
