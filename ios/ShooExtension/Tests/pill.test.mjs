// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../Resources/pipeline.js");
await import("../Resources/pill.js"); // view part skips itself outside the browser
const { decide, dismissed, toneFor, reasonTexts, snap, place, validPos, SIZE, MARGIN } = globalThis.ShooPill;

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

test("low final score stays on screen", () => {
    const { views } = play([{ score: 10 }, { score: 10, done: true }]);
    assert.equal(views[1].visible, true);
    assert.equal(views[1].analyzing, false);
    assert.equal(views[1].tone, "safe");
});

test("a re-check after the page changed moves the score live", () => {
    const { views } = play([{ score: 10, done: true }, { score: 35 }, { score: 35, done: true, status: "warning" }]);
    assert.deepEqual(views.map((v) => [v.visible, v.score, v.analyzing]), [[true, 10, false], [true, 35, true], [true, 35, false]]);
});

test("warning final score stays on screen", () => {
    const { views } = play([{ score: 55, done: true, status: "warning" }]);
    assert.equal(views[0].visible, true);
    assert.equal(views[0].tone, "danger");
});

test("blocked → hidden (block screen owns the page)", () => {
    const { views } = play([{ score: 40 }, { score: 100, status: "blocked", done: true }]);
    assert.deepEqual(views.map((v) => v.visible), [true, false]);
});

test("safe verdict → score 0, still on screen", () => {
    const { views } = play([{ score: 40 }, { score: 0, done: true, verdict: { value: "safe" } }]);
    assert.equal(views[1].visible, true);
    assert.equal(views[1].score, 0);
    assert.equal(views[1].tone, "safe");
});

test("Hide tapped → stays hidden on this page, comes back on the next one", () => {
    let { memo } = play([{ score: 35 }]);
    memo = dismissed(memo);
    const same = play([{ score: 60 }], { memo });
    assert.equal(same.views[0].visible, false);
    const next = play([{ score: 0 }], { scanId: 2, memo: same.memo });
    assert.equal(next.views[0].visible, true);
});

const sig = (id, weight, en, simpleEn) => ({
    id, layer: 2, weight,
    label: { en, id: `${en} (id)` },
    labelSimple: { en: simpleEn ?? `${en} simply`, id: `${simpleEn ?? en} sederhana` },
});

test("card reasons: heaviest first, max 2, mode and language pick the wording", () => {
    const signals = [sig("cheap_tld", 10, "Cheap TLD"), sig("asks_pin", 40, "Asks for PIN"), sig("new_domain", 25, "New domain")];
    assert.deepEqual(reasonTexts(signals, { simple: false, lang: "en" }), ["Asks for PIN", "New domain"]);
    assert.deepEqual(reasonTexts(signals, { simple: true, lang: "en" }), ["Asks for PIN simply", "New domain simply"]);
    assert.deepEqual(reasonTexts(signals, { simple: false, lang: "id" }), ["Asks for PIN (id)", "New domain (id)"]);
});

test("card reasons: missing wording and duplicates are skipped", () => {
    const signals = [sig("a", 30, "Same"), sig("b", 20, "Same"), { id: "c", layer: 3, weight: 50, label: {}, labelSimple: {} }];
    assert.deepEqual(reasonTexts(signals, { simple: false, lang: "en" }), ["Same"]);
    assert.deepEqual(reasonTexts(undefined, { simple: false, lang: "en" }), []);
});

const phone = { width: 390, height: 700, top: 47, bottom: 34 };

test("drop snaps to the nearer side edge", () => {
    assert.equal(snap({ x: 100, y: 300 }, phone).side, "left");
    assert.equal(snap({ x: 300, y: 300 }, phone).side, "right");
    assert.deepEqual(place({ side: "left", y: 300 / 700 }, phone), { x: MARGIN, y: 300 - SIZE / 2 });
    assert.equal(place({ side: "right", y: 0.5 }, phone).x, 390 - SIZE - MARGIN);
});

test("drop stays inside the safe area (notch and home bar)", () => {
    const high = place(snap({ x: 10, y: 0 }, phone), phone);
    assert.equal(high.y, phone.top + MARGIN);
    const low = place(snap({ x: 10, y: 700 }, phone), phone);
    assert.equal(low.y + SIZE, phone.height - phone.bottom - MARGIN);
});

test("stored position: bad values fall back to the default", () => {
    assert.deepEqual(validPos({ side: "left", y: 0.2 }), { side: "left", y: 0.2 });
    for (const bad of [null, undefined, {}, { side: "top", y: 0.5 }, { side: "left", y: 2 }, { side: "right", y: "x" }]) {
        assert.equal(validPos(bad).side, "right");
    }
});
