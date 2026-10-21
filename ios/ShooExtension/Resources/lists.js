// Owner: lead. Layer-1 lists on the phone (docs/design/blocklist.md). ES module, used by background.js.
// Downloads GET /blocklist (backend) and GET /public-blocklist (AI service), keeps them in storage.local,
// refreshes them, and answers match(hostname) for content scripts. The visited URL never leaves the phone.

const HOUR = 60 * 60 * 1000;

export const SOURCES = [
    { id: "shoo", baseKey: "apiBaseURL", path: "/blocklist", every: 1 * HOUR },
    { id: "public", baseKey: "aiBaseURL", path: "/public-blocklist", every: 6 * HOUR },
];
export const FULL_EVERY = 24 * HOUR; // full download also drops domains removed server-side
export const MAX_AGE = 7 * 24 * HOUR; // older copies are ignored, not trusted
export const MAX_ENTRIES = 200_000; // per source; ≈ 4 MB in storage
const MAX_PAGES = 10;
const TIMEOUT_MS = 20 * 1000;
const STORAGE_PREFIX = "lists.v1.";

/** Hostname and each parent down to the registrable domain — never above it (no "vercel.app", no "co.id"). */
export function candidates(hostname, registrable) {
    const host = String(hostname || "").toLowerCase().replace(/\.+$/, "");
    if (!host || !registrable || !host.endsWith(registrable)) return registrable ? [registrable] : [];
    const labels = host.split(".");
    const stop = registrable.split(".").length;
    const out = [];
    for (let i = 0; labels.length - i >= stop; i++) out.push(labels.slice(i).join("."));
    return out;
}

/** "full" | "incremental" | null — what this source needs now. */
export function due(meta, source, now) {
    if (meta?.fullAt == null || now - meta.fullAt >= FULL_EVERY) return "full";
    if (meta.fetchedAt == null || now - meta.fetchedAt >= source.every) return "incremental";
    return null;
}

/** Applies one response page to a Map(domain → addedAt). Mutates and returns it. */
export function applyPage(map, page) {
    for (const entry of Array.isArray(page?.domains) ? page.domains : []) {
        const domain = typeof entry?.domain === "string" ? entry.domain.toLowerCase().trim() : "";
        if (domain && map.size < MAX_ENTRIES) map.set(domain, entry.addedAt ?? null);
    }
    for (const entry of Array.isArray(page?.removed) ? page.removed : []) {
        if (typeof entry?.domain === "string") map.delete(entry.domain.toLowerCase().trim());
    }
    return map;
}

/**
 * @param {object} deps
 * @param {{get(keys): Promise<object>, set(items): Promise<void>}} deps.storage  browser.storage.local
 * @param {() => Promise<object|null>} deps.getSession   getSession reply (token, apiBaseURL, aiBaseURL) or null
 * @param {(url, init) => Promise<object>} deps.fetchJSON
 * @param {(hostname) => string} deps.registrableDomain
 * @param {() => number} [deps.now]
 */
export function createLists({ storage, getSession, fetchJSON, registrableDomain, now = () => Date.now() }) {
    const state = new Map(); // source id → { map: Map, meta: { fetchedAt, fullAt, nextSince } }
    let loaded = null;
    const inFlight = new Map(); // source id → Promise

    function load() {
        loaded ??= (async () => {
            const keys = SOURCES.map((s) => STORAGE_PREFIX + s.id);
            let stored = {};
            try {
                stored = (await storage.get(keys)) ?? {};
            } catch (error) {
                console.warn("[Shoo] lists: storage read failed", error);
            }
            for (const source of SOURCES) {
                const saved = stored[STORAGE_PREFIX + source.id];
                state.set(source.id, {
                    map: new Map(Array.isArray(saved?.domains) ? saved.domains : []),
                    meta: saved?.meta ?? {},
                });
            }
        })();
        return loaded;
    }

    async function save(source) {
        const { map, meta } = state.get(source.id);
        try {
            await storage.set({ [STORAGE_PREFIX + source.id]: { domains: [...map], meta } });
        } catch (error) {
            console.warn(`[Shoo] lists: storage write failed (${source.id})`, error);
        }
    }

    async function refreshSource(source, session) {
        const current = state.get(source.id);
        const kind = due(current.meta, source, now());
        const base = session?.[source.baseKey];
        if (!kind || !base) return;

        const full = kind === "full";
        const map = full ? new Map() : new Map(current.map);
        let since = full ? null : current.meta.nextSince ?? null;
        for (let page = 0; page < MAX_PAGES; page++) {
            const query = since ? `?since=${encodeURIComponent(since)}` : "";
            const body = await fetchJSON(base.replace(/\/+$/, "") + source.path + query, {
                method: "GET",
                token: session.token,
                timeoutMs: TIMEOUT_MS,
            });
            applyPage(map, body);
            const next = body?.nextSince ?? null;
            const empty = !body?.domains?.length && !body?.removed?.length;
            const caughtUp = empty || next == null || next === since;
            if (next != null) since = next;
            if (caughtUp) break; // otherwise ask again from the new cursor (server may page)
        }
        const at = now();
        state.set(source.id, { map, meta: { fetchedAt: at, fullAt: full ? at : current.meta.fullAt, nextSince: since } });
        await save(source);
    }

    /** Refreshes whatever is due. Never rejects; one download per source at a time. */
    async function refresh() {
        await load();
        let session = null;
        try {
            session = await getSession();
        } catch {
            session = null;
        }
        if (!session?.token) return; // not set up → no lists (layer 2 still runs)
        await Promise.all(
            SOURCES.map((source) => {
                if (!inFlight.has(source.id)) {
                    const job = refreshSource(source, session)
                        .catch((error) => console.warn(`[Shoo] lists: refresh failed (${source.id})`, error))
                        .finally(() => inFlight.delete(source.id));
                    inFlight.set(source.id, job);
                }
                return inFlight.get(source.id);
            }),
        );
    }

    /**
     * contracts/detector-interface.md "ShooLists". Never rejects. Uses what's stored now and
     * starts a background refresh if one is due — a page never waits for a download.
     * @returns {Promise<{source: string, domain: string, addedAt: string|null} | null>}
     */
    async function match(hostname) {
        try {
            await load();
            refresh(); // fire and forget
            let registrable = "";
            try {
                registrable = registrableDomain(hostname);
            } catch {
                return null;
            }
            const names = candidates(hostname, registrable);
            for (const source of SOURCES) {
                const { map, meta } = state.get(source.id);
                if (meta.fetchedAt == null || now() - meta.fetchedAt > MAX_AGE) continue; // stale copy: don't trust it
                for (const name of names) {
                    if (map.has(name)) return { source: source.id, domain: name, addedAt: map.get(name) };
                }
            }
            return null;
        } catch (error) {
            console.warn("[Shoo] lists: match failed", error);
            return null;
        }
    }

    return { load, refresh, match, _state: state };
}
