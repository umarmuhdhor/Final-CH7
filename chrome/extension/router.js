// Owner: lead. Chrome only. ES module, used by background.js: answers the messages the shared content
// scripts and blocked.html send (same types as the Safari background.js). Kept free of chrome.* for tests.
// Content scripts run in the page's process: no reply ever carries the token or the base URLs.

/**
 * @param {object} deps
 * @param {() => Promise<object|null>} deps.getSession    session.js
 * @param {{ match(hostname): Promise<object|null> }} deps.lists
 * @param {{ lookup(domain, opts): Promise<object> }} deps.verdicts
 * @param {(hostname) => string} deps.domainFor
 * @param {(snapshot, localSignals) => Promise<object>} deps.analyze  layer 3–4, never rejects
 */
export function createRouter({ getSession, lists, verdicts, domainFor, analyze }) {
    return function route(message) {
        switch (message?.type) {
            case "heartbeat":
                // EX-01 / C11 tell the iPhone app the extension is on; there is no app on Chrome.
                return { ok: true, skipped: "no_app" };
            case "profile":
                // What blocked.html, the popup and the marks need to pick their wording. Never the token.
                return getSession().then((s) => ({
                    ok: true,
                    onboarded: Boolean(s),
                    mode: s?.mode ?? null,
                    guardianName: s?.guardianName ?? null,
                }));
            case "listMatch":
                return lists.match(message.hostname).then((match) => ({ ok: true, match }));
            case "domain":
                return { ok: true, domain: domainFor(message.hostname) };
            case "analyze":
                return analyze(message.snapshot, message.localSignals ?? []);
            case "report":
                // EX-07 (POST /scans + screenshot) is not part of the Chrome extension yet (README).
                return { ok: false, skipped: "not_supported" };
            case "recordId":
                return { ok: true, recordId: null };
            case "verdict":
                return verdicts.lookup(message.domain, { fresh: Boolean(message.fresh) });
            default:
                return { ok: false, error: "unknown_type" };
        }
    };
}
