// Domain age from RDAP, done on the server so a phone never tells a third party what its user browses.
// Rules (SECURITY A2/Q2, D-imelda-13):
//  - only a validated registrable domain is sent, never a URL, path, query or page data;
//  - the RDAP server comes from the IANA bootstrap file (fixed URL), never from the page, and must be a public https host;
//  - redirects are not followed; every failure (network, status, shape, timeout) means "no signal";
//  - nothing is logged.
import { registrableDomain, isPublicHostname } from "./domain.js";
import { SUCCESS_TTL_MS, FAIL_TTL_MS } from "./cache.js";

export const BOOTSTRAP_URL = "https://data.iana.org/rdap/dns.json";
/**
 * RDAP timeout. Covers bootstrap + domain lookup together. D-imelda-47 cut it to 1 s to leave layer 4 (LLM) its time; layer 4
 * has been off since 19 Nov 2026 (SHOO_L4=off), and a cold .cc lookup (Verisign) takes 0.6-1.0 s plus the bootstrap, so 1 s
 * often missed it and the page lost new_domain AND the young-domain model warning (jnex.cc, 23 Nov 2026). Well inside the
 * 6.5 s server deadline.
 */
export const TIMEOUT_MS = 3000;
/**
 * A lookup still running at TIMEOUT_MS goes on in the background (Worker waitUntil) up to this long in total, then its
 * result is cached for the next check. Measured from a Mac on 23 Nov 2026 (150 lab domains): lookups over 3 s took 3.6-5.5 s
 * (one .ca 9.9 s, one .nl over 15 s), and the same domains answered in 0.1-0.5 s when asked again.
 */
export const BACKGROUND_MS = 15_000;
const MAX_BOOTSTRAP_BYTES = 1_500_000;
const MAX_RDAP_BYTES = 256 * 1024;
const BOOTSTRAP_FAIL_TTL_MS = 60_000;
const BOOTSTRAP_TIMEOUT_MS = 5000;
const DAY_MS = 86_400_000;
const EARLIEST = Date.parse("1985-01-01T00:00:00Z"); // first .com registration; older dates are nonsense

/** Reads at most `max` bytes; null when the body is bigger. */
async function readCapped(res, max) {
    const declared = Number(res.headers.get("content-length"));
    if (Number.isFinite(declared) && declared > max) return null;
    if (!res.body) return null;
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let size = 0;
    let out = "";
    for (;;) {
        const { done, value } = await reader.read();
        if (done) return out + decoder.decode();
        size += value.byteLength;
        if (size > max) {
            await reader.cancel().catch(() => {});
            return null;
        }
        out += decoder.decode(value, { stream: true });
    }
}

/** A bootstrap server URL is used only when it is plain public https on port 443 with no credentials. */
function safeServer(raw) {
    if (typeof raw !== "string") return null;
    let u;
    try {
        u = new URL(raw);
    } catch {
        return null;
    }
    if (u.protocol !== "https:" || u.username || u.password || u.port || u.search || u.hash) return null;
    if (!isPublicHostname(u.hostname)) return null;
    return u.origin + (u.pathname.endsWith("/") ? u.pathname : `${u.pathname}/`);
}

function parseBootstrap(data) {
    if (!data || !Array.isArray(data.services)) return null;
    const map = new Map();
    for (const entry of data.services) {
        if (!Array.isArray(entry) || !Array.isArray(entry[0]) || !Array.isArray(entry[1])) continue;
        const server = entry[1].map(safeServer).find(Boolean);
        if (!server) continue;
        for (const tld of entry[0]) if (typeof tld === "string") map.set(tld.toLowerCase(), server);
    }
    return map.size ? map : null;
}

function registrationDate(data, now) {
    const events = data && Array.isArray(data.events) ? data.events : [];
    for (const e of events) {
        if (!e || typeof e.eventAction !== "string" || e.eventAction.toLowerCase() !== "registration") continue;
        const t = Date.parse(e.eventDate);
        if (Number.isFinite(t) && t >= EARLIEST && t <= now + DAY_MS) return t;
    }
    return null;
}

/**
 * @param {{ fetch: typeof fetch, cache: { get(d: string): Promise<{registeredAt:number|null}|null>, set(d: string, v: {registeredAt:number|null}, ttl: number): Promise<void> }, now?: () => number, timeoutMs?: number, backgroundMs?: number }} deps
 */
export function createRdapClient({ fetch: doFetch, cache, now = Date.now, timeoutMs = TIMEOUT_MS, backgroundMs = BACKGROUND_MS }) {
    let bootstrap = null; // { map, expires }

    let inflight = null; // one bootstrap download at a time, shared by concurrent requests

    function getServers() {
        if (bootstrap && bootstrap.expires > now()) return Promise.resolve(bootstrap.map);
        inflight ??= loadBootstrap().finally(() => (inflight = null));
        return inflight;
    }

    // The download is shared by every request that arrives meanwhile, so it must not borrow one request's
    // abort signal or deadline: it gets its own timeout.
    async function loadBootstrap() {
        const controller = new AbortController();
        let timer;
        const timeout = new Promise((resolve) => {
            timer = setTimeout(() => {
                controller.abort();
                resolve(null);
            }, BOOTSTRAP_TIMEOUT_MS);
        });
        let map = null;
        try {
            // network error, abort or timeout: remember the failure briefly instead of retrying on every request
            map = await Promise.race([downloadBootstrap(controller.signal).catch(() => null), timeout]);
        } finally {
            clearTimeout(timer);
        }
        bootstrap = { map, expires: now() + (map ? SUCCESS_TTL_MS : BOOTSTRAP_FAIL_TTL_MS) };
        return map;
    }

    async function downloadBootstrap(signal) {
        const res = await doFetch(BOOTSTRAP_URL, { method: "GET", headers: { accept: "application/json" }, redirect: "manual", signal });
        const text = res.status === 200 ? await readCapped(res, MAX_BOOTSTRAP_BYTES) : null;
        if (res.status !== 200) res.body?.cancel().catch(() => {});
        return text ? parseBootstrap(JSON.parse(text)) : null;
    }

    /**
     * `state.answered` tells the caller whether a null is about this domain (cacheable: the TLD has no RDAP server, or the
     * registry replied without a usable date) or just bad luck (no bootstrap, network error, timeout: ask again next visit).
     */
    async function fetchRegistration(domain, signal, state) {
        const servers = await getServers();
        if (!servers) return null; // no bootstrap: says nothing about this domain
        const server = servers.get(domain.slice(domain.lastIndexOf(".") + 1));
        if (!server) {
            state.answered = true; // no RDAP server for this TLD: asking again will not help
            return null;
        }
        const res = await doFetch(`${server}domain/${domain}`, { method: "GET", headers: { accept: "application/rdap+json, application/json" }, redirect: "manual", signal });
        state.answered = true; // the registry replied; its status or body is about this domain
        if (res.status !== 200) {
            res.body?.cancel().catch(() => {});
            return null;
        }
        const text = await readCapped(res, MAX_RDAP_BYTES);
        return text ? registrationDate(JSON.parse(text), now()) : null;
    }

    /**
     * One network lookup with a hard stop at `hardMs`, even if fetch ignores the abort signal.
     * @returns {Promise<{ registeredAt: number|null, cacheable: boolean }>} never rejects
     */
    function runLookup(domain, hardMs) {
        const controller = new AbortController();
        const state = { answered: false, timedOut: false };
        let timer;
        const hardStop = new Promise((resolve) => {
            timer = setTimeout(() => {
                state.timedOut = true; // set before the abort, so a reply cut off mid-body is never cached as "no date"
                controller.abort();
                resolve(null);
            }, hardMs);
        });
        const work = fetchRegistration(domain, controller.signal, state).catch(() => null);
        return Promise.race([work, hardStop]).then((registeredAt) => {
            clearTimeout(timer);
            // Cached only when the registry (or the bootstrap) really answered. A timeout or a network error is not cached:
            // before 23 Nov 2026 it was, for 10 min, so a slow first lookup kept a new scam domain at no signal.
            return { registeredAt, cacheable: state.answered && !state.timedOut };
        });
    }

    /** domain -> running lookup (already writing its result to the cache), so concurrent requests share one network call. */
    const running = new Map();

    function startLookup(domain, hardMs, requestCache) {
        const pending = runLookup(domain, hardMs)
            .then(async (fresh) => {
                if (fresh.cacheable) {
                    try {
                        await requestCache.set(domain, { registeredAt: fresh.registeredAt }, fresh.registeredAt === null ? FAIL_TTL_MS : SUCCESS_TTL_MS);
                    } catch {
                        /* ignore */
                    }
                }
                return fresh;
            })
            .finally(() => running.delete(domain));
        running.set(domain, pending);
        return pending;
    }

    const ageOf = (registeredAt) => (registeredAt === null ? null : Math.max(0, Math.floor((now() - registeredAt) / DAY_MS)));

    const dateOf = (registeredAt) => (registeredAt === null ? null : new Date(registeredAt).toISOString().slice(0, 10));

    /**
     * Registration date and age, both null for anything that goes wrong. Never throws, never logs.
     * The answer waits at most `timeoutMs` (cache read + network). With `waitUntil` (the Worker's), a lookup that is still
     * running then goes on in the background up to `backgroundMs` in total and caches its result, so the next check of the
     * page, or the next page on the domain, gets the age. Without `waitUntil` it is cut at `timeoutMs`, as before.
     * @param {string} host hostname of the page
     * @param {{ cache?: object, waitUntil?: (p: Promise<unknown>) => void }} [opts] cache for this request only (memory + KV
     *   tiers, app.js); default: the client's cache. waitUntil: keeps the background lookup alive after the response.
     * @returns {Promise<{ registeredAt: string|null, ageDays: number|null }>} registeredAt = `YYYY-MM-DD` (UTC), #270
     */
    async function lookup(host, { cache: requestCache = cache, waitUntil } = {}) {
        const domain = registrableDomain(host);
        if (!domain) return { registeredAt: null, ageDays: null };
        const startedAt = now();
        let registeredAt;
        try {
            const cached = await requestCache.get(domain);
            if (cached) registeredAt = cached.registeredAt;
        } catch {
            /* a broken cache must not break the answer */
        }
        if (registeredAt === undefined) {
            const budget = Math.max(0, timeoutMs - (now() - startedAt));
            const background = typeof waitUntil === "function";
            const pending = running.get(domain) ?? startLookup(domain, background ? Math.max(budget, backgroundMs - (now() - startedAt)) : budget, requestCache);
            let timer;
            const answerBy = new Promise((resolve) => (timer = setTimeout(resolve, budget, null)));
            const fresh = await Promise.race([pending, answerBy]);
            clearTimeout(timer);
            if (fresh) {
                registeredAt = fresh.registeredAt;
            } else {
                registeredAt = null; // not yet: answer without an age
                if (background) waitUntil(pending);
            }
        }
        return { registeredAt: dateOf(registeredAt), ageDays: ageOf(registeredAt) };
    }

    return {
        lookup,
        /** Whole days since registration, or null. Same lookup as `lookup`, age only. */
        lookupAgeDays: async (host, opts) => (await lookup(host, opts)).ageDays,
    };
}
