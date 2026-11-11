// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/block.js"); // no ShooPipeline/browser here → helpers only
await import("../Resources/blocked-page.js");
const { payloadFor, encode, decode } = globalThis.ShooBlock;
const { viewFor, nextPollMs, middleEllipsis } = globalThis.ShooBlockedPage;

const blocked92 = JSON.parse(readFileSync(new URL("../../../contracts/fixtures/blocked-92.json", import.meta.url), "utf8"));
const state = { ...blocked92, scanId: 3, status: "blocked" };

test("payload keeps the top 3 reasons by weight, both languages, nothing else", () => {
    const p = payloadFor(state);
    assert.deepEqual(p.reasons.map((r) => r.weight), [30, 25, 22]);
    assert.deepEqual(Object.keys(p).sort(), ["domain", "reasons", "recordId", "remembered", "reportKey", "score", "url"]);
    assert.deepEqual(Object.keys(p.reasons[0]).sort(), ["id", "label", "labelSimple", "weight"]);
});

test("payload round-trips through the URL fragment", () => {
    const p = payloadFor(state);
    assert.deepEqual(decode("#" + encode(p)), p);
});

test("tampered or missing fragment → null (stays blocked, never reopens)", () => {
    assert.equal(decode(""), null);
    assert.equal(decode("#not-json"), null);
    const evil = { ...payloadFor(state), url: "javascript:alert(1)" };
    assert.equal(decode("#" + encode(evil)), null);
    const noScore = { ...payloadFor(state), score: "92" };
    assert.equal(decode("#" + encode(noScore)), null);
});

const payload = payloadFor(state);

test("Protected: plain wording, link sent to the guardian, Review in Shoo, reopens once marked safe", () => {
    const v = viewFor({ onboarded: true, mode: "protected", guardianName: "Adhella" }, payload, "id");
    assert.equal(v.reasons[0], "Situs ini baru dibuat 3 hari lalu");
    assert.equal(v.sentTo, "Adhella");
    assert.deepEqual(v.button, { textKey: "block_review", href: "shoo://activity" });
    assert.equal(v.poll, true);
});

test("Protected without a connected guardian → no Link sent pill", () => {
    const v = viewFor({ onboarded: true, mode: "protected", guardianName: null }, payload, "en");
    assert.equal(v.sentTo, null);
});

test("Guardian: full wording, Review in Shoo, reopens after own Safe", () => {
    const v = viewFor({ onboarded: true, mode: "guardian" }, payload, "en");
    assert.equal(v.reasons[0], "Domain age 3 days");
    assert.equal(v.sentTo, null);
    assert.deepEqual(v.button, { textKey: "block_review", href: "shoo://activity" });
    assert.equal(v.poll, true);
});

test("Review in Shoo opens the scan once it has an id", () => {
    const v = viewFor({ onboarded: true, mode: "guardian" }, { ...payload, recordId: "abc" }, "en");
    assert.equal(v.button.href, "shoo://scan/abc");
});

test("App not set up → Open Shoo, nothing to poll", () => {
    const v = viewFor({ onboarded: false }, payload, "en");
    assert.deepEqual(v.button, { textKey: "block_open_app", href: "shoo://activity" });
    assert.equal(v.poll, false);
    assert.equal(v.sentTo, null);
});

test("block screen polls every 5 s, and waits out a 429's Retry-After instead of hammering", () => {
    assert.equal(nextPollMs({ ok: true, verdict: null }), 5000);
    assert.equal(nextPollMs(null), 5000); // offline
    assert.equal(nextPollMs({ ok: true, verdict: null, rateLimited: true, retryAfterMs: 12000 }), 12000);
    assert.equal(nextPollMs({ ok: true, verdict: null, rateLimited: true, retryAfterMs: 1000 }), 5000); // never faster
});

test("#382: a block from memory shows no reasons of its own (they may be another page's)", () => {
    const p = { ...payloadFor({ ...state, remembered: true }) };
    assert.equal(p.remembered, true);
    const v = viewFor({ onboarded: true, mode: "protected", guardianName: "Adhella" }, p, "id");
    assert.equal(v.remembered, true);
    assert.deepEqual(v.reasons, []);
    assert.equal(viewFor({ onboarded: true, mode: "guardian" }, payloadFor(state), "en").remembered, false);
});

test("#382: a long name is cut in the middle and keeps its ending", () => {
    const long = "verifikasi-akun-nasabah-prioritas-bank-central-asia-2026-resmi.com";
    const chip = middleEllipsis(long);
    assert.equal(chip.length, 32);
    assert.ok(chip.includes("…"));
    assert.ok(chip.endsWith("resmi.com"));
    assert.ok(chip.startsWith("verifikasi"));
    assert.equal(middleEllipsis("klikbca.com"), "klikbca.com");
    assert.ok(middleEllipsis(`a.${"x".repeat(40)}.co.id`).endsWith(".co.id"));
});

test("#382: an IDN look-alike keeps its punycode, with the detector's look-alike line under it", () => {
    const lookalike = { id: "lookalike_domain", weight: 25, label: { en: "Domain spelled like BCA", id: "Nama domain meniru BCA" }, labelSimple: { en: "x", id: "y" } };
    const p = { url: "https://xn--bc-8kc.co.id/", domain: "xn--bc-8kc.co.id", score: 90, reasons: [lookalike, ...payloadFor(state).reasons] };
    const v = viewFor({ onboarded: true, mode: "guardian" }, p, "id");
    assert.equal(v.chip, "xn--bc-8kc.co.id");
    assert.equal(v.lookalike, "Nama domain meniru BCA");
    assert.ok(!v.reasons.includes("Nama domain meniru BCA"));
    assert.equal(viewFor({ onboarded: true, mode: "guardian" }, { ...p, domain: "bca-verify.xyz" }, "id").lookalike, null);
});
