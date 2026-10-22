// Cache for RDAP answers (D-imelda-14). It holds a domain name and its registration date, nothing else:
// never a URL, text, title or snapshot. Memory only in phase 03; the KV adapter is ready but not enabled (M7).

export const SUCCESS_TTL_MS = 24 * 3_600_000;
export const FAIL_TTL_MS = 10 * 60_000;
export const MAX_ENTRIES = 1000;

/** value: { registeredAt: epoch ms, or null when the lookup failed } */
const EARLIEST = Date.parse("1985-01-01T00:00:00Z");
const validEntry = (v) => v !== null && typeof v === "object" && (v.registeredAt === null || (Number.isFinite(v.registeredAt) && v.registeredAt >= EARLIEST && v.registeredAt <= Date.now() + 86_400_000));

/**
 * Per-isolate cache. Oldest entry goes first once `max` is reached.
 * @param {{ max?: number, now?: () => number }} [opts]
 */
export function createMemoryCache({ max = MAX_ENTRIES, now = Date.now } = {}) {
    const map = new Map();
    return {
        async get(domain) {
            const hit = map.get(domain);
            if (!hit) return null;
            if (hit.expires <= now()) {
                map.delete(domain);
                return null;
            }
            return { registeredAt: hit.value.registeredAt };
        },
        async set(domain, value, ttlMs) {
            if (!validEntry(value)) return;
            map.delete(domain);
            map.set(domain, { value: { registeredAt: value.registeredAt }, expires: now() + ttlMs });
            while (map.size > max) map.delete(map.keys().next().value);
        },
    };
}

/**
 * Cloudflare KV adapter. NOT enabled in phase 03: it needs a KV namespace and wrangler (M7).
 * KV's minimum expirationTtl is 60 seconds.
 * @param {{ get(key: string): Promise<string | null>, put(key: string, value: string, opts: { expirationTtl: number }): Promise<void> }} kv
 */
export function createKvCache(kv) {
    const key = (domain) => `rdap:${domain}`;
    return {
        async get(domain) {
            const raw = await kv.get(key(domain));
            if (!raw) return null;
            try {
                const value = JSON.parse(raw);
                return validEntry(value) ? { registeredAt: value.registeredAt } : null;
            } catch {
                return null;
            }
        },
        async set(domain, value, ttlMs) {
            if (!validEntry(value)) return;
            await kv.put(key(domain), JSON.stringify({ registeredAt: value.registeredAt }), { expirationTtl: Math.max(60, Math.ceil(ttlMs / 1000)) });
        },
    };
}
