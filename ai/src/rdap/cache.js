// Cache for RDAP answers (D-imelda-14). It holds a domain name and its registration date, nothing else:
// never a URL, text, title or snapshot. Memory per isolate first; with the RDAP_KV binding, Workers KV is a second tier
// shared by all isolates (D-imelda-40). KV is best effort: any error, timeout or spent budget means "memory only".

export const SUCCESS_TTL_MS = 24 * 3_600_000;
export const FAIL_TTL_MS = 10 * 60_000;
export const MAX_ENTRIES = 1000;
/** A registration date does not change, so KV keeps a success for a week: a domain seen every day costs one write a week. */
export const KV_SUCCESS_TTL_MS = 7 * 24 * 3_600_000;
/** KV read budget, taken out of the RDAP lookup's 1.5 s deadline (rdap.js). */
export const KV_READ_TIMEOUT_MS = 200;
/**
 * Per-isolate KV budget per UTC day (the KV Free limits reset at 00:00 UTC). The account has 1,000 writes and
 * 100,000 reads a day, shared with the public blocklist (~120 writes a day, plus every phone's downloads).
 */
export const KV_WRITES_PER_DAY = 100;
export const KV_READS_PER_DAY = 2000;
/** After a failed write (quota, 1 write/s per key, outage) this isolate stops writing for a while. */
export const KV_WRITE_PAUSE_MS = 10 * 60_000;
const DAY_MS = 86_400_000;

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
 * Cloudflare KV adapter (binding RDAP_KV, namespace shoo-rdap-cache). Key `rdap:<domain>`, value `{"registeredAt":...}`.
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

/**
 * Counts KV reads and writes in this isolate per UTC day, so a burst of new hosts cannot spend the account's daily
 * KV quota (and with it the public blocklist build). It is per isolate, not global: see D-imelda-40.
 * @param {{ readsPerDay?: number, writesPerDay?: number, now?: () => number }} [opts]
 */
export function createKvBudget({ readsPerDay = KV_READS_PER_DAY, writesPerDay = KV_WRITES_PER_DAY, now = Date.now } = {}) {
    let day = -1;
    let reads = 0;
    let writes = 0;
    let writesPausedUntil = 0;
    function roll() {
        const today = Math.floor(now() / DAY_MS);
        if (today !== day) {
            day = today;
            reads = 0;
            writes = 0;
        }
    }
    return {
        /** true = one read may be spent now */
        read() {
            roll();
            if (reads >= readsPerDay) return false;
            reads++;
            return true;
        },
        write() {
            roll();
            if (writes >= writesPerDay || now() < writesPausedUntil) return false;
            writes++;
            return true;
        },
        writeFailed() {
            writesPausedUntil = now() + KV_WRITE_PAUSE_MS;
        },
    };
}

/**
 * Memory first, then KV, for one request. A KV hit is copied into memory. Only a successful lookup is written to KV
 * (a failure stays 10 min in memory), in the background through `waitUntil`, so the answer never waits for a write.
 * A KV error or a read slower than `readTimeoutMs` is a miss; nothing here throws because of KV.
 * @param {{ memory: { get: Function, set: Function }, kv: { get: Function, set: Function }, budget: ReturnType<typeof createKvBudget>, waitUntil?: (p: Promise<unknown>) => void, readTimeoutMs?: number }} deps
 */
export function createTieredCache({ memory, kv, budget, waitUntil, readTimeoutMs = KV_READ_TIMEOUT_MS }) {
    return {
        async get(domain) {
            const hit = await memory.get(domain);
            if (hit || !budget.read()) return hit;
            let timer;
            const timeout = new Promise((resolve) => (timer = setTimeout(resolve, readTimeoutMs, null)));
            let value;
            try {
                value = await Promise.race([Promise.resolve().then(() => kv.get(domain)).catch(() => null), timeout]);
            } finally {
                clearTimeout(timer);
            }
            if (value) await memory.set(domain, value, value.registeredAt === null ? FAIL_TTL_MS : SUCCESS_TTL_MS);
            return value ?? null;
        },
        async set(domain, value, ttlMs) {
            await memory.set(domain, value, ttlMs);
            if (!validEntry(value) || value.registeredAt === null || !budget.write()) return;
            const write = Promise.resolve()
                .then(() => kv.set(domain, value, KV_SUCCESS_TTL_MS))
                .catch(() => budget.writeFailed());
            waitUntil?.(write);
        },
    };
}
