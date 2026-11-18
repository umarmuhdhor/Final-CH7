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

test("bar: one piece per detection layer, as long as its share; the rest is track (Figma Bar)", () => {
    const { barParts, layerWeights } = globalThis.ShooGauge;
    const sig = (layer, weight) => ({ layer, weight });
    // Layer 2 only: one piece, however many reasons.
    assert.deepEqual(layerWeights([sig(2, 40), sig(2, 14)]), [54]);
    assert.deepEqual(barParts(54, [54]), { fills: [{ color: "#FF9500", weight: 54 }], track: 46 });
    // Layer 2 + 3: two pieces, lowest layer first, scaled to the score.
    assert.deepEqual(layerWeights([sig(3, 30), sig(2, 14), sig(3, 25)]), [14, 55]);
    assert.deepEqual(barParts(69, [14, 55]).fills, [{ color: "#FF9500", weight: 14 }, { color: "#F87541", weight: 55 }]);
    // Layer 2–4: three pieces; zero weights and junk are left out.
    assert.deepEqual(layerWeights([sig(4, 22), sig(2, 15), sig(3, 55), sig(5, 0), null]), [15, 55, 22]);
    assert.deepEqual(barParts(92, [15, 55, 22]).fills.map((f) => f.color), ["#FF9500", "#F87541", "#E5483B"]);
    assert.equal(barParts(92, [15, 55, 22]).track, 8);
    // Sum over 100 (score capped): pieces shrink to the score, keeping their shares.
    assert.deepEqual(barParts(100, [70, 50]).fills.map((f) => f.weight), [58.333, 41.667]);
    // No layer known: one piece for the whole score; out of range clamped.
    assert.deepEqual(barParts(80, []), { fills: [{ color: "#FF9500", weight: 80 }], track: 20 });
    assert.deepEqual(barParts(140, [1]), barParts(100, [1]));
});
