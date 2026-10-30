// Owner: lead. Page replica for EX-07 (contracts/api.md "Page replica"): the page's DOM serialized as
// static HTML at the moment we report, so the app can rebuild it later even after the page is blocked or
// the scam site is taken down. Plain content script, loaded before report.js.
// The result is a draft: stylesheets and images are tokens that background.js fills in (replica-build.js),
// because only the background can fetch cross-origin files.
// Static on purpose: no script, no handler, no frame, no form target, no typed value (PRD §10).
// Nodes are read through the prototypes (like dom.js): a page can shadow a form's `attributes`/`childNodes`.

(() => {
    const MAX_ELEMENTS = 20000;
    const MAX_CHARS = 2_000_000; // HTML without stylesheets and images; past it the rest of the page is cut
    const MAX_DEPTH = 400;
    const ELEMENT = 1;
    const TEXT = 3;
    const CDATA = 4;
    const FRAGMENT = 11;

    const VOID = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
    // Dropped with everything inside. <template> only when it isn't a shadow root (those are written out below).
    const DROP = new Set(["script", "noscript", "template", "base", "meta", "source", "track", "param", "portal", "xmp", "plaintext", "noembed", "noframes"]);
    // Replaced by a grey box of the same size: their content isn't in the DOM (or can't be read safely).
    const BOX = new Set(["iframe", "frame", "frameset", "object", "embed", "video", "audio", "canvas"]);
    // Attributes that would load, run or send something, or that only make sense with the live page.
    const DROP_ATTRS = new Set(["srcset", "sizes", "integrity", "nonce", "ping", "action", "formaction", "target", "manifest", "autofocus", "loading", "fetchpriority", "http-equiv", "poster", "background", "lowsrc", "dynsrc", "longdesc"]);
    const KEEP_VALUE = new Set(["submit", "button", "reset"]); // a button's label, not something typed
    // Form fields keep only what shapes their look; a page script can mirror typed text into any other
    // attribute (data-*, aria-valuetext, title). placeholder is the page's own prompt ("Masukkan PIN"), kept as evidence.
    const FIELDS = new Set(["input", "select", "textarea"]);
    const FIELD_ATTRS = new Set(["type", "name", "id", "class", "style", "disabled", "readonly", "checked", "placeholder", "size", "maxlength", "minlength", "multiple", "rows", "cols", "src", "alt", "width", "height", "hidden", "dir", "lang", "value"]);
    const EDITABLE_ROLES = new Set(["textbox", "searchbox", "combobox"]);
    const EDITABLE = (el, attr) => {
        const editable = attr(el, "contenteditable");
        return (editable != null && editable.toLowerCase() !== "false") || EDITABLE_ROLES.has((attr(el, "role") || "").toLowerCase());
    };
    const ATTR_NAME = /^[a-zA-Z_:][-a-zA-Z0-9_:.]*$/;
    const SCRIPT_URL = /^[\s\u0000-\u001f]*((java|vb)[\s\u0000-\u001f]*script[\s\u0000-\u001f]*:|data:text\/html)/i;
    const LINK_URL = /^(https?:|mailto:|tel:)/i;
    const CSS_URL = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)'"\s]*))\s*\)/gi;
    const CSP = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'";
    const BOX_STYLE = "display:inline-block;background:#e5e5ea;border-radius:4px;max-width:100%";

    const proto = (name) => globalThis[name]?.prototype;
    function getter(name, key) {
        const get = proto(name) && Object.getOwnPropertyDescriptor(proto(name), key)?.get;
        return get ? (node) => get.call(node) : (node) => node[key];
    }
    function method(name, key) {
        const fn = proto(name)?.[key];
        return typeof fn === "function" ? (node, ...args) => fn.apply(node, args) : (node, ...args) => node[key]?.(...args);
    }
    const nodeType = getter("Node", "nodeType");
    const childNodes = getter("Node", "childNodes");
    const textOf = getter("CharacterData", "data");
    const localName = getter("Element", "localName");
    const attributes = getter("Element", "attributes");
    const shadowRoot = getter("Element", "shadowRoot");
    const getAttr = method("Element", "getAttribute");
    const rectOf = method("Element", "getBoundingClientRect");

    const escapeText = (text) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;");
    const escapeAttr = (text) => text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

    function absolute(url, base) {
        try {
            return new URL(url, base).href;
        } catch {
            return null;
        }
    }

    /** Where a link goes, for the Guardian: origin + path only (a query can hold a token), or null. */
    function shareableLink(url) {
        if (!url || !LINK_URL.test(url)) return null;
        if (!/^https?:/i.test(url)) return url.split("?")[0]; // mailto:/tel: without a prefilled body
        const parsed = new URL(url);
        return parsed.origin + parsed.pathname;
    }

    /** CSS text of a sheet's rules, or null when the sheet is cross-origin (background fetches it instead). */
    function sheetText(sheet, depth = 0) {
        let rules;
        try {
            rules = sheet?.cssRules;
        } catch {
            return null;
        }
        if (!rules) return null;
        let text = "";
        for (const rule of rules) {
            const imported = depth < 3 && rule.styleSheet ? sheetText(rule.styleSheet, depth + 1) : null;
            // A readable @import is inlined; its url()s are relative to it, so wrap them as absolute now.
            if (imported != null) text += absoluteUrls(imported, rule.styleSheet.href || rule.href) + "\n";
            else text += rule.cssText + "\n";
        }
        return text;
    }

    /** url(x) → url("absolute x"), so a sheet keeps working once it is moved into the replica. */
    function absoluteUrls(css, base) {
        return css.replace(CSS_URL, (whole, dq, sq, bare) => {
            const raw = dq ?? sq ?? bare ?? "";
            if (!raw || raw.startsWith("#") || /^data:/i.test(raw)) return whole;
            const url = absolute(raw, base);
            return url ? `url("${url}")` : "none";
        });
    }

    /**
     * Serializes a document into the replica draft.
     * @param doc  the page's document
     * @param {{ url: string, focus?: {top:number}|null, scrollY?: number, viewport: {width,height}, now: string }} page
     * @returns {{ html: string, sheets: Array<{text?: string, href?: string, base: string, media?: string}>,
     *             resources: string[], nonce: string, truncated: boolean } | null}
     */
    function capture(doc, page) {
        const root = getter("Document", "documentElement")(doc);
        if (!root || localName(root) !== "html") return null; // SVG or XML document: no replica
        const base = getter("Document", "baseURI")(doc) || page.url;
        // designMode "on" makes the whole page one editable area: its text may be typed, so the body stays empty.
        const editableDoc = String(getter("Document", "designMode")(doc) ?? "").toLowerCase() === "on";
        const nonce = `shoo${Math.random().toString(36).slice(2, 10)}`;
        const sheets = [];
        const resources = [];
        const resourceIds = new Map();
        const out = [];
        let chars = 0;
        let elements = 0;
        let truncated = false;

        const emit = (text) => {
            out.push(text);
            chars += text.length;
        };
        const full = () => {
            if (chars > MAX_CHARS || elements > MAX_ELEMENTS) truncated = true;
            return truncated;
        };

        /** Token for an image the background fetches; same URL → same token. */
        function resource(url) {
            if (!url || !/^https?:/i.test(url)) return null;
            if (!resourceIds.has(url)) {
                resourceIds.set(url, resources.length);
                resources.push(url);
            }
            return `${nonce}-i-${resourceIds.get(url)}`;
        }
        /** url(…) in a style attribute → a token the background swaps for url(data:…) or none. */
        function inlineStyle(css) {
            return css.replace(CSS_URL, (whole, dq, sq, bare) => {
                const raw = dq ?? sq ?? bare ?? "";
                if (!raw || raw.startsWith("#")) return whole;
                if (/^data:image\//i.test(raw)) return `url(${raw.replace(/[\s"'()]/g, "")})`;
                const token = resource(absolute(raw, base));
                return token ? `url(${token})` : "none";
            });
        }
        function sheet(entry) {
            sheets.push(entry);
            return `${nonce}-s-${sheets.length - 1}`;
        }

        function writeAttrs(el, name) {
            const list = attributes(el);
            if (!list) return;
            const isInput = name === "input";
            const isField = FIELDS.has(name);
            const type = isInput ? (getAttr(el, "type") || "text").toLowerCase() : null;
            for (const attr of list) {
                const key = attr.name;
                const lower = key.toLowerCase();
                let value = attr.value;
                if (!ATTR_NAME.test(key) || lower.startsWith("on") || DROP_ATTRS.has(lower)) continue;
                if (isField && !FIELD_ATTRS.has(lower)) continue;
                if (SCRIPT_URL.test(value)) continue;
                if (isInput && lower === "value" && !KEEP_VALUE.has(type)) continue; // typed input (PRD §10)
                if (lower === "style") value = inlineStyle(value);
                else if ((name === "a" || name === "area") && (lower === "href" || lower === "xlink:href")) {
                    // The look of a link stays, the link itself never opens.
                    const url = shareableLink(absolute(value, base));
                    emit(` href="#"`);
                    if (url) emit(` data-shoo-href="${escapeAttr(url)}"`);
                    continue;
                } else if (lower === "src" && (name === "img" || isInput)) {
                    value = imageSrc(el, value);
                    if (!value) continue;
                } else if ((lower === "href" || lower === "xlink:href") && name === "image") {
                    value = /^data:image\//i.test(value) ? value : resource(absolute(value, base));
                    if (!value) continue;
                } else if ((lower === "href" || lower === "xlink:href") && !value.trim().startsWith("#")) {
                    continue; // <use href="other.svg#x"> and friends would load something
                } else if (lower === "src" || lower === "data" || lower === "codebase") {
                    continue;
                }
                emit(` ${key}="${escapeAttr(value)}"`);
            }
        }

        function imageSrc(el, value) {
            if (/^data:image\//i.test(value)) return value;
            return resource(absolute(el.currentSrc || value, base));
        }

        function box(el, name) {
            const rect = rectOf(el) || {};
            const width = Math.round(rect.width || 0);
            const height = Math.round(rect.height || 0);
            emit(`<div data-shoo-box="${name}" style="${BOX_STYLE};width:${width}px;height:${height}px"></div>`);
        }

        function writeChildren(parent, depth) {
            for (const child of childNodes(parent) ?? []) {
                if (full()) return;
                writeNode(child, depth);
            }
        }

        function writeShadow(el, depth) {
            const shadow = shadowRoot(el); // open only; closed roots can't be read from an extension
            if (!shadow) return;
            emit(`<template shadowrootmode="open">`);
            adopted(shadow);
            writeChildren(shadow, depth + 1);
            emit("</template>");
        }

        function adopted(scope) {
            for (const s of scope.adoptedStyleSheets ?? []) {
                const text = sheetText(s);
                if (text != null) emit(`<style>${sheet({ text, base })}</style>`);
            }
        }

        function writeNode(node, depth) {
            const type = nodeType(node);
            if (type === TEXT || type === CDATA) {
                emit(escapeText(textOf(node) ?? ""));
                return;
            }
            if (type !== ELEMENT || depth > MAX_DEPTH) return; // comments, processing instructions
            const name = localName(node) || ""; // SVG keeps its case (foreignObject); the HTML parser expects it
            const lower = name.toLowerCase();
            if (!lower || lower.startsWith("shoo-") || DROP.has(lower)) return; // shoo-* = our own UI
            elements++;
            if (BOX.has(lower)) return box(node, lower);
            if (lower === "link") {
                const rel = (getAttr(node, "rel") || "").toLowerCase().split(/\s+/);
                if (!rel.includes("stylesheet") || rel.includes("alternate")) return;
                const href = absolute(getAttr(node, "href") || "", base);
                const text = sheetText(node.sheet);
                if (text == null && !href) return;
                const media = getAttr(node, "media");
                const token = sheet(text != null ? { text, base: href || base } : { href, base: href });
                emit(`<style${media ? ` media="${escapeAttr(media)}"` : ""}>${token}</style>`);
                return;
            }
            if (lower === "style") {
                // cssRules, not the text: CSS-in-JS libraries insert rules that never show up in the text.
                const text = sheetText(node.sheet) ?? node.textContent ?? "";
                const media = getAttr(node, "media");
                emit(`<style${media ? ` media="${escapeAttr(media)}"` : ""}>${sheet({ text, base })}</style>`);
                return;
            }

            emit(`<${name}`);
            writeAttrs(node, lower);
            emit(">");
            if (lower === "head") {
                headWritten = true;
                emit(headMeta(page, metaToken));
            }
            if (VOID.has(lower)) return;
            writeShadow(node, depth);
            // Typed input never leaves the phone: no textarea text, no editable area content.
            if (lower !== "textarea" && !EDITABLE(node, getAttr) && !(lower === "body" && editableDoc)) writeChildren(node, depth + 1);
            if (lower === "body") adopted(doc); // constructed sheets come last, as in the cascade
            emit(`</${name}>`);
        }

        const metaToken = `${nonce}-meta`;
        let headWritten = false;
        writeNode(root, 0);
        let html = out.join("");
        // The parser always makes a <head>; a page that removed it still gets the CSP first.
        if (!headWritten) html = html.replace(/^<html[^>]*>/, (open) => `${open}<head>${headMeta(page, metaToken)}</head>`);
        const doctype = getter("Document", "doctype")(doc) ? "<!doctype html>" : ""; // none = quirks mode, as on the page
        const meta = JSON.stringify({ v: 1, url: page.url, capturedAt: page.now, viewport: page.viewport, focusY: focusY(page), truncated });
        // A function, not a string: "$&" or "$'" in the page URL would otherwise splice the document into the meta.
        html = doctype + html.replace(metaToken, () => escapeAttr(meta));
        return { html, sheets, resources, nonce, truncated };
    }

    /** Document y the app scrolls to first: the sensitive form, else what was on screen. */
    function focusY(page) {
        const scrollY = Math.max(0, Math.round(page.scrollY ?? 0));
        if (!page.focus) return scrollY;
        return Math.max(0, Math.round(page.focus.top + scrollY - 16));
    }

    /** First children of <head>: charset, the CSP, the page's viewport width, our metadata. */
    function headMeta(page, metaToken) {
        return [
            `<meta charset="utf-8">`,
            `<meta http-equiv="Content-Security-Policy" content="${CSP}">`,
            `<meta name="viewport" content="width=${Math.round(page.viewport?.width || 390)}">`,
            `<meta name="shoo-replica" content="${metaToken}">`,
        ].join("");
    }

    globalThis.ShooReplica = { capture, shareableLink, CSP, MAX_CHARS };
})();
