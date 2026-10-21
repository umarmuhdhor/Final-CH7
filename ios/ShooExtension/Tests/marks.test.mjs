// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

await import("../Resources/pipeline.js");
await import("../Resources/marks.js"); // view part skips itself outside the browser
const { classifyField, phrasesFrom, marksFor } = globalThis.ShooMarks;

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
