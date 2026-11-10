// Owner: lead. EX-03 path C (#49): tells background.js which page is on screen and its running score, for
// the Dynamic Island (background → POST /live → APNs; contracts/api.md "Live score (Dynamic Island)").
// Hidden tab, Safari left or page closed → `open: false`, and background ends the island.
// Plain content script, loaded after pipeline.js. Top frame only (no all_frames).

(() => {
    // Through the prototype: a page can clobber `document.visibilityState` with a named element.
    const visibility = Object.getOwnPropertyDescriptor(Document.prototype, "visibilityState").get;
    const isVisible = () => visibility.call(document) === "visible";
    let last = null; // newest pipeline state of this page

    function post(message) {
        browser.runtime.sendMessage({ type: "liveScore", ...message }).catch(() => {});
    }

    function show(state) {
        if (!state || !isVisible()) return;
        post({
            open: true,
            hostname: location.hostname, // background turns it into the registrable domain
            score: state.score ?? 0,
            status: state.status,
            analyzing: !state.done,
        });
    }

    const hide = () => post({ open: false });

    globalThis.ShooPipeline.subscribe((state) => {
        last = state;
        show(state);
    });

    // Back to this tab → this page again; tab hidden / Safari left → the island goes away.
    addEventListener("visibilitychange", () => (isVisible() ? show(last) : hide()));
    addEventListener("pagehide", hide);
    // Back/forward cache: the page comes back without a new scan, so report its last state again.
    addEventListener("pageshow", (event) => event.persisted && show(last));
})();
