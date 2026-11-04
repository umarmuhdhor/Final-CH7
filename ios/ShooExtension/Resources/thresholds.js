// Owner: lead (built by the admin dashboard lane, dashboard phase 05b X1, D-dash-10). ES module, used
// by background.js. Score thresholds from GET /config/public: the admins set them in the admin
// dashboard; until they switch them live the backend serves the built-in 30/80 (version 0).
// Safari only: Chrome keeps pipeline.js's built-in values (chrome/CLAUDE.md). Content scripts get the
// numbers through thresholds-client.js and never see the token or the URL.

const HOUR = 60 * 60 * 1000;
export const REFRESH_EVERY = 1 * HOUR; // the backend caches the answer for an hour too
export const MAX_AGE = 7 * 24 * HOUR; // older copies are ignored, like the lists
const TIMEOUT_MS = 10 * 1000;
export const RETRY_AFTER_FAILURE = 10 * 60 * 1000; // a server that is down is not asked on every page load
const CLOCK_SKEW = 5 * 60 * 1000;
const STORAGE_KEY = "thresholds.v1";

/** pipeline.js THRESHOLD as built in, plus the version it stands for. */
export const DEFAULTS = Object.freeze({ firstWarning: 30, secondWarning: 50, blocked: 80, version: 0 });

/**
 * Server body → pipeline thresholds, or null when it breaks the fence the dashboard enforces
 * (warn 30–60, block 50–95, gap ≥ 15). The second warning (popup tier 2, struck fields) is not a
 * setting: 50, kept between the two thresholds (dashboard 05b K2).
 */
export function toThresholds(body) {
    const { warnAt, blockAt, version } = body ?? {};
    if (![warnAt, blockAt, version].every(Number.isInteger)) return null;
    if (warnAt < 30 || warnAt > 60 || blockAt < 50 || blockAt > 95 || blockAt - warnAt < 15 || version < 0) return null;
    // Popup tier 2 starts at 50, as built in. When warnAt is already ≥ 50 that would leave tier 1
    // empty, so tier 2 moves to the middle of the warning band instead (gap ≥ 15, so it stays inside).
    const secondWarning = warnAt < 50 ? Math.min(50, blockAt) : Math.round((warnAt + blockAt) / 2);
    return { firstWarning: warnAt, secondWarning, blocked: blockAt, version };
}

/**
 * @param {object} deps
 * @param {{get(keys): Promise<object>, set(items): Promise<void>}} deps.storage  browser.storage.local
 * @param {() => Promise<object|null>} deps.getSession   getSession reply (token, apiBaseURL) or null
 * @param {(url, init) => Promise<object>} deps.fetchJSON
 * @param {() => number} [deps.now]
 */
export function createThresholds({ storage, getSession, fetchJSON, now = () => Date.now() }) {
    let saved = null; // { value, fetchedAt }
    let loaded = null;
    let inFlight = null;
    let failedAt = null;

    /** Age of the saved value; a value from the future counts as expired. */
    const age = () => (saved ? now() - saved.fetchedAt : Infinity);
    const fresh = (limit) => age() >= -CLOCK_SKEW && age() < limit;

    function load() {
        loaded ??= (async () => {
            try {
                const stored = (await storage.get(STORAGE_KEY))?.[STORAGE_KEY];
                const value = toThresholds(stored?.value ? { warnAt: stored.value.firstWarning, blockAt: stored.value.blocked,
                    version: stored.value.version } : null);
                // A time in the future (clock moved back, corrupt entry) would never expire: dropped.
                if (value && Number.isFinite(stored.fetchedAt) && stored.fetchedAt <= now() + CLOCK_SKEW) {
                    saved = { value, fetchedAt: stored.fetchedAt };
                }
            } catch (error) {
                console.warn("[Shoo] thresholds: storage read failed", error);
            }
        })();
        return loaded;
    }

    async function download() {
        let session = null;
        try {
            session = await getSession();
        } catch {
            session = null;
        }
        if (!session?.token || !session.apiBaseURL) return; // not set up → built-in values
        const body = await fetchJSON(session.apiBaseURL.replace(/\/+$/, "") + "/config/public", {
            method: "GET",
            token: session.token,
            timeoutMs: TIMEOUT_MS,
        });
        const value = toThresholds(body);
        if (!value) throw new Error("invalid /config/public answer");
        saved = { value, fetchedAt: now() };
        try {
            await storage.set({ [STORAGE_KEY]: saved });
        } catch (error) {
            console.warn("[Shoo] thresholds: storage write failed", error); // kept in memory until restart
        }
    }

    /** Downloads when due. Never rejects; a failure keeps the last good value. One download at a time. */
    async function refresh() {
        await load();
        if (fresh(REFRESH_EVERY)) return;
        if (failedAt != null && now() - failedAt >= 0 && now() - failedAt < RETRY_AFTER_FAILURE) return;
        inFlight ??= download()
            .then(() => (failedAt = null))
            .catch((error) => {
                failedAt = now();
                console.warn("[Shoo] thresholds: refresh failed", error);
            })
            .finally(() => (inFlight = null));
        return inFlight;
    }

    /** What a page should use now. Never waits for a download (starts one if due); never rejects. */
    async function current() {
        await load();
        refresh(); // fire and forget
        if (!fresh(MAX_AGE + 1)) return { ...DEFAULTS };
        return { ...saved.value };
    }

    return { load, refresh, current };
}
