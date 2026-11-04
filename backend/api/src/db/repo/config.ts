import type { Sql } from "postgres";

/** Score thresholds the extension applies (dashboard phase 05, W12). */
export interface PublicThresholds {
  warnAt: number;
  blockAt: number;
  version: number;
  /** ISO 8601 UTC with microseconds. */
  updatedAt: string;
}

/**
 * admin.public_config (dashboard phase 04a): the thresholds the admins set, or the built-in 30/80
 * with version 0 until thresholds_live is switched on (I12). shoo_api may read this one view in
 * schema admin and nothing else there (I2).
 */
export async function publicThresholds(sql: Sql): Promise<PublicThresholds> {
  const [r] = await sql<{ warn_at: number; block_at: number; version: number; updated_at: string }[]>`
    select warn_at, block_at, version,
           to_char(updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as updated_at
    from admin.public_config`;
  if (!r) throw new Error("admin.public_config is empty");
  return { warnAt: r.warn_at, blockAt: r.block_at, version: r.version, updatedAt: r.updated_at };
}
