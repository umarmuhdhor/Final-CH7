// node --test chrome/test/*.test.mjs
// Chrome popup.js = Safari's (PR #160) minus "See detail": the tier logic must stay the same.
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../extension/pipeline.js");
await import("../extension/popup.js"); // view part skips itself outside the browser
const { decide, dismissed, tierFor, layoutFor, describe } = globalThis.ShooPopup;

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

test("first warning at 30, second at 50, each once; straight to ≥80 shows nothing", () => {
    assert.deepEqual(play([0, 35, 35, 60, 60]).actions, ["show1", "update", "show2", "update"]);
    assert.deepEqual(play([0, 92]).actions, []);
    assert.deepEqual(play([0, 41, 92, 41]).actions, ["show1", "hide"]);
});

test("closed mini card stays closed for its tier; new page resets", () => {
    let { memo } = play([0, 35]);
    memo = dismissed(memo);
    assert.deepEqual(play([40], { memo }).actions, []);
    assert.deepEqual(play([55], { memo }).actions, ["show2"]);
    const shown = play([0, 55], { scanId: 1 }).memo;
    assert.deepEqual(play([0, 35], { scanId: 2, memo: shown }).actions, ["hide", "show1"]);
});

test("30–49 is the mini card; 50–79 is the sheet until Continue shrinks it", () => {
    assert.equal(layoutFor(1, false), "mini");
    assert.equal(layoutFor(2, false), "sheet");
    assert.equal(layoutFor(2, true), "mini");
});

test("card text: heaviest reason, plain wording for Protected, then the advice", () => {
    const signals = [
        { weight: 10, label: { en: "Young domain" }, labelSimple: { en: "This site is new" } },
        { weight: 30, label: { en: "Asks for PIN" }, labelSimple: { en: "This page asks for your PIN!" } },
    ];
    assert.equal(describe(signals, { simple: false, lang: "en", advice: "Don't type it." }), "Asks for PIN. Don't type it.");
    assert.equal(describe(signals, { simple: true, lang: "en", advice: "Don't type it." }), "This page asks for your PIN! Don't type it.");
    assert.equal(describe([], { simple: false, lang: "en", advice: "Be careful." }), "Be careful.");
});

test("no detail link: Chrome has no Shoo app", () => {
    assert.equal("detailUrl" in globalThis.ShooPopup, false);
});
