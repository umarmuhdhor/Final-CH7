// node --test chrome/test/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../extension/block.js");
await import("../extension/blocked-page.js"); // page part skips itself outside the browser
const { viewFor, nextPollMs } = globalThis.ShooBlockedPage;
const { payloadFor, encode, decode } = globalThis.ShooBlock;

const fixture = JSON.parse(readFileSync(new URL("../../contracts/fixtures/blocked-92.json", import.meta.url), "utf8"));
const payload = decode(encode(payloadFor({ ...fixture, scanId: 1 })));

test("fixture survives the URL fragment", () => {
    assert.equal(payload.score, 92);
    assert.equal(payload.domain, fixture.domain);
    assert.ok(payload.reasons.length >= 1 && payload.reasons.length <= 3);
});

test("no session (the Chrome default): reasons, no waiting box, no polling, no app button", () => {
    const view = viewFor(null, payload, "id");
    assert.deepEqual(view.reasons, payload.reasons.map((r) => r.label.id));
    assert.equal(view.showWaiting, false);
    assert.equal(view.poll, false);
    assert.equal("button" in view, false);
});

test("dev session, Protected: plain wording, waits for the guardian, polls", () => {
    const view = viewFor({ onboarded: true, mode: "protected", guardianName: "Rina" }, payload, "en");
    assert.deepEqual(view.reasons, payload.reasons.map((r) => r.labelSimple.en));
    assert.equal(view.waitingFor, "Rina");
    assert.equal(view.showWaiting, true);
    assert.equal(view.poll, true);
});

test("dev session, Guardian: polls without the waiting box", () => {
    const view = viewFor({ onboarded: true, mode: "guardian" }, payload, "en");
    assert.equal(view.showWaiting, false);
    assert.equal(view.poll, true);
});

test("a tampered fragment decodes to null (stays blocked, reopens nothing)", () => {
    assert.equal(decode("#not-json"), null);
    assert.equal(decode(encode({ ...payload, url: "javascript:alert(1)" })), null);
});

test("429 waits at least Retry-After", () => {
    assert.equal(nextPollMs(null), 5000);
    assert.equal(nextPollMs({ rateLimited: true, retryAfterMs: 12000 }), 12000);
});
