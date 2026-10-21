// Owner: lead. Scan pipeline for one page (EX-02). Plain script — content scripts share one global scope.
// Pure logic only: no DOM, no network. content.js wires it to the page, background.js does the network.
// Rules: contracts/detector-interface.md "Scoring". Thresholds: contracts/README.md.

(() => {
    const THRESHOLD = { firstWarning: 30, secondWarning: 50, blocked: 80 };
    const DB_MATCH = "db_match";

    function scoreFrom(signals) {
        if (signals.some((s) => s.id === DB_MATCH)) return 100;
        return Math.min(100, signals.reduce((sum, s) => sum + s.weight, 0));
    }

    function statusFor(score) {
        if (score >= THRESHOLD.blocked) return "blocked";
        if (score >= THRESHOLD.firstWarning) return "warning";
        return "normal";
    }

    function isLocalizedText(value) {
        return Boolean(value) && typeof value.en === "string" && value.en && typeof value.id === "string" && value.id;
    }

    /** Drops anything that doesn't match scan-result.schema.json#/$defs/Signal or comes from the wrong layers. */
    function validSignals(list, allowedLayers) {
        if (!Array.isArray(list)) return [];
        return list.filter(
            (s) =>
                s &&
                typeof s.id === "string" &&
                s.id &&
                allowedLayers.includes(s.layer) &&
                Number.isInteger(s.weight) &&
                s.weight >= 0 &&
                s.weight <= 100 &&
                isLocalizedText(s.label) &&
                isLocalizedText(s.labelSimple),
        );
    }

    /** Same id twice (e.g. local + server) counts once, with the higher weight. Highest weight first. */
    function mergeSignals(...lists) {
        const byId = new Map();
        for (const signal of lists.flat()) {
            const existing = byId.get(signal.id);
            if (!existing || signal.weight > existing.weight) byId.set(signal.id, signal);
        }
        return [...byId.values()].sort((a, b) => b.weight - a.weight);
    }

    /**
     * Runs layer 1–2 (on device), then 3–4 (server), publishing the score after each layer.
     * The verdict is looked up only once the score reaches 30 — the domain would be sent with
     * POST /scans anyway, so low-score browsing never leaves the phone (PRD §10).
     *
     * @param {object} deps
     * @param {object} deps.snapshot          PageSnapshot
     * @param {(snapshot) => Promise<Signal[]>} deps.analyzeLocal    layer 1–2
     * @param {(snapshot, localSignals) => Promise<Signal[]>} deps.analyzeRemote  layer 3–4, resolves [] on failure
     * @param {(domain) => Promise<{value: "safe"|"not_safe"}|null>} deps.lookupVerdict
     * @param {() => boolean} deps.isCurrent  false once the user navigated away — stop and publish nothing
     * @param {(state) => void} deps.publish
     */
    async function runScan({ snapshot, analyzeLocal, analyzeRemote, lookupVerdict, isCurrent, publish }) {
        const state = {
            url: snapshot.url,
            domain: snapshot.domain,
            score: 0,
            status: "normal",
            signals: [],
            layersDone: [],
            verdict: null,
            done: false,
        };
        let verdictChecked = false;

        const emit = (changes) => {
            Object.assign(state, changes);
            publish({ ...state, signals: [...state.signals], layersDone: [...state.layersDone] });
        };

        const settle = (signals) => {
            const score = scoreFrom(signals);
            return { signals, score, status: statusFor(score) };
        };

        // Returns true when a verdict decided the page and the scan is over.
        const applyVerdict = async () => {
            if (verdictChecked || state.score < THRESHOLD.firstWarning) return false;
            verdictChecked = true;
            let verdict = null;
            try {
                verdict = await lookupVerdict(state.domain);
            } catch {
                verdict = null; // server down → keep detecting (PRD §5)
            }
            if (!isCurrent()) return true;
            if (verdict?.value === "safe") {
                emit({ verdict, signals: [], score: 0, status: "normal", done: true });
                return true;
            }
            if (verdict?.value === "not_safe") {
                emit({ verdict, score: 100, status: "blocked", done: true });
                return true;
            }
            return false;
        };

        emit({});

        // Layer 1–2
        let local = [];
        try {
            local = validSignals(await analyzeLocal(snapshot), [1, 2]);
        } catch {
            local = []; // detector must never break the page
        }
        if (!isCurrent()) return;
        Object.assign(state, settle(mergeSignals(local)), { layersDone: [1, 2] });
        if (await applyVerdict()) return;
        if (local.some((s) => s.id === DB_MATCH)) {
            emit({ done: true });
            return;
        }
        emit({});

        // Layer 3–4
        let remote = [];
        try {
            remote = validSignals(await analyzeRemote(snapshot, local), [3, 4]);
        } catch {
            remote = [];
        }
        if (!isCurrent()) return;
        Object.assign(state, settle(mergeSignals(local, remote)), { layersDone: [1, 2, 3, 4] });
        if (await applyVerdict()) return;
        emit({ done: true });
    }

    // Tiny pub/sub so UI scripts (EX-03/04/05/06) can listen without knowing about content.js.
    const listeners = new Set();
    function subscribe(listener) {
        listeners.add(listener);
        return () => listeners.delete(listener);
    }
    function notify(state) {
        for (const listener of listeners) {
            try {
                listener(state);
            } catch (error) {
                console.warn("[Shoo] listener failed", error);
            }
        }
    }

    globalThis.ShooPipeline = {
        THRESHOLD,
        scoreFrom,
        statusFor,
        validSignals,
        mergeSignals,
        runScan,
        subscribe,
        notify,
    };
})();
