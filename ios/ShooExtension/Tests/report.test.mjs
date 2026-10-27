// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/dom.js");
await import("../Resources/report.js"); // no pipeline/DOM here → helpers only
import { cropBox, findMarker, smallestFitting } from "../Resources/capture.js";
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

test("crop starts at the viewport's corner in the image, not at the image's (area under the status bar)", () => {
    // iPhone 17 Pro, Safari 26: viewport y = 0 is 62 pt (186 px) down the capture
    const box = cropBox({ x: 4, y: 284, width: 382, height: 252, viewportWidth: 402 }, 1206, 2622, 1280, { x: 0, y: 186 });
    assert.equal(box.sx, 12);
    assert.equal(box.sy, 186 + 852);
});

// Capture stand-in: background colour plus report.js's marker (magenta band over cyan band) at (mx, my).
const MAGENTA = [255, 0, 255];
const CYAN = [0, 255, 255];
const captureWith = ({ mx, my, band, extra = () => null }) => (x, y) => {
    const own = extra(x, y);
    if (own) return own;
    if (mx == null || x < mx || x >= mx + 2 * band || y < my || y >= my + 2 * band) return [245, 246, 250];
    return y < my + band ? MAGENTA : CYAN;
};

test("paint marker gives the viewport's corner in the capture", () => {
    const band = 12; // 4 CSS px at 3x
    assert.deepEqual(findMarker(captureWith({ mx: 0, my: 186, band }), 1206, 2622, band), { x: 0, y: 186 });
    assert.deepEqual(findMarker(captureWith({ mx: 177, my: 0, band }), 2622, 1206, band), { x: 177, y: 0 }); // landscape inset
});

test("no paint marker → null, so the capture is retried or dropped instead of sent unblurred", () => {
    const band = 12;
    assert.equal(findMarker(captureWith({ band }), 1206, 2622, band), null);
    // A page's own magenta (logo, ad) above the marker isn't taken for it
    const logo = (x, y) => (x >= 40 && x < 400 && y >= 20 && y < 60 ? MAGENTA : null);
    assert.deepEqual(findMarker(captureWith({ mx: 0, my: 186, band, extra: logo }), 1206, 2622, band), { x: 0, y: 186 });
    assert.equal(findMarker(captureWith({ mx: 0, my: 186, band }), 1206, 2622, undefined), null); // old message shape
});

test("crop never reads outside the image", () => {
    const box = cropBox({ x: 300, y: 800, width: 200, height: 200, viewportWidth: 390 }, 390, 844);
    assert.equal(box.sx + box.sw, 390);
    assert.equal(box.sy + box.sh, 844);
    assert.equal(cropBox({ x: 400, y: 0, width: 10, height: 10, viewportWidth: 390 }, 390, 844), null);
});

// Minimal DOM stand-ins for screenshotTargets: fields, frames and shadow hosts per document.
const fakeDoc = (name, { fields = [], frames = [], hosts = [] } = {}) => ({
    querySelectorAll: (sel) => {
        if (sel.startsWith("iframe")) return frames;
        if (sel === "*") return hosts;
        return fields.map((type, i) => ({ type, name: `${name}.${type}.${i}` }));
    },
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

test("screenshot hides an iframe still loading a cross-origin src: its blank document has no fields yet", () => {
    // Before the src loads, contentDocument is the initial about:blank, which is same-origin with the page
    const blank = { ...fakeDoc("blank"), URL: "about:blank" };
    const loading = { contentDocument: blank, getAttribute: (a) => (a === "src" ? "https://pay.example/form" : null), hasAttribute: () => false };
    const page = fakeDoc("page", { fields: ["text"], frames: [loading] });
    assert.deepEqual(screenshotTargets(page).hide, [loading]);
});

test("screenshot still looks into iframes that stay blank (no src, about:, srcdoc)", () => {
    const blankWith = (name) => ({ ...fakeDoc(name, { fields: ["text"] }), URL: "about:blank" });
    const frame = (doc, attrs) => ({ contentDocument: doc, getAttribute: (a) => attrs[a] ?? null, hasAttribute: (a) => a in attrs });
    const page = fakeDoc("page", {
        frames: [frame(blankWith("nosrc"), {}), frame(blankWith("about"), { src: "about:blank" }), frame(blankWith("srcdoc"), { srcdoc: "<p>" })],
    });
    const { blur, hide } = screenshotTargets(page);
    assert.deepEqual(names(blur), ["nosrc.text.0", "about.text.0", "srcdoc.text.0"]);
    assert.deepEqual(hide, []);
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

test("screenshot blurs any editable area: bare, empty and plaintext-only contenteditable, role=textbox", () => {
    const selector = [];
    screenshotTargets({ querySelectorAll: (sel) => (selector.push(sel), []) });
    const fields = selector[0];
    for (const part of ["input", "textarea", "select", "[contenteditable]", ':not([contenteditable="false" i])', '[role="textbox"]']) {
        assert.ok(fields.includes(part), part);
    }
});

test("screenshot walks into open shadow roots (web components), frames inside them too", () => {
    const framed = fakeDoc("framed", { fields: ["text"] });
    const shadow = fakeDoc("shadow", { fields: ["password"], frames: [frameOf(framed)] });
    const page = fakeDoc("page", { fields: ["email"], hosts: [{ shadowRoot: shadow }, { shadowRoot: null }] });
    const { blur, hide } = screenshotTargets(page);
    assert.deepEqual(names(blur), ["page.email.0", "shadow.password.0", "framed.text.0"]);
    assert.deepEqual(hide, []);
});

test("screenshot hides embeds and objects it can't read, and reads a same-origin <object data> document", () => {
    const embed = { contentDocument: undefined };
    const image = { contentDocument: null, getAttribute: (a) => (a === "data" ? "logo.png" : null), hasAttribute: () => false };
    const html = { contentDocument: fakeDoc("object", { fields: ["text"] }), getAttribute: (a) => (a === "data" ? "form.html" : null), hasAttribute: () => false };
    const page = fakeDoc("page", { frames: [embed, image, html] });
    const { blur, hide } = screenshotTargets(page);
    assert.deepEqual(names(blur), ["object.text.0"]);
    assert.deepEqual(hide, [embed, image]);
});
