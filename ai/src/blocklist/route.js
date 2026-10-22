// GET /public-blocklist?since= (contracts/api.md, docs/design/blocklist.md). Read-only, stateless besides a short in-memory copy of the built list.
import { HttpError } from "../http.js";
import { buildList, pageSince } from "./build.js";

export const BLOCKLIST_LIMITS = Object.freeze({
    /** The extension keeps at most this many per source. */
    MAX_DOMAINS: 200_000,
    /** Rebuild from the source at most this often. */
    REFRESH_MS: 5 * 60 * 1000,
});

/** `since` must look like 2026-10-22T08:00:00Z (the nextSince we hand out); anything else is a client bug. */
export function parseSince(raw) {
    if (raw === undefined) return null;
    if (raw.length < 10 || raw.length > 40 || raw[4] !== "-" || raw[7] !== "-") throw new HttpError(400, "invalid_query", "since must be an ISO 8601 timestamp.");
    const ms = Date.parse(raw);
    if (Number.isNaN(ms)) throw new HttpError(400, "invalid_query", "since must be an ISO 8601 timestamp.");
    return new Date(ms).toISOString();
}

/** @param {{ source: import("./source.js").BlocklistSource, now: () => number }} deps */
export function createBlocklist({ source, now }) {
    let built = null; // { at, list }
    let building = null;
    async function current() {
        if (built && now() - built.at < BLOCKLIST_LIMITS.REFRESH_MS) return built.list;
        building ??= source
            .entries()
            .then((raw) => {
                built = { at: now(), list: buildList(raw, { maxDomains: BLOCKLIST_LIMITS.MAX_DOMAINS }) };
                return built.list;
            })
            .finally(() => {
                building = null;
            });
        try {
            return await building;
        } catch {
            if (built) return built.list; // keep serving the last good copy
            throw new HttpError(500, "internal", "Something went wrong.");
        }
    }
    return async (sinceRaw) => pageSince(await current(), parseSince(sinceRaw));
}
