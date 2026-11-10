// Owner: lead. Live score → Dynamic Island through the backend (EX-03 path C, #49). ES module, used by
// background.js. Contract: contracts/api.md "Live score (Dynamic Island)".
// Content scripts report the page on screen (`show`) and when it leaves the screen (`hide`). This module
// coalesces them into `POST /live` calls:
// - a new page, a status change or an `analyzing` change → sent right away;
// - a score-only change → at most one call per LIVE_SCORE_INTERVAL_MS, the newest score wins;
// - hidden → `open: false` after LIVE_CLOSE_DELAY_MS, cancelled when a page comes on screen meanwhile
//   (a tab switch must not end and restart the island).
// Only with the online check on (`getSession().aiBaseURL`, same rule as /analyze). Domain and score are
// forwarded by the backend and stored nowhere.

export const LIVE_CLOSE_DELAY_MS = 1500;
export const LIVE_SCORE_INTERVAL_MS = 1000;

// Same rule as the backend (backend/api/src/http/validate.ts DOMAIN): registrable, lowercase, no www.
const DOMAIN = /^(?!www\.)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;
const IPV4 = /^\d{1,3}(?:\.\d{1,3}){3}$/; // passes DOMAIN, but an IP is no site name
const STATUSES = new Set(["normal", "warning", "blocked"]);

/**
 * @param {object} deps
 * @param {() => Promise<object|null>} deps.getSession  getSession reply, or null when not onboarded
 * @param {(session: object, body: object) => Promise<unknown>} deps.post  POST /live with the device token
 */
export function createLive({ getSession, post, now = () => Date.now(), setTimer = setTimeout, clearTimer = clearTimeout }) {
    let last = null; // last body sent with open: true; null = no island
    let lastAt = -Infinity;
    let pending = null; // newest score-only body waiting for the interval
    let scoreTimer = null;
    let closeTimer = null;

    async function send(body) {
        const session = await getSession();
        // Online check off (no aiBaseURL) or not onboarded: the in-page pill only.
        if (!session?.aiBaseURL || !session?.apiBaseURL || !session?.token) return { ok: true, skipped: "online_check_off" };
        try {
            await post(session, body);
            return { ok: true };
        } catch (error) {
            // A dropped update is fine: the next change sends the newest state. Never logs the domain.
            console.warn("[Shoo] /live failed", error?.status ?? "network");
            return { ok: false };
        }
    }

    function flush(body) {
        last = body;
        lastAt = now();
        return send(body);
    }

    function cancelScore() {
        if (scoreTimer !== null) clearTimer(scoreTimer);
        scoreTimer = null;
        pending = null;
    }

    /** A page is on screen with this state. */
    function show({ domain, score, status, analyzing }) {
        // No registrable domain (IP address, localhost): no island for this page.
        if (!DOMAIN.test(domain ?? "") || IPV4.test(domain) || !STATUSES.has(status)) return hide();
        if (closeTimer !== null) clearTimer(closeTimer);
        closeTimer = null;

        const body = { domain, score: Math.max(0, Math.min(100, Math.round(Number(score) || 0))), status, analyzing: Boolean(analyzing), open: true };
        const urgent = !last || last.domain !== domain || last.status !== body.status || last.analyzing !== body.analyzing;
        if (!urgent && last.score === body.score) return Promise.resolve({ ok: true, unchanged: true });
        if (urgent || now() - lastAt >= LIVE_SCORE_INTERVAL_MS) {
            cancelScore();
            return flush(body);
        }
        pending = body;
        if (scoreTimer === null) {
            scoreTimer = setTimer(() => {
                const next = pending;
                scoreTimer = null;
                pending = null;
                if (next) flush(next);
            }, lastAt + LIVE_SCORE_INTERVAL_MS - now());
        }
        return Promise.resolve({ ok: true, coalesced: true });
    }

    /** No page is on screen any more (tab hidden, Safari left, page closed). */
    function hide() {
        cancelScore(); // a score for a page that left the screen is stale
        if (!last || closeTimer !== null) return Promise.resolve({ ok: true });
        closeTimer = setTimer(() => {
            closeTimer = null;
            const body = { ...last, open: false };
            last = null;
            send(body);
        }, LIVE_CLOSE_DELAY_MS);
        return Promise.resolve({ ok: true, closing: true });
    }

    return { show, hide };
}
