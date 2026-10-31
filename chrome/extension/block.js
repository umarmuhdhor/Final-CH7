// Owner: lead. Block screen trigger (EX-06). Plain script: loaded as a content script after pipeline.js,
// and by blocked.html for decode(). At ≥80% the tab is moved to the extension's own blocked.html —
// a page no website script can reach, so the block can't be removed or bypassed (PRD §5).

(() => {
    const MAX_REASONS = 3; // DT-04 shows 1–3

    /** Everything blocked.html needs, kept small enough for the URL fragment. Never contains typed input. */
    function payloadFor(state) {
        return {
            url: state.url,
            domain: state.domain,
            score: state.score,
            recordId: state.recordId ?? null,
            reportKey: state.reportKey ?? null, // EX-07: blocked.html asks background for the record id
            reasons: [...state.signals]
                .sort((a, b) => b.weight - a.weight)
                .slice(0, MAX_REASONS)
                .map(({ id, weight, label, labelSimple }) => ({ id, weight, label, labelSimple })),
        };
    }

    function encode(payload) {
        return encodeURIComponent(JSON.stringify(payload));
    }

    /** @returns {object|null} null when the fragment is missing or tampered with */
    function decode(fragment) {
        try {
            const payload = JSON.parse(decodeURIComponent(String(fragment).replace(/^#/, "")));
            const url = new URL(payload.url);
            if (!/^https?:$/.test(url.protocol)) return null; // only ever reopen web pages
            if (typeof payload.domain !== "string" || !Number.isInteger(payload.score)) return null;
            return { ...payload, reasons: Array.isArray(payload.reasons) ? payload.reasons : [] };
        } catch {
            return null;
        }
    }

    globalThis.ShooBlock = { payloadFor, encode, decode };

    // ---- Content script part -------------------------------------------------------------

    const pipeline = globalThis.ShooPipeline;
    if (!pipeline || typeof browser === "undefined") return; // running inside blocked.html

    let blockedScanId = null;
    pipeline.subscribe(async (state) => {
        if (state.status !== "blocked" || state.scanId === blockedScanId) return;
        blockedScanId = state.scanId;
        // EX-07 copies the page (replica) and hands the report to background first — the page is gone once we leave (≤ 1.2 s).
        const report = globalThis.ShooReport;
        // Never let a failed report keep the page open.
        await Promise.resolve(report?.ready(state.scanId)).catch(() => {});
        const reportKey = report?.keyFor(state.scanId) ?? null;
        const target = `${browser.runtime.getURL("blocked.html")}#${encode(payloadFor({ ...state, reportKey }))}`;
        // replace(): Back skips the scam page instead of landing on it again.
        location.replace(target);
    });
})();
