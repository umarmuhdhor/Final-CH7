import type { Sql, TransactionSql } from "postgres";

type Q = Sql | TransactionSql;

/**
 * storage_tombstones (D-alief-B12, SECURITY §3 P13): an intent log of every screenshot, favicon and
 * replica object, in Supabase Storage or R2 (the store follows from the path, storeKind).
 * Written in the transaction that reserves an upload (before the object can exist) and with the
 * rows' delete; dropped only after Storage confirmed a remove of a path no scan points at, and
 * only once it is older than 10 minutes (an upload, 5 s timeout, may still be landing). So a
 * failed remove or a late-landing upload is retried by the daily cron instead of left behind.
 */
export async function addTombstones(sql: Q, paths: string[], opts: { settled?: boolean } = {}): Promise<void> {
  if (paths.length === 0) return;
  // `settled`: no upload can still be landing (retention of 14-day-old rows), so the 10-minute
  // grace is skipped. An existing tombstone keeps its own age.
  const age = opts.settled ? sql`interval '1 hour'` : sql`interval '0'`;
  await sql`
    insert into storage_tombstones (path, created_at)
    select p, now() - ${age} from jsonb_array_elements_text(${sql.json(paths)}) as p
    on conflict (path) do nothing`;
}

/** After a confirmed remove. Young tombstones stay: their upload may land after the remove. */
export async function dropTombstones(sql: Q, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  await sql`delete from storage_tombstones where path in ${sql(paths)} and created_at < now() - interval '10 minutes'`;
}

/** A remove failed: try these later than the ones never tried (one bad batch cannot stall the rest). */
export async function markTombstonesTried(sql: Sql, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  await sql`update storage_tombstones set attempts = attempts + 1, last_try_at = now() where path in ${sql(paths)}`;
}

// Same rule as storeKind (services/screenshots.ts): replicas and new favicons live in R2.
const R2_PATH = String.raw`(t.path like '%-replica.html.gz' or t.path ~ '-icon\.[a-z]+$')`;

/**
 * What the cron may remove from one store: no scan points at the path (a live scan or a reuse keeps
 * its object; no new scan can start pointing at it, the reuse helpers pick originals of live scans
 * only) and older than 10 minutes. A replica tombstone is written at reservation, so without the
 * replica_path check the cron would remove a live replica 10 minutes after upload (K6).
 */
export async function dueTombstones(sql: Sql, limit: number, store: "supabase" | "r2" = "supabase"): Promise<string[]> {
  const rows = await sql<{ path: string }[]>`
    select t.path from storage_tombstones t
    where t.created_at < now() - interval '10 minutes'
      and ${sql.unsafe(store === "r2" ? R2_PATH : `not ${R2_PATH}`)}
      and not exists (
        select 1 from scans s where s.owner_id = split_part(t.path, '/', 1) and s.screenshot_path = t.path)
      and not exists (
        select 1 from scans s where s.owner_id = split_part(t.path, '/', 1) and s.favicon_path = t.path)
      and not exists (
        select 1 from scans s where s.owner_id = split_part(t.path, '/', 1) and s.replica_path = t.path)
    order by t.last_try_at nulls first, t.created_at, t.path
    limit ${limit}`;
  return rows.map((r) => r.path);
}
