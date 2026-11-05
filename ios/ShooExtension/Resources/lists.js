// Owner: lead. Layer-1 lists on the phone (docs/design/blocklist.md). ES module, used by background.js.
// Downloads GET /blocklist (backend) and GET /public-blocklist (AI service), keeps them in storage.local,
// refreshes them, and answers match(hostname) for content scripts. The visited URL never leaves the phone.
// The public list is about 14 MB and Safari can stop this page at any time, so the lists stay in storage,
// split into shards: a page reads the shards of its own names, a delta rewrites only the shards it changes.

const HOUR = 60 * 60 * 1000;

export const SOURCES = [
    { id: "shoo", baseKey: "apiBaseURL", path: "/blocklist", every: 1 * HOUR },
    { id: "public", baseKey: "aiBaseURL", path: "/public-blocklist", every: 6 * HOUR },
];
export const FULL_EVERY = 24 * HOUR; // full download also drops domains removed server-side
export const MAX_AGE = 7 * 24 * HOUR; // older copies are ignored, not trusted
export const MAX_ENTRIES = 200_000; // per source, kept at each full download; ≈ 15 MB in storage
export const RETRY_AFTER_FAILURE = 10 * 60 * 1000; // a server that is down is not asked on every page load
export const SHARDS = 256;
const WRITE_BATCH = 16; // shards per storage.set
const MAX_PAGES = 10;
const TIMEOUT_MS = 20 * 1000;
const STORAGE_PREFIX = "lists.v2.";
const OLD_PREFIX = "lists.v1."; // one key per source, the whole list in it

const metaKey = (id) => `${STORAGE_PREFIX}${id}.meta`;
const shardKey = (id, shard) => `${STORAGE_PREFIX}${id}.${shard}`;

/** The shard a domain lives in (FNV-1a). */
export function shardOf(domain) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < domain.length; i++) hash = Math.imul(hash ^ domain.charCodeAt(i), 0x01000193);
    return (hash >>> 0) % SHARDS;
}

/** Map(domain → addedAt) as shard → { domain: addedAt }, with every shard present so old entries go. */
function toShards(map) {
    const shards = new Map(Array.from({ length: SHARDS }, (_, shard) => [shard, {}]));
    for (const [domain, addedAt] of map) shards.get(shardOf(domain))[domain] = addedAt;
    return shards;
}

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

/**
 * Applies one response page to a Map(domain → addedAt). Mutates and returns it.
 * removed[] goes first so it frees room. Past MAX_ENTRIES the oldest entries go (newest scams matter most).
 */
export function applyPage(map, page) {
    for (const entry of Array.isArray(page?.removed) ? page.removed : []) {
        if (typeof entry?.domain === "string") map.delete(entry.domain.toLowerCase().trim());
    }
    for (const entry of Array.isArray(page?.domains) ? page.domains : []) {
        const domain = typeof entry?.domain === "string" ? entry.domain.toLowerCase().trim() : "";
        if (domain) map.set(domain, entry.addedAt ?? null);
    }
    if (map.size > MAX_ENTRIES) evictOldest(map, map.size - MAX_ENTRIES);
    return map;
}

/** One page of an incremental update into changes: Map(domain → addedAt), undefined = remove. Mutates it. */
function collectChanges(changes, page) {
    for (const entry of Array.isArray(page?.removed) ? page.removed : []) {
        if (typeof entry?.domain === "string") changes.set(entry.domain.toLowerCase().trim(), undefined);
    }
    for (const entry of Array.isArray(page?.domains) ? page.domains : []) {
        const domain = typeof entry?.domain === "string" ? entry.domain.toLowerCase().trim() : "";
        if (domain) changes.set(domain, entry.addedAt ?? null);
    }
}

/** a older than b? null addedAt is oldest; ties go to the earlier-inserted entry. Items: [addedAt, index, domain]. */
const older = (a, b) => (a[0] === b[0] ? a[1] < b[1] : a[0] == null || (b[0] != null && a[0] < b[0]));

/** Deletes the `count` oldest entries in one pass: max-heap of the oldest seen so far, O(n log count). */
function evictOldest(map, count) {
    const heap = []; // heap[0] = newest of the kept-for-eviction set
    const down = (i) => {
        for (;;) {
            const l = 2 * i + 1, r = l + 1;
            let top = i;
            if (l < heap.length && older(heap[top], heap[l])) top = l;
            if (r < heap.length && older(heap[top], heap[r])) top = r;
            if (top === i) return;
            [heap[i], heap[top]] = [heap[top], heap[i]];
            i = top;
        }
    };
    let index = 0;
    for (const [domain, addedAt] of map) {
        const item = [addedAt, index++, domain];
        if (heap.length < count) {
            heap.push(item);
            for (let i = heap.length - 1, p; i > 0 && older(heap[(p = (i - 1) >> 1)], heap[i]); i = p) {
                [heap[i], heap[p]] = [heap[p], heap[i]];
            }
        } else if (older(item, heap[0])) {
            heap[0] = item;
            down(0);
        }
    }
    for (const [, , domain] of heap) map.delete(domain);
}

/**
 * @param {object} deps
 * @param {{get(keys): Promise<object>, set(items): Promise<void>, remove(keys): Promise<void>}} deps.storage  browser.storage.local
 * @param {() => Promise<object|null>} deps.getSession   getSession reply (token, apiBaseURL, aiBaseURL) or null
 * @param {(url, init) => Promise<object>} deps.fetchJSON
 * @param {(hostname) => string} deps.registrableDomain
 * @param {() => number} [deps.now]
 */
export function createLists({ storage, getSession, fetchJSON, registrableDomain, now = () => Date.now() }) {
    const state = new Map(); // source id → { meta: { fetchedAt, fullAt, nextSince, failedAt } }
    let loaded = null;
    let generation = 0; // reset() moves it on: work started before that writes nothing
    const inFlight = new Map(); // source id → Promise

    function load() {
        loaded ??= (async () => {
            let stored = {};
            try {
                stored = (await storage.get(SOURCES.flatMap((s) => [metaKey(s.id), OLD_PREFIX + s.id]))) ?? {};
            } catch (error) {
                console.warn("[Shoo] lists: storage read failed", error);
            }
            for (const source of SOURCES) {
                state.set(source.id, { meta: stored[metaKey(source.id)] ?? {} });
                const old = stored[OLD_PREFIX + source.id];
                if (old) await migrate(source, old, generation);
            }
        })();
        return loaded;
    }

    /** The whole list under one key, as an earlier version stored it, moves into shards. */
    async function migrate(source, old, run) {
        try {
            if (state.get(source.id).meta.fetchedAt == null && Array.isArray(old.domains)) {
                await writeShards(source, toShards(new Map(old.domains)), run);
                await saveMeta(source, old.meta ?? {}, run);
            }
            await storage.remove(OLD_PREFIX + source.id);
        } catch (error) {
            console.warn(`[Shoo] lists: migration failed (${source.id})`, error);
        }
    }

    async function writeShards(source, shards, run) {
        const entries = [...shards];
        for (let i = 0; i < entries.length && run === generation; i += WRITE_BATCH) {
            const batch = entries.slice(i, i + WRITE_BATCH).map(([shard, domains]) => [shardKey(source.id, shard), domains]);
            await storage.set(Object.fromEntries(batch));
        }
    }

    async function saveMeta(source, meta, run) {
        if (run !== generation) return;
        state.get(source.id).meta = meta;
        await storage.set({ [metaKey(source.id)]: meta });
    }

    /** Applies an incremental update to the shards it touches. */
    async function writeChanges(source, changes, run) {
        const bySlot = new Map();
        for (const [domain, addedAt] of changes) {
            const shard = shardOf(domain);
            if (!bySlot.has(shard)) bySlot.set(shard, []);
            bySlot.get(shard).push([domain, addedAt]);
        }
        const stored = (await storage.get([...bySlot.keys()].map((shard) => shardKey(source.id, shard)))) ?? {};
        const shards = new Map();
        for (const [shard, entries] of bySlot) {
            const domains = stored[shardKey(source.id, shard)] ?? {};
            for (const [domain, addedAt] of entries) {
                if (addedAt === undefined) delete domains[domain];
                else domains[domain] = addedAt;
            }
            shards.set(shard, domains);
        }
        await writeShards(source, shards, run);
    }

    async function refreshSource(source, session, run) {
        const current = state.get(source.id);
        if (!current) return;
        const { meta } = current;
        const kind = due(meta, source, now());
        const base = session?.[source.baseKey];
        if (!kind || !base) return;
        const waited = now() - meta.failedAt;
        if (waited >= 0 && waited < RETRY_AFTER_FAILURE) return;

        const full = kind === "full";
        const map = new Map();
        const changes = new Map();
        let since = full ? null : meta.nextSince ?? null;
        for (let page = 0; page < MAX_PAGES; page++) {
            const query = since ? `?since=${encodeURIComponent(since)}` : "";
            const body = await fetchJSON(base.replace(/\/+$/, "") + source.path + query, {
                method: "GET",
                token: session.token,
                timeoutMs: TIMEOUT_MS,
            });
            if (full) applyPage(map, body);
            else collectChanges(changes, body);
            const next = body?.nextSince ?? null;
            const empty = !body?.domains?.length && !body?.removed?.length;
            const caughtUp = empty || next == null || next === since;
            if (next != null) since = next;
            if (caughtUp) break; // otherwise ask again from the new cursor (server may page)
        }
        if (run !== generation) return;
        if (full) await writeShards(source, toShards(map), run);
        else if (changes.size) await writeChanges(source, changes, run);
        const at = now();
        await saveMeta(source, { fetchedAt: at, fullAt: full ? at : meta.fullAt, nextSince: since }, run);
    }

    /** Remembered in storage too: Safari can stop this page at any time. */
    async function noteFailure(source, run) {
        try {
            await saveMeta(source, { ...state.get(source.id)?.meta, failedAt: now() }, run);
        } catch (error) {
            console.warn(`[Shoo] lists: storage write failed (${source.id})`, error);
        }
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
                    const run = generation;
                    const job = refreshSource(source, session, run)
                        .catch((error) => {
                            console.warn(`[Shoo] lists: refresh failed (${source.id})`, error);
                            return noteFailure(source, run);
                        })
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
            const usable = SOURCES.filter((source) => {
                const fetchedAt = state.get(source.id)?.meta.fetchedAt;
                return fetchedAt != null && now() - fetchedAt <= MAX_AGE; // stale copy: don't trust it
            });
            if (!usable.length || !names.length) return null;
            const stored = await storage.get([...new Set(usable.flatMap((source) => names.map((name) => shardKey(source.id, shardOf(name)))))]);
            for (const source of usable) {
                for (const name of names) {
                    const domains = stored?.[shardKey(source.id, shardOf(name))];
                    if (domains && Object.hasOwn(domains, name)) return { source: source.id, domain: name, addedAt: domains[name] };
                }
            }
            return null;
        } catch (error) {
            console.warn("[Shoo] lists: match failed", error);
            return null;
        }
    }

    /** Storage was cleared for a new device: nothing of the old one stays or gets written back. */
    function reset() {
        generation++;
        state.clear();
        loaded = null;
    }

    return { load, refresh, match, reset };
}
