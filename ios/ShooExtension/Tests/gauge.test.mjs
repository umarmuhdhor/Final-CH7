// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

await import("../Resources/gauge.js");
const { gauge, ring } = globalThis.ShooGauge;

test("needle points at the score: 0 = left, 100 = right (Figma: 92% → -14.4°, 72% → -50.4°)", () => {
    assert.match(gauge(92, "bahaya"), /rotate\(-14\.4 /);
    assert.match(gauge(72, "tinggi"), /rotate\(-50\.4 /);
    assert.match(gauge(0, "sedang"), /fill="#383d43" transform="rotate\(-180 /);
});

test("the tube uses the level's colours", () => {
    assert.match(gauge(92, "bahaya"), /#C42B1C/);
    assert.match(gauge(72, "tinggi"), /#EB8900/);
    assert.doesNotMatch(gauge(40, "sedang"), /sg-shadow/); // no shadow on Level=Sedang in Figma
});

test("out-of-range scores are clamped", () => {
    assert.equal(gauge(140, "bahaya"), gauge(100, "bahaya"));
    assert.equal(ring(-5, "tinggi"), ring(0, "tinggi"));
});

test("ring: a full score still draws a closed tube", () => {
    assert.match(ring(100, "tinggi"), /url\(#sr-tube-fill\)/);
    assert.doesNotMatch(ring(0, "tinggi"), /url\(#sr-tube-fill\)/);
});
