// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/pipeline.js");
await import("../Resources/marks.js"); // view part skips itself outside the browser
const { classifyField, phrasesFrom, marksFor, reasonFor, placeReason } = globalThis.ShooMarks;

const cases = [
    [{ type: "password", hints: "pin" }, "pin"],
    [{ type: "tel", hints: "mpin Masukkan MPIN" }, "pin"],
    [{ type: "text", hints: "otp one-time-code" }, "otp"],
    [{ type: "text", hints: "Kode verifikasi SMS" }, "otp"],
    [{ type: "text", hints: "cc-number Nomor kartu" }, "card"],
    [{ type: "text", hints: "cvv" }, "card"],
    [{ type: "text", hints: "nik Nomor KTP" }, "ktp"],
    [{ type: "password", hints: "current-password" }, "password"],
    [{ type: "password", hints: "" }, "password"],
    [{ type: "text", hints: "Kata sandi" }, "password"],
    [{ type: "email", hints: "email Alamat email" }, null],
    [{ type: "text", hints: "search Cari produk" }, null],
    [{ type: "text", hints: "spinner opinion" }, null], // "pin" inside other words is not a PIN field
];
for (const [field, expected] of cases) {
    test(`classify ${JSON.stringify(field)} → ${expected}`, () => assert.equal(classifyField(field), expected));
}

const sig = (id, layer, weight, evidence) => ({ id, layer, weight, label: { en: id, id }, labelSimple: { en: id, id }, evidence });

test("phrases come from text evidence only, longest first, deduped", () => {
    const signals = [
        sig("urgent_language", 3, 10, "diblokir dalam 24 jam"),
        sig("asks_pin", 3, 25, "pin"), // field name, not page text
        sig("brand_logo_offsite", 3, 10, "BCA"),
        sig("urgent_language", 3, 10, "diblokir dalam 24 jam"),
        sig("cheap_tld", 2, 15), // no evidence
        sig("x", 3, 1, "ab"), // too short to highlight safely
    ];
    assert.deepEqual(phrasesFrom(signals), ["diblokir dalam 24 jam", "BCA"]);
});

const warning41 = JSON.parse(readFileSync(new URL("../../../contracts/fixtures/warning-41.json", import.meta.url), "utf8"));

test("layer 1–2 evidence is never highlighted (db_match \"public\" must not mark the word on the page)", () => {
    const signals = [sig("db_match", 1, 100, "public"), sig("lookalike_domain", 2, 30, "BCA"), sig("urgent_language", 3, 10, "segera verifikasi")];
    assert.deepEqual(phrasesFrom(signals), ["segera verifikasi"]);
});

test("30–49: highlight only", () => {
    assert.deepEqual(marksFor({ ...warning41, status: "warning" }).highlight, true);
    assert.deepEqual(marksFor({ ...warning41, status: "warning" }).strike, false);
});

test("50–79: highlight + struck fields", () => {
    const m = marksFor({ score: 63, status: "warning", signals: [] });
    assert.equal(m.highlight, true);
    assert.equal(m.strike, true);
});

test("< 30 or blocked: nothing (block screen takes over)", () => {
    assert.deepEqual(marksFor({ score: 29, status: "normal", signals: [] }), { highlight: false, strike: false, phrases: [] });
    const blocked = marksFor({ score: 92, status: "blocked", signals: [] });
    assert.equal(blocked.highlight || blocked.strike, false);
});

// ---- EX-08: tap a mark → short reason ----------------------------------------------------

const warning63 = JSON.parse(readFileSync(new URL("../../../contracts/fixtures/warning-63.json", import.meta.url), "utf8"));
const urgent = warning41.signals.find((s) => s.id === "urgent_language"); // evidence "klaim dalam 1 jam"
const guardian = { simple: false, lang: "en" };
const protectedId = { simple: true, lang: "id" };

test("highlighted phrase → reason of the signal that quoted it (fixture warning-41)", () => {
    assert.equal(reasonFor(warning41.signals, { phrase: urgent.evidence }, guardian), urgent.label.en);
    assert.equal(reasonFor(warning41.signals, { phrase: urgent.evidence.toUpperCase() }, protectedId), urgent.labelSimple.id);
});

test("phrase quoted by two signals → the heavier one explains it", () => {
    const signals = [sig("urgent_language", 3, 10, "segera"), sig("unreasonable_request", 4, 30, "Segera ")];
    assert.equal(reasonFor(signals, { phrase: "segera" }, guardian), "unreasonable_request");
});

test("layer 1–2 and asks_* evidence never explain highlighted text", () => {
    const signals = [sig("db_match", 1, 100, "public"), sig("asks_pin", 3, 25, "pin")];
    assert.equal(reasonFor(signals, { phrase: "public" }, guardian), null);
    assert.equal(reasonFor(signals, { phrase: "pin" }, guardian), null);
});

test("struck field → asks_* signal whose evidence is the field name or id (fixture: asks_ktp \"nik\")", () => {
    const asksKtp = warning63.signals.find((s) => s.id === "asks_ktp");
    assert.equal(reasonFor(warning63.signals, { field: { kind: "ktp", name: "NIK", id: "" } }, protectedId), asksKtp.labelSimple.id);
    assert.equal(reasonFor(warning63.signals, { field: { kind: "ktp", name: "", id: "nik" } }, guardian), asksKtp.label.en);
});

test("struck field with another name → asks_<kind>; nothing matching → null (caller uses mark_why_<kind>)", () => {
    const signals = [sig("asks_pin", 3, 25, "mpin"), sig("asks_otp", 3, 20, "code")];
    assert.equal(reasonFor(signals, { field: { kind: "pin", name: "pin1" } }, guardian), "asks_pin");
    assert.equal(reasonFor(signals, { field: { kind: "card", name: "cc" } }, guardian), null);
    assert.equal(reasonFor([], { field: { kind: "pin" } }, guardian), null);
});

test("signal without text in that language → null, never \"undefined\"", () => {
    const signals = [{ id: "urgent_language", layer: 3, weight: 10, label: { en: "Urgent" }, labelSimple: { en: "Rushes you" }, evidence: "segera" }];
    assert.equal(reasonFor(signals, { phrase: "segera" }, { simple: false, lang: "id" }), null);
});

const screen = { width: 390, height: 800 };
const bubble = { width: 200, height: 60 };

test("reason bubble sits under the tap, centred, and stays on screen", () => {
    assert.deepEqual(placeReason({ x: 195, y: 300 }, bubble, screen), { left: 95, top: 320 });
    assert.equal(placeReason({ x: 5, y: 300 }, bubble, screen).left, 10);
    assert.equal(placeReason({ x: 385, y: 300 }, bubble, screen).left, 180);
});

test("reason bubble goes above the tap near the bottom of the screen", () => {
    assert.equal(placeReason({ x: 195, y: 760 }, bubble, screen).top, 680);
    assert.equal(placeReason({ x: 195, y: 30 }, { width: 200, height: 790 }, screen).top, 10);
});

test("_locales: en and id have the same keys, every struck kind has a mark_why_ fallback", () => {
    const read = (lang) => JSON.parse(readFileSync(new URL(`../Resources/_locales/${lang}/messages.json`, import.meta.url), "utf8"));
    const en = read("en");
    const id = read("id");
    assert.deepEqual(Object.keys(en).sort(), Object.keys(id).sort());
    for (const kind of ["pin", "otp", "card", "ktp", "password"]) {
        assert.ok(en[`mark_why_${kind}`]?.message && id[`mark_why_${kind}`]?.message, kind);
    }
});
