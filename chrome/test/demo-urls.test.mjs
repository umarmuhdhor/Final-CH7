// node --test chrome/test/*.test.mjs
// The demo URLs (README, test/e2e) land in the band they are meant to show, with layer 1–2 only.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PSL_RULES } from "../extension/psl.js";
import { parseRules, registrableDomain } from "../extension/domain.js";

await import("../extension/pipeline.js");
await import("../extension/detector.js");
const { scoreFrom, validSignals } = globalThis.ShooPipeline;
const urls = JSON.parse(readFileSync(new URL("./fixtures/demo-urls.json", import.meta.url), "utf8"));
const rules = parseRules(PSL_RULES);

async function score(url) {
    const { hostname } = new URL(url);
    const snapshot = { url, domain: registrableDomain(hostname, rules), title: "", lang: null, text: "", forms: [], imageAlts: [], capturedAt: "" };
    return scoreFrom(validSignals(await globalThis.ShooDetector.analyzeLocal(snapshot), [1, 2]));
}

const bands = { safe: [0, 29], mini: [30, 49], sheet: [50, 79], block: [80, 100] };
for (const [name, [min, max]] of Object.entries(bands)) {
    test(`${name}: ${urls[name]} scores ${min}–${max}`, async () => {
        const value = await score(urls[name]);
        assert.ok(value >= min && value <= max, `got ${value}`);
    });
}
