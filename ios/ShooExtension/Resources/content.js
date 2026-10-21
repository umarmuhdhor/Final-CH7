// Owner: lead. Collects the page, runs detection, shows UI (EX-02 … EX-06).
// Skeleton only: popup, highlight, block screen and server calls come in their own PRs.

(() => {
    const MAX_TEXT_CHARS = 20000;
    const MAX_IMAGE_ALTS = 50;
    const THRESHOLD = { firstWarning: 30, secondWarning: 50, blocked: 80 }; // contracts/README.md

    // TODO(EX-02): use the Public Suffix List — "a.b.co.id" must become "b.co.id".
    function registrableDomain(hostname) {
        return hostname.toLowerCase().replace(/^www\./, "");
    }

    function labelFor(input) {
        if (input.id) {
            const label = document.querySelector(`label[for="${CSS.escape(input.id)}"]`);
            if (label) return label.innerText.trim();
        }
        return input.closest("label")?.innerText.trim() || null;
    }

    /** PageSnapshot — contracts/detector-interface.md. Never includes typed values. */
    function takeSnapshot() {
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
            domain: registrableDomain(location.hostname),
            title: document.title,
            lang: document.documentElement.lang || null,
            text: (document.body?.innerText || "").slice(0, MAX_TEXT_CHARS),
            forms,
            imageAlts: [...document.images].map((img) => img.alt).filter(Boolean).slice(0, MAX_IMAGE_ALTS),
            capturedAt: new Date().toISOString(),
        };
    }

    function scoreFrom(signals) {
        if (signals.some((s) => s.id === "db_match")) return 100;
        return Math.min(100, signals.reduce((sum, s) => sum + s.weight, 0));
    }

    function statusFor(score) {
        if (score >= THRESHOLD.blocked) return "blocked";
        if (score >= THRESHOLD.firstWarning) return "warning";
        return "normal";
    }

    async function scan() {
        const snapshot = takeSnapshot();
        let signals = [];
        try {
            signals = (await globalThis.ShooDetector?.analyzeLocal(snapshot)) ?? [];
        } catch (error) {
            console.warn("[Shoo] detector failed", error);
        }
        // TODO(EX-02): call POST /analyze (layer 3–4) and merge signals; recompute score after each layer.
        const score = scoreFrom(signals);
        console.log("[Shoo]", snapshot.domain, score, statusFor(score), signals);
        // TODO(EX-04/05/06): popup at 30/50 (once per page), highlight, block screen.
        // TODO(EX-07): if score >= 30, POST /scans.
    }

    // Score resets on every navigation, including URL changes without reload (PRD §5).
    let lastUrl = location.href;
    setInterval(() => {
        if (location.href !== lastUrl) {
            lastUrl = location.href;
            scan();
        }
    }, 1000);

    browser.runtime.sendMessage({ type: "heartbeat" }).catch(() => {});
    scan();
})();
