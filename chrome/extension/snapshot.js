// Owner: lead. Reads the page's forms for the PageSnapshot (EX-02). Plain content script, loaded before content.js.
// Field shape only (contracts/detector-interface.md), never typed values.
// C1 (#75): forms inside same-origin iframes are read too, from the top frame. No all_frames: the pipeline and
// UI must run once per page. Cross-origin iframes can't be read from here (Phase 2).
// Documents and forms are read through ShooDom (dom.js): the page can shadow their properties.

(() => {
    const MAX_FRAMES = 5;
    const EDITABLE = '[contenteditable]:not([contenteditable="false" i]), [role="textbox" i]';
    const NOT_READ = new Set(["script", "style", "noscript", "template"]);
    const INLINE = new Set(["a", "abbr", "b", "bdi", "bdo", "code", "em", "font", "i", "kbd", "label", "mark", "q", "s", "small", "span", "strong", "sub", "sup", "u"]);
    const SHOW_ELEMENTS_AND_TEXT = 1 | 4; // NodeFilter
    const ACCEPT = 1, REJECT = 2, SKIP = 3; // NodeFilter
    const { all, one, forms, attr, isText, matches, visible, walker } = globalThis.ShooDom;

    function labelFor(input) {
        if (input.id) {
            const label = one(input.ownerDocument, `label[for="${CSS.escape(input.id)}"]`);
            if (label) return label.innerText.trim();
        }
        return input.closest("label")?.innerText.trim() || null;
    }

    /** Where a form posts, without what its address carries: a query or credentials can hold a token. */
    function formTarget(action) {
        if (!action) return action;
        try {
            const parsed = new URL(action);
            return parsed.origin === "null" ? parsed.protocol : parsed.origin + parsed.pathname;
        } catch {
            return action.split(/[?#]/)[0]; // relative
        }
    }

    /** The forms of one document. */
    function formsOf(doc) {
        return [...forms(doc)].map((form) => ({
            action: formTarget(attr(form, "action")),
            fields: all(form, "input, select, textarea").map((el) => ({
                type: el.type || el.tagName.toLowerCase(),
                name: el.getAttribute("name"),
                id: el.id || null,
                label: labelFor(el),
                placeholder: el.getAttribute("placeholder"),
                autocomplete: el.getAttribute("autocomplete"),
                accept: el.getAttribute("accept"),
                capture: el.getAttribute("capture"), // "user" = front camera (selfie hint, C8)
            })),
        }));
    }

    /** Documents of same-origin iframes that hold a form, max MAX_FRAMES. Cross-origin ones give null or throw. */
    function frameDocuments(doc, max = MAX_FRAMES) {
        const docs = [];
        for (const frame of all(doc, "iframe, frame")) {
            if (docs.length >= max) break;
            let inner = null;
            try {
                inner = frame.contentDocument;
            } catch {
                // cross-origin → skip
            }
            if (inner && forms(inner).length) docs.push(inner);
        }
        return docs;
    }

    /** The page's words, read node by node, leaving out editable areas and what innerText would leave out. */
    function textBesideEditables(doc, body, max) {
        const walk = walker(doc, body, SHOW_ELEMENTS_AND_TEXT, {
            acceptNode(node) {
                if (isText(node)) return ACCEPT;
                const name = String(node.localName);
                return NOT_READ.has(name) || name.startsWith("shoo-") || matches(node, EDITABLE) || !visible(node) ? REJECT : SKIP;
            },
        });
        const blockOf = (node) => {
            let el = node.parentElement;
            while (el && INLINE.has(String(el.localName))) el = el.parentElement;
            return el;
        };
        let text = "";
        let block = null;
        for (let node = walk.nextNode(); node && text.length < max; node = walk.nextNode()) {
            const words = node.data.replace(/\s+/g, " ");
            if (words === " " || !words) continue;
            const nodeBlock = blockOf(node);
            text += block === null || block === nodeBlock ? words : `\n${words.trimStart()}`;
            block = nodeBlock;
        }
        return text.trim();
    }

    /**
     * Visible text of the page without what the user typed into editable areas (chat and mail composers,
     * contenteditable): innerText includes those, and typed input never leaves the phone. Open shadow roots
     * and iframes are not in innerText, in Safari or Chrome. A site that draws typed digits in plain divs
     * (some OTP boxes) can't be told from page text.
     */
    function pageText(doc, max) {
        const body = globalThis.ShooDom.body(doc);
        if (!body) return "";
        const typed = all(doc, EDITABLE).some((el) => el.innerText);
        return (typed ? textBesideEditables(doc, body, max) : body.innerText || "").slice(0, max);
    }

    /** Forms of the page, then of its same-origin iframes. */
    function pageForms(doc) {
        return [doc, ...frameDocuments(doc)].flatMap(formsOf);
    }

    globalThis.ShooSnapshot = { formsOf, formTarget, frameDocuments, pageForms, pageText };
})();
