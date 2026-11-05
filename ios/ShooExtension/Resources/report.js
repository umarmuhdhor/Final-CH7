// Owner: lead. Sends one result per page to the backend when score ≥ 30 (EX-07).
// Plain content script, loaded after replica.js and before block.js (block.js waits for our report).
// When: the moment a page is blocked, or when a warning page has finished all layers — never both,
// so a guardian gets one push per page. The POST itself runs in background.js so it survives the
// block screen navigation. Evidence: a static copy of the page's DOM (replica.js), taken here, at once,
// before the block screen replaces the page; no typed value is in it (PRD §10).

(() => {
    const SEND_TIMEOUT_MS = 1200; // block screen never waits longer than this for our message to go out
    const SENSITIVE = /pin|otp|cvv|cvc|card|kartu|ktp|nik|password|sandi|kata ?kunci|rekening/i;
    const dom = globalThis.ShooDom; // the page can shadow document/form properties (dom.js)

    /** Report now? Once per page: on blocked, or on a finished warning. */
    function shouldReport(state, reportedScanIds) {
        if (reportedScanIds.has(state.scanId)) return false;
        if (state.remembered) return false; // blocked again from memory (#231): reported the first time, no second push
        if (state.status === "blocked") return true;
        return state.status === "warning" && state.done === true;
    }

    /** Count this page in `stats.checked`? Once per page, when its scan is done (#183). */
    function shouldCount(state, countedScanIds) {
        return state.done === true && !countedScanIds.has(state.scanId);
    }

    /**
     * `https://host/path` only: the URL is kept 14 days and shown to the Guardian, so a reset token
     * or session id in the query/fragment (or credentials before the host) must never leave the phone.
     */
    function shareableUrl(url) {
        try {
            const parsed = new URL(url);
            return parsed.origin + parsed.pathname;
        } catch {
            return String(url).split(/[?#]/)[0];
        }
    }

    /** ScanResult without id/verdict/owner (background adds the owner from the session). */
    function scanBody(state, page) {
        return {
            url: shareableUrl(state.url),
            domain: state.domain,
            pageTitle: page.title || undefined,
            faviconUrl: page.faviconUrl ?? null,
            score: state.score,
            status: state.status,
            signals: [...state.signals].sort((a, b) => b.weight - a.weight),
            detectedAt: page.now,
            // X1: the GET /config/public version the status was decided with; absent before thresholds-client.js answered.
            ...(Number.isInteger(page.thresholdsVersion) ? { thresholdsVersion: page.thresholdsVersion } : {}),
            // #270: from POST /analyze; absent when unknown (the page was blocked before it answered, RDAP failed).
            ...(typeof state.rdapRegisteredAt === "string" ? { rdapRegisteredAt: state.rdapRegisteredAt } : {}),
        };
    }

    // ---- Marks (#176): where each signal sits on the page, for the spotlight on the app's Detail ----

    const MARKS_PER_SIGNAL = 3;
    const MAX_MARKS = 24;
    const NOT_TEXT = "script, style, noscript, textarea, input, select, shoo-live-score, shoo-warning, shoo-marks";
    const NOT_FIELD = new Set(["hidden", "checkbox", "radio", "submit", "button", "image", "reset"]);
    const ASK_KIND = { cvv: "card", selfie_ktp: "ktp" }; // asks_<x> whose field classifyField calls something else

    /**
     * Boxes for the replica's `marks`, heaviest signal first: a text signal → where its evidence phrase is
     * (brand_logo_offsite: an image whose alt holds it first, the logo itself; neither, or no evidence → the
     * page's own logo), an asks_* signal → its field (by name/id, else by kind).
     * Signals with nothing on the page (new_domain, db_match, …) get none. Document coordinates, CSS px.
     * @param {object[]} signals
     * @param {{ text(phrase): DOMRect[], images(phrase): DOMRect[],
     *           fields(): Array<{rect: DOMRect, name: string, id: string, kind: string|null}>, logos?(): DOMRect[],
     *           scroll: {x, y} }} page
     * @returns {Array<{signalId, x, y, w, h}>}
     */
    function signalMarks(signals, page) {
        const { TEXT_SIGNALS, FIELD_SIGNAL } = globalThis.ShooMarks ?? {};
        if (!TEXT_SIGNALS) return [];
        const marks = [];
        const seen = new Set();
        let fields = null;
        for (const signal of [...(signals ?? [])].sort((a, b) => b.weight - a.weight)) {
            const evidence = typeof signal.evidence === "string" ? signal.evidence.trim() : "";
            const key = `${signal.id}\n${evidence.toLowerCase()}`;
            if (seen.has(key)) continue;
            seen.add(key);
            let rects = [];
            if (signal.id === "brand_logo_offsite") {
                rects = evidence.length >= 3 ? [...page.images(evidence), ...page.text(evidence)] : [];
                if (!rects.length) rects = page.logos?.() ?? []; // named in the title only, or a copied form
            } else if (TEXT_SIGNALS.has(signal.id) && evidence.length >= 3) {
                rects = page.text(evidence);
            } else if (FIELD_SIGNAL.test(signal.id)) {
                fields ??= page.fields();
                const name = evidence.toLowerCase();
                let hits = name ? fields.filter((f) => f.name === name || f.id === name) : [];
                const ask = signal.id.slice("asks_".length);
                if (!hits.length) hits = fields.filter((f) => f.kind && f.kind === (ASK_KIND[ask] ?? ask));
                rects = hits.map((f) => f.rect);
            }
            for (const r of rects.filter((r) => r?.width > 0 && r?.height > 0).slice(0, MARKS_PER_SIGNAL)) {
                if (marks.length >= MAX_MARKS) return marks;
                marks.push({ signalId: signal.id, x: r.left + page.scroll.x, y: r.top + page.scroll.y, w: r.width, h: r.height });
            }
        }
        return marks;
    }

    /** The signal's own label for a fragment's spotlight ("Kalimat mendesak: …"), or "". */
    const markLabel = (signal) => String(signal.label?.id || signal.label?.en || "").trim().slice(0, 80);

    /**
     * ADM-07 evidence fragments: the page part behind each signal, heaviest signal first, for replica.js
     * captureFragments (which merges nested parts). Same lookup as signalMarks: a text signal → the block around
     * its phrase (brand_logo_offsite: around the logo image too; neither, or no evidence → the page's own logo),
     * an asks_* signal → its field's form, else the field's nearby container. Signals with nothing on the page
     * get none. No cap on the count: the size limit trims the lightest parts (replica-build.js buildFragments).
     * Each part also names the element that holds the evidence (`marks`), for the dashboard's spotlight.
     * @param {{ textElements(phrase): object[], imageElements(phrase): object[], logos?(): object[],
     *           fields(): Array<{el: object, name: string, id: string, kind: string|null}>,
     *           blockOf(el): object, fieldBlock(el): object }} page
     * @returns {Array<{element: object, signalIds: string[], marks: Array<{element: object, signalId: string, label: string}>}>}
     */
    function fragmentGroups(signals, page) {
        const { TEXT_SIGNALS, FIELD_SIGNAL } = globalThis.ShooMarks ?? {};
        if (!TEXT_SIGNALS) return [];
        const groups = [];
        let fields = null;
        for (const signal of [...(signals ?? [])].sort((a, b) => b.weight - a.weight)) {
            const evidence = typeof signal.evidence === "string" ? signal.evidence.trim() : "";
            let found = [];
            let around = page.blockOf;
            if (signal.id === "brand_logo_offsite") {
                found = evidence.length >= 3 ? [...page.imageElements(evidence), ...page.textElements(evidence)] : [];
                if (!found.length) found = page.logos?.() ?? []; // named in the title only, or a copied form
            } else if (TEXT_SIGNALS.has(signal.id) && evidence.length >= 3) {
                found = page.textElements(evidence);
            } else if (FIELD_SIGNAL.test(signal.id)) {
                fields ??= page.fields();
                const name = evidence.toLowerCase();
                let hits = name ? fields.filter((f) => f.name === name || f.id === name) : [];
                const ask = signal.id.slice("asks_".length);
                if (!hits.length) hits = fields.filter((f) => f.kind && f.kind === (ASK_KIND[ask] ?? ask));
                found = hits.map((f) => f.el);
                around = page.fieldBlock;
            }
            const label = markLabel(signal);
            for (const el of new Set(found)) {
                const element = el && around(el);
                if (element) groups.push({ element, signalIds: [signal.id], marks: [{ element: el, signalId: signal.id, label }] });
            }
        }
        return groups;
    }

    globalThis.ShooReport = {
        shouldReport, shouldCount, scanBody, shareableUrl, signalMarks, fragmentGroups, ready: () => Promise.resolve(), keyFor: () => null,
    };

    // ---- Content script part -------------------------------------------------------------

    const pipeline = globalThis.ShooPipeline;
    if (!pipeline || typeof document === "undefined" || typeof browser === "undefined") return;

    const send = (message) => browser.runtime.sendMessage(message);
    const reported = new Set();
    const counted = new Set();
    const sending = new Map(); // scanId → promise that settles once background has the report
    const keys = new Map(); // scanId → report key (background maps it to the backend's scan id)

    function faviconUrl() {
        const link = dom.one(document, 'link[rel~="icon"][href]');
        try {
            return new URL(link ? link.getAttribute("href") : "/favicon.ico", location.href).href;
        } catch {
            return null;
        }
    }

    function sensitiveFormRect() {
        for (const form of dom.forms(document)) {
            const fields = dom.all(form, "input, textarea");
            const sensitive = fields.some((el) => {
                if (el.type === "password") return true;
                const hint = [el.name, el.id, el.placeholder, el.getAttribute("autocomplete"), el.labels?.[0]?.innerText]
                    .filter(Boolean)
                    .join(" ");
                return SENSITIVE.test(hint);
            });
            if (sensitive) return dom.rect(form); // the app scrolls the replica to it
        }
        return null;
    }

    /** Up to `max` boxes of `phrase` in the page text (case-insensitive, within one text node). */
    function textRects(phrase, max = MARKS_PER_SIGNAL) {
        const needle = phrase.toLowerCase();
        const rects = [];
        const walker = dom.walker(document, dom.body(document) || dom.root(document), NodeFilter.SHOW_TEXT, {
            acceptNode: (node) => (node.parentElement?.closest(NOT_TEXT) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
        });
        while (rects.length < max && walker.nextNode()) {
            const node = walker.currentNode;
            const at = node.data.toLowerCase().indexOf(needle);
            if (at === -1) continue;
            const range = new Range();
            range.setStart(node, at);
            range.setEnd(node, at + needle.length);
            const rect = range.getBoundingClientRect();
            if (rect.width > 0 && rect.height > 0) rects.push(rect);
        }
        return rects;
    }

    /** Boxes of images whose alt text holds `phrase` (a brand logo). */
    function imageRects(phrase, max = MARKS_PER_SIGNAL) {
        const needle = phrase.toLowerCase();
        return dom
            .all(document, "img[alt]")
            .filter((img) => (dom.attr(img, "alt") || "").toLowerCase().includes(needle))
            .slice(0, max)
            .map((img) => dom.rect(img));
    }

    // Layer 3 names a brand from the title or a copied sign-in form too (ai/src/layer3/content.js), so its
    // evidence may be nowhere in the page text; the logo is then the element the page itself calls a logo.
    const LOGO = '[class*="logo" i], [id*="logo" i], [alt*="logo" i], [aria-label*="logo" i]';
    const MAX_LOGO_HEIGHT = 400; // CSS px: a "logo-wrapper" holding the whole header is not the logo

    /** Up to `max` visible elements the page calls a logo, outermost first (a logo box and its <svg> → the box). */
    function logoElements(max = MARKS_PER_SIGNAL) {
        const found = [];
        for (const el of dom.all(document, LOGO)) {
            if (found.length >= max) break;
            if (el.closest(NOT_TEXT) || outside(el) || found.some((f) => f.contains(el))) continue;
            const rect = dom.rect(el);
            if (rect.width > 0 && rect.height > 0 && rect.height <= MAX_LOGO_HEIGHT) found.push(el);
        }
        return found;
    }

    /** Every fillable field with its box, name/id (lowercase) and sensitive kind (marks.js classifyField). */
    function fieldBoxes() {
        const classify = globalThis.ShooMarks?.classifyField ?? (() => null);
        return dom
            .all(document, "input, textarea, select")
            .filter((el) => !NOT_FIELD.has(el.type))
            .map((el) => {
                const label = el.labels?.[0]?.innerText || el.closest("label")?.innerText || "";
                const hints = [el.name, el.id, el.placeholder, dom.attr(el, "autocomplete"), dom.attr(el, "aria-label"), label]
                    .filter(Boolean)
                    .join(" ");
                return {
                    el,
                    rect: dom.rect(el),
                    name: String(el.name || "").toLowerCase(),
                    id: String(el.id || "").toLowerCase(),
                    kind: classify({ type: el.type, hints }),
                };
            });
    }

    // ---- Evidence fragments (ADM-07) ----

    const BLOCK = "p, li, td, th, h1, h2, h3, h4, h5, h6, section, article, form, div";
    const outside = (el) => !el || el === dom.body(document) || el === dom.root(document);

    /** The block element around `el`; `el` itself when the nearest block would be the whole page. */
    function blockOf(el) {
        const block = el?.closest?.(BLOCK);
        return outside(block) ? el : block;
    }

    /** A field's form, else its container up to 3 levels above (never the body). */
    function fieldBlock(el) {
        const form = el?.closest?.("form");
        if (!outside(form)) return form;
        let box = el;
        for (let i = 0; i < 3 && !outside(box?.parentElement); i++) box = box.parentElement;
        return box;
    }

    /** The elements whose own text holds `phrase` (case-insensitive, within one text node), once each. */
    function textElements(phrase) {
        const needle = phrase.toLowerCase();
        const found = new Set();
        const walker = dom.walker(document, dom.body(document) || dom.root(document), NodeFilter.SHOW_TEXT, {
            acceptNode: (node) => (node.parentElement?.closest(NOT_TEXT) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
        });
        while (walker.nextNode()) {
            const node = walker.currentNode;
            if (node.data.toLowerCase().includes(needle) && node.parentElement) found.add(node.parentElement);
        }
        return [...found];
    }

    /** Images whose alt text holds `phrase` (a brand logo). */
    function imageElements(phrase) {
        const needle = phrase.toLowerCase();
        return dom.all(document, "img[alt]").filter((img) => (dom.attr(img, "alt") || "").toLowerCase().includes(needle));
    }

    /** The fragments draft (replica.js), or null: a page that breaks the lookup is still reported. */
    function fragments(state) {
        try {
            const groups = fragmentGroups(state.signals, { textElements, imageElements, logos: () => logoElements(), fields: fieldBoxes, blockOf, fieldBlock });
            return globalThis.ShooReplica?.captureFragments?.(document, {
                url: shareableUrl(location.href),
                viewport: { width: innerWidth, height: innerHeight },
                now: new Date().toISOString(),
            }, groups) ?? null;
        } catch (error) {
            console.warn("[Shoo] evidence fragments failed, reporting without them", error);
            return null;
        }
    }

    /** marks for the replica; [] when the page breaks the lookup (the replica goes without the spotlight). */
    function pageMarks(state) {
        try {
            return signalMarks(state.signals, {
                text: textRects, images: imageRects, fields: fieldBoxes, logos: () => logoElements().map((el) => dom.rect(el)),
                scroll: { x: scrollX, y: scrollY },
            });
        } catch (error) {
            console.warn("[Shoo] replica marks failed, sending the replica without them", error);
            return [];
        }
    }

    /** The replica draft (replica.js), or null: a page that breaks the serializer is still reported. */
    function replica(state) {
        try {
            return globalThis.ShooReplica?.capture(document, {
                url: shareableUrl(location.href),
                focus: sensitiveFormRect(),
                scrollY,
                viewport: { width: innerWidth, height: innerHeight },
                now: new Date().toISOString(),
                marks: pageMarks(state),
            }) ?? null;
        } catch (error) {
            console.warn("[Shoo] page replica failed, reporting without it", error);
            return null;
        }
    }

    async function report(state, key) {
        try {
            // Taken now, synchronously: a blocked page is replaced by the block screen right after.
            const draft = replica(state);
            const parts = fragments(state);
            // Background replies once it has the message; replica + POST carry on there.
            return await send({
                type: "report",
                key,
                scan: scanBody(state, {
                    title: dom.title(document), faviconUrl: faviconUrl(), now: new Date().toISOString(),
                    thresholdsVersion: globalThis.ShooPipeline?.THRESHOLD?.version,
                }),
                replica: draft,
                fragments: parts,
            });
        } catch {
            return null;
        }
    }

    async function linkPopupToRecord(state, key) {
        const reply = await send({ type: "recordId", key }).catch(() => null);
        if (reply?.recordId) pipeline.notify({ ...state, recordId: reply.recordId }); // popup's See detail → Detail
    }

    /** For block.js: resolves once background has the report (or after a short timeout). */
    globalThis.ShooReport.ready = (scanId) =>
        Promise.race([sending.get(scanId) ?? Promise.resolve(), new Promise((r) => setTimeout(r, SEND_TIMEOUT_MS))]);
    /** For block.js: lets blocked.html ask background for the record id later. */
    globalThis.ShooReport.keyFor = (scanId) => keys.get(scanId) ?? null;

    pipeline.subscribe((state) => {
        if (!shouldCount(state, counted)) return;
        counted.add(state.scanId);
        send({ type: "pageChecked" }).catch(() => {});
    });

    pipeline.subscribe((state) => {
        if (!shouldReport(state, reported)) return;
        reported.add(state.scanId);
        const key = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
        keys.set(state.scanId, key);
        const sent = report(state, key); // registered synchronously, before block.js runs
        sending.set(state.scanId, sent);
        if (state.status === "warning") {
            sent.then((accepted) => accepted?.ok && linkPopupToRecord(state, key));
        }
    });
})();
