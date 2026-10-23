// Builds the pre-built /public-blocklist and writes it to Workers KV (D-imelda-38, src/blocklist/prebuilt.js).
// Run by .github/workflows/public-blocklist.yml every 6 h; never by the Worker. Plain Node, no npm install needed.
//
//   BLOCKLIST_CF_API_TOKEN=… BLOCKLIST_CF_ACCOUNT_ID=… BLOCKLIST_KV_NAMESPACE_ID=… node ai/scripts/build-blocklist.mjs
//   node ai/scripts/build-blocklist.mjs --out /tmp/blocklist   (no KV: writes the files to a folder, starts from an empty state)
//
// Prints counts only. The token is never printed; a failed Cloudflare call reports its HTTP status, not its body.
import { gzipSync, gunzipSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { createPhishingDatabaseSource } from "../src/blocklist/phishing-database.js";
import { PREBUILT, buildArtifacts, deltaKey } from "../src/blocklist/prebuilt.js";

/** Larger than any real feed (~11 MB today); a bigger answer is refused instead of filling memory. */
const MAX_FEED_BYTES = 64 * 1024 * 1024;
const FEED_TIMEOUT_MS = 60_000;
/** Cloudflare's bulk write takes at most 100 MB and 10,000 keys per request. */
const MAX_BATCH_BYTES = 90 * 1024 * 1024;
const MAX_BATCH_KEYS = 10_000;

const decode = (bytes) => new TextDecoder().decode(bytes);

/**
 * @param {{ kv: { get(key: string): Promise<Uint8Array | null>, putMany(items: { key: string, value: string | Uint8Array, expirationTtl?: number }[]): Promise<void> },
 *           fetchText: (url: string) => Promise<string>, now?: () => number, minHosts?: number }} deps
 * @returns {Promise<object>} the meta that was written
 */
export async function runBuild({ kv, fetchText, now = Date.now, minHosts }) {
    const builtAt = new Date(Math.floor(now() / 1000) * 1000).toISOString();
    const [metaBytes, stateBytes] = await Promise.all([kv.get(PREBUILT.META_KEY), kv.get(PREBUILT.STATE_KEY)]);
    const previousMeta = metaBytes ? JSON.parse(decode(metaBytes)) : null;
    const previous = stateBytes ? JSON.parse(decode(gunzipSync(stateBytes))) : [];
    if (!Array.isArray(previous)) throw new Error("stored state is not a list");
    const source = createPhishingDatabaseSource({ fetchText, previous, builtAt, minHosts });
    const entries = await source.entries();
    const { full, deltas, meta } = buildArtifacts({ entries, builtAt, previousMeta, source });
    const before = Number(previousMeta?.active) || 0;
    if (before && meta.active < before * (1 - PREBUILT.MAX_DROP)) {
        throw new Error(`list would drop from ${before} to ${meta.active} domains; refusing to publish (check the feed)`);
    }
    await kv.putMany([
        { key: PREBUILT.STATE_KEY, value: gzipSync(JSON.stringify(entries)) },
        { key: PREBUILT.FULL_KEY, value: JSON.stringify(full) },
        ...deltas.map((d) => ({ key: deltaKey(d.since), value: JSON.stringify(d.body), expirationTtl: PREBUILT.DELTA_TTL_SEC })),
    ]);
    // Last: the Worker only starts using this build once everything it points at is stored.
    await kv.putMany([{ key: PREBUILT.META_KEY, value: JSON.stringify(meta) }]);
    return meta;
}

/** Workers KV over the Cloudflare REST API (token needs "Workers KV Storage: Edit" on this account only). */
export function createKvRest({ accountId, namespaceId, token, fetch: http = fetch }) {
    const base = `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountId)}/storage/kv/namespaces/${encodeURIComponent(namespaceId)}`;
    const auth = { authorization: `Bearer ${token}` };
    async function putBatch(batch) {
        const res = await http(`${base}/bulk`, { method: "PUT", headers: { ...auth, "content-type": "application/json" }, body: JSON.stringify(batch) });
        if (!res.ok) throw new Error(`KV bulk write failed: HTTP ${res.status}`);
        const body = await res.json().catch(() => null);
        const failed = body?.result?.unsuccessful_keys ?? [];
        if (body?.success === false || failed.length) throw new Error(`KV bulk write failed for keys: ${failed.join(", ") || "unknown"}`);
    }
    return {
        async get(key) {
            const res = await http(`${base}/values/${encodeURIComponent(key)}`, { headers: auth });
            if (res.status === 404) return null;
            if (!res.ok) throw new Error(`KV read of ${key} failed: HTTP ${res.status}`);
            return new Uint8Array(await res.arrayBuffer());
        },
        async putMany(items) {
            let batch = [];
            let bytes = 0;
            for (const { key, value, expirationTtl } of items) {
                const item = typeof value === "string" ? { key, value } : { key, value: Buffer.from(value).toString("base64"), base64: true };
                if (expirationTtl) item.expiration_ttl = expirationTtl;
                const size = item.value.length + key.length + 64;
                if (batch.length && (bytes + size > MAX_BATCH_BYTES || batch.length >= MAX_BATCH_KEYS)) {
                    await putBatch(batch);
                    batch = [];
                    bytes = 0;
                }
                batch.push(item);
                bytes += size;
            }
            if (batch.length) await putBatch(batch);
        },
    };
}

/** GET with a timeout and a size cap; anything but 200 is an error. */
export async function fetchFeed(url, { fetch: http = fetch } = {}) {
    const res = await http(url, { redirect: "follow", signal: AbortSignal.timeout(FEED_TIMEOUT_MS) });
    if (!res.ok) throw new Error(`feed download failed: HTTP ${res.status}`);
    const chunks = [];
    let size = 0;
    for await (const chunk of res.body) {
        size += chunk.length;
        if (size > MAX_FEED_BYTES) throw new Error(`feed larger than ${MAX_FEED_BYTES} bytes`);
        chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString("utf8");
}

/** A folder instead of KV, for a local dry run (`--out`). */
function createFolderKv(dir) {
    mkdirSync(dir, { recursive: true });
    return {
        async get() {
            return null;
        },
        async putMany(items) {
            for (const { key, value } of items) writeFileSync(join(dir, `${key.replaceAll(":", "_")}${key === PREBUILT.STATE_KEY ? ".json.gz" : ".json"}`), value);
        },
    };
}

async function main(argv) {
    const outAt = argv.indexOf("--out");
    let kv;
    if (outAt !== -1) {
        if (!argv[outAt + 1]) throw new Error("--out needs a folder");
        kv = createFolderKv(argv[outAt + 1]);
    } else {
        const env = { token: "BLOCKLIST_CF_API_TOKEN", accountId: "BLOCKLIST_CF_ACCOUNT_ID", namespaceId: "BLOCKLIST_KV_NAMESPACE_ID" };
        const missing = Object.values(env).filter((name) => !process.env[name]);
        if (missing.length) throw new Error(`missing environment variable(s): ${missing.join(", ")}`);
        kv = createKvRest(Object.fromEntries(Object.entries(env).map(([k, name]) => [k, process.env[name]])));
    }
    const meta = await runBuild({ kv, fetchText: (url) => fetchFeed(url) });
    console.log(`public blocklist built at ${meta.builtAt}: ${meta.active} domains, ${meta.removed} removed, ${meta.builds.length - 1} delta(s)`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
    main(process.argv.slice(2)).catch((err) => {
        console.error(`public blocklist build failed: ${err.message}`);
        process.exitCode = 1;
    });
}
