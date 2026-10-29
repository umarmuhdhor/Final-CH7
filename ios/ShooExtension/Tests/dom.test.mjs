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
    get childNodes() {
        return this._children ?? [];
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
    get localName() {
        return this.tagName.toLowerCase();
    }
    get attributes() {
        return Object.entries(this._attrs).map(([name, value]) => ({ name, value }));
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
// MutationObserver stand-in: mutate() runs every live observer's callback, like the browser would.
const observers = [];
class MutationObserver {
    constructor(callback) {
        this.callback = callback;
        this.live = true;
        observers.push(this);
    }
    observe() {}
    disconnect() {
        this.live = false;
    }
}
const mutate = () => observers.filter((o) => o.live).forEach((o) => o.callback([]));
Object.assign(globalThis, { Node, Element, Document, MutationObserver, CSS: { escape: (s) => s } });

await import("../Resources/dom.js");
await import("../Resources/snapshot.js");
await import("../Resources/replica.js");
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

test("the page replica still drops the form target and typed PIN on a clobbered form", () => {
    const { login, pin } = clobberedPage();
    pin._attrs.value = "123456"; // React mirrors typed input into the value attribute
    for (const key of ["attributes", "childNodes", "localName"]) Object.defineProperty(login, key, { value: pin });
    const html = new Element("html", {}, [new Element("head"), new Element("body", {}, [login])]);
    const doc = { documentElement: html, baseURI: "https://scam.example/login", doctype: null };
    const { html: out } = globalThis.ShooReplica.capture(doc, { url: "https://scam.example/login", viewport: { width: 390, height: 844 }, now: "" });
    assert.match(out, /<form><input type="password" name="pin" id="pin"><\/form>/);
});

/** One of our UI hosts (shoo-live-score …) and <html>, enough for guard(). */
function uiHost() {
    const attrs = new Map();
    const host = {
        isConnected: false,
        get attributes() {
            return [...attrs.keys()].map((name) => ({ name }));
        },
        getAttribute: (name) => attrs.get(name) ?? null,
        setAttribute: (name, value) => attrs.set(name, String(value)),
        removeAttribute: (name) => attrs.delete(name),
        remove: () => (host.isConnected = false),
    };
    const parent = { append: (node) => (node.isConnected = true) };
    return { host, parent, attrs };
}

test("guard puts the host on screen with a style no page stylesheet can override", () => {
    const { host, parent } = uiHost();
    dom.guard(host, parent);
    assert.equal(host.isConnected, true);
    assert.equal(host.getAttribute("style"), "all: initial !important");
});

test("guard undoes what the page does to the host: style, hidden, inert, remove()", () => {
    const { host, parent, attrs } = uiHost();
    dom.guard(host, parent);
    host.setAttribute("style", "display: none !important");
    host.setAttribute("hidden", "");
    host.setAttribute("inert", "");
    mutate();
    assert.deepEqual([...attrs], [["style", "all: initial !important"]]);
    host.remove();
    mutate();
    assert.equal(host.isConnected, true);
});

test("guard gives up after MAX_REPAIRS, so a page that keeps fighting can't keep us busy", () => {
    const { host, parent } = uiHost();
    dom.guard(host, parent);
    for (let i = 0; i < dom.MAX_REPAIRS; i++) {
        host.remove();
        mutate();
    }
    host.remove();
    mutate();
    assert.equal(host.isConnected, false);
});

test("release() stops guarding, so our own hide() can remove the host", () => {
    const { host, parent } = uiHost();
    const release = dom.guard(host, parent);
    release();
    host.remove();
    mutate();
    assert.equal(host.isConnected, false);
});
