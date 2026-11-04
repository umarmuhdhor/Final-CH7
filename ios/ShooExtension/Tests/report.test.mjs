// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/dom.js");
await import("../Resources/pipeline.js");
await import("../Resources/marks.js");
await import("../Resources/report.js"); // no pipeline/DOM here → helpers only
const { shouldReport, shouldCount, scanBody, shareableUrl, signalMarks } = globalThis.ShooReport;

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

test("counts a page once, when its scan is done, at any score", () => {
    const seen = new Set();
    assert.equal(shouldCount({ scanId: 1, status: "normal", done: false }, seen), false); // layers still running
    assert.equal(shouldCount({ scanId: 1, status: "normal", done: true }, seen), true);
    assert.equal(shouldCount({ scanId: 2, status: "blocked", done: true, remembered: true }, seen), true);
    seen.add(1);
    assert.equal(shouldCount({ scanId: 1, status: "warning", done: true }, seen), false); // a re-check is the same page
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

test("marks (#176): text evidence → its boxes, asks_* → its field by name, else by kind; nothing for page-less signals", () => {
    const box = (left, top, width = 100, height = 20) => ({ left, top, width, height });
    const texts = { "diblokir dalam 24 jam": [box(10, 50), box(10, 400)], bca: [box(20, 330, 40, 20)] };
    const images = { bca: [box(16, 4, 120, 40)] }; // the logo comes before "m-BCA" in a label
    const fields = [
        { rect: box(20, 300, 350, 52), name: "mpin", id: "", kind: "pin" },
        { rect: box(20, 380, 350, 52), name: "kode", id: "otp-field", kind: "otp" },
        { rect: box(20, 460, 350, 52), name: "cvv2", id: "", kind: "card" },
        { rect: box(0, 0, 0, 0), name: "pin_hidden", id: "", kind: "pin" }, // not rendered
    ];
    const page = {
        text: (p) => texts[p.toLowerCase()] ?? [],
        images: (p) => images[p.toLowerCase()] ?? [],
        fields: () => fields,
        scroll: { x: 0, y: 1000 },
    };
    const signals = [
        { id: "new_domain", weight: 20, evidence: "3" },
        { id: "urgent_language", weight: 10, evidence: "Diblokir dalam 24 jam" },
        { id: "brand_logo_offsite", weight: 15, evidence: "BCA" },
        { id: "asks_pin", weight: 25, evidence: "nothing-by-that-name" },
        { id: "asks_otp", weight: 13, evidence: "otp-field" },
        { id: "asks_cvv", weight: 12, evidence: "" },
        { id: "urgent_language", weight: 10, evidence: "diblokir dalam 24 jam" }, // same phrase again
        { id: "hoax_claim", weight: 5, evidence: "not on the page" },
    ];
    assert.deepEqual(signalMarks(signals, page), [
        { signalId: "asks_pin", x: 20, y: 1300, w: 350, h: 52 },
        { signalId: "brand_logo_offsite", x: 16, y: 1004, w: 120, h: 40 },
        { signalId: "brand_logo_offsite", x: 20, y: 1330, w: 40, h: 20 },
        { signalId: "asks_otp", x: 20, y: 1380, w: 350, h: 52 },
        { signalId: "asks_cvv", x: 20, y: 1460, w: 350, h: 52 },
        { signalId: "urgent_language", x: 10, y: 1050, w: 100, h: 20 },
        { signalId: "urgent_language", x: 10, y: 1400, w: 100, h: 20 },
    ]);
});

test("marks stop at 24 and at 3 per signal", () => {
    const many = Array.from({ length: 10 }, (_, i) => ({ left: 0, top: i * 30, width: 50, height: 20 }));
    const page = { text: () => many, images: () => [], fields: () => [], scroll: { x: 0, y: 0 } };
    const signals = Array.from({ length: 12 }, (_, i) => ({ id: "urgent_language", weight: 10, evidence: `phrase ${i}` }));
    const marks = signalMarks(signals, page);
    assert.equal(marks.length, 24);
    assert.equal(marks.filter((m) => m.y === 0).length, 8); // 3 per phrase → 8 phrases fit
});

test("a page blocked again from memory (#231) is not reported again: one push per site", () => {
    const seen = new Set();
    assert.equal(shouldReport({ scanId: 9, status: "blocked", done: true, remembered: true }, seen), false);
    assert.equal(shouldReport({ scanId: 9, status: "blocked", done: true }, seen), true);
});
