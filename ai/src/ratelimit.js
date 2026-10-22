// Per-client fixed-window rate limit, in memory (one Worker isolate). Keys are IPs and live only as long as the window.
// Nothing is logged. The limiter is best-effort protection against a single noisy client, not a hard quota
// (isolates are many and short-lived); the hard cap, if needed, is a Cloudflare rule (phase 08 checklist).

/** Client key from Cloudflare's header. IPv6 is cut to its /64 so one network cannot take many buckets. */
export function clientKey(request) {
    const raw = (request.headers.get("cf-connecting-ip") ?? "").trim().toLowerCase();
    if (!raw) return "unknown";
    const mapped = raw.startsWith("::ffff:") ? raw.slice(7) : raw; // IPv4-mapped IPv6 counts as the IPv4 address
    if (!mapped.includes(":")) return mapped.slice(0, 15);
    const [head, tail = ""] = raw.split("::");
    const first = head.split(":").filter(Boolean);
    const rest = tail.split(":").filter(Boolean);
    const groups = raw.includes("::") ? [...first, ...Array(Math.max(0, 8 - first.length - rest.length)).fill("0"), ...rest] : first;
    return `v6:${groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, "")).join(":")}`;
}

/**
 * @param {{ limit: number, windowMs: number, now?: () => number, maxKeys?: number }} opts
 * @returns {(key: string) => { ok: boolean, retryAfterSec: number }}
 */
export function createRateLimiter({ limit, windowMs, now = Date.now, maxKeys = 10_000 }) {
    const hits = new Map(); // key -> { start, count }
    return (key) => {
        const t = now();
        let h = hits.get(key);
        if (!h || t - h.start >= windowMs) {
            if (hits.size >= maxKeys) {
                for (const [k, v] of hits) if (t - v.start >= windowMs) hits.delete(k);
                if (hits.size >= maxKeys) hits.delete(hits.keys().next().value); // oldest key goes first
            }
            h = { start: t, count: 0 };
            hits.set(key, h);
        }
        h.count += 1;
        if (h.count <= limit) return { ok: true, retryAfterSec: 0 };
        return { ok: false, retryAfterSec: Math.max(1, Math.ceil((h.start + windowMs - t) / 1000)) };
    };
}
