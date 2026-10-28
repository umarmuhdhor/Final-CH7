// Owner: lead. Collects the page, runs the scan pipeline, publishes the score (EX-02).
// Loaded last (manifest.json) so UI scripts have already called ShooPipeline.subscribe().
// UI lives in subscribers: popup.js (EX-04), marks.js (EX-05), block.js (EX-06), report.js (EX-07).

(() => {
    const MAX_TEXT_CHARS = 20000;
    const MAX_IMAGE_ALTS = 50;
    const URL_POLL_MS = 500;
    const SPA_SETTLE_MS = 800; // let a client-side route render before reading it
    const RECHECK_QUIET_MS = 1500; // page must stop changing this long before it is re-checked
    const RECHECK_GAP_MS = 8000; // at most one re-check per this long (each one asks the server again)
    const MAX_RECHECKS = 6; // per page, so a busy feed can't keep calling /analyze
    const TEXT_STEP = 200; // text growth below this many chars (a clock, a counter) isn't a change

    const send = (message) => browser.runtime.sendMessage(message);
    const dom = globalThis.ShooDom; // the page can shadow document properties (dom.js)

    async function registrableDomain(hostname) {
        try {
            const reply = await send({ type: "domain", hostname });
            if (reply?.ok && reply.domain) return reply.domain;
        } catch {
            // background unavailable → fall through
        }
        return hostname.toLowerCase().replace(/\.+$/, "").replace(/^www\./, "");
    }

    /** fn(), or fallback if the page made it throw: one unreadable part must not stop the scan. */
    function read(fn, fallback) {
        try {
            return fn();
        } catch (error) {
            console.warn("[Shoo] snapshot", error);
            return fallback;
        }
    }

    /**
     * PageSnapshot — contracts/detector-interface.md. Never includes typed values.
     * url and domain always come through, so layer 1 (blocklist, verdict) runs whatever the page does.
     */
    async function takeSnapshot() {
        return {
            url: location.href,
            domain: await registrableDomain(location.hostname),
            title: read(() => dom.title(document), ""),
            lang: read(() => dom.root(document).lang || null, null),
            text: read(() => ShooSnapshot.pageText(document, MAX_TEXT_CHARS), ""), // minus editable areas (snapshot.js)
            forms: read(() => ShooSnapshot.pageForms(document), []), // page + same-origin iframes (snapshot.js)
            imageAlts: read(() => [...dom.images(document)].map((img) => img.alt).filter(Boolean).slice(0, MAX_IMAGE_ALTS), []),
            capturedAt: new Date().toISOString(),
        };
    }

    /** What has to differ for a re-check: title, forms, images, or the text by ≥ TEXT_STEP chars. */
    function fingerprint(s) {
        return JSON.stringify([s.title, s.forms, s.imageAlts.length, Math.floor(s.text.length / TEXT_STEP)]);
    }

    // Each navigation gets a new id; results from an older page are dropped.
    let currentScan = 0;
    let run = 0; // every scan or re-check; only the newest may publish
    let page = null; // the open page: { scanId, state, print, rechecks, running, dirty, lastAt }

    function scan() {
        page = { scanId: ++currentScan, state: null, print: null, rechecks: 0, running: false, dirty: false, lastAt: 0 };
        return check(page, null);
    }

    /**
     * One pipeline run, one at a time per page. previous = null → fresh scan; else a re-check that
     * keeps previous's signals and is skipped when the page reads the same as last time.
     */
    async function check(p, previous) {
        const token = ++run;
        const isCurrent = () => token === run && p.scanId === currentScan;
        p.running = true;
        p.dirty = false;
        p.lastAt = Date.now();
        try {
            const snapshot = await takeSnapshot();
            const print = fingerprint(snapshot);
            if (!isCurrent() || (previous && print === p.print)) return;
            p.print = print;
            if (previous) p.rechecks++;
            await ShooPipeline.runScan({
                snapshot,
                previous,
                analyzeLocal: async (s) => (await globalThis.ShooDetector?.analyzeLocal(s)) ?? [],
                analyzeRemote: async (s, localSignals) =>
                    (await send({ type: "analyze", snapshot: s, localSignals }))?.signals ?? [],
                lookupVerdict: async (domain) => (await send({ type: "verdict", domain }))?.verdict ?? null,
                isCurrent,
                publish: (state) => {
                    const result = { ...state, scanId: p.scanId };
                    if (state.done) p.state = result;
                    console.log("[Shoo]", result.domain, result.score, result.status, result.layersDone, result);
                    ShooPipeline.notify(result);
                },
            });
        } finally {
            p.running = false;
        }
        if (p.dirty && p === page) scheduleRecheck();
    }

    // Live score: pages keep changing after load (a login form slides in, a chat widget, lazy text),
    // so a settled page is checked again and the score climbs if something new turns up.
    let recheckTimer = null;
    function scheduleRecheck() {
        const p = page;
        if (!p) return;
        clearTimeout(recheckTimer);
        if (p.running) {
            p.dirty = true; // checked again once the current run is done
            return;
        }
        recheckTimer = setTimeout(recheck, Math.max(RECHECK_QUIET_MS, p.lastAt + RECHECK_GAP_MS - Date.now()));
    }

    function recheck() {
        const p = page;
        if (p.running) return scheduleRecheck();
        const settled = p.state;
        // Decided by a verdict, or blocked (block screen takes over): nothing left to add.
        if (!settled || settled.verdict || settled.status === "blocked" || p.rechecks >= MAX_RECHECKS) return;
        check(p, settled);
    }

    const ours = (node) => node.nodeType === 1 && node.localName.startsWith("shoo-");
    new MutationObserver((records) => {
        if (records.every((r) => ours(r.target) || [...r.addedNodes, ...r.removedNodes].every(ours))) return;
        scheduleRecheck();
    }).observe(dom.root(document), { childList: true, subtree: true, characterData: true });

    // A fragment-only change is the same page (anchors), except hash routers ("#/login", "#!/login").
    function isNewPage(from, to) {
        const a = new URL(from);
        const b = new URL(to);
        if (a.origin !== b.origin || a.pathname !== b.pathname || a.search !== b.search) return true;
        return a.hash !== b.hash && /^#!?\//.test(b.hash);
    }

    // Score resets on every navigation, including URL changes without reload (PRD §5).
    let lastUrl = location.href;
    let settleTimer = null;
    setInterval(() => {
        if (location.href === lastUrl) return;
        const previous = lastUrl;
        lastUrl = location.href;
        if (!isNewPage(previous, lastUrl)) return;

        currentScan++; // invalidate the running scan right away
        ShooPipeline.notify({ url: lastUrl, domain: null, score: 0, status: "normal", signals: [], layersDone: [], done: false, scanId: currentScan });
        clearTimeout(settleTimer);
        settleTimer = setTimeout(scan, SPA_SETTLE_MS);
    }, URL_POLL_MS);

    send({ type: "heartbeat" }).catch(() => {});
    scan();
})();
