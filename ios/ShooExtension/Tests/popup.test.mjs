// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../Resources/pipeline.js");
await import("../Resources/popup.js"); // view part skips itself outside the browser
const { decide, dismissed, tierFor, detailUrl } = globalThis.ShooPopup;

/** Feeds a page's score updates through decide(); returns the actions, flattened. */
function play(scores, { scanId = 1, memo = null } = {}) {
    const actions = [];
    for (const score of scores) {
        const r = decide(memo, { scanId, score, url: "https://x.test/" });
        memo = r.memo;
        actions.push(...r.actions.map((a) => (a.type === "show" ? `show${a.tier}` : a.type)));
    }
    return { actions, memo };
}

test("tiers follow the thresholds", () => {
    assert.deepEqual([0, 29, 30, 49, 50, 79, 80].map(tierFor), [0, 0, 1, 1, 2, 2, "blocked"]);
});

test("first warning at 30, second at 50, each once", () => {
    assert.deepEqual(play([0, 35, 35, 60, 60]).actions, ["show1", "update", "show2", "update"]);
});

test("jumping straight past 50 shows only the second popup", () => {
    assert.deepEqual(play([0, 63]).actions, ["show2"]);
});

test("straight to ≥80 → no popup at all (block screen instead)", () => {
    assert.deepEqual(play([0, 92]).actions, []);
});

test("warning then blocked → popup hides and never returns on that page", () => {
    assert.deepEqual(play([0, 41, 92, 41]).actions, ["show1", "hide"]);
});

test("safe verdict drops the score to 0 → popup hides", () => {
    assert.deepEqual(play([0, 41, 0]).actions, ["show1", "hide"]);
});

test("closed popup stays closed for its tier, the stronger one still appears", () => {
    let { memo } = play([0, 35]);
    memo = dismissed(memo);
    assert.deepEqual(play([40], { memo }).actions, []); // no update, no re-show
    assert.deepEqual(play([55], { memo }).actions, ["show2"]);
});

test("new page resets: old popup hides, warnings can show again", () => {
    const { memo } = play([0, 55], { scanId: 1 });
    assert.deepEqual(play([0, 35], { scanId: 2, memo }).actions, ["hide", "show1"]);
});

test("See detail links to the scan once EX-07 has an id, else Activity", () => {
    assert.equal(detailUrl({ recordId: "6f1c2a4e" }), "shoo://scan/6f1c2a4e");
    assert.equal(detailUrl({}), "shoo://activity");
});

test("50–79 opens as the sheet until minimized; 30–49 is always the mini card", () => {
    const { layoutFor } = globalThis.ShooPopup;
    assert.equal(layoutFor(2, false), "sheet");
    assert.equal(layoutFor(2, true), "mini");
    assert.equal(layoutFor(1, false), "mini");
});

test("card text: heaviest reason first, plain wording for Protected, advice last", () => {
    const { describe } = globalThis.ShooPopup;
    const signals = [
        { weight: 10, label: { en: "Young domain" }, labelSimple: { en: "This site is new" } },
        { weight: 30, label: { en: "Asks for PIN" }, labelSimple: { en: "This page asks for your PIN!" } },
    ];
    assert.equal(describe(signals, { simple: false, lang: "en", advice: "Don't type it." }), "Asks for PIN. Don't type it.");
    assert.equal(describe(signals, { simple: true, lang: "en", advice: "Don't type it." }), "This page asks for your PIN! Don't type it.");
    assert.equal(describe([], { simple: false, lang: "en", advice: "Be careful." }), "Be careful.");
});
