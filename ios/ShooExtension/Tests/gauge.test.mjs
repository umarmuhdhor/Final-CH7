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

test("bar: one piece per level reached, the rest is track (Figma Bar)", () => {
    const { barParts } = globalThis.ShooGauge;
    assert.deepEqual(barParts(70, 2), { fills: [{ color: "#FF9500", weight: 35 }, { color: "#F87541", weight: 35 }], track: 30 });
    assert.deepEqual(barParts(90, 3).fills.map((f) => f.color), ["#FF9500", "#F87541", "#E5483B"]);
    assert.equal(barParts(90, 3).track, 10);
    assert.deepEqual(barParts(140, 9), barParts(100, 3)); // clamped
});
