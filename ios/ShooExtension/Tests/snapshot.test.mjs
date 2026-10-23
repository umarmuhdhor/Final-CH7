// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

globalThis.CSS ??= { escape: (s) => s };
await import("../Resources/snapshot.js");
const { formsOf, frameDocuments, pageForms } = globalThis.ShooSnapshot;

// Minimal DOM stand-ins: only what snapshot.js reads.
function makeDoc({ forms = [], labels = {}, frames = [] } = {}) {
    const doc = {
        forms: [],
        querySelector: (sel) => {
            const id = /label\[for="(.*)"\]/.exec(sel)?.[1];
            return id in labels ? { innerText: ` ${labels[id]} ` } : null;
        },
        querySelectorAll: (sel) => (sel === "iframe, frame" ? frames : []),
    };
    doc.forms = forms.map((fields) => ({
        getAttribute: (k) => (k === "action" ? "/submit" : null),
        querySelectorAll: () =>
            fields.map((attrs) => ({
                type: attrs.type,
                tagName: "INPUT",
                id: attrs.id ?? "",
                value: "typed-secret", // must never be read
                ownerDocument: doc,
                getAttribute: (k) => attrs[k] ?? null,
                closest: () => null,
            })),
    }));
    return doc;
}
const frame = (contentDocument) => ({ contentDocument });

test("page forms keep the PageSnapshot field shape and never the typed value", () => {
    const doc = makeDoc({ forms: [[{ type: "password", name: "pin", id: "pin", placeholder: "PIN", autocomplete: "off" }]], labels: { pin: "Masukkan PIN" } });
    assert.deepEqual(formsOf(doc), [
        { action: "/submit", fields: [{ type: "password", name: "pin", id: "pin", label: "Masukkan PIN", placeholder: "PIN", autocomplete: "off" }] },
    ]);
    assert.ok(!JSON.stringify(formsOf(doc)).includes("typed-secret"));
});

test("same-origin iframe forms come after the page's, labels read from the iframe's own document (lphone-login, #75)", () => {
    const inner = makeDoc({ forms: [[{ type: "password", name: "passcode", id: "code" }]], labels: { code: "Passcode" } });
    const top = makeDoc({ forms: [[{ type: "email", name: "email" }]], labels: { code: "wrong document" }, frames: [frame(inner)] });
    const forms = pageForms(top);
    assert.deepEqual(forms.map((f) => f.fields[0].name), ["email", "passcode"]);
    assert.equal(forms[1].fields[0].label, "Passcode");
});

test("cross-origin iframes (null document or access error) are skipped without error", () => {
    const blocked = { get contentDocument() { throw new Error("SecurityError"); } };
    const top = makeDoc({ frames: [frame(null), blocked, frame(makeDoc({ forms: [[{ type: "text", name: "otp" }]] }))] });
    assert.deepEqual(pageForms(top).map((f) => f.fields[0].name), ["otp"]);
});

test("at most 5 iframe documents are read; iframes without forms don't count", () => {
    const empty = Array.from({ length: 3 }, () => frame(makeDoc()));
    const withForms = Array.from({ length: 7 }, (_, i) => frame(makeDoc({ forms: [[{ type: "text", name: `f${i}` }]] })));
    const top = makeDoc({ frames: [...empty, ...withForms] });
    assert.equal(frameDocuments(top).length, 5);
    assert.deepEqual(pageForms(top).map((f) => f.fields[0].name), ["f0", "f1", "f2", "f3", "f4"]);
});

test("page without iframes → only its own forms", () => {
    assert.deepEqual(pageForms(makeDoc()), []);
});
