// Domain age from RDAP, done on the server so a phone never tells a third party what its user browses.
// Rules (SECURITY A2/Q2, D-imelda-13):
//  - only a validated registrable domain is sent, never a URL, path, query or page data;
//  - the RDAP server comes from the IANA bootstrap file (fixed URL), never from the page, and must be a public https host;
//  - redirects are not followed; every failure (network, status, shape, timeout) means "no signal";
//  - nothing is logged.
import { registrableDomain, isPublicHostname } from "./domain.js";
import { SUCCESS_TTL_MS, FAIL_TTL_MS } from "./cache.js";

export const BOOTSTRAP_URL = "https://data.iana.org/rdap/dns.json";
/** D-imelda-08: RDAP timeout. Covers bootstrap + domain lookup together. */
export const TIMEOUT_MS = 1500;
const MAX_BOOTSTRAP_BYTES = 1_500_000;
const MAX_RDAP_BYTES = 256 * 1024;
const BOOTSTRAP_FAIL_TTL_MS = 60_000;
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
 * @param {{ fetch: typeof fetch, cache: { get(d: string): Promise<{registeredAt:number|null}|null>, set(d: string, v: {registeredAt:number|null}, ttl: number): Promise<void> }, now?: () => number, timeoutMs?: number }} deps
 */
export function createRdapClient({ fetch: doFetch, cache, now = Date.now, timeoutMs = TIMEOUT_MS }) {
    let bootstrap = null; // { map, expires }

    let inflight = null; // one bootstrap download at a time, shared by concurrent requests

    function getServers(signal) {
        if (bootstrap && bootstrap.expires > now()) return Promise.resolve(bootstrap.map);
        inflight ??= loadBootstrap(signal).finally(() => (inflight = null));
        return inflight;
    }

    async function loadBootstrap(signal) {
        let map = null;
        try {
            map = await downloadBootstrap(signal);
        } catch {
            map = null; // network error or abort: remember the failure briefly instead of retrying on every request
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

    async function fetchRegistration(domain, signal) {
        const servers = await getServers(signal);
        const server = servers && servers.get(domain.slice(domain.lastIndexOf(".") + 1));
        if (!server) return null;
        const res = await doFetch(`${server}domain/${domain}`, { method: "GET", headers: { accept: "application/rdap+json, application/json" }, redirect: "manual", signal });
        if (res.status !== 200) {
            res.body?.cancel().catch(() => {});
            return null;
        }
        const text = await readCapped(res, MAX_RDAP_BYTES);
        return text ? registrationDate(JSON.parse(text), now()) : null;
    }

    /** One deadline for the whole lookup, even if fetch ignores the abort signal. */
    async function withDeadline(domain) {
        const controller = new AbortController();
        let timer;
        const deadline = new Promise((resolve) => {
            timer = setTimeout(() => {
                controller.abort();
                resolve(null);
            }, timeoutMs);
        });
        const work = fetchRegistration(domain, controller.signal).catch(() => null);
        try {
            return await Promise.race([work, deadline]);
        } finally {
            clearTimeout(timer);
        }
    }

    const ageOf = (registeredAt) => (registeredAt === null ? null : Math.max(0, Math.floor((now() - registeredAt) / DAY_MS)));

    return {
        /**
         * Whole days since registration, or null for anything that goes wrong. Never throws, never logs.
         * @param {string} host hostname of the page
         */
        async lookupAgeDays(host) {
            const domain = registrableDomain(host);
            if (!domain) return null;
            try {
                const cached = await cache.get(domain);
                if (cached) return ageOf(cached.registeredAt);
            } catch {
                /* a broken cache must not break the answer */
            }
            const registeredAt = await withDeadline(domain);
            try {
                await cache.set(domain, { registeredAt }, registeredAt === null ? FAIL_TTL_MS : SUCCESS_TTL_MS);
            } catch {
                /* ignore */
            }
            return ageOf(registeredAt);
        },
    };
}
