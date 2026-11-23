// Raw feed entries -> the published list: the feed's full hostnames (#643), allowlist applied, one entry per name.
import { toListed, toRegistrable } from "./domains.js";
import { OFFICIAL, POPULAR, SHARED_HOSTS } from "./allowlist.js";
import { POPULAR_APEX } from "./popular-apex.js";

/** True when `domain` (a registrable domain or a hostname) is, or sits under, an official or popular name, or is a shared platform apex. */
export function isAllowlisted(domain) {
    if (POPULAR.has(domain) || SHARED_HOSTS.has(domain)) return true;
    const labels = domain.split(".");
    for (let i = 0; i < labels.length - 1; i++) {
        const tail = labels.slice(i).join(".");
        if (OFFICIAL.has(tail) || POPULAR.has(tail)) return true; // shared hosts match only as the exact apex (checked above)
    }
    return false;
}

/**
 * The allowlist for a published hostname: the host itself and its parents (isAllowlisted), and its registrable domain as
 * well, so a host on a shared platform that is not on the Public Suffix List (`x.sharepoint.com`, `x.weebly.com`) stays
 * off the list as it did when the registrable domain was published. Platforms on the PSL (`x.github.io`, `x.vercel.app`)
 * are their own registrable domains, so their customer sites are still published one by one.
 */
export function isListedAllowlisted(host) {
    // A Tranco top-1000 apex is never published as a whole (23 Nov 2026: zendesk.com, gravatar.com, mit.edu ... were, so
    // every page of them was db_match 100 on the phone). Exact apex only: a host under it is still published.
    if (POPULAR_APEX.has(host)) return true;
    const reg = toRegistrable(host);
    return isAllowlisted(host) || (reg !== null && reg !== host && isAllowlisted(reg));
}

const MIN_MS = Date.UTC(2000, 0, 1);
const SKEW_MS = 24 * 60 * 60 * 1000;
/** ISO string, only for dates between 2000 and now + 1 day: a future date would park every client's cursor in the future. */
const makeIso = (now) => (v) => {
    if (typeof v !== "string" || v.length > 40) return null;
    const ms = Date.parse(v);
    return Number.isNaN(ms) || ms < MIN_MS || ms > now + SKEW_MS ? null : new Date(ms).toISOString();
};

/**
 * @param {object[]} raw entries from a source
 * @param {{ maxDomains: number, now?: number }} opts
 * @returns {{ active: {domain:string, addedAt:string}[], removed: {domain:string, removedAt:string}[] }}
 *   active: sorted oldest -> newest, newest `maxDomains` kept. removed: domains taken off the list.
 */
export function buildList(raw, { maxDomains, now = Date.now() }) {
    const iso = makeIso(now);
    const byDomain = new Map(); // domain -> { addedAt, removedAt|null }
    for (const e of Array.isArray(raw) ? raw : []) {
        if (!e || typeof e !== "object") continue;
        const domain = toListed(e.host);
        const addedAt = iso(e.addedAt);
        if (!domain || !addedAt || isListedAllowlisted(domain)) continue;
        const removedAt = e.removedAt == null ? null : iso(e.removedAt);
        if (e.removedAt != null && !removedAt) continue;
        const cur = byDomain.get(domain);
        if (!cur) {
            byDomain.set(domain, { addedAt, removedAt });
            continue;
        }
        if (addedAt < cur.addedAt) cur.addedAt = addedAt;
        // One live entry for the same name keeps it on the list.
        if (!removedAt) cur.removedAt = null;
        else if (cur.removedAt && removedAt > cur.removedAt) cur.removedAt = removedAt;
    }
    const active = [];
    const removed = [];
    for (const [domain, v] of byDomain) {
        if (v.removedAt) removed.push({ domain, removedAt: v.removedAt });
        else active.push({ domain, addedAt: v.addedAt });
    }
    const byTime = (key) => (a, b) => (a[key] < b[key] ? -1 : a[key] > b[key] ? 1 : a.domain < b.domain ? -1 : 1);
    active.sort(byTime("addedAt"));
    removed.sort(byTime("removedAt"));
    return { active: active.slice(Math.max(0, active.length - maxDomains)), removed };
}

/**
 * @param {{ active: {domain:string, addedAt:string}[], removed: {domain:string, removedAt:string}[] }} list
 * @param {string | null} since ISO timestamp (already validated) or null for a full list
 */
export function pageSince(list, since) {
    if (!since) {
        const domains = list.active;
        const last = [domains[domains.length - 1]?.addedAt, list.removed[list.removed.length - 1]?.removedAt].filter(Boolean).sort().pop();
        return { domains, nextSince: last ?? null };
    }
    const domains = list.active.filter((d) => d.addedAt > since);
    const removed = list.removed.filter((r) => r.removedAt > since);
    let next = since;
    if (domains.length) next = domains[domains.length - 1].addedAt > next ? domains[domains.length - 1].addedAt : next;
    if (removed.length) next = removed[removed.length - 1].removedAt > next ? removed[removed.length - 1].removedAt : next;
    return removed.length ? { domains, removed, nextSince: next } : { domains, nextSince: next };
}
