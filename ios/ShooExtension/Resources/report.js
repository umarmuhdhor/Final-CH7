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

    /** Report now? Once per page: on blocked, or on a finished warning. */
    function shouldReport(state, reportedScanIds) {
        if (reportedScanIds.has(state.scanId)) return false;
        if (state.status === "blocked") return true;
        return state.status === "warning" && state.done === true;
    }

    /** ScanResult without id/verdict/owner (background adds the owner from the session). */
    function scanBody(state, page) {
        return {
            url: state.url,
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

    globalThis.ShooReport = { shouldReport, scanBody, evidenceRect, ready: () => Promise.resolve(), keyFor: () => null };

    // ---- Content script part -------------------------------------------------------------

    const pipeline = globalThis.ShooPipeline;
    if (!pipeline || typeof document === "undefined" || typeof browser === "undefined") return;

    const send = (message) => browser.runtime.sendMessage(message);
    const reported = new Set();
    const captures = new Map(); // scanId → promise that settles once the screenshot is taken
    const keys = new Map(); // scanId → report key (background maps it to the backend's scan id)

    function faviconUrl() {
        const link = document.querySelector('link[rel~="icon"][href]');
        try {
            return new URL(link ? link.getAttribute("href") : "/favicon.ico", location.href).href;
        } catch {
            return null;
        }
    }

    function sensitiveFormRect() {
        for (const form of document.forms) {
            const fields = [...form.querySelectorAll("input, textarea")];
            const sensitive = fields.some((el) => {
                if (el.type === "password") return true;
                const hint = [el.name, el.id, el.placeholder, el.getAttribute("autocomplete"), el.labels?.[0]?.innerText]
                    .filter(Boolean)
                    .join(" ");
                return SENSITIVE.test(hint);
            });
            if (sensitive) return form.getBoundingClientRect();
        }
        return null;
    }

    /** Blurs every text-like field and hides our own popup; returns a function that undoes it. */
    function prepareForScreenshot() {
        const touched = [];
        for (const el of document.querySelectorAll("input, textarea, select, [contenteditable='true']")) {
            if (BLUR_SKIP.has(el.type)) continue;
            touched.push([el, el.getAttribute("style")]);
            el.style.setProperty("filter", "blur(8px)", "important");
        }
        for (const el of document.querySelectorAll("shoo-warning")) {
            touched.push([el, el.getAttribute("style")]);
            el.style.setProperty("visibility", "hidden", "important");
        }
        return () => {
            for (const [el, style] of touched) {
                if (style == null) el.removeAttribute("style");
                else el.setAttribute("style", style);
            }
        };
    }

    async function report(state, key) {
        const restore = prepareForScreenshot();
        try {
            const rect = evidenceRect(sensitiveFormRect(), { width: innerWidth, height: innerHeight });
            // Two frames so the blur is actually painted before the capture.
            await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            // Background replies once the screenshot is taken; the POST carries on there.
            return await send({
                type: "report",
                key,
                scan: scanBody(state, { title: document.title, faviconUrl: faviconUrl(), now: new Date().toISOString() }),
                evidence: { ...rect, viewportWidth: innerWidth },
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
