// Owner: lead. Clobber-proof DOM reads for the content scripts. Plain content script, loaded first.
// A page can shadow document and form properties with named elements: `<form name="querySelectorAll">`
// turns document.querySelectorAll into that form, and `<input name="getAttribute">` does the same to its
// form (Document and HTMLFormElement are [LegacyOverrideBuiltIns]). Content scripts have their own JS
// world, but the DOM is shared, so a scam page could crash the scan and never get blocked.
// Reads of a document or a form go through the prototypes instead, which the page can't reach.
// guard() keeps our warning UI on screen when the page tries to hide it.

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

    const HOST_STYLE = "all: initial !important"; // inline + important: beats every page stylesheet
    const MAX_REPAIRS = 20; // per host, so a page that keeps fighting can't keep us busy forever

    /** Takes off what the page put on host (style, hidden, inert, …) and puts it back in parent. @returns true if it changed anything */
    function repair(host, parent) {
        let changed = false;
        for (const name of [...host.attributes].map((a) => a.name)) {
            if (name === "style") continue;
            host.removeAttribute(name);
            changed = true;
        }
        if (host.getAttribute("style") !== HOST_STYLE) {
            host.setAttribute("style", HOST_STYLE);
            changed = true;
        }
        if (!host.isConnected) {
            parent.append(host);
            changed = true;
        }
        return changed;
    }

    /**
     * Keeps one of our UI hosts (pill, popup, marks) on screen while the page tries to hide it with CSS,
     * attributes or remove(). Best effort: after MAX_REPAIRS a page that keeps fighting wins, which is why
     * ≥ 80 is the block screen, a page no website can reach.
     * @returns {() => void} release: call it before removing the host on purpose
     */
    function guard(host, parent) {
        let repairs = 0;
        repair(host, parent);
        const observer = new MutationObserver(() => {
            if (repair(host, parent) && ++repairs >= MAX_REPAIRS) observer.disconnect();
        });
        observer.observe(host, { attributes: true });
        observer.observe(parent, { childList: true });
        return () => observer.disconnect();
    }

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
        walker: method("Document", "createTreeWalker"),
        attr: method("Element", "getAttribute"),
        rect: method("Element", "getBoundingClientRect"),
        on: method("EventTarget", "addEventListener"),
        off: method("EventTarget", "removeEventListener"),
        guard,
        HOST_STYLE,
        MAX_REPAIRS,
    };
})();
