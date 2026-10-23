// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/report.js"); // no pipeline/DOM here → helpers only
import { cropBox, smallestFitting } from "../Resources/capture.js";
const { shouldReport, scanBody, shareableUrl, evidenceRect, screenshotTargets } = globalThis.ShooReport;

const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), "utf8"));
const schema = read("../../../contracts/scan-result.schema.json");
const warning63 = read("../../../contracts/fixtures/warning-63.json");

test("reports once per page: when blocked, or when a warning page is done", () => {
    const seen = new Set();
    assert.equal(shouldReport({ scanId: 1, status: "warning", done: false }, seen), false); // layers still running
    assert.equal(shouldReport({ scanId: 1, status: "warning", done: true }, seen), true);
    assert.equal(shouldReport({ scanId: 2, status: "blocked", done: false }, seen), true); // don't wait: page is leaving
    assert.equal(shouldReport({ scanId: 3, status: "normal", done: true }, seen), false); // < 30 never leaves the phone
    seen.add(2);
    assert.equal(shouldReport({ scanId: 2, status: "blocked", done: true }, seen), false);
});

test("POST /scans body matches ScanResult once background adds the owner", () => {
    const state = { ...warning63, signals: [...warning63.signals].reverse(), scanId: 1, done: true };
    const body = {
        ...scanBody(state, { title: "Bansos", faviconUrl: null, now: "2026-10-21T10:00:00.000Z" }),
        ownerDeviceId: "dev-1",
        ownerName: "Ibu",
    };
    const sendable = schema.required.filter((k) => k !== "id"); // id is assigned by the backend
    for (const key of sendable) assert.ok(key in body, `missing ${key}`);
    for (const key of Object.keys(body)) assert.ok(key in schema.properties, `unknown field ${key}`);
    assert.ok(!("verdict" in body) && !("id" in body));
    assert.ok(schema.properties.status.enum.includes(body.status));
    assert.deepEqual(body.signals.map((s) => s.weight), [25, 15, 13, 10]); // highest weight first
});

test("POST /scans url drops query, fragment and credentials; domain is untouched", () => {
    assert.equal(shareableUrl("https://bank.example/reset?token=abc123#sid=9"), "https://bank.example/reset");
    assert.equal(shareableUrl("https://user:pw@bansos.example:8443/klaim/form?nik=1"), "https://bansos.example:8443/klaim/form");
    assert.equal(shareableUrl("https://bansos.example"), "https://bansos.example/");
    const state = { ...warning63, url: "https://bansos-klaim.example/form?otp=1234#x", scanId: 1, done: true };
    const body = scanBody(state, { title: "", faviconUrl: null, now: "2026-10-21T10:00:00.000Z" });
    assert.equal(body.url, "https://bansos-klaim.example/form");
    assert.equal(body.domain, warning63.domain);
});

test("evidence = the sensitive form plus padding, clamped to the viewport", () => {
    const viewport = { width: 390, height: 844 };
    assert.deepEqual(evidenceRect({ left: 20, top: 300, right: 370, bottom: 520 }, viewport), { x: 4, y: 284, width: 382, height: 252 });
    assert.deepEqual(evidenceRect({ left: -50, top: 800, right: 500, bottom: 1200 }, viewport), { x: 0, y: 784, width: 390, height: 60 });
});

test("no form on screen → whole viewport", () => {
    const viewport = { width: 390, height: 844 };
    const full = { x: 0, y: 0, width: 390, height: 844 };
    assert.deepEqual(evidenceRect(null, viewport), full);
    assert.deepEqual(evidenceRect({ left: 0, top: 2000, right: 390, bottom: 2300 }, viewport), full); // scrolled away
});

test("crop maps CSS px to device px; a small form keeps full resolution", () => {
    // 3x iPhone: 390 CSS px → 1170 image px
    const box = cropBox({ x: 4, y: 284, width: 382, height: 252, viewportWidth: 390 }, 1170, 2532);
    assert.deepEqual(box, { sx: 12, sy: 852, sw: 1146, sh: 756, width: 1146, height: 756 });
});

test("longest side is capped at 1280 px (contract), also for tall full-screen crops", () => {
    const full = cropBox({ x: 0, y: 0, width: 390, height: 844, viewportWidth: 390 }, 1170, 2532);
    assert.equal(Math.max(full.width, full.height), 1280);
    assert.equal(full.width, Math.round(1170 * (1280 / 2532)));
});

test("screenshot falls back to lower quality, then to none, to stay ≤ 150 KB", async () => {
    const sizes = { 0.6: 200_000, 0.45: 140_000, 0.3: 90_000 };
    const fits = await smallestFitting(async (q) => ({ size: sizes[q], q }));
    assert.equal(fits.q, 0.45);
    assert.equal(await smallestFitting(async () => ({ size: 500_000 })), null);
});

test("crop never reads outside the image", () => {
    const box = cropBox({ x: 300, y: 800, width: 200, height: 200, viewportWidth: 390 }, 390, 844);
    assert.equal(box.sx + box.sw, 390);
    assert.equal(box.sy + box.sh, 844);
    assert.equal(cropBox({ x: 400, y: 0, width: 10, height: 10, viewportWidth: 390 }, 390, 844), null);
});

// Minimal DOM stand-ins for screenshotTargets: fields and iframes per document.
const fakeDoc = (name, { fields = [], frames = [] } = {}) => ({
    querySelectorAll: (sel) => (sel === "iframe, frame" ? frames : fields.map((type, i) => ({ type, name: `${name}.${type}.${i}` }))),
});
const frameOf = (doc) => ({ contentDocument: doc });
const names = (els) => els.map((el) => el.name);

test("screenshot blurs text fields of the page and of same-origin iframes, nested too (#75)", () => {
    const nested = fakeDoc("nested", { fields: ["text"] });
    const inner = fakeDoc("inner", { fields: ["password", "checkbox"], frames: [frameOf(nested)] });
    const page = fakeDoc("page", { fields: ["email", "submit"], frames: [frameOf(inner)] });
    const { blur, hide } = screenshotTargets(page);
    assert.deepEqual(names(blur), ["page.email.0", "inner.password.0", "nested.text.0"]);
    assert.deepEqual(hide, []);
});

test("screenshot hides iframes it can't look into: cross-origin fields can't be blurred", () => {
    const empty = frameOf(null);
    const throwing = { get contentDocument() { throw new Error("SecurityError"); } };
    const page = fakeDoc("page", { fields: ["text"], frames: [empty, throwing] });
    const { blur, hide } = screenshotTargets(page);
    assert.deepEqual(names(blur), ["page.text.0"]);
    assert.deepEqual(hide, [empty, throwing]);
});

test("screenshot hides same-origin iframes nested deeper than the limit instead of walking forever", () => {
    let doc = fakeDoc("d5", { fields: ["text"] });
    const frames = [];
    for (let i = 4; i >= 0; i--) {
        const frame = frameOf(doc);
        frames.unshift(frame);
        doc = fakeDoc(`d${i}`, { fields: ["text"], frames: [frame] });
    }
    const { blur, hide } = screenshotTargets(doc); // d0 → d1 → d2 → d3 | d4 hidden
    assert.deepEqual(names(blur), ["d0.text.0", "d1.text.0", "d2.text.0", "d3.text.0"]);
    assert.deepEqual(hide, [frames[3]]);
});
