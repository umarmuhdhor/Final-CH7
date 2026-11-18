// Owner: lead. Block screen trigger (EX-06). Plain script: loaded as a content script after pipeline.js,
// and by blocked.html for decode(). At ≥80% the tab is moved to the extension's own blocked.html —
// a page no website script can reach, so the block can't be removed or bypassed (PRD §5).

(() => {
    const MAX_REASONS = 3; // DT-04 shows 1–3
    const REMEMBER_TIMEOUT_MS = 300; // block memory (#231) must not hold the scam page open

    /** Everything blocked.html needs, kept small enough for the URL fragment. Never contains typed input. */
    function payloadFor(state) {
        return {
            url: state.url,
            domain: state.domain,
            score: state.score,
            recordId: state.recordId ?? null,
            reportKey: state.reportKey ?? null, // EX-07: blocked.html asks background for the record id
            remembered: Boolean(state.remembered), // #382: from block memory, the reasons may be another page's
            reasons: [...state.signals]
                .sort((a, b) => b.weight - a.weight)
                .slice(0, MAX_REASONS)
                .map(({ id, layer, weight, label, labelSimple }) => ({ id, layer, weight, label, labelSimple })),
            // Score bar: summed weight per layer over every signal, not only the top reasons (gauge.js layerWeights).
            // Left out where gauge.js isn't loaded (Chrome); blocked-page.js then falls back to the reasons.
            ...(globalThis.ShooGauge ? { layers: globalThis.ShooGauge.layerWeights(state.signals) } : {}),
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
            const { layers, ...rest } = payload;
            const goodLayers = Array.isArray(layers) && layers.length <= 6 &&
                layers.every((w) => Number.isFinite(w) && w > 0 && w <= 1000);
            return { ...rest, reasons: Array.isArray(payload.reasons) ? payload.reasons : [], ...(goodLayers ? { layers } : {}) };
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
        // #231: next time this site opens straight to the block screen, without asking the server's layers again.
        // Background keeps only the reasons, never their evidence (block-memory.js); never wait on it for long.
        // Remembered without a record (its first report failed): sent again, so this report's id is linked to it.
        if (!state.remembered || !state.recordId) {
            const remember = browser.runtime
                .sendMessage({ type: "rememberBlock", url: state.url, domain: state.domain, score: state.score, signals: state.signals, reportKey })
                .catch(() => {});
            await Promise.race([remember, new Promise((r) => setTimeout(r, REMEMBER_TIMEOUT_MS))]);
        }
        const target = `${browser.runtime.getURL("blocked.html")}#${encode(payloadFor({ ...state, reportKey }))}`;
        // replace(): Back skips the scam page instead of landing on it again.
        location.replace(target);
    });
})();
