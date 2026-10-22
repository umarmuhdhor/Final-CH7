// Raw feed entries -> the published list: registrable domains, allowlist applied, one entry per domain.
import { toRegistrable } from "./domains.js";
import { OFFICIAL, POPULAR, SHARED_HOSTS } from "./allowlist.js";

/** True when `domain` (a registrable domain) is official, popular or a shared platform apex. */
export function isAllowlisted(domain) {
    if (POPULAR.has(domain) || SHARED_HOSTS.has(domain)) return true;
    const labels = domain.split(".");
    for (let i = 0; i < labels.length - 1; i++) {
        const tail = labels.slice(i).join(".");
        if (OFFICIAL.has(tail) || POPULAR.has(tail)) return true; // shared hosts match only as the exact apex (checked above)
    }
    return false;
}

const iso = (v) => (typeof v === "string" && v.length <= 40 && !Number.isNaN(Date.parse(v)) ? new Date(v).toISOString() : null);

/**
 * @param {object[]} raw entries from a source
 * @param {{ maxDomains: number }} opts
 * @returns {{ active: {domain:string, addedAt:string}[], removed: {domain:string, removedAt:string}[] }}
 *   active: sorted oldest -> newest, newest `maxDomains` kept. removed: domains taken off the list.
 */
export function buildList(raw, { maxDomains }) {
    const byDomain = new Map(); // domain -> { addedAt, removedAt|null }
    for (const e of Array.isArray(raw) ? raw : []) {
        if (!e || typeof e !== "object") continue;
        const domain = toRegistrable(e.host);
        const addedAt = iso(e.addedAt);
        if (!domain || !addedAt || isAllowlisted(domain)) continue;
        const removedAt = e.removedAt == null ? null : iso(e.removedAt);
        if (e.removedAt != null && !removedAt) continue;
        const cur = byDomain.get(domain);
        if (!cur) {
            byDomain.set(domain, { addedAt, removedAt });
            continue;
        }
        if (addedAt < cur.addedAt) cur.addedAt = addedAt;
        // One live entry under the same registrable domain keeps it on the list.
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
