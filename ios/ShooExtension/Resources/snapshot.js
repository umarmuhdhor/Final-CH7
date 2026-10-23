// Owner: lead. Reads the page's forms for the PageSnapshot (EX-02). Plain content script, loaded before content.js.
// Field shape only (contracts/detector-interface.md), never typed values.
// C1 (#75): forms inside same-origin iframes are read too, from the top frame. No all_frames: the pipeline and
// UI must run once per page. Cross-origin iframes can't be read from here (Phase 2).

(() => {
    const MAX_FRAMES = 5;

    function labelFor(input) {
        if (input.id) {
            const label = input.ownerDocument.querySelector(`label[for="${CSS.escape(input.id)}"]`);
            if (label) return label.innerText.trim();
        }
        return input.closest("label")?.innerText.trim() || null;
    }

    /** The forms of one document. */
    function formsOf(doc) {
        return [...doc.forms].map((form) => ({
            action: form.getAttribute("action"),
            fields: [...form.querySelectorAll("input, select, textarea")].map((el) => ({
                type: el.type || el.tagName.toLowerCase(),
                name: el.getAttribute("name"),
                id: el.id || null,
                label: labelFor(el),
                placeholder: el.getAttribute("placeholder"),
                autocomplete: el.getAttribute("autocomplete"),
            })),
        }));
    }

    /** Documents of same-origin iframes that hold a form, max MAX_FRAMES. Cross-origin ones give null or throw. */
    function frameDocuments(doc, max = MAX_FRAMES) {
        const docs = [];
        for (const frame of doc.querySelectorAll("iframe, frame")) {
            if (docs.length >= max) break;
            let inner = null;
            try {
                inner = frame.contentDocument;
            } catch {
                // cross-origin → skip
            }
            if (inner?.forms?.length) docs.push(inner);
        }
        return docs;
    }

    /** Forms of the page, then of its same-origin iframes. */
    function pageForms(doc) {
        return [doc, ...frameDocuments(doc)].flatMap(formsOf);
    }

    globalThis.ShooSnapshot = { formsOf, frameDocuments, pageForms };
})();
