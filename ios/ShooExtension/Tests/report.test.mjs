// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/dom.js");
await import("../Resources/report.js"); // no pipeline/DOM here → helpers only
const { shouldReport, scanBody, shareableUrl } = globalThis.ShooReport;

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
