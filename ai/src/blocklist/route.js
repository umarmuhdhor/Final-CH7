// GET /public-blocklist?since= (contracts/api.md, docs/design/blocklist.md). Read-only, stateless besides a short in-memory copy of the built list.
import { HttpError } from "../http.js";
import { buildList, pageSince } from "./build.js";

export const BLOCKLIST_LIMITS = Object.freeze({
    /** Served at most. Below the extension's 200,000 per source (lists.js MAX_ENTRIES), which skips every add once full. */
    MAX_DOMAINS: 190_000,
    /** Room the extension keeps for domains that arrive in deltas between two full downloads (24 h). */
    DELTA_HEADROOM: 10_000,
    /** Rebuild from the source at most this often. */
    REFRESH_MS: 5 * 60 * 1000,
    /** After a failed rebuild, do not ask the source again for this long. */
    RETRY_MS: 60 * 1000,
});

const SINCE_FORMAT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;

/** `since` must look like 2026-10-22T08:00:00Z (the nextSince we hand out); anything else is a client bug. */
export function parseSince(raw) {
    if (raw === undefined) return null;
    if (!SINCE_FORMAT.test(raw)) throw new HttpError(422, "invalid_body", "since must be an ISO 8601 timestamp.");
    const ms = Date.parse(raw);
    if (Number.isNaN(ms)) throw new HttpError(422, "invalid_body", "since must be an ISO 8601 timestamp.");
    return new Date(ms).toISOString();
}

/** @param {{ source: import("./source.js").BlocklistSource, now: () => number }} deps */
export function createBlocklist({ source, now }) {
    let built = null; // { at, list }
    let failedAt = -Infinity;
    let building = null;
    async function current() {
        if (built && now() - built.at < BLOCKLIST_LIMITS.REFRESH_MS) return built.list;
        if (now() - failedAt < BLOCKLIST_LIMITS.RETRY_MS) {
            if (built) return built.list;
            throw new HttpError(500, "internal", "Something went wrong.");
        }
        building ??= source
            .entries()
            .then((raw) => {
                built = { at: now(), list: buildList(raw, { maxDomains: BLOCKLIST_LIMITS.MAX_DOMAINS, now: now() }) };
                return built.list;
            })
            .finally(() => {
                building = null;
            });
        try {
            return await building;
        } catch {
            failedAt = now();
            if (built) return built.list; // keep serving the last good copy
            throw new HttpError(500, "internal", "Something went wrong.");
        }
    }
    return async (sinceRaw) => pageSince(await current(), parseSince(sinceRaw));
}
