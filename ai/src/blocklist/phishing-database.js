// The production feed (plan TODO A3, D-imelda-38): Phishing.Database `phishing-domains-ACTIVE.txt`, MIT licence.
// The feed is a bare list of hostnames with no dates, so the date a domain was added is the build in which we first
// saw it (fase-05 MED-6). That needs the previous build's entries, which the build script keeps in Workers KV.
// Runs in the GitHub Action (ai/scripts/build-blocklist.mjs), never in the Worker: parsing ~440k lines costs ~1 s CPU.
import { toRegistrable } from "./domains.js";
import { PREBUILT } from "./prebuilt.js";

export const PHISHING_DATABASE = Object.freeze({
    name: "Phishing.Database phishing-domains-ACTIVE.txt",
    license: "MIT (c) Mitchell Krog, Nissar Chababy, Phishing.Database contributors; upstream sources not documented (Phishing.Database issue #2315)",
    url: "https://raw.githubusercontent.com/Phishing-Database/Phishing.Database/master/phishing-domains-ACTIVE.txt",
});

/** A feed smaller than this is a broken download, not a quiet day (the real file has ~440k lines). */
export const MIN_FEED_HOSTS = 10_000;

/** One hostname per line. Blank lines, `#`/`!` comments and lines with spaces (hosts-file style) are skipped. */
export function parseHostList(text) {
    const hosts = [];
    for (const line of String(text ?? "").split("\n")) {
        const s = line.trim();
        if (!s || s.startsWith("#") || s.startsWith("!") || /\s/.test(s)) continue;
        hosts.push(s);
    }
    return hosts;
}

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const isIso = (v) => typeof v === "string" && ISO.test(v) && !Number.isNaN(Date.parse(v));

/** Previous entries by registrable domain; anything malformed is ignored (treated as never seen). */
function indexPrevious(previous) {
    const byDomain = new Map();
    for (const e of Array.isArray(previous) ? previous : []) {
        if (!e || typeof e !== "object" || !isIso(e.addedAt)) continue;
        if (e.removedAt !== undefined && !isIso(e.removedAt)) continue;
        if (toRegistrable(e.host) !== e.host) continue;
        byDomain.set(e.host, e);
    }
    return byDomain;
}

/**
 * @param {import("./source.js").RawEntry[]} previous entries from the last build ([] on the first)
 * @param {string[]} hosts this build's feed
 * @param {string} builtAt ISO time of this build
 * @returns {import("./source.js").RawEntry[]} one entry per registrable domain: still listed (addedAt kept), new
 *   (addedAt = builtAt), or gone (removedAt = builtAt, kept for KEEP_REMOVED_MS so incremental clients see it).
 */
export function trackFirstSeen(previous, hosts, builtAt) {
    const prev = indexPrevious(previous);
    const builtMs = Date.parse(builtAt);
    const seen = new Set();
    const out = [];
    for (const raw of hosts) {
        const domain = toRegistrable(raw);
        if (!domain || seen.has(domain)) continue;
        seen.add(domain);
        const p = prev.get(domain);
        out.push({ host: domain, addedAt: p && p.removedAt === undefined ? p.addedAt : builtAt });
    }
    for (const [domain, p] of prev) {
        if (seen.has(domain)) continue;
        if (p.removedAt === undefined) out.push({ host: domain, addedAt: p.addedAt, removedAt: builtAt });
        else if (builtMs - Date.parse(p.removedAt) < PREBUILT.KEEP_REMOVED_MS) out.push({ host: domain, addedAt: p.addedAt, removedAt: p.removedAt });
    }
    return out;
}

/**
 * @param {{ fetchText: (url: string) => Promise<string>, previous?: object[], builtAt: string, minHosts?: number }} deps
 * @returns {import("./source.js").BlocklistSource}
 */
export function createPhishingDatabaseSource({ fetchText, previous = [], builtAt, minHosts = MIN_FEED_HOSTS }) {
    return {
        name: PHISHING_DATABASE.name,
        license: PHISHING_DATABASE.license,
        async entries() {
            const hosts = parseHostList(await fetchText(PHISHING_DATABASE.url));
            if (hosts.length < minHosts) throw new Error(`feed too small: ${hosts.length} hosts (expected at least ${minHosts})`);
            return trackFirstSeen(previous, hosts, builtAt);
        },
    };
}
