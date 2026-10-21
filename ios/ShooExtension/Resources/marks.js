// Owner: lead. Marks dangerous parts of a page (EX-05). Plain content script, loaded after popup.js.
// ≥30%: suspicious text gets a thick highlighter stroke (PRD §5).
// ≥50%: PIN/OTP/card/KTP/password fields are struck through + "Don't enter your PIN here"; they stay typeable.
// Protected can't remove the marks; Guardian (or a not-yet-set-up phone) can hide them.

(() => {
    const { THRESHOLD } = globalThis.ShooPipeline;
    const MAX_PHRASES = 10;
    const MAX_RANGES = 50;

    // Field signals carry a field name as evidence, not page text — they're shown as struck fields instead.
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

    /** Text to highlight: evidence of non-field signals, deduped, longest first (so overlaps prefer the full phrase). */
    function phrasesFrom(signals) {
        const phrases = new Set();
        for (const s of signals) {
            if (FIELD_SIGNAL.test(s.id) || typeof s.evidence !== "string") continue;
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

    globalThis.ShooMarks = { classifyField, phrasesFrom, marksFor };

    // ---- View (browser only) -------------------------------------------------------------

    if (typeof document === "undefined" || typeof browser === "undefined") return;

    const t = (key) => browser.i18n.getMessage(key) || key;
    const HIGHLIGHT = "shoo-suspicious";

    // --- Highlighter stroke via the CSS Custom Highlight API: no page DOM is touched (Safari 17.2+).
    let pageStyle = null;
    function highlightText(phrases) {
        if (!globalThis.CSS?.highlights || typeof Highlight === "undefined") return; // older iOS: skip, fields still struck
        if (!pageStyle) {
            pageStyle = document.createElement("style");
            pageStyle.textContent = `::highlight(${HIGHLIGHT}) { background-color: rgba(255, 214, 10, .55);
                text-decoration: underline 3px rgba(229, 72, 77, .9); text-underline-offset: 3px; }`;
            document.documentElement.appendChild(pageStyle);
        }
        const ranges = [];
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
            for (const needle of needles) {
                let from = 0;
                let at;
                while ((at = haystack.indexOf(needle, from)) !== -1 && ranges.length < MAX_RANGES) {
                    const range = new Range();
                    range.setStart(node, at);
                    range.setEnd(node, at + needle.length);
                    ranges.push(range);
                    from = at + needle.length;
                }
            }
        }
        CSS.highlights.set(HIGHLIGHT, new Highlight(...ranges));
    }

    function clearHighlight() {
        globalThis.CSS?.highlights?.delete(HIGHLIGHT);
    }

    // --- Struck fields: an overlay that ignores touches, so the input stays usable.
    const CSS_TEXT = `
        :host { all: initial; }
        .layer { position: fixed; inset: 0; pointer-events: none; z-index: 2147483646; }
        .strike { position: fixed; box-sizing: border-box; border: 2px solid #e5484d; border-radius: 6px;
                  background: repeating-linear-gradient(-45deg, rgba(229,72,77,.18) 0 6px, transparent 6px 12px); }
        .strike::after { content: ""; position: absolute; left: -2px; right: -2px; top: 50%;
                         border-top: 3px solid #e5484d; transform: rotate(-4deg); }
        .label { position: fixed; padding: 3px 8px; border-radius: 6px; background: #e5484d; color: #fff;
                 font: 600 13px/1.3 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; white-space: nowrap; }
        .hide { position: fixed; top: calc(10px + env(safe-area-inset-top, 0px)); right: 10px; pointer-events: auto;
                padding: 8px 12px; border: 0; border-radius: 999px; background: #1c1c1e; color: #fff;
                font: 600 13px -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; cursor: pointer; }
    `;

    let host = null;
    let layer = null;
    let struck = []; // [{ input, box, label }]
    let canHide = true;

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
            const label = Object.assign(document.createElement("div"), { className: "label", textContent: t(`mark_dont_${kind}`) });
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

    function clearAll() {
        clearHighlight();
        host?.remove();
        host = layer = null;
        struck = [];
    }

    // Guardian or not set up → may hide. Unknown (background unreachable) → may hide, never trap a user.
    browser.runtime
        .sendMessage({ type: "profile" })
        .then((p) => {
            canHide = !(p?.onboarded && p.mode === "protected");
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
