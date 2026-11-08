import { test } from "node:test";
import assert from "node:assert/strict";
import { assertLocalUrl, toRecords } from "../eval/dataset/review-loop.mjs";

const rows = [
    { domain: "a.shoo-dummy.test", input: { domain: "a.shoo-dummy.test", families_not_safe: 3 } },
    { domain: "b.shoo-dummy.test", input: { domain: "b.shoo-dummy.test", families_not_safe: 0 } },
];

test("toRecords pairs each /review result with the row it was asked about", () => {
    const records = toRecords(rows, {
        results: [
            { index: 0, result: "scam", confidence: 0.9, reason: "r", suggestion: "approve" },
            { index: 1, result: null, confidence: null, reason: null, suggestion: "none" },
        ],
    });
    assert.deepEqual(records.map((r) => [r.domain, r.result, r.suggestion]), [["a.shoo-dummy.test", "scam", "approve"], ["b.shoo-dummy.test", null, "none"]]);
    assert.equal(records[0].input, rows[0].input);
});

test("toRecords throws on a wrong count or a wrong index instead of storing misaligned answers", () => {
    assert.throws(() => toRecords(rows, { results: [] }), /different number/);
    assert.throws(() => toRecords(rows, undefined), /different number/);
    assert.throws(
        () => toRecords(rows, { results: [{ index: 1, result: "scam" }, { index: 0, result: "scam" }] }),
        /index/,
    );
});

test("assertLocalUrl accepts loopback and refuses everything else", () => {
    assertLocalUrl("postgresql://postgres:postgres@127.0.0.1:54322/postgres", "DB_URL");
    assertLocalUrl("http://localhost:8787/review", "REVIEW_URL");
    for (const bad of ["https://shoo-ai.afindo-mi01.workers.dev/review", "postgresql://u:p@db.abc.supabase.co:5432/postgres", "http://127.0.0.1.evil.com/review", "postgresql://u:p@127.0.0.1/db?host=db.abc.supabase.co", "not a url"]) {
        assert.throws(() => assertLocalUrl(bad, "X"), /refusing/, bad);
    }
});
