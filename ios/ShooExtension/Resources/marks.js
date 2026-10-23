// Owner: lead. Marks dangerous parts of a page (EX-05). Plain content script, loaded after popup.js.
// ≥30%: suspicious text gets a thick highlighter stroke (PRD §5).
// ≥50%: PIN/OTP/card/KTP/password fields are struck through + "Don't enter your PIN here"; they stay typeable.
// Protected can't remove the marks; Guardian (or a not-yet-set-up phone) can hide them.
// EX-08: tapping a highlighted phrase or a struck field's label shows one short reason.

(() => {
    const { THRESHOLD } = globalThis.ShooPipeline;
    const MAX_PHRASES = 10;
    const MAX_RANGES = 50;

    // Only these signals quote page text (docs/mandates/imelda.md). Field signals (asks_*) carry a field name and
    // are shown as struck fields; other evidence is free-form (db_match → "shoo"/"public", new_domain → age in
    // days). A new text signal must be added here (#74).
    const TEXT_SIGNALS = new Set(["urgent_language", "brand_logo_offsite", "unreasonable_request"]);
    const FIELD_SIGNAL = /^asks_/;

    const FIELD_KINDS = [
        ["otp", /\botp\b|one.?time|kode verifikasi|verification code|one-time-code/i],
        ["card", /cvv|cvc|card|kartu|cc-(number|csc|exp)|kredit|debit/i],
        ["ktp", /\bktp\b|\bnik\b|e-?ktp/i],
        ["pin", /\bpin\b|m-?pin|mpin/i],
        ["password", /password|passwd|sandi|kata ?kunci/i],
    ];

    /**
     * @param {{type?: string, hints: string}} field  hints = name, id, placeholder, autocomplete, label joined
     * @returns {"pin"|"otp"|"card"|"ktp"|"password"|null}
     */
    function classifyField({ type, hints }) {
        for (const [kind, pattern] of FIELD_KINDS) if (pattern.test(hints)) return kind;
        return type === "password" ? "password" : null;
    }

    /** Text to highlight: evidence of text signals, deduped, longest first (so overlaps prefer the full phrase). */
    function phrasesFrom(signals) {
        const phrases = new Set();
        for (const s of signals) {
            if (!TEXT_SIGNALS.has(s.id) || typeof s.evidence !== "string") continue;
            const text = s.evidence.trim();
            if (text.length >= 3) phrases.add(text);
        }
        return [...phrases].sort((a, b) => b.length - a.length).slice(0, MAX_PHRASES);
    }

    /** What this page should show for the newest pipeline state. */
    function marksFor(state) {
        const blocked = state.status === "blocked"; // block screen takes over
        return {
            highlight: !blocked && state.score >= THRESHOLD.firstWarning,
            strike: !blocked && state.score >= THRESHOLD.secondWarning,
            phrases: phrasesFrom(state.signals ?? []),
        };
    }

    /**
     * EX-08: short reason for one mark — the heaviest signal behind it, in the viewer's wording.
     * Text mark: a text signal (TEXT_SIGNALS) whose evidence is that phrase. Field mark: the asks_* signal whose
     * evidence is the field's name/id, else the asks_<kind> signal.
     * @param {object[]} signals
     * @param {{phrase: string} | {field: {kind: string, name?: string, id?: string}}} mark
     * @param {{simple: boolean, lang: "en"|"id"}} wording  simple = Protected (labelSimple)
     * @returns {string|null}  null → no signal says why (field marks then use mark_why_<kind>)
     */
    function reasonFor(signals, mark, { simple, lang }) {
        const evidenceOf = (s) => (typeof s.evidence === "string" ? s.evidence.trim().toLowerCase() : "");
        let matches;
        if (typeof mark.phrase === "string") {
            const phrase = mark.phrase.trim().toLowerCase();
            matches = (signals ?? []).filter((s) => TEXT_SIGNALS.has(s.id) && evidenceOf(s) === phrase);
        } else {
            const { kind, name, id } = mark.field;
            const names = [name, id].filter(Boolean).map((v) => v.toLowerCase());
            const asks = (signals ?? []).filter((s) => FIELD_SIGNAL.test(s.id));
            matches = asks.filter((s) => names.includes(evidenceOf(s)));
            if (!matches.length) matches = asks.filter((s) => s.id === `asks_${kind}`);
        }
        const best = [...matches].sort((a, b) => b.weight - a.weight)[0];
        return (simple ? best?.labelSimple : best?.label)?.[lang] || null;
    }

    const GAP = 10; // px between the bubble and the screen edge
    const ARROW = 8; // px the bubble's arrow sticks out towards what was tapped
    const ARROW_INSET = 16; // arrow stays clear of the rounded corners

    /**
     * Where the reason bubble goes: on the preferred side of what was tapped, the other side when it doesn't
     * fit, kept on screen, with its arrow pointing at the tap.
     * @param {{x, top, bottom}} anchor  what was tapped, viewport px (a finger: a small box around the touch)
     * @param {{width, height}} bubble  px
     * @param {{width, height}} viewport  px
     * @param {"below"|"above"} [prefer]
     * @returns {{left, top, above: boolean, arrowX}}  px; arrowX from the bubble's left edge
     */
    function placeReason(anchor, bubble, viewport, prefer = "below") {
        const left = Math.min(Math.max(GAP, anchor.x - bubble.width / 2), Math.max(GAP, viewport.width - bubble.width - GAP));
        const below = anchor.bottom + ARROW;
        const aboveTop = anchor.top - ARROW - bubble.height;
        const fitsBelow = below + bubble.height <= viewport.height - GAP;
        const fitsAbove = aboveTop >= GAP;
        const above = prefer === "above" ? fitsAbove || !fitsBelow : !fitsBelow && fitsAbove;
        const top = Math.min(Math.max(GAP, above ? aboveTop : below), Math.max(GAP, viewport.height - GAP - bubble.height));
        const arrowX = Math.min(Math.max(ARROW_INSET, anchor.x - left), Math.max(ARROW_INSET, bubble.width - ARROW_INSET));
        return { left, top, above, arrowX };
    }

    globalThis.ShooMarks = { classifyField, phrasesFrom, marksFor, reasonFor, placeReason };

    // ---- View (browser only) -------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key) => browser.i18n.getMessage(key) || key;
    const lang = (browser.i18n.getUILanguage?.() || "en").toLowerCase().startsWith("id") ? "id" : "en";
    const HIGHLIGHT = "shoo-suspicious";
    const ACTIVE = "shoo-suspicious-active"; // the phrase whose reason is showing
    const REASON_MS = 6000;
    const TAP_SLOP = 4; // px around a highlighted line that still counts as a tap on it

    // --- Highlighter stroke via the CSS Custom Highlight API: no page DOM is touched (Safari 17.2+).
    let pageStyle = null;
    function highlightText(phrases) {
        if (!globalThis.CSS?.highlights || typeof Highlight === "undefined") return; // older iOS: skip, fields still struck
        if (!pageStyle) {
            pageStyle = document.createElement("style");
            pageStyle.textContent = `::highlight(${HIGHLIGHT}) { background-color: rgba(255, 214, 10, .55);
                text-decoration: underline 3px rgba(229, 72, 77, .9); text-underline-offset: 3px; }
                ::highlight(${ACTIVE}) { background-color: rgba(255, 176, 0, .85); }`;
            document.documentElement.appendChild(pageStyle);
        }
        const ranges = [];
        marked = [];
        const needles = phrases.map((p) => p.toLowerCase());
        const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
            acceptNode: (node) =>
                node.parentElement?.closest("script, style, noscript, textarea, input, select, shoo-warning, shoo-marks")
                    ? NodeFilter.FILTER_REJECT
                    : NodeFilter.FILTER_ACCEPT,
        });
        while (walker.nextNode() && ranges.length < MAX_RANGES) {
            const node = walker.currentNode;
            const haystack = node.data.toLowerCase();
            for (const [i, needle] of needles.entries()) {
                let from = 0;
                let at;
                while ((at = haystack.indexOf(needle, from)) !== -1 && ranges.length < MAX_RANGES) {
                    const range = new Range();
                    range.setStart(node, at);
                    range.setEnd(node, at + needle.length);
                    ranges.push(range);
                    marked.push({ range, phrase: phrases[i] });
                    from = at + needle.length;
                }
            }
        }
        CSS.highlights.set(HIGHLIGHT, new Highlight(...ranges));
    }

    function clearHighlight() {
        globalThis.CSS?.highlights?.delete(HIGHLIGHT);
        globalThis.CSS?.highlights?.delete(ACTIVE);
        marked = [];
    }

    // --- Struck fields: an overlay that ignores touches, so the input stays usable.
    const CSS_TEXT = `
        :host { all: initial; }
        .layer { position: fixed; inset: 0; pointer-events: none; z-index: 2147483646; }
        .strike { position: fixed; box-sizing: border-box; border: 2px solid #e5484d; border-radius: 6px;
                  background: repeating-linear-gradient(-45deg, rgba(229,72,77,.18) 0 6px, transparent 6px 12px); }
        .strike::after { content: ""; position: absolute; left: -2px; right: -2px; top: 50%;
                         border-top: 3px solid #e5484d; transform: rotate(-4deg); }
        .label { position: fixed; margin: 0; padding: 3px 8px; border: 0; border-radius: 6px; background: #e5484d; color: #fff;
                 font: 600 13px/1.3 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; white-space: nowrap;
                 pointer-events: auto; cursor: pointer; }
        .label::after { content: "ⓘ"; margin-left: 6px; font-weight: 400; }
        .reason { position: fixed; box-sizing: border-box; max-width: min(280px, calc(100vw - 20px)); padding: 10px 14px;
                  border-radius: 14px; background: #1c1c1e; color: #fff; pointer-events: auto; cursor: pointer;
                  font: 500 15px/1.35 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                  -webkit-font-smoothing: antialiased; text-wrap: pretty;
                  box-shadow: 0 8px 24px rgba(0,0,0,.28), 0 1px 3px rgba(0,0,0,.2);
                  animation: reason-in .16s ease-out both; transform-origin: var(--arrow-x) top; }
        .reason.above { transform-origin: var(--arrow-x) bottom; }
        .reason::before { content: ""; position: absolute; left: var(--arrow-x); top: -5px; width: 12px; height: 12px;
                          margin-left: -6px; background: inherit; border-radius: 2px; transform: rotate(45deg); }
        .reason.above::before { top: auto; bottom: -5px; }
        @keyframes reason-in { from { opacity: 0; transform: scale(.94); } }
        @media (prefers-reduced-motion: reduce) { .reason { animation: none; } }
        .hide { position: fixed; top: calc(10px + env(safe-area-inset-top, 0px)); right: 10px; pointer-events: auto;
                padding: 8px 12px; border: 0; border-radius: 999px; background: #1c1c1e; color: #fff;
                font: 600 13px -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; cursor: pointer; }
    `;

    let host = null;
    let layer = null;
    let struck = []; // [{ input, box, label }]
    let marked = []; // highlighted text: [{ range, phrase }]
    let signals = [];
    let canHide = true;
    let simple = false; // Protected → plain reason wording (same rule as the pill card)
    let reason = null;
    let reasonOwner = null; // the mark (label element or highlight range) the open bubble belongs to
    let reasonTimer = 0;

    function fieldHints(el) {
        const label = el.labels?.[0]?.innerText || el.closest("label")?.innerText || "";
        return [el.name, el.id, el.placeholder, el.getAttribute("autocomplete"), el.getAttribute("aria-label"), label]
            .filter(Boolean)
            .join(" ");
    }

    function mountLayer() {
        if (host?.isConnected) return;
        host = document.createElement("shoo-marks");
        const root = host.attachShadow({ mode: "closed" });
        const style = document.createElement("style");
        style.textContent = CSS_TEXT;
        layer = document.createElement("div");
        layer.className = "layer";
        root.append(style, layer);
        document.documentElement.appendChild(host);
    }

    /** Draws the overlay layer: struck fields (≥50%) and, for Guardian, a Hide button for any mark. */
    function renderLayer(withStrike) {
        hideReason();
        mountLayer();
        layer.replaceChildren();
        struck = [];
        if (withStrike) strikeFields();
        if (canHide) {
            const hide = Object.assign(document.createElement("button"), { className: "hide", type: "button", textContent: t("mark_hide") });
            hide.addEventListener("click", () => {
                dismissedScanId = currentScanId;
                clearAll();
            });
            layer.append(hide);
        }
        place();
    }

    function strikeFields() {
        for (const input of document.querySelectorAll("input, textarea")) {
            if (["hidden", "checkbox", "radio", "submit", "button", "image", "file"].includes(input.type)) continue;
            const kind = classifyField({ type: input.type, hints: fieldHints(input) });
            if (!kind) continue;
            const box = Object.assign(document.createElement("div"), { className: "strike" });
            const label = Object.assign(document.createElement("button"), { className: "label", type: "button", textContent: t(`mark_dont_${kind}`) });
            label.setAttribute("aria-description", t("mark_why_hint"));
            // EX-08: the label explains itself; the struck box still ignores touches so the field stays typeable.
            // Bubble goes above the label when it fits, so the field itself stays in view.
            label.addEventListener("click", () => {
                if (reasonOwner === label) return hideReason(); // second tap on the same mark closes it
                const r = label.getBoundingClientRect();
                const field = { kind, name: input.name, id: input.id };
                const text = reasonFor(signals, { field }, { simple, lang }) || t(`mark_why_${kind}`);
                showReason(text, { x: r.left + r.width / 2, top: r.top, bottom: r.bottom }, { owner: label, prefer: "above" });
            });
            layer.append(box, label);
            struck.push({ input, box, label });
        }
    }

    function place() {
        for (const { input, box, label } of struck) {
            const r = input.getBoundingClientRect();
            const visible = r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight;
            box.hidden = label.hidden = !visible;
            if (!visible) continue;
            Object.assign(box.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
            Object.assign(label.style, { left: `${r.left}px`, top: `${Math.max(0, r.top - 24)}px` });
        }
    }

    let frame = 0;
    const schedulePlace = () => {
        if (frame || !struck.length) return;
        frame = requestAnimationFrame(() => {
            frame = 0;
            place();
        });
    };
    addEventListener("scroll", schedulePlace, { passive: true, capture: true });
    addEventListener("resize", schedulePlace, { passive: true });
    setInterval(schedulePlace, 1000); // layout shifts nobody tells us about

    // --- EX-08: tap a mark → one short reason bubble. Closes on the next tap, a scroll, or after 6 s.
    /** @param {{x, top, bottom}} anchor  @param {{owner, prefer?, range?}} opts  owner = the mark, for tap-again-to-close */
    function showReason(text, anchor, { owner, prefer = "below", range = null }) {
        hideReason();
        if (!text || !layer) return;
        reason = Object.assign(document.createElement("div"), { className: "reason", textContent: text });
        reason.setAttribute("role", "status");
        reason.addEventListener("click", hideReason);
        layer.append(reason);
        const size = { width: reason.offsetWidth, height: reason.offsetHeight }; // layout size: the enter animation scales it
        const spot = placeReason(anchor, size, { width: innerWidth, height: innerHeight }, prefer);
        reason.classList.toggle("above", spot.above);
        reason.style.setProperty("--arrow-x", `${spot.arrowX}px`);
        Object.assign(reason.style, { left: `${spot.left}px`, top: `${spot.top}px` });
        if (range) CSS.highlights.set(ACTIVE, new Highlight(range));
        reasonOwner = owner;
        reasonTimer = setTimeout(hideReason, REASON_MS);
    }

    function hideReason() {
        clearTimeout(reasonTimer);
        reason?.remove();
        reason = null;
        reasonOwner = null;
        globalThis.CSS?.highlights?.delete(ACTIVE);
    }

    const hits = (rect, x, y) =>
        x >= rect.left - TAP_SLOP && x <= rect.right + TAP_SLOP && y >= rect.top - TAP_SLOP && y <= rect.bottom + TAP_SLOP;

    // Highlights have no element to listen on, so taps are hit-tested against the ranges. Pointer events, not
    // click: iOS Safari doesn't send `click` to the document for taps on plain text. Passive and never
    // cancelled: a highlighted link still opens. Taps on our own layer (labels, bubble, Hide) are theirs.
    let down = null;
    document.addEventListener("pointerdown", (event) => (down = { x: event.clientX, y: event.clientY }), { capture: true, passive: true });
    document.addEventListener(
        "pointerup",
        (event) => {
            const { clientX: x, clientY: y } = event;
            const tap = down && Math.hypot(x - down.x, y - down.y) < 10; // a drag or a scroll is not a tap
            down = null;
            if (!tap || !host || event.composedPath().includes(host)) return;
            const hit = marked.find(({ range }) => [...range.getClientRects()].some((rect) => hits(rect, x, y)));
            if (!hit || reasonOwner === hit.range) return hideReason(); // elsewhere, or the same phrase again
            const line = [...hit.range.getClientRects()].find((rect) => hits(rect, x, y));
            const text = reasonFor(signals, { phrase: hit.phrase }, { simple, lang });
            showReason(text, { x, top: line.top, bottom: line.bottom }, { owner: hit.range, range: hit.range });
        },
        { capture: true, passive: true },
    );
    addEventListener("scroll", () => reason && hideReason(), { passive: true, capture: true });

    function clearAll() {
        hideReason();
        clearHighlight();
        host?.remove();
        host = layer = null;
        struck = [];
    }

    // Guardian or not set up → may hide. Unknown (background unreachable) → may hide, never trap a user.
    browser.runtime
        .sendMessage({ type: "profile" })
        .then((p) => {
            simple = Boolean(p?.onboarded && p.mode === "protected");
            canHide = !simple;
            if (host) renderLayer(shown.strike); // marks may already be up
        })
        .catch(() => {});

    let currentScanId = null;
    let dismissedScanId = null;
    let shown = { highlight: false, strike: false, key: "" };

    globalThis.ShooPipeline.subscribe((state) => {
        if (state.scanId !== currentScanId) {
            currentScanId = state.scanId;
            shown = { highlight: false, strike: false, key: "" };
            clearAll();
        }
        if (dismissedScanId === state.scanId) return;

        signals = state.signals ?? [];
        const want = marksFor(state);
        if (!want.highlight && !want.strike) {
            if (shown.highlight || shown.strike) clearAll();
            shown = { highlight: false, strike: false, key: "" };
            return;
        }
        const key = want.phrases.join("\n");
        if (want.highlight && (!shown.highlight || key !== shown.key)) highlightText(want.phrases);
        if (!host || want.strike !== shown.strike) renderLayer(want.strike);
        shown = { highlight: want.highlight, strike: want.strike, key };
    });
})();
