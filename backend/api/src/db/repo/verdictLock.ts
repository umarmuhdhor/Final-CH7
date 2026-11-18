import type { Sql, TransactionSql } from "postgres";

/**
 * #476: a `safe` verdict cannot change until Shoo's weekly AI review has read it. The review is the
 * daily shoo-admin cron at 18:00 UTC that only acts on a Monday in WITA (shoo-dashboard
 * src/worker/cron/review.ts), so a safe verdict unlocks at the first Sunday 18:00 UTC strictly after
 * it was decided. Same rule as the app's VerdictLock.swift. A `not_safe` verdict is never locked:
 * blocking more is the safe side.
 *
 * Returns a SQL expression with the unlock time as ISO text (ms, Z), or null when the verdict is
 * `not_safe` or no longer locked. `value` and `decidedAt` are trusted column names, never input.
 */
export function lockedUntilSql(sql: Sql | TransactionSql, value: string, decidedAt: string) {
  // date_trunc('week') is the Monday 00:00 of that ISO week; Sunday 18:00 is 6 days 18 hours later.
  const t = sql.unsafe(`(${decidedAt} at time zone 'UTC')`);
  const unlock = sql`(date_trunc('week', ${t}) + case
      when date_trunc('week', ${t}) + interval '6 days 18 hours' > ${t} then interval '6 days 18 hours'
      else interval '13 days 18 hours' end)`;
  return sql`case when ${sql.unsafe(value)} = 'safe' and (now() at time zone 'UTC') < ${unlock}
    then to_char(${unlock}, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end`;
}

/** Drops `lockedUntil: null`, so the field is only there on a safe verdict that is still locked. */
export function withLock<T extends { lockedUntil?: string | null }>(row: T): T {
  if (row.lockedUntil == null) delete row.lockedUntil;
  return row;
}
