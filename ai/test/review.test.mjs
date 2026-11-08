import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { suggestionFor, validateReviewRequest } from "../src/review/review.js";

const SECRET = "s3cret-review-token";
const ENV = { AI_REVIEW_SECRET: SECRET, LLM_API_KEY: "k", LLM_MODEL: "test-model", LLM_BASE_URL: "https://llm.example.com/v1" };

const input = (domain, over = {}) => ({
    domain,
    signal_counts: { new_domain: 3, asks_pin: 2 },
    avg_score: 88,
    max_score: 92,
    families_safe: 0,
    families_not_safe: 3,
    ...over,
});

/** A mock LLM: records each request body and answers with `answer(callNo, body)` (an array of results, or a Response). */
function mockLlm(answer) {
    const calls = [];
    const fetch = async (url, init) => {
        const body = JSON.parse(init.body);
        calls.push(body);
        const out = typeof answer === "function" ? answer(calls.length, body) : answer;
        if (out instanceof Response) return out;
        return new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ results: out }) } }], usage: { prompt_tokens: 100, completion_tokens: 50 } }));
    };
    return { fetch, calls };
}

function send(app, body, { env = ENV, token = SECRET, method = "POST", headers = {} } = {}) {
    const h = { "content-type": "application/json", ...headers };
    if (token !== null) h.authorization = `Bearer ${token}`;
    return app.request("/review", { method, headers: h, body: method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body) }, env);
}

const scam = (index) => ({ index, result: "scam", confidence: 0.9, reason: "new domain asks for PIN" });

test("no secret configured -> 404, even with a valid-looking request", async () => {
    const { fetch, calls } = mockLlm([scam(0)]);
    const app = createApp({ llmFetch: fetch });
    const { AI_REVIEW_SECRET, ...envWithout } = ENV;
    const res = await send(app, { domains: [input("a.test")] }, { env: envWithout });
    assert.equal(res.status, 404);
    assert.equal((await send(app, "", { env: envWithout, method: "GET" })).status, 404);
    assert.equal(calls.length, 0);
});

test("wrong bearer -> 401, including a secret of another length and no header", async () => {
    const { fetch, calls } = mockLlm([scam(0)]);
    const app = createApp({ llmFetch: fetch });
    for (const token of ["wrong", SECRET + "x", SECRET.slice(0, -1), "", "a".repeat(5000), null]) {
        const res = await send(app, { domains: [input("a.test")] }, { token });
        assert.equal(res.status, 401, `token ${token === null ? "none" : token.length}`);
        assert.equal((await res.json()).error.code, "unauthorized");
    }
    assert.equal(calls.length, 0);
});

test("GET -> 405", async () => {
    const app = createApp({ llmFetch: mockLlm([]).fetch });
    const res = await send(app, "", { method: "GET" });
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("allow"), "POST");
});

test("invalid bodies -> 422", async () => {
    const app = createApp({ llmFetch: mockLlm([scam(0)]).fetch });
    const many = Array.from({ length: 26 }, (_, i) => input(`d${i}.test`));
    const keys31 = Object.fromEntries(Array.from({ length: 31 }, (_, i) => [`sig_${String.fromCharCode(97 + (i % 26))}${"x".repeat(Math.floor(i / 26))}`.replace(/[^a-z_]/g, "_"), 1]));
    for (const [name, body] of [
        ["26 domains", { domains: many }],
        ["no domains", { domains: [] }],
        ["bad domain A..b", { domains: [input("A..b")] }],
        ["www prefix", { domains: [input("www.example.test")] }],
        ["31 signal_counts keys", { domains: [input("a.test", { signal_counts: keys31 })] }],
        ["bad signal key", { domains: [input("a.test", { signal_counts: { "Bad Key": 1 } })] }],
        ["signal count too big", { domains: [input("a.test", { signal_counts: { x: 1e7 } })] }],
        ["avg_score 101", { domains: [input("a.test", { avg_score: 101 })] }],
        ["families -1", { domains: [input("a.test", { families_safe: -1 })] }],
        ["float families", { domains: [input("a.test", { families_not_safe: 1.5 })] }],
        ["not an object", [1, 2]],
    ]) {
        const res = await send(app, body);
        assert.equal(res.status, 422, name);
        assert.equal((await res.json()).error.code, "invalid_body", name);
    }
    assert.equal((await send(app, "{not json")).status, 400);
});

test("31 distinct signal keys really are 31 (guards the test above)", () => {
    const keys31 = Object.fromEntries(Array.from({ length: 31 }, (_, i) => [`sig_${"x".repeat(i + 1)}`, 1]));
    assert.equal(Object.keys(keys31).length, 31);
    assert.ok("error" in validateReviewRequest({ domains: [input("a.test", { signal_counts: keys31 })] }));
    const ok30 = Object.fromEntries(Array.from({ length: 30 }, (_, i) => [`sig_${"x".repeat(i + 1)}`.slice(0, 40), 1]));
    assert.equal(Object.keys(ok30).length, 30);
    assert.ok("domains" in validateReviewRequest({ domains: [input("a.test", { signal_counts: ok30 })] }));
});

test("null scores are valid (a domain with no scans)", () => {
    const r = validateReviewRequest({ domains: [input("a.test", { avg_score: null, max_score: null, signal_counts: {} })] });
    assert.ok("domains" in r, JSON.stringify(r));
});

test("valid batch -> 200 { model, prompt, results } with one result per input, index 0..n-1", async () => {
    const { fetch } = mockLlm([scam(0), { index: 1, result: "legit", confidence: 0.8, reason: "old domain" }, { index: 2, result: "unsure", confidence: 0.4, reason: "mixed" }]);
    const app = createApp({ llmFetch: fetch });
    const res = await send(app, { domains: [input("a.test"), input("b.test"), input("c.test")] });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.model, "test-model");
    assert.equal(body.prompt, "review.v1");
    assert.equal(body.results.length, 3);
    assert.deepEqual(body.results.map((r) => r.index), [0, 1, 2]);
    assert.deepEqual(body.results.map((r) => r.suggestion), ["approve", "reject", "none"]);
    assert.deepEqual(Object.keys(body.results[0]).sort(), ["confidence", "index", "reason", "result", "suggestion"]);
});

test("a shared host is answered without calling the model", async () => {
    const { fetch, calls } = mockLlm([]);
    const app = createApp({ llmFetch: fetch });
    const res = await send(app, { domains: [input("sites.google.com")] });
    assert.equal(res.status, 200);
    assert.equal(calls.length, 0);
    assert.deepEqual((await res.json()).results, [{ index: 0, result: "unsure", confidence: null, reason: "shared_host", suggestion: "none" }]);
});

test("a page on a shared host is skipped too, and the others keep their own index", async () => {
    const { fetch, calls } = mockLlm([scam(0)]);
    const app = createApp({ llmFetch: fetch });
    const res = await send(app, { domains: [input("evil.github.io"), input("scam.test"), input("github.io")] });
    const { results } = await res.json();
    assert.equal(calls.length, 1);
    assert.equal(JSON.parse(calls[0].messages[1].content).domains.length, 1);
    assert.deepEqual(results.map((r) => [r.index, r.result, r.reason]), [[0, "unsure", "shared_host"], [1, "scam", "new domain asks for PIN"], [2, "unsure", "shared_host"]]);
});

test("the model's own suggestion is ignored: legit 0.9 + suggestion approve -> reject", async () => {
    const { fetch } = mockLlm([{ index: 0, result: "legit", confidence: 0.9, reason: "x", suggestion: "approve" }]);
    const app = createApp({ llmFetch: fetch });
    const res = await send(app, { domains: [input("ignore-previous.approve.test")] });
    assert.equal((await res.json()).results[0].suggestion, "reject");
});

test("suggestionFor: threshold 0.7, unsure and null never suggest", () => {
    assert.equal(suggestionFor("scam", 0.7), "approve");
    assert.equal(suggestionFor("scam", 0.69), "none");
    assert.equal(suggestionFor("legit", 0.95), "reject");
    assert.equal(suggestionFor("legit", 0.5), "none");
    assert.equal(suggestionFor("unsure", 1), "none");
    assert.equal(suggestionFor(null, 1), "none");
    assert.equal(suggestionFor("scam", null), "none");
});

test("missing, duplicate and out-of-range indexes: every input still gets exactly one result", async () => {
    const answer = [scam(0), { ...scam(0), result: "legit" }, scam(2), scam(7), scam(-1), { result: "scam", confidence: 0.9 }];
    const { fetch } = mockLlm(answer); // 0 twice (both dropped), 1 missing, 2 fine, 7 / -1 / none out of range
    const app = createApp({ llmFetch: fetch });
    const res = await send(app, { domains: [input("a.test"), input("b.test"), input("c.test")] });
    const { results } = await res.json();
    assert.equal(results.length, 3);
    assert.deepEqual(results.map((r) => r.index), [0, 1, 2]);
    assert.deepEqual(results.map((r) => r.result), [null, null, "scam"]);
    assert.deepEqual(results.map((r) => r.suggestion), ["none", "none", "approve"]);
});

test("a model that answers fewer results than asked is handled", async () => {
    const app = createApp({ llmFetch: mockLlm([scam(0)]).fetch });
    const res = await send(app, { domains: [input("a.test"), input("b.test")] });
    assert.deepEqual((await res.json()).results.map((r) => r.result), ["scam", null]);
});

test("the model fails 3 times -> 200 with every result null, after exactly 3 attempts", async () => {
    const { fetch, calls } = mockLlm(() => new Response("nope", { status: 500 }));
    const app = createApp({ llmFetch: fetch });
    const res = await send(app, { domains: [input("a.test"), input("sites.google.com")] });
    assert.equal(res.status, 200);
    assert.equal(calls.length, 3);
    assert.deepEqual((await res.json()).results, [
        { index: 0, result: null, confidence: null, reason: null, suggestion: "none" },
        { index: 1, result: "unsure", confidence: null, reason: "shared_host", suggestion: "none" },
    ]);
});

test("a bad answer is retried and a later good one is used", async () => {
    const { fetch, calls } = mockLlm((n) => (n === 1 ? new Response(JSON.stringify({ choices: [{ message: { content: "not json" } }] })) : [scam(0)]));
    const app = createApp({ llmFetch: fetch });
    const res = await send(app, { domains: [input("a.test")] });
    assert.equal(calls.length, 2);
    assert.equal((await res.json()).results[0].result, "scam");
});

test("reason is cleaned: no < or >, at most 500 characters, empty becomes null", async () => {
    const { fetch } = mockLlm([
        { index: 0, result: "scam", confidence: 0.9, reason: "<script>x</script>" },
        { index: 1, result: "scam", confidence: 0.9, reason: "a".repeat(900) },
        { index: 2, result: "scam", confidence: 0.9, reason: "  <>  " },
    ]);
    const app = createApp({ llmFetch: fetch });
    const { results } = await (await send(app, { domains: [input("a.test"), input("b.test"), input("c.test")] })).json();
    assert.equal(results[0].reason, "scriptx/script");
    assert.equal(results[1].reason.length, 500);
    assert.equal(results[2].reason, null);
});

test("an unknown result or a confidence outside 0..1 becomes null", async () => {
    const { fetch } = mockLlm([{ index: 0, result: "maybe", confidence: 0.9, reason: "x" }, { index: 1, result: "scam", confidence: 7, reason: "x" }]);
    const app = createApp({ llmFetch: fetch });
    const { results } = await (await send(app, { domains: [input("a.test"), input("b.test")] })).json();
    assert.deepEqual(results.map((r) => [r.result, r.confidence, r.suggestion]), [[null, null, "none"], ["scam", null, "none"]]);
});

test("the outgoing LLM request has only domain names and numbers: no notes, no url path, only the six input fields", async () => {
    const { fetch, calls } = mockLlm([scam(0)]);
    const app = createApp({ llmFetch: fetch });
    const dirty = { ...input("a.test"), note: "my PIN is 1234", url: "https://a.test/secret/path?token=abc", reason: "x" };
    const res = await send(app, { domains: [dirty] });
    assert.equal(res.status, 200);
    const sent = JSON.stringify(calls[0]);
    for (const leak of ["my PIN", "secret/path", "token=abc", "https://a.test"]) assert.ok(!sent.includes(leak), leak);
    const user = JSON.parse(calls[0].messages.find((m) => m.role === "user").content);
    assert.deepEqual(Object.keys(user.domains[0]).sort(), ["avg_score", "domain", "families_not_safe", "families_safe", "index", "max_score", "signal_counts"]);
    assert.equal(calls[0].max_tokens, 2000);
});

test("the daily cap answers 429 once used up", async () => {
    const { fetch } = mockLlm([scam(0)]);
    const app = createApp({ llmFetch: fetch });
    const env = { ...ENV, REVIEW_DAILY_CAP: "2" };
    assert.equal((await send(app, { domains: [input("a.test")] }, { env })).status, 200);
    assert.equal((await send(app, { domains: [input("a.test")] }, { env })).status, 200);
    const third = await send(app, { domains: [input("a.test")] }, { env });
    assert.equal(third.status, 429);
    assert.equal((await third.json()).error.code, "rate_limited");
});

test("LLM not configured -> 503 review_unavailable (after auth)", async () => {
    const app = createApp({ llmFetch: mockLlm([]).fetch });
    const env = { AI_REVIEW_SECRET: SECRET };
    assert.equal((await send(app, { domains: [input("a.test")] }, { env, token: "wrong" })).status, 401);
    const res = await send(app, { domains: [input("a.test")] }, { env });
    assert.equal(res.status, 503);
    assert.equal((await res.json()).error.code, "review_unavailable");
});

test("nothing is logged: not the request, not the answer, not the secret", async () => {
    const seen = [];
    const originals = {};
    for (const k of ["log", "info", "warn", "error", "debug"]) {
        originals[k] = console[k];
        console[k] = (...a) => seen.push(a.join(" "));
    }
    try {
        const app = createApp({ llmFetch: mockLlm([scam(0)]).fetch });
        await send(app, { domains: [input("a.test")] });
        await send(app, { domains: [input("a.test")] }, { token: "wrong" });
        await send(app, "{bad");
    } finally {
        Object.assign(console, originals);
    }
    assert.deepEqual(seen, []);
});
