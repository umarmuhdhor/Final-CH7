// Owner: lead (dashboard phase 05b X1). Content-script side of thresholds.js, loaded right after
// pipeline.js (manifest.json). Safari only: not in chrome/scripts/shared-files.txt.
// Asks background.js for the thresholds and writes them into ShooPipeline.THRESHOLD, the object
// pipeline.js, pill.js, popup.js and marks.js read when they decide. Only numbers cross: never the
// token or the URL. If the page's state was already published, it is published again with the status
// the new thresholds give, so the UI scripts and block.js never disagree with pipeline.js.

(() => {
    const pipeline = globalThis.ShooPipeline;
    const THRESHOLD = pipeline?.THRESHOLD;
    if (!THRESHOLD || !globalThis.browser?.runtime?.sendMessage) return;

    // The fence thresholds.js and the dashboard enforce; repeated here because this runs in the page's process.
    const inFence = (t) =>
        [t?.firstWarning, t?.secondWarning, t?.blocked].every(Number.isInteger) &&
        t.firstWarning >= 30 && t.firstWarning <= 60 && t.blocked >= 50 && t.blocked <= 95 &&
        t.blocked - t.firstWarning >= 15 && t.firstWarning <= t.secondWarning && t.secondWarning <= t.blocked;

    let last = null; // subscribed before the UI scripts load, so this sees every state
    pipeline.subscribe((state) => {
        last = state;
    });

    browser.runtime
        .sendMessage({ type: "thresholds" })
        .then((reply) => {
            const t = reply?.thresholds;
            if (!reply?.ok || !inFence(t)) return;
            // version: report.js sends it as POST /scans `thresholdsVersion`, so the backend checks the
            // status against the numbers it was decided with. pipeline.js never reads it.
            Object.assign(THRESHOLD, { firstWarning: t.firstWarning, secondWarning: t.secondWarning, blocked: t.blocked,
                ...(Number.isInteger(t.version) ? { version: t.version } : {}) });
            if (!last || typeof last.score !== "number") return;
            const status = pipeline.statusFor(last.score);
            // Verdict and block memory states score 0 or 100, so their status never changes here.
            if (status !== last.status) pipeline.notify({ ...last, status });
            else pipeline.notify(last); // tiers (popup, marks, pill) follow the new numbers
        })
        .catch(() => {}); // background asleep or reloading: keep the built-in values
})();
