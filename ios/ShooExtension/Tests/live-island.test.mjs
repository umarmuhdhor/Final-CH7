// node --test ios/ShooExtension/Tests/*.test.mjs
// #486: live-island.js tells background the same thing the pill says, so the island never reads "Aman" when the
// pill says "Cek online tidak tersedia" or "Ditandai aman oleh …".
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../Resources/pipeline.js");
const pipeline = globalThis.ShooPipeline;

// Just enough of a page for a content script: visibility, location, events, runtime messages.
const messages = [];
let subscriber = null;
globalThis.Document ??= class Document {};
Object.defineProperty(Document.prototype, "visibilityState", { configurable: true, get: () => "visible" });
globalThis.document = Object.create(Document.prototype);
globalThis.location = { hostname: "hadiah-gratis.xyz" };
globalThis.addEventListener = () => {};
globalThis.browser = { runtime: { sendMessage: async (m) => { messages.push(m); } } };
const realSubscribe = pipeline.subscribe;
pipeline.subscribe = (fn) => { subscriber = fn; return () => {}; };
await import("../Resources/live-island.js");
pipeline.subscribe = realSubscribe;

function sendState(state) {
    messages.length = 0;
    subscriber({ scanId: 1, status: "normal", score: 0, done: true, onlineChecked: true, verdict: null, ...state });
    return messages[0];
}

test("/analyze failed on a low score → label offline_check", () => {
    const m = sendState({ score: 25, onlineChecked: false });
    assert.equal(m.label, "offline_check");
    assert.equal(m.status, "normal");
});

test("a link a Guardian marked safe → label marked_safe", () => {
    assert.equal(sendState({ score: 60, verdict: { value: "safe", byName: "Gita" } }).label, "marked_safe");
});

test("checked online, still analyzing, or a warning → no label", () => {
    assert.equal(sendState({ score: 25 }).label, null);
    assert.equal(sendState({ score: 25, onlineChecked: false, done: false }).label, null);
    assert.equal(sendState({ score: 40, status: "warning", onlineChecked: false }).label, null);
    assert.equal(sendState({ score: 90, status: "blocked", verdict: { value: "safe" } }).label, null);
});

test("secondWarning follows the thresholds the pill uses", () => {
    const saved = { ...pipeline.THRESHOLD };
    Object.assign(pipeline.THRESHOLD, { firstWarning: 50, secondWarning: 65, blocked: 80 });
    try {
        assert.equal(sendState({ score: 55, status: "warning" }).secondWarning, 65);
    } finally {
        Object.assign(pipeline.THRESHOLD, saved);
    }
});
