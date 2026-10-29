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

    globalThis.ShooReport = { shouldReport, scanBody, shareableUrl, ready: () => Promise.resolve(), keyFor: () => null };

    // ---- Content script part -------------------------------------------------------------

    const pipeline = globalThis.ShooPipeline;
    if (!pipeline || typeof document === "undefined" || typeof browser === "undefined") return;

    const send = (message) => browser.runtime.sendMessage(message);
    const reported = new Set();
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

    /** The replica draft (replica.js), or null: a page that breaks the serializer is still reported. */
    function replica() {
        try {
            return globalThis.ShooReplica?.capture(document, {
                url: shareableUrl(location.href),
                focus: sensitiveFormRect(),
                scrollY,
                viewport: { width: innerWidth, height: innerHeight },
                now: new Date().toISOString(),
            }) ?? null;
        } catch (error) {
            console.warn("[Shoo] page replica failed, reporting without it", error);
            return null;
        }
    }

    async function report(state, key) {
        try {
            // Taken now, synchronously: a blocked page is replaced by the block screen right after.
            const draft = replica();
            // Background replies once it has the message; replica + POST carry on there.
            return await send({
                type: "report",
                key,
                scan: scanBody(state, { title: dom.title(document), faviconUrl: faviconUrl(), now: new Date().toISOString() }),
                replica: draft,
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
