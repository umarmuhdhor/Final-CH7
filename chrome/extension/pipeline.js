// Owner: lead. Scan pipeline for one page (EX-02). Plain script — content scripts share one global scope.
// Pure logic only: no DOM, no network. content.js wires it to the page, background.js does the network.
// Rules: contracts/detector-interface.md "Scoring". Thresholds: contracts/README.md.

(() => {
    const CHURN_WINDOW_MS = 10_000;
    const CHURN_CHANGES = 3; // more new addresses than this in the window
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

    /** True when `fresh` has a signal `kept` lacks, or the same one with more weight. */
    function addsToKept(fresh, kept) {
        const weights = new Map(kept.map((s) => [s.id, s.weight]));
        return fresh.some((s) => !weights.has(s.id) || s.weight > weights.get(s.id));
    }

    /**
     * Runs layer 1–2 (on device), then 3–4 (server), publishing the score after each layer.
     * The verdict is looked up only once the score reaches 30 — the domain would be sent with
     * POST /scans anyway, so low-score browsing never leaves the phone (PRD §10).
     *
     * @param {object} deps
     * @param {object} deps.snapshot          PageSnapshot
     * @param {(snapshot) => Promise<Signal[]>} deps.analyzeLocal    layer 1–2
     * @param {(snapshot, localSignals) => Promise<{signals: Signal[], rdapRegisteredAt?: string|null}|null>} deps.analyzeRemote
     *   layer 3–4, resolves with no signals on failure. `rdapRegisteredAt` (#270) is kept on the state for report.js
     * @param {(domain, options?: {fresh?: boolean, url?: string}) => Promise<{value: "safe"|"not_safe"}|null>} deps.lookupVerdict  per link when `url` is given (#241)
     * @param {(url) => Promise<{score, signals, recordId}|null>} [deps.recallBlock]  block memory (#231): a site
     *   blocked before is asked for its verdict once and, without a `safe`, blocked again with no layer run
     *   (no /analyze, so no LLM call) and `remembered: true` (report.js sends nothing again)
     * @param {() => boolean} deps.isCurrent  false once the user navigated away — stop and publish nothing
     * @param {(state) => void} deps.publish
     * @param {object} [deps.previous]  last state of this page when it is re-checked after a change
     *   (content.js). Its signals are kept, so the score only goes up. Layer 1–2 only look at the
     *   domain, so layer 3–4 (which read the page) always run again; nothing is published unless a
     *   layer finds a signal that's new or heavier than before.
     */
    async function runScan({ snapshot, analyzeLocal, analyzeRemote, lookupVerdict, recallBlock, isCurrent, publish, previous }) {
        const kept = previous?.signals ?? [];
        const state = {
            url: snapshot.url,
            domain: snapshot.domain,
            score: previous?.score ?? 0,
            status: previous?.status ?? "normal",
            signals: [...kept],
            layersDone: previous ? [...previous.layersDone] : [],
            verdict: null,
            done: false,
            rdapRegisteredAt: previous?.rdapRegisteredAt ?? null,
            // #379: false once /analyze was skipped or failed (offline, no session, server down). A low score
            // then only means "nothing found on the phone", and the UI must not call it low risk.
            onlineChecked: previous?.onlineChecked ?? null,
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
                verdict = await lookupVerdict(state.domain, { url: state.url });
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

        if (!previous) emit({});

        // Blocked here before: only a guardian's verdict decides now (#231). Server down → still blocked.
        if (!previous && recallBlock) {
            let memory = null;
            try {
                memory = await recallBlock(snapshot.url);
            } catch {
                memory = null; // memory unreadable → scan as usual
            }
            if (!isCurrent()) return;
            if (memory) {
                verdictChecked = true;
                let verdict = null;
                try {
                    verdict = await lookupVerdict(state.domain, { fresh: true, url: state.url });
                } catch {
                    verdict = null;
                }
                if (!isCurrent()) return;
                if (verdict?.value === "safe") {
                    emit({ verdict, signals: [], score: 0, status: "normal", done: true });
                    return;
                }
                if (verdict?.value === "not_safe") {
                    emit({ verdict, signals: validSignals(memory.signals, [1, 2, 3, 4]), score: 100, status: "blocked", remembered: true, recordId: memory.recordId, done: true });
                    return;
                }
                emit({
                    signals: validSignals(memory.signals, [1, 2, 3, 4]),
                    score: memory.score,
                    status: "blocked",
                    remembered: true,
                    recordId: memory.recordId,
                    done: true,
                });
                return;
            }
        }

        // Layer 1–2
        let local = [];
        try {
            local = validSignals(await analyzeLocal(snapshot), [1, 2]);
        } catch {
            local = []; // detector must never break the page
        }
        if (!isCurrent()) return;
        const localAdds = !previous || addsToKept(local, kept);
        if (localAdds) {
            Object.assign(state, settle(mergeSignals(kept, local)), { layersDone: previous ? state.layersDone : [1, 2] });
            if (await applyVerdict()) return;
            if (local.some((s) => s.id === DB_MATCH)) {
                emit({ done: true });
                return;
            }
            emit({});
        }

        // Layer 3–4
        let remote = [];
        try {
            // #379: the phone's own asks_* (layer 2C) stay here. /analyze finds the form itself (layer 3), and
            // counting both there would push its LLM gate with the same field twice.
            const reply = await analyzeRemote(snapshot, local.filter((s) => !s.id.startsWith("asks_")));
            remote = validSignals(reply?.signals, [3, 4]);
            state.rdapRegisteredAt = reply?.rdapRegisteredAt ?? state.rdapRegisteredAt;
            state.onlineChecked = Boolean(reply) && !reply.skipped;
        } catch {
            remote = [];
            state.onlineChecked = false;
        }
        if (!isCurrent()) return;
        if (!localAdds && !addsToKept(remote, kept)) return; // re-check found nothing new
        Object.assign(state, settle(mergeSignals(kept, local, remote)), { layersDone: [1, 2, 3, 4] });
        if (await applyVerdict()) return;
        emit({ done: true });
    }

    /**
     * #370: a Guardian's verdict that arrives while a warning (30–79) is open. `not_safe` → the block screen,
     * `safe` → the warning goes away (#369). null when there is nothing to change.
     */
    function withVerdict(state, verdict) {
        if (verdict?.value === "not_safe") return { ...state, verdict, score: 100, status: "blocked", done: true };
        if (verdict?.value === "safe") return { ...state, verdict, signals: [], score: 0, status: "normal", done: true };
        return null;
    }

    /** #370: how often an open warning asks for a verdict, the same schedule as the block screen (#350). */
    function verdictPollMs(openForMs) {
        if (openForMs < 2 * 60 * 1000) return 2000;
        if (openForMs < 10 * 60 * 1000) return 5000;
        return 15000;
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

    /**
     * Tells a page that keeps changing its address from one being browsed. Without it a page could
     * call replaceState faster than a scan takes and restart the scan for ever, staying at score 0.
     * @returns {(now: number) => boolean} call on every new page address; true while it is churning
     */
    function urlChurn() {
        let changes = [];
        return (now) => {
            changes = changes.filter((at) => now - at < CHURN_WINDOW_MS);
            changes.push(now);
            return changes.length > CHURN_CHANGES;
        };
    }

    globalThis.ShooPipeline = {
        THRESHOLD,
        scoreFrom,
        statusFor,
        validSignals,
        mergeSignals,
        runScan,
        withVerdict,
        verdictPollMs,
        urlChurn,
        subscribe,
        notify,
    };
})();
