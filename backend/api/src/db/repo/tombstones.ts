import type { Sql, TransactionSql } from "postgres";

type Q = Sql | TransactionSql;

/**
 * storage_tombstones (D-alief-B12, SECURITY §3 P13): screenshot objects still to remove from
 * Storage. Written before or with the rows' delete, dropped only after Storage confirmed, so a
 * failed remove is retried by the daily cron instead of leaving an object behind.
 */
export async function addTombstones(sql: Q, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  await sql`insert into storage_tombstones ${sql(paths.map((path) => ({ path })))} on conflict (path) do nothing`;
}

export async function dropTombstones(sql: Q, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  await sql`delete from storage_tombstones where path in ${sql(paths)}`;
}

export async function oldestTombstones(sql: Sql, limit: number): Promise<string[]> {
  const rows = await sql<{ path: string }[]>`select path from storage_tombstones order by created_at, path limit ${limit}`;
  return rows.map((r) => r.path);
}
