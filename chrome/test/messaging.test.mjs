// node --test chrome/test/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { listen } from "../extension/messaging.js";

/** Fake chrome.runtime.onMessage: dispatch() resolves with what the listener sent back. */
function fakeOnMessage() {
    let listener = null;
    return {
        addListener: (fn) => (listener = fn),
        dispatch: (message) =>
            new Promise((resolve) => {
                const kept = listener(message, { tab: { id: 1 } }, resolve);
                assert.equal(kept, true, "must return true so Chrome keeps the channel open");
            }),
    };
}

test("a promise-returning handler answers through sendResponse", async () => {
    const onMessage = fakeOnMessage();
    listen(onMessage, async (message, sender) => ({ ok: true, echo: message.type, tab: sender.tab.id }));
    assert.deepEqual(await onMessage.dispatch({ type: "ping" }), { ok: true, echo: "ping", tab: 1 });
});

test("a plain return value works too", async () => {
    const onMessage = fakeOnMessage();
    listen(onMessage, () => ({ ok: true }));
    assert.deepEqual(await onMessage.dispatch({ type: "x" }), { ok: true });
});

test("a handler that throws answers ok:false instead of leaving the caller hanging", async () => {
    const onMessage = fakeOnMessage();
    listen(onMessage, () => {
        throw new Error("boom");
    });
    const warn = console.warn;
    console.warn = () => {};
    try {
        assert.deepEqual(await onMessage.dispatch({ type: "x" }), { ok: false, error: "internal" });
    } finally {
        console.warn = warn;
    }
});
