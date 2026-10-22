// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../Resources/pipeline.js");
await import("../Resources/pill.js"); // view part skips itself outside the browser
const { decide, dismissed, toneFor, LINGER_MS } = globalThis.ShooPill;

/** Feeds a page's pipeline states through decide(); returns the views. */
function play(states, { scanId = 1, memo = null } = {}) {
    const views = [];
    for (const s of states) {
        const r = decide(memo, { scanId, status: "normal", done: false, ...s });
        memo = r.memo;
        views.push(r.view);
    }
    return { views, memo };
}

test("tone follows the thresholds", () => {
    assert.deepEqual([0, 29, 30, 49, 50, 79].map(toneFor), ["safe", "safe", "warning", "warning", "danger", "danger"]);
});

test("visible and analyzing while layers run, score moves with each layer", () => {
    const { views } = play([{ score: 0 }, { score: 20 }, { score: 45 }]);
    assert.deepEqual(
        views.map((v) => [v.visible, v.score, v.analyzing]),
        [[true, 0, true], [true, 20, true], [true, 45, true]],
    );
});

test("low final score fades out after a few seconds", () => {
    const { views } = play([{ score: 10 }, { score: 10, done: true }]);
    assert.equal(views[1].visible, true);
    assert.equal(views[1].analyzing, false);
    assert.equal(views[1].hideAfterMs, LINGER_MS);
});

test("warning final score stays on screen", () => {
    const { views } = play([{ score: 55, done: true, status: "warning" }]);
    assert.equal(views[0].visible, true);
    assert.equal(views[0].tone, "danger");
    assert.equal(views[0].hideAfterMs, undefined);
});

test("blocked → hidden (block screen owns the page)", () => {
    const { views } = play([{ score: 40 }, { score: 100, status: "blocked", done: true }]);
    assert.deepEqual(views.map((v) => v.visible), [true, false]);
});

test("safe verdict → score 0, then fades out", () => {
    const { views } = play([{ score: 40 }, { score: 0, done: true, verdict: { value: "safe" } }]);
    assert.equal(views[1].score, 0);
    assert.equal(views[1].tone, "safe");
    assert.equal(views[1].hideAfterMs, LINGER_MS);
});

test("tapped → stays hidden on this page, comes back on the next one", () => {
    let { memo } = play([{ score: 35 }]);
    memo = dismissed(memo);
    const same = play([{ score: 60 }], { memo });
    assert.equal(same.views[0].visible, false);
    const next = play([{ score: 0 }], { scanId: 2, memo: same.memo });
    assert.equal(next.views[0].visible, true);
});
