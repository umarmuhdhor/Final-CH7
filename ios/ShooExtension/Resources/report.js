// Owner: lead. Sends one result per page to the backend when score ≥ 30 (EX-07).
// Plain content script, loaded after popup.js and before block.js (block.js waits for our screenshot).
// When: the moment a page is blocked, or when a warning page has finished all layers — never both,
// so a guardian gets one push per page. The POST itself runs in background.js so it survives the
// block screen navigation. Screenshot: evidence area only, every text field blurred (PRD §10).

(() => {
    const CAPTURE_TIMEOUT_MS = 1200; // block screen never waits longer than this for the screenshot
    const PADDING = 16;
    const SENSITIVE = /pin|otp|cvv|cvc|card|kartu|ktp|nik|password|sandi|kata ?kunci|rekening/i;
    const BLUR_SKIP = new Set(["hidden", "checkbox", "radio", "submit", "button", "reset", "image", "range", "color", "file"]);
    // Any editable area: contenteditable="", "plaintext-only" and bare contenteditable are editable too.
    const FIELD_SELECTOR = 'input, textarea, select, [contenteditable]:not([contenteditable="false" i]), [role="textbox"]';
    const FRAME_SELECTOR = "iframe, frame, object, embed"; // object/embed can hold a document too
    const MAX_FRAME_DEPTH = 3;
    const dom = globalThis.ShooDom; // the page can shadow document/form properties (dom.js)
    // Paint marker (capture.js): magenta band over cyan band at the viewport's top-left corner, set in the
    // same change as the blur. Found in the capture → that frame has the blur, and it shows where the
    // viewport starts in the image (Safari captures the area under the status bar too).
    const MARKER_BAND = 4; // CSS px per band
    const MARKER_STYLE = [
        "position: fixed", "left: 0", "top: 0", `width: ${2 * MARKER_BAND}px`, `height: ${2 * MARKER_BAND}px`,
        `background: linear-gradient(#ff00ff ${MARKER_BAND}px, #00ffff ${MARKER_BAND}px)`,
        "z-index: 2147483647", "pointer-events: none", "margin: 0", "padding: 0", "border: 0",
    ].map((rule) => `${rule} !important`).join("; ");

    /** Report now? Once per page: on blocked, or on a finished warning. */
    function shouldReport(state, reportedScanIds) {
        if (reportedScanIds.has(state.scanId)) return false;
        if (state.status === "blocked") return true;
        return state.status === "warning" && state.done === true;
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
        };
    }

    /**
     * Evidence area in viewport CSS pixels: the first sensitive form if it's on screen, else the viewport.
     * @param {{left,top,right,bottom}|null} formRect
     * @param {{width,height}} viewport
     */
    function evidenceRect(formRect, viewport) {
        const full = { x: 0, y: 0, width: viewport.width, height: viewport.height };
        if (!formRect) return full;
        const left = Math.max(0, formRect.left - PADDING);
        const top = Math.max(0, formRect.top - PADDING);
        const right = Math.min(viewport.width, formRect.right + PADDING);
        const bottom = Math.min(viewport.height, formRect.bottom + PADDING);
        if (right - left < 40 || bottom - top < 40) return full; // off screen or tiny
        return { x: left, y: top, width: right - left, height: bottom - top };
    }

    /** A src that never leaves about:blank (none, about:…, srcdoc), so a blank document is the real one. */
    function staysBlank(frame) {
        if (frame.hasAttribute?.("srcdoc")) return true;
        const src = (frame.getAttribute?.("src") ?? frame.getAttribute?.("data") ?? "").trim(); // <object data>
        return !src || /^about:/i.test(src);
    }

    /**
     * The frame's document if we can see everything it will show, else null (→ hide the frame).
     * While a cross-origin src is still loading, contentDocument is the initial about:blank, which is
     * same-origin with us: it has no fields, and the cross-origin form appears a moment later.
     */
    function readableDocument(frame) {
        let inner = null;
        try {
            inner = frame.contentDocument;
        } catch {
            return null; // cross-origin
        }
        if (!inner) return null;
        if (dom.url(inner) === "about:blank" && !staysBlank(frame)) return null; // still loading its src
        return inner;
    }

    /**
     * What to change before the screenshot, so no typed value is readable in it (PRD §10, #75).
     * blur: text-like fields and editable areas of the page, of every same-origin frame (nested too) and
     * of open shadow roots (web components), which querySelectorAll doesn't reach.
     * hide: frames we can't look into (cross-origin, still loading, embeds, or nested deeper than
     * MAX_FRAME_DEPTH): their fields can't be blurred, so the whole frame is hidden.
     * Closed shadow roots can't be reached from an extension in Safari.
     * @param root  a document or a shadow root
     */
    function screenshotTargets(root, depth = 0) {
        const blur = dom.all(root, FIELD_SELECTOR).filter((el) => !BLUR_SKIP.has(el.type));
        const hide = [];
        for (const frame of dom.all(root, FRAME_SELECTOR)) {
            const inner = readableDocument(frame);
            if (!inner || depth >= MAX_FRAME_DEPTH) {
                hide.push(frame);
                continue;
            }
            const nested = screenshotTargets(inner, depth + 1);
            blur.push(...nested.blur);
            hide.push(...nested.hide);
        }
        for (const el of dom.all(root, "*")) {
            if (!el.shadowRoot) continue; // closed or none
            const nested = screenshotTargets(el.shadowRoot, depth);
            blur.push(...nested.blur);
            hide.push(...nested.hide);
        }
        return { blur, hide };
    }

    globalThis.ShooReport = { shouldReport, scanBody, shareableUrl, evidenceRect, screenshotTargets, MARKER_BAND, ready: () => Promise.resolve(), keyFor: () => null };

    // ---- Content script part -------------------------------------------------------------

    const pipeline = globalThis.ShooPipeline;
    if (!pipeline || typeof document === "undefined" || typeof browser === "undefined") return;

    const send = (message) => browser.runtime.sendMessage(message);
    const reported = new Set();
    const captures = new Map(); // scanId → promise that settles once the screenshot is taken
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
            if (sensitive) return dom.rect(form);
        }
        return null;
    }

    /**
     * Blurs every text-like field (iframes too), hides unreadable iframes and our own popup, and shows
     * the paint marker in the same change; returns an undo. The popup hides its own card (popup.js
     * capture): its host is guarded, so a style set on it from here would be put back at once.
     */
    function prepareForScreenshot() {
        const touched = [];
        const { blur, hide } = screenshotTargets(document);
        for (const el of blur) {
            touched.push([el, el.getAttribute("style")]);
            el.style.setProperty("filter", "blur(8px)", "important");
        }
        for (const el of hide) {
            touched.push([el, el.getAttribute("style")]);
            el.style.setProperty("visibility", "hidden", "important");
        }
        globalThis.ShooPopup?.capture?.(true);
        const marker = dom.create(document, "shoo-capture-marker");
        marker.setAttribute("style", MARKER_STYLE);
        dom.root(document).append(marker);
        return () => {
            marker.remove();
            globalThis.ShooPopup?.capture?.(false);
            for (const [el, style] of touched) {
                if (style == null) el.removeAttribute("style");
                else el.setAttribute("style", style);
            }
        };
    }

    async function report(state, key) {
        let restore = () => {};
        try {
            restore = prepareForScreenshot();
            const rect = evidenceRect(sensitiveFormRect(), { width: innerWidth, height: innerHeight });
            // Two frames so the blur is likely painted; capture.js still checks for the marker and retries.
            await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            // Background replies once the screenshot is taken; the POST carries on there.
            return await send({
                type: "report",
                key,
                scan: scanBody(state, { title: dom.title(document), faviconUrl: faviconUrl(), now: new Date().toISOString() }),
                evidence: { ...rect, viewportWidth: innerWidth, markerBand: MARKER_BAND },
            });
        } catch {
            return null;
        } finally {
            restore();
        }
    }

    async function linkPopupToRecord(state, key) {
        const reply = await send({ type: "recordId", key }).catch(() => null);
        if (reply?.recordId) pipeline.notify({ ...state, recordId: reply.recordId }); // popup's See detail → Detail
    }

    /** For block.js: resolves once the screenshot is taken (or after a short timeout). */
    globalThis.ShooReport.ready = (scanId) =>
        Promise.race([captures.get(scanId) ?? Promise.resolve(), new Promise((r) => setTimeout(r, CAPTURE_TIMEOUT_MS))]);
    /** For block.js: lets blocked.html ask background for the record id later. */
    globalThis.ShooReport.keyFor = (scanId) => keys.get(scanId) ?? null;

    pipeline.subscribe((state) => {
        if (!shouldReport(state, reported)) return;
        reported.add(state.scanId);
        const key = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
        keys.set(state.scanId, key);
        const capture = report(state, key); // registered synchronously, before block.js runs
        captures.set(state.scanId, capture);
        if (state.status === "warning") {
            capture.then((accepted) => accepted?.ok && linkPopupToRecord(state, key));
        }
    });
})();
