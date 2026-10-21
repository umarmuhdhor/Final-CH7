// Owner: lead. Collects the page, runs the scan pipeline, publishes the score (EX-02).
// Loaded last (manifest.json) so UI scripts have already called ShooPipeline.subscribe().
// TODO(EX-04/05/06): popup at 30/50, highlight, block screen — subscribers in their own files.
// TODO(EX-07): if score >= 30, POST /scans.

(() => {
    const MAX_TEXT_CHARS = 20000;
    const MAX_IMAGE_ALTS = 50;
    const URL_POLL_MS = 500;
    const SPA_SETTLE_MS = 800; // let a client-side route render before reading it

    const send = (message) => browser.runtime.sendMessage(message);

    async function registrableDomain(hostname) {
        try {
            const reply = await send({ type: "domain", hostname });
            if (reply?.ok && reply.domain) return reply.domain;
        } catch {
            // background unavailable → fall through
        }
        return hostname.toLowerCase().replace(/\.+$/, "").replace(/^www\./, "");
    }

    function labelFor(input) {
        if (input.id) {
            const label = document.querySelector(`label[for="${CSS.escape(input.id)}"]`);
            if (label) return label.innerText.trim();
        }
        return input.closest("label")?.innerText.trim() || null;
    }

    /** PageSnapshot — contracts/detector-interface.md. Never includes typed values. */
    async function takeSnapshot() {
        const forms = [...document.forms].map((form) => ({
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

        return {
            url: location.href,
            domain: await registrableDomain(location.hostname),
            title: document.title,
            lang: document.documentElement.lang || null,
            text: (document.body?.innerText || "").slice(0, MAX_TEXT_CHARS),
            forms,
            imageAlts: [...document.images].map((img) => img.alt).filter(Boolean).slice(0, MAX_IMAGE_ALTS),
            capturedAt: new Date().toISOString(),
        };
    }

    // Each navigation gets a new id; results from an older page are dropped.
    let currentScan = 0;

    async function scan() {
        const scanId = ++currentScan;
        const isCurrent = () => scanId === currentScan;
        const snapshot = await takeSnapshot();
        if (!isCurrent()) return;

        await ShooPipeline.runScan({
            snapshot,
            analyzeLocal: async (s) => (await globalThis.ShooDetector?.analyzeLocal(s)) ?? [],
            analyzeRemote: async (s, localSignals) =>
                (await send({ type: "analyze", snapshot: s, localSignals }))?.signals ?? [],
            lookupVerdict: async (domain) => (await send({ type: "verdict", domain }))?.verdict ?? null,
            isCurrent,
            publish: (state) => {
                const result = { ...state, scanId };
                console.log("[Shoo]", result.domain, result.score, result.status, result.layersDone, result);
                ShooPipeline.notify(result);
            },
        });
    }

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
