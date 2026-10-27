// Owner: lead. Clobber-proof DOM reads for the content scripts. Plain content script, loaded first.
// A page can shadow document and form properties with named elements: `<form name="querySelectorAll">`
// turns document.querySelectorAll into that form, and `<input name="getAttribute">` does the same to its
// form (Document and HTMLFormElement are [LegacyOverrideBuiltIns]). Content scripts have their own JS
// world, but the DOM is shared, so a scam page could crash the scan and never get blocked.
// Reads of a document or a form go through the prototypes instead, which the page can't reach.

(() => {
    const proto = (name) => globalThis[name]?.prototype;

    /** Native getter of `name.prototype[key]`; outside the browser (Node tests) a plain property read. */
    function getter(name, key) {
        const get = proto(name) && Object.getOwnPropertyDescriptor(proto(name), key)?.get;
        return get ? (node) => get.call(node) : (node) => node[key];
    }

    /** Native method of `name.prototype[key]`; outside the browser a plain call. */
    function method(name, key) {
        const fn = proto(name)?.[key];
        return typeof fn === "function" ? (node, ...args) => fn.apply(node, args) : (node, ...args) => node[key](...args);
    }

    const nodeType = getter("Node", "nodeType");
    const DOCUMENT = 9;
    const FRAGMENT = 11; // shadow roots too

    const queryAll = { doc: method("Document", "querySelectorAll"), frag: method("DocumentFragment", "querySelectorAll"), el: method("Element", "querySelectorAll") };
    const queryOne = { doc: method("Document", "querySelector"), frag: method("DocumentFragment", "querySelector"), el: method("Element", "querySelector") };
    const kind = (node) => ({ [DOCUMENT]: "doc", [FRAGMENT]: "frag" })[nodeType(node)] ?? "el";

    globalThis.ShooDom = {
        /** querySelectorAll on a document, element or shadow root, as an array. */
        all: (node, selector) => [...queryAll[kind(node)](node, selector)],
        one: (node, selector) => queryOne[kind(node)](node, selector),
        forms: getter("Document", "forms"),
        images: getter("Document", "images"),
        body: getter("Document", "body"),
        title: getter("Document", "title"),
        root: getter("Document", "documentElement"),
        url: getter("Document", "URL"),
        create: method("Document", "createElement"),
        attr: method("Element", "getAttribute"),
        rect: method("Element", "getBoundingClientRect"),
    };
})();
