// GET /public-blocklist from the pre-built list in Workers KV (prebuilt.js). The Worker only picks a key and streams
// the stored JSON back: about 1 ms CPU, whatever the list size. Used when the BLOCKLIST_KV binding exists.
import { HttpError } from "../http.js";
import { PREBUILT, deltaKey } from "./prebuilt.js";
import { parseSince } from "./route.js";

const fail = () => new HttpError(500, "internal", "Something went wrong.");

/** @param {{ now: () => number }} deps @returns {(kv: object, sinceRaw?: string) => Promise<{ json: object } | { stream: ReadableStream }>} */
export function createKvBlocklist({ now }) {
    let cached = null; // { at, meta }
    async function readMeta(kv) {
        if (cached && now() - cached.at < PREBUILT.META_CACHE_MS) return cached.meta;
        const meta = await kv.get(PREBUILT.META_KEY, "json");
        const builds = Array.isArray(meta?.builds) ? meta.builds.filter((b) => typeof b === "string") : [];
        const value = builds.length ? { builds } : null;
        cached = { at: now(), meta: value };
        return value;
    }
    return async (kv, sinceRaw) => {
        const since = parseSince(sinceRaw);
        let meta;
        try {
            meta = await readMeta(kv);
        } catch {
            throw fail();
        }
        if (!meta) return { json: { domains: [], nextSince: since } }; // nothing built yet: honest empty list
        if (since && since >= meta.builds[0]) return { json: { domains: [], nextSince: since } };
        const base = since ? meta.builds.find((b) => b <= since) : undefined; // builds are newest first
        try {
            const stream = (base && (await kv.get(deltaKey(base), "stream"))) || (await kv.get(PREBUILT.FULL_KEY, "stream"));
            if (!stream) throw fail();
            return { stream };
        } catch {
            throw fail();
        }
    };
}
