// Owner: lead. What background.js has to remember about its reports past the page's life. ES module.
// Safari can stop the background page at any time, so the Map in memory is not enough:
//  - report key → backend scan id, which blocked.html asks for after the block screen has opened
//  - domains already reported: POST /scans keeps the first visit's evidence, so a page copy sent
//    again is thrown away there and only costs the user's data plan.
// Stored in storage.local only; nothing here leaves the phone.

export const STORAGE_KEY = "reportLog.v1";
export const DOMAIN_TTL_MS = 24 * 60 * 60 * 1000;
export const ID_TTL_MS = 60 * 60 * 1000;
export const MAX_DOMAINS = 500;
export const MAX_IDS = 50;

/** Drops what is older than ttl, then the oldest past max. `at(value)` is its time. */
function prune(entries, ttl, max, at, now) {
    for (const [key, value] of Object.entries(entries)) {
        if (!(now - at(value) < ttl)) delete entries[key];
    }
    const keys = Object.keys(entries);
    if (keys.length <= max) return;
    keys.sort((a, b) => at(entries[a]) - at(entries[b]));
    for (const key of keys.slice(0, keys.length - max)) delete entries[key];
}

/**
 * @param {object} deps
 * @param {{get(keys): Promise<object>, set(items): Promise<void>}} deps.storage  browser.storage.local
 * @param {() => number} [deps.now]
 */
export function createReportLog({ storage, now = () => Date.now() }) {
    let queue = Promise.resolve(); // read-modify-write one at a time

    async function read() {
        const stored = (await storage.get([STORAGE_KEY]))?.[STORAGE_KEY];
        const object = (value) => (value && typeof value === "object" && !Array.isArray(value) ? value : {});
        return { ids: object(stored?.ids), domains: object(stored?.domains) };
    }

    /** Never rejects: losing this only means a page copy goes out again. */
    function update(change) {
        queue = queue.then(async () => {
            const log = await read();
            change(log);
            prune(log.ids, ID_TTL_MS, MAX_IDS, (entry) => entry?.at, now());
            prune(log.domains, DOMAIN_TTL_MS, MAX_DOMAINS, (at) => at, now());
            await storage.set({ [STORAGE_KEY]: log });
        }).catch((error) => console.warn("[Shoo] report log", error));
        return queue;
    }

    const saveRecord = (key, id) => update((log) => (log.ids[key] = { id, at: now() }));
    const markSent = (domain) => update((log) => (log.domains[domain] = now()));

    /** @returns {Promise<string|null>} the backend's scan id of this report, once it answered */
    async function recordId(key) {
        await queue;
        try {
            const entry = (await read()).ids[key];
            return entry && now() - entry.at < ID_TTL_MS ? entry.id : null;
        } catch {
            return null;
        }
    }

    /** @returns {Promise<boolean>} true when this domain's evidence is already with the backend */
    async function sentRecently(domain) {
        await queue;
        try {
            return now() - (await read()).domains[domain] < DOMAIN_TTL_MS;
        } catch {
            return false;
        }
    }

    return { saveRecord, markSent, recordId, sentRecently };
}
