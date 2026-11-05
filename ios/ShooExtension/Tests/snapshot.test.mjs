// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

globalThis.CSS ??= { escape: (s) => s };
await import("../Resources/dom.js");
await import("../Resources/snapshot.js");
const { formsOf, frameDocuments, pageForms, formTarget } = globalThis.ShooSnapshot;

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
        { action: "/submit", fields: [{ type: "password", name: "pin", id: "pin", label: "Masukkan PIN", placeholder: "PIN", autocomplete: "off", accept: null, capture: null }] },
    ]);
    assert.ok(!JSON.stringify(formsOf(doc)).includes("typed-secret"));
});

test("file inputs report accept and capture (C8); a bare capture attribute stays an empty string", () => {
    const doc = makeDoc({ forms: [[
        { type: "file", name: "selfie", accept: "image/*", capture: "user" },
        { type: "file", name: "doc", capture: "" },
    ]] });
    const [selfie, docField] = formsOf(doc)[0].fields;
    assert.equal(selfie.accept, "image/*");
    assert.equal(selfie.capture, "user");
    assert.equal(docField.accept, null);
    assert.equal(docField.capture, "");
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

test("the form target keeps where it goes, never what its query carries", () => {
    assert.equal(formTarget("/submit?token=abc#x"), "/submit");
    assert.equal(formTarget("https://u:p@evil.test/post?session=1"), "https://evil.test/post");
    assert.equal(formTarget("mailto:a@b.test?subject=x"), "mailto:");
    assert.equal(formTarget("javascript:send('secret')"), "javascript:");
    assert.equal(formTarget(""), "");
    assert.equal(formTarget(null), null);
});

/** A tiny page: strings are text nodes. createTreeWalker follows the DOM's filter contract (accept 1, reject 2, skip 3). */
function page(root) {
    const editables = [];
    const build = (node, parent) => {
        if (typeof node === "string") return { nodeType: 3, data: node, parentElement: parent };
        const el = { nodeType: 1, localName: node.tag, parentElement: parent, matches: () => Boolean(node.typed !== undefined), checkVisibility: () => !node.hidden };
        el.kids = (node.kids ?? []).map((kid) => build(kid, el));
        if (node.typed !== undefined) {
            el.innerText = node.typed;
            editables.push(el);
        }
        return el;
    };
    const body = build(root, null);
    const flat = (el) => el.kids.flatMap((kid) => (kid.nodeType === 3 ? [kid] : [kid, ...flat(kid)]));
    body.innerText = flat(body).filter((n) => n.nodeType === 3).map((n) => n.data).join("\n");
    return {
        body,
        querySelectorAll: (selector) => (selector.includes("contenteditable") ? editables : []),
        createTreeWalker: (_root, _show, filter) => {
            function* walk(el) {
                for (const kid of el.kids) {
                    const answer = filter.acceptNode(kid);
                    if (kid.nodeType === 3) {
                        if (answer === 1) yield kid;
                    } else if (answer === 3) {
                        yield* walk(kid);
                    }
                }
            }
            const nodes = walk(body);
            return { nextNode: () => nodes.next().value ?? null };
        },
    };
}

test("the typed words go, the same words printed on the page stay", () => {
    const doc = page({ tag: "body", kids: [
        { tag: "p", kids: ["Your transfer is pending"] },
        { tag: "div", typed: "transfer", kids: ["transfer"] },
        { tag: "p", kids: ["Send"] },
    ] });
    assert.equal(ShooSnapshot.pageText(doc, 20000), "Your transfer is pending\nSend");
    assert.equal(ShooSnapshot.pageText(doc, 4), "Your");
});

test("nested editable areas are left out with the outer one", () => {
    const doc = page({ tag: "body", kids: [
        { tag: "p", kids: ["Chat with CS"] },
        { tag: "div", typed: "my PIN is 123456", kids: ["my ", { tag: "span", typed: "PIN", kids: ["PIN"] }, " is 123456"] },
        { tag: "p", kids: ["Send"] },
    ] });
    assert.equal(ShooSnapshot.pageText(doc, 20000), "Chat with CS\nSend");
});

test("page text skips what innerText would skip: scripts, styles, hidden parts, our own UI", () => {
    const doc = page({ tag: "body", kids: [
        { tag: "script", kids: ["var a"] }, { tag: "style", kids: ["p{}"] }, { tag: "noscript", kids: ["no"] }, { tag: "template", kids: ["t"] },
        { tag: "p", hidden: true, kids: ["gone"] }, { tag: "shoo-warning", kids: ["ours"] }, { tag: "div", typed: "x", kids: ["x"] },
        { tag: "p", kids: ["Masukkan ", { tag: "b", kids: ["PIN"] }, " Anda"] },
    ] });
    assert.equal(ShooSnapshot.pageText(doc, 20000), "Masukkan PIN Anda");
});

test("inline tags stay on the line, a new block starts a new one", () => {
    const doc = page({ tag: "body", kids: [
        { tag: "h1", kids: ["Your transfer is ", { tag: "b", kids: ["pending"] }] },
        { tag: "form", kids: [{ tag: "label", kids: ["Masukkan PIN"] }] },
        { tag: "div", typed: "x", kids: ["x"] },
    ] });
    assert.equal(ShooSnapshot.pageText(doc, 20000), "Your transfer is pending\nMasukkan PIN");
});

test("an empty composer changes nothing: the page is read the fast way", () => {
    const doc = { body: { innerText: "Plain page" }, querySelectorAll: () => [{ innerText: "" }], createTreeWalker: () => { throw new Error("not needed"); } };
    assert.equal(ShooSnapshot.pageText(doc, 20000), "Plain page");
});

test("page text without a body is empty", () => {
    assert.equal(ShooSnapshot.pageText({ body: null, querySelectorAll: () => [] }, 100), "");
});
