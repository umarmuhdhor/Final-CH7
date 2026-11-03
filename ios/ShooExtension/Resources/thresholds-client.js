// Owner: lead (dashboard phase 05b X1). Content-script side of thresholds.js, loaded right after
// pipeline.js (manifest.json). Safari only: not in chrome/scripts/shared-files.txt.
// Asks background.js for the thresholds and writes them into ShooPipeline.THRESHOLD, the object
// pipeline.js, pill.js, popup.js and marks.js read when they decide. A scan that settles before the
// reply uses the built-in values, as before. Only numbers cross: never the token or the URL.

(() => {
    const THRESHOLD = globalThis.ShooPipeline?.THRESHOLD;
    if (!THRESHOLD || !globalThis.browser?.runtime?.sendMessage) return;

    const ordered = (t) =>
        [t?.firstWarning, t?.secondWarning, t?.blocked].every(Number.isInteger) &&
        t.firstWarning >= 30 && t.firstWarning <= t.secondWarning && t.secondWarning <= t.blocked && t.blocked <= 95;

    browser.runtime
        .sendMessage({ type: "thresholds" })
        .then((reply) => {
            const t = reply?.thresholds;
            if (!reply?.ok || !ordered(t)) return;
            Object.assign(THRESHOLD, { firstWarning: t.firstWarning, secondWarning: t.secondWarning, blocked: t.blocked });
        })
        .catch(() => {}); // background asleep or reloading: keep the built-in values
})();
