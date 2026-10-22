// A blocklist source is the only place that knows where phishing domains come from.
// Everything else (normalising, allowlist, paging) works on this shape, so changing the feed later
// (plan TODO A3, not decided yet) changes one file and nothing else.
//
// @typedef {{ host: string, addedAt: string, removedAt?: string }} RawEntry
//   host: a hostname or a URL as the feed gives it. addedAt/removedAt: ISO 8601.
// @typedef {{ name: string, license: string, entries(): Promise<RawEntry[]> }} BlocklistSource

/**
 * @param {{ name: string, license: string, entries: object[] }} spec
 * @returns {{ name: string, license: string, entries(): Promise<object[]> }}
 */
export function createStaticSource({ name, license, entries }) {
    return { name, license, entries: async () => entries };
}

/** What the deployed Worker uses until a feed is approved: an honest empty list, never invented domains. */
export const emptySource = createStaticSource({ name: "none", license: "n/a", entries: [] });
