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
 * Approvals use clock_timestamp(), one domain per statement, so times are unique
 * and paging by time never skips a domain.
 */
export async function blocklistEvents(sql: Sql, since: string | null): Promise<BlocklistEvent[]> {
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
