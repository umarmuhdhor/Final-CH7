// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/block.js"); // no ShooPipeline/browser here → helpers only
await import("../Resources/blocked-page.js");
const { payloadFor, encode, decode } = globalThis.ShooBlock;
const { viewFor } = globalThis.ShooBlockedPage;

const blocked92 = JSON.parse(readFileSync(new URL("../../../contracts/fixtures/blocked-92.json", import.meta.url), "utf8"));
const state = { ...blocked92, scanId: 3, status: "blocked" };

test("payload keeps the top 3 reasons by weight, both languages, nothing else", () => {
    const p = payloadFor(state);
    assert.deepEqual(p.reasons.map((r) => r.weight), [30, 25, 22]);
    assert.deepEqual(Object.keys(p).sort(), ["domain", "reasons", "recordId", "score", "url"]);
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

test("Protected: plain wording, waits for the guardian, no decision button", () => {
    const v = viewFor({ onboarded: true, mode: "protected", guardianName: "Adhella" }, payload, "id");
    assert.equal(v.reasons[0], "Situs ini baru dibuat 3 hari lalu");
    assert.equal(v.showWaiting, true);
    assert.equal(v.waitingFor, "Adhella");
    assert.equal(v.button, null);
    assert.equal(v.poll, true);
});

test("Protected without a connected guardian → generic waiting text", () => {
    const v = viewFor({ onboarded: true, mode: "protected", guardianName: null }, payload, "en");
    assert.equal(v.waitingFor, null);
});

test("Guardian: full wording, Review in Shoo, reopens after own Safe", () => {
    const v = viewFor({ onboarded: true, mode: "guardian" }, payload, "en");
    assert.equal(v.reasons[0], "Domain age 3 days");
    assert.equal(v.showWaiting, false);
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
    assert.equal(v.showWaiting, false);
});
