// node --test ios/ShooExtension/Tests/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";

// Browser-like DOM classes: dom.js reads through their prototypes. A page "clobbers" a document or
// form by putting a named element on it, which shadows the prototype ([LegacyOverrideBuiltIns]);
// here that's an own property on the instance.
const matches = (el, selector) => selector.split(",").some((s) => s.trim() === el.tagName.toLowerCase());
class Node {
    constructor(type) {
        this._type = type;
    }
    get nodeType() {
        return this._type;
    }
}
class Element extends Node {
    constructor(tag, attrs = {}, children = []) {
        super(1);
        this.tagName = tag.toUpperCase();
        this.id = attrs.id ?? "";
        this.type = attrs.type ?? tag;
        this._attrs = attrs;
        this._children = children;
    }
    getAttribute(key) {
        return this._attrs[key] ?? null;
    }
    querySelectorAll(selector) {
        return this._children.filter((el) => matches(el, selector));
    }
    querySelector(selector) {
        return Element.prototype.querySelectorAll.call(this, selector)[0] ?? null;
    }
    getBoundingClientRect() {
        return { left: 10, top: 10, right: 200, bottom: 120 };
    }
    closest() {
        return null;
    }
}
class Document extends Node {
    constructor(elements) {
        super(9);
        this._elements = elements;
        for (const el of elements) el.ownerDocument = this;
        for (const form of elements.filter((el) => el.tagName === "FORM")) for (const field of form._children) field.ownerDocument = this;
    }
    get forms() {
        return this._elements.filter((el) => el.tagName === "FORM");
    }
    get title() {
        return "Real title";
    }
    get URL() {
        return "https://scam.example/login";
    }
    querySelectorAll(selector) {
        const fields = this._elements.flatMap((el) => el._children);
        return [...this._elements, ...fields].filter((el) => matches(el, selector));
    }
    querySelector(selector) {
        return Document.prototype.querySelectorAll.call(this, selector)[0] ?? null;
    }
}
Object.assign(globalThis, { Node, Element, Document, CSS: { escape: (s) => s } });

await import("../Resources/dom.js");
await import("../Resources/snapshot.js");
await import("../Resources/report.js");
const dom = globalThis.ShooDom;

/** A login page that shadows what the content scripts read: `<form name="querySelectorAll">` and friends. */
function clobberedPage() {
    const pin = new Element("input", { type: "password", name: "pin", id: "pin" });
    const login = new Element("form", { action: "/steal" }, [pin]);
    const decoy = new Element("form", { name: "querySelectorAll" });
    const doc = new Document([login, decoy]);
    for (const key of ["querySelectorAll", "querySelector", "forms", "title", "URL"]) Object.defineProperty(doc, key, { value: decoy });
    // <input name="getAttribute"> / <input name="querySelectorAll"> inside the form
    for (const key of ["getAttribute", "querySelectorAll", "getBoundingClientRect"]) Object.defineProperty(login, key, { value: pin });
    return { doc, login, pin };
}

test("a clobbered document or form breaks plain reads — the attack this guards against", () => {
    const { doc, login } = clobberedPage();
    assert.throws(() => doc.querySelectorAll("iframe"), TypeError);
    assert.throws(() => login.getAttribute("action"), TypeError);
    assert.equal(doc.forms.length, undefined);
});

test("ShooDom reads documents and forms through the prototypes, whatever the page shadows", () => {
    const { doc, login, pin } = clobberedPage();
    assert.deepEqual(dom.all(doc, "input"), [pin]);
    assert.equal(dom.one(doc, "input"), pin);
    assert.equal(dom.forms(doc).length, 2);
    assert.equal(dom.title(doc), "Real title");
    assert.equal(dom.url(doc), "https://scam.example/login");
    assert.equal(dom.attr(login, "action"), "/steal");
    assert.deepEqual(dom.all(login, "input"), [pin]);
    assert.deepEqual(dom.rect(login), { left: 10, top: 10, right: 200, bottom: 120 });
});

test("the snapshot still reads the page's real forms from a clobbered page", () => {
    const { doc } = clobberedPage();
    const forms = globalThis.ShooSnapshot.pageForms(doc);
    assert.equal(forms[0].action, "/steal");
    assert.deepEqual(forms[0].fields.map((f) => [f.type, f.name]), [["password", "pin"]]);
});

test("the screenshot still finds the fields to blur on a clobbered page", () => {
    const { doc, pin } = clobberedPage();
    assert.deepEqual(globalThis.ShooReport.screenshotTargets(doc), { blur: [pin], hide: [] });
});
