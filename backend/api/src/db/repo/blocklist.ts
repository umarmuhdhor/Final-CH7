import type { Sql } from "postgres";

export interface BlocklistEvent {
  domain: string;
  kind: "added" | "removed";
  /** ISO 8601 UTC with microseconds, so the cursor is exact. */
  at: string;
}

export const BLOCKLIST_PAGE = 1000;

/**
 * Approved entries (and, with `since`, removals) ordered by event time (R2 §5).
 * The cursor is a time and the next page uses `> since`, so a full page is
 * extended with every event that shares its last time: a page never ends in the
 * middle of a tie (e.g. a bulk manual approval).
 */
export async function blocklistEvents(sql: Sql, since: string | null): Promise<BlocklistEvent[]> {
  const page = await eventsAfter(sql, since);
  if (page.length < BLOCKLIST_PAGE) return page;
  const last = page.at(-1)!;
  const ties = await sql<BlocklistEvent[]>`
    select domain, kind, to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as at from (
      select domain, 'added' as kind, approved_at as t
      from blocklist_entries
      where approved_at is not null and removed_at is null
      union all
      select domain, 'removed' as kind, removed_at as t
      from blocklist_entries
      where ${since !== null} and approved_at is not null and removed_at is not null
    ) e
    where t = ${last.at}::text::timestamptz and domain > ${last.domain}
    order by domain`;
  return [...page, ...ties];
}

async function eventsAfter(sql: Sql, since: string | null): Promise<BlocklistEvent[]> {
  if (since === null) {
    return sql<BlocklistEvent[]>`
      select domain, 'added' as kind, to_char(approved_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as at
      from blocklist_entries
      where approved_at is not null and removed_at is null
      order by approved_at, domain
      limit ${BLOCKLIST_PAGE}`;
  }
  return sql<BlocklistEvent[]>`
    select domain, kind, to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as at from (
      select domain, 'added' as kind, approved_at as t
      from blocklist_entries
      where approved_at is not null and removed_at is null and approved_at > ${since}::text::timestamptz
      union all
      select domain, 'removed' as kind, removed_at as t
      from blocklist_entries
      where approved_at is not null and removed_at is not null and removed_at > ${since}::text::timestamptz
    ) e
    order by t, domain
    limit ${BLOCKLIST_PAGE}`;
}
