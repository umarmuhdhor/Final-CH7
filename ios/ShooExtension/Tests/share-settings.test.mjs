// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { mayReport } from "../Resources/share-settings.js";

test("blocked always goes out, whatever the switches say", () => {
    assert.equal(mayReport("blocked", { autoSend: false, shareWarnings: false }), true);
    assert.equal(mayReport("blocked", { autoSend: false, shareWarnings: true }), true);
    assert.equal(mayReport("blocked", { autoSend: true, shareWarnings: false }), true);
});

test("warning goes out only with both switches on", () => {
    assert.equal(mayReport("warning", { autoSend: true, shareWarnings: true }), true);
    assert.equal(mayReport("warning", { autoSend: false, shareWarnings: true }), false);
    assert.equal(mayReport("warning", { autoSend: true, shareWarnings: false }), false);
});

test("an older app without the switches keeps sending", () => {
    assert.equal(mayReport("warning", { token: "t0k" }), true);
});
