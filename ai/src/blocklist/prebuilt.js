// The pre-built /public-blocklist (D-imelda-38). Building 200,000 entries takes ~1 s CPU, far over the Workers Free
// limit of 10 ms, so a GitHub Action builds every answer the Worker can give and stores them in Workers KV:
//   meta          { v, builtAt, builds: [newest ... oldest], source, license, active, removed }
//   full          the answer without `since`
//   delta:<build> the answer for since=<build>, one per build of the last RETENTION_MS
//   state         gzipped entries of the last build (first-seen dates), read only by the next build
// Every addedAt/removedAt is a build time (phishing-database.js), so every nextSince a client holds is a build time:
// the answer for any `since` is the delta of the newest build <= since (blocklist/kv.js). No parsing in the Worker.
import { buildList, pageSince } from "./build.js";
import { BLOCKLIST_LIMITS } from "./route.js";

const DAY_MS = 24 * 60 * 60 * 1000;

export const PREBUILT = Object.freeze({
    META_KEY: "meta",
    FULL_KEY: "full",
    STATE_KEY: "state",
    /** Deltas are kept for builds this recent. The extension downloads the full list daily, so 7 days is generous. */
    RETENTION_MS: 7 * DAY_MS,
    /** A delta outlives the meta that points at it, so a Worker with a cached meta never misses one. */
    DELTA_TTL_SEC: 8 * 24 * 60 * 60,
    /** Removed domains stay in the state (and in deltas) this long, then they are forgotten. */
    KEEP_REMOVED_MS: 8 * DAY_MS,
    /** Hard cap on builds listed in meta (every 6 h for 7 days = 28). */
    MAX_BUILDS: 40,
    /** The Worker re-reads meta at most this often per isolate. */
    META_CACHE_MS: 5 * 60 * 1000,
    /** A build whose list shrinks by more than this share is refused (broken feed, not a good day). */
    MAX_DROP: 0.5,
});

export const deltaKey = (since) => `delta:${since}`;

/**
 * @param {{ entries: object[], builtAt: string, previousMeta: { builds?: string[] } | null, source: { name: string, license: string } }} input
 * @returns {{ full: object, deltas: { since: string, body: object }[], meta: object }}
 */
export function buildArtifacts({ entries, builtAt, previousMeta, source }) {
    const builtMs = Date.parse(builtAt);
    const list = buildList(entries, { maxDomains: BLOCKLIST_LIMITS.MAX_DOMAINS, now: builtMs });
    const earlier = (Array.isArray(previousMeta?.builds) ? previousMeta.builds : [])
        .filter((b) => typeof b === "string" && !Number.isNaN(Date.parse(b)) && b < builtAt && builtMs - Date.parse(b) <= PREBUILT.RETENTION_MS)
        .sort()
        .reverse()
        .slice(0, PREBUILT.MAX_BUILDS - 1);
    return {
        full: pageSince(list, null),
        deltas: earlier.map((since) => ({ since, body: pageSince(list, since) })),
        meta: { v: 1, builtAt, builds: [builtAt, ...earlier], source: source.name, license: source.license, active: list.active.length, removed: list.removed.length },
    };
}
