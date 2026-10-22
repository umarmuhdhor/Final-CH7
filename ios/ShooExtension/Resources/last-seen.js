// Owner: lead. PATCH /devices/me { extensionLastSeenAt } (C11, GD-03). ES module, used by background.js.
// Rides along with the heartbeat, at most once per hour (contracts/api.md). The backend turns it into
// `extensionActive` for "Not connected" on the Guardian side. The time it last went out is kept in
// storage.local: Safari can stop the background page at any time, so a counter in memory would reset.

export const INTERVAL_MS = 60 * 60 * 1000;
const TIMEOUT_MS = 8 * 1000;
const STORAGE_KEY = "lastSeen.v1.sentAt";

/**
 * @param {object} deps
 * @param {{get(keys): Promise<object>, set(items): Promise<void>}} deps.storage  browser.storage.local
 * @param {() => Promise<object|null>} deps.getSession  getSession reply (token, apiBaseURL) or null
 * @param {(url, init) => Promise<object>} deps.fetchJSON
 * @param {() => number} [deps.now]
 */
export function createLastSeen({ storage, getSession, fetchJSON, intervalMs = INTERVAL_MS, now = () => Date.now() }) {
    let sentAt = null; // null = not read from storage yet
    let inFlight = null;

    async function lastSentAt() {
        if (sentAt !== null) return sentAt;
        try {
            const stored = (await storage.get([STORAGE_KEY])) ?? {};
            sentAt = Number.isFinite(stored[STORAGE_KEY]) ? stored[STORAGE_KEY] : -Infinity;
        } catch (error) {
            console.warn("[Shoo] lastSeen: storage read failed", error);
            sentAt = -Infinity;
        }
        return sentAt;
    }

    async function send() {
        if (now() - (await lastSentAt()) < intervalMs) return { ok: true, throttled: true };
        const session = await getSession();
        if (!session?.apiBaseURL || !session.token) return { ok: true, skipped: "no_api_url" }; // not onboarded

        const at = now();
        try {
            await fetchJSON(session.apiBaseURL.replace(/\/+$/, "") + "/devices/me", {
                method: "PATCH",
                token: session.token,
                timeoutMs: TIMEOUT_MS,
                body: JSON.stringify({ extensionLastSeenAt: new Date(at).toISOString() }),
            });
        } catch (error) {
            // Not recorded as sent → the next heartbeat tries again. A 429 waits the same way.
            console.warn("[Shoo] PATCH /devices/me failed", error);
            return { ok: true, skipped: "error" };
        }
        sentAt = at;
        try {
            await storage.set({ [STORAGE_KEY]: at });
        } catch (error) {
            console.warn("[Shoo] lastSeen: storage write failed", error);
        }
        return { ok: true, sent: true };
    }

    /** Never rejects. Calls that overlap share one request. */
    function report() {
        inFlight ??= send().finally(() => {
            inFlight = null;
        });
        return inFlight;
    }

    return { report };
}
