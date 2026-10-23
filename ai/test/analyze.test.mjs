// POST /analyze: contract, validation, size limits, method handling, privacy (no logging).
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { sanitizeSnapshot } from "../src/validate.js";
import { LIMITS } from "../src/limits.js";
import { field, page, post, readFixture, SCAM_URL, ids } from "./helpers.mjs";

const app = createApp();
const PIN_PAGE = () => page(SCAM_URL, [field({ name: "pin", label: "PIN m-banking" })]);

function assertSignalShape(s) {
    assert.deepEqual(Object.keys(s).filter((k) => !["id", "layer", "weight", "label", "labelSimple", "evidence"].includes(k)), [], "no extra keys");
    assert.equal(typeof s.id, "string");
    assert.equal(s.layer, 3);
    assert.ok(Number.isInteger(s.weight) && s.weight >= 0 && s.weight <= 100);
    for (const k of ["label", "labelSimple"]) {
        assert.deepEqual(Object.keys(s[k]).sort(), ["en", "id"]);
        assert.ok(s[k].en.length > 0 && s[k].id.length > 0);
    }
    if ("evidence" in s) assert.equal(typeof s.evidence, "string");
}

// ---- a. contract -----------------------------------------------------------
test("a. valid request -> 200 { signals } and nothing else", async () => {
    const res = await post(app, { snapshot: PIN_PAGE(), localSignals: [] });
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type"), /application\/json/);
    const body = await res.json();
    assert.deepEqual(Object.keys(body), ["signals"]);
    assert.ok(Array.isArray(body.signals));
    assert.deepEqual(ids(body.signals), ["asks_pin"]);
    body.signals.forEach(assertSignalShape);
});

test("a. only layer 3 signals come back, even when localSignals carry layer 1-2", async () => {
    const local = readFixture("blocked-92.json").signals.filter((s) => s.layer <= 2);
    const body = await (await post(app, { snapshot: PIN_PAGE(), localSignals: local })).json();
    assert.ok(body.signals.every((s) => s.layer === 3));
});

test("a. no signals -> 200 { signals: [] }", async () => {
    const res = await post(app, { snapshot: page("https://toko.example.com/", [field({ name: "alamat" })]), localSignals: [] });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { signals: [] });
});

test("a. fixtures: asks_pin / asks_ktp match the fixtures' shape and stay within weight +-10", async () => {
    const fixtureSignals = [...readFixture("blocked-92.json").signals, ...readFixture("warning-63.json").signals];
    const pinFx = fixtureSignals.find((s) => s.id === "asks_pin");
    const ktpFx = fixtureSignals.find((s) => s.id === "asks_ktp");
    const res = await (await post(app, { snapshot: page(SCAM_URL, [field({ name: "pin" }), field({ name: "nik" })]), localSignals: [] })).json();
    for (const fx of [pinFx, ktpFx]) {
        const got = res.signals.find((s) => s.id === fx.id);
        assert.ok(got, `${fx.id} missing`);
        assert.deepEqual(Object.keys(got).sort(), Object.keys(fx).sort(), `${fx.id} key set`);
        assert.equal(got.evidence, fx.evidence);
        assert.ok(Math.abs(got.weight - fx.weight) <= 10, `${fx.id} weight ${got.weight} vs fixture ${fx.weight}`);
    }
});

// ---- b. validation ---------------------------------------------------------
async function expectError(res, status, code) {
    assert.equal(res.status, status);
    const body = await res.json();
    assert.deepEqual(Object.keys(body), ["error"]);
    assert.deepEqual(Object.keys(body.error).sort(), ["code", "message"]);
    assert.equal(body.error.code, code);
    assert.equal(typeof body.error.message, "string");
    assert.ok(body.error.message.length > 0);
}

test("b. body is not JSON -> 400 bad_json", async () => {
    await expectError(await post(app, "{not json"), 400, "bad_json");
    await expectError(await post(app, ""), 400, "bad_json");
});

test("b. wrong shape -> 422 invalid_body", async () => {
    for (const bad of [[], 42, null, "str", {}, { snapshot: null }, { snapshot: [] }, { snapshot: {} }, { snapshot: { url: 5 } }, { snapshot: { url: "" } }, { snapshot: { url: "not a url" } }, { snapshot: { url: "ftp://x.example/" } }, { snapshot: { url: "javascript:alert(1)" } }]) {
        await expectError(await post(app, JSON.stringify(bad)), 422, "invalid_body");
    }
});

test("b. localSignals present but not an array -> 422; missing is tolerated", async () => {
    await expectError(await post(app, { snapshot: PIN_PAGE(), localSignals: "x" }), 422, "invalid_body");
    const res = await post(app, { snapshot: PIN_PAGE() });
    assert.equal(res.status, 200);
});

test("b. malformed forms/fields are dropped, not fatal", async () => {
    const snap = { ...PIN_PAGE(), forms: [null, 7, { fields: "x" }, { fields: [null, 3, { type: "text", name: "pin" }] }], imageAlts: [1, null, "ok"] };
    const res = await post(app, { snapshot: snap, localSignals: [] });
    assert.equal(res.status, 200);
    assert.deepEqual(ids((await res.json()).signals), ["asks_pin"]);
});

// ---- c. size limit ---------------------------------------------------------
test("c. body over 200 KB -> 413 too_large", async () => {
    const big = JSON.stringify({ snapshot: { ...PIN_PAGE(), text: "x".repeat(300 * 1024) } });
    await expectError(await post(app, big), 413, "too_large");
});

test("c. content-length over the limit -> 413 without reading the body", async () => {
    await expectError(await post(app, "{}", { headers: { "content-length": String(LIMITS.MAX_BODY_BYTES + 1) } }), 413, "too_large");
});

test("c. a streamed body is cut off early (not read to the end, not parsed)", async () => {
    let pulled = 0;
    const chunk = new Uint8Array(64 * 1024).fill(0x20);
    const body = new ReadableStream({
        pull(controller) {
            pulled++;
            if (pulled > 200) controller.close();
            else controller.enqueue(chunk);
        },
    });
    const res = await app.request("/analyze", { method: "POST", headers: { "content-type": "application/json" }, body, duplex: "half" });
    await expectError(res, 413, "too_large");
    assert.ok(pulled <= 6, `read ${pulled} chunks before giving up`);
});

// ---- d. caps ---------------------------------------------------------------
test("d. limits are the documented ones", () => {
    assert.equal(LIMITS.MAX_BODY_BYTES, 200 * 1024);
    assert.equal(LIMITS.MAX_TEXT_CHARS, 20_000);
    assert.equal(LIMITS.MAX_IMAGE_ALTS, 50);
    assert.ok(LIMITS.MAX_FORMS > 0 && LIMITS.MAX_FIELDS_PER_FORM > 0 && LIMITS.MAX_FIELD_TEXT > 0);
});

test("d. text cut to 20,000 chars; forms, fields, imageAlts and field strings are capped", () => {
    const manyFields = Array.from({ length: LIMITS.MAX_FIELDS_PER_FORM + 10 }, (_, i) => field({ name: `f${i}`, label: "l".repeat(LIMITS.MAX_FIELD_TEXT + 50) }));
    const snap = {
        url: "https://a.example/",
        text: "t".repeat(25_000),
        imageAlts: Array.from({ length: 80 }, (_, i) => `alt${i}`),
        forms: Array.from({ length: LIMITS.MAX_FORMS + 5 }, () => ({ action: null, fields: manyFields })),
    };
    const out = sanitizeSnapshot(snap);
    assert.equal(out.text.length, 20_000);
    assert.equal(out.imageAlts.length, 50);
    assert.equal(out.forms.length, LIMITS.MAX_FORMS);
    assert.ok(out.forms.every((f) => f.fields.length <= LIMITS.MAX_FIELDS_PER_FORM));
    assert.equal(out.forms[0].fields[0].label.length, LIMITS.MAX_FIELD_TEXT);
    const total = out.forms.reduce((n, f) => n + f.fields.length, 0);
    assert.ok(total <= LIMITS.MAX_FIELDS_TOTAL);
});

test("d. a sensitive field past the cap does not produce a signal", async () => {
    const filler = Array.from({ length: LIMITS.MAX_FIELDS_PER_FORM }, (_, i) => field({ name: `x${i}` }));
    const res = await post(app, { snapshot: page(SCAM_URL, [...filler, field({ name: "pin" })]), localSignals: [] });
    assert.deepEqual((await res.json()).signals, []);
});

test("d. accept and capture are kept and capped; an older extension that omits them gives null (C8)", () => {
    const out = sanitizeSnapshot({ url: "https://a.example/", forms: [{ fields: [
        { type: "file", accept: "a".repeat(LIMITS.MAX_FIELD_TEXT + 50), capture: "user".repeat(20) },
        { type: "text", name: "pin" },
    ] }] });
    const [file, old] = out.forms[0].fields;
    assert.equal(file.accept.length, LIMITS.MAX_FIELD_TEXT);
    assert.equal(file.capture.length, LIMITS.MAX_CAPTURE_CHARS);
    assert.equal(old.accept, null);
    assert.equal(old.capture, null);
});

test("d. unknown keys on fields are dropped (typed values never travel further)", () => {
    const out = sanitizeSnapshot({ url: "https://a.example/", forms: [{ fields: [{ type: "text", name: "pin", value: "123456" }] }] });
    assert.equal("value" in out.forms[0].fields[0], false);
});

// ---- e. method / auth ------------------------------------------------------
test("e. other methods -> 405 with Allow: POST", async () => {
    for (const method of ["GET", "PUT", "DELETE", "PATCH"]) {
        const res = await app.request("/analyze", { method });
        await expectError(res, 405, "method_not_allowed");
        assert.equal(res.headers.get("allow"), "POST");
    }
});

test("e. unknown path -> 404 not_found", async () => {
    await expectError(await app.request("/nope", { method: "POST", body: "{}" }), 404, "not_found");
});

test("e. Authorization is accepted but not verified", async () => {
    const results = [];
    for (const headers of [{}, { authorization: "Bearer real-looking-token" }, { authorization: "garbage" }, { authorization: "" }]) {
        const res = await post(app, { snapshot: PIN_PAGE(), localSignals: [] }, { headers });
        results.push([res.status, await res.json()]);
    }
    for (const r of results) assert.deepEqual(r, results[0]);
    assert.equal(results[0][0], 200);
});

// ---- p. performance --------------------------------------------------------
test("p. largest allowed input answers in < 100 ms CPU (no ReDoS)", async () => {
    const evil = ["pin otp cvv ktp selfie ", "a".repeat(120), "pinpinpinpin".repeat(10), "nomor kartu ".repeat(10), "o-t-p ".repeat(20)];
    const fields = Array.from({ length: 300 }, (_, i) => field({ type: i % 7 === 0 ? "password" : i % 5 === 0 ? "file" : "text", name: `n${i}`, id: `i${i}`, label: evil[i % evil.length], placeholder: evil[(i + 1) % evil.length], autocomplete: "off" }));
    const snap = {
        ...page("https://slow.example.com/"),
        text: "pin otp ".repeat(2500),
        imageAlts: Array.from({ length: 50 }, () => "pin ".repeat(30)),
        forms: Array.from({ length: 200 }, () => ({ action: null, fields })),
    };
    const warm = post(app, { snapshot: page(SCAM_URL, [field({ name: "pin" })]) });
    await warm;
    const { analyzeSnapshot } = await import("../src/analyze.js");
    const t0 = performance.now();
    const out = analyzeSnapshot(snap);
    const ms = performance.now() - t0;
    assert.ok(ms < 100, `took ${ms.toFixed(1)} ms`);
    assert.ok(Array.isArray(out));
});

test("p. a 200 KB request end to end stays fast", async () => {
    // ~199 KB with the full field shape (accept + capture since C8), just under MAX_BODY_BYTES.
    const fields = Array.from({ length: 30 }, (_, i) => field({ name: `n${i}`, label: "pin ".repeat(20) }));
    const snap = { ...page("https://slow.example.com/"), text: "otp ".repeat(5000), forms: Array.from({ length: 30 }, () => ({ action: null, fields })) };
    const raw = JSON.stringify({ snapshot: snap, localSignals: [] });
    assert.ok(raw.length < LIMITS.MAX_BODY_BYTES, `fixture ${raw.length} bytes`);
    const t0 = performance.now();
    const res = await post(app, raw);
    const ms = performance.now() - t0;
    assert.equal(res.status, 200);
    assert.ok(ms < 100, `took ${ms.toFixed(1)} ms`);
});

// ---- q. no logging ---------------------------------------------------------
test("q. nothing is logged: no console output on success or on any error path", async () => {
    const calls = [];
    const names = ["log", "info", "debug", "warn", "error", "trace", "dir"];
    const originals = Object.fromEntries(names.map((n) => [n, console[n]]));
    names.forEach((n) => (console[n] = (...a) => calls.push([n, a])));
    const stdoutWrite = process.stdout.write;
    const stderrWrite = process.stderr.write;
    let wrote = 0;
    process.stdout.write = () => ((wrote++), true);
    process.stderr.write = () => ((wrote++), true);
    try {
        const headers = { authorization: "Bearer SECRET-TOKEN-123" };
        const secretPage = page("https://secret.example/private/path?x=SECRETQUERY", [field({ name: "pin" })], { text: "SECRETTEXT" });
        await post(app, { snapshot: secretPage, localSignals: [] }, { headers });
        await post(app, "{broken", { headers });
        await post(app, { snapshot: { url: "nope" } }, { headers });
        await post(app, "x".repeat(LIMITS.MAX_BODY_BYTES + 10), { headers });
        await app.request("/analyze", { method: "GET", headers });
        await app.request("/zzz", { method: "POST", headers, body: "{}" });
    } finally {
        names.forEach((n) => (console[n] = originals[n]));
        process.stdout.write = stdoutWrite;
        process.stderr.write = stderrWrite;
    }
    assert.deepEqual(calls, []);
    assert.equal(wrote, 0);
});
