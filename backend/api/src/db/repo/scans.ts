import type { Sql, TransactionSql } from "postgres";
import { addTombstones } from "./tombstones";

export interface NewScan {
  ownerId: string;
  url: string;
  domain: string;
  pageTitle: string | null;
  faviconUrl: string | null;
  score: number;
  status: "warning" | "blocked";
  signals: unknown[];
  detectedAt: string;
}

export async function insertScan(sql: Sql, s: NewScan): Promise<string> {
  const [row] = await sql<{ id: string }[]>`
    insert into scans (owner_id, url, domain, page_title, favicon_url, score, status, signals, detected_at)
    values (${s.ownerId}, ${s.url}, ${s.domain}, ${s.pageTitle}, ${s.faviconUrl}, ${s.score}, ${s.status},
            ${sql.json(s.signals as never)}, ${s.detectedAt}::text::timestamptz)
    returning id`;
  return row!.id;
}

export type ScreenshotSlot = { reuse: string } | { upload: string } | { quota: "owner" | "global" } | { gone: true };

/**
 * Picks the screenshot for a new scan in one transaction, locked per owner so parallel scans
 * cannot overrun the quota (R3 §4): reuse the owner's screenshot of this domain from the last
 * 24 h (dedupe), else reserve `path` when fewer than `quota.owner` were stored in 24 h by this
 * owner and fewer than `quota.global` by everyone (D-alief-B12; not locked across owners, so
 * parallel scans may overshoot the global count by a few).
 * The path is written and tombstoned before the upload (D-alief-B12); clearScreenshotPath undoes
 * the path on failure.
 */
export async function reserveScreenshot(
  sql: Sql,
  scan: { id: string; ownerId: string; domain: string },
  path: string,
  quota: { owner: number; global: number },
): Promise<ScreenshotSlot> {
  return sql.begin(async (tx): Promise<ScreenshotSlot> => {
    await tx`select pg_advisory_xact_lock(3, hashtext(${scan.ownerId}))`;
    const reuse = await recentScreenshot(tx, scan.ownerId, scan.domain);
    const chosen = reuse ?? path;
    if (!reuse) {
      if ((await screenshotsToday(tx, scan.ownerId)) >= quota.owner) return { quota: "owner" };
      if ((await allScreenshotsToday(tx)) >= quota.global) return { quota: "global" };
    }
    // Zero rows: the scan was deleted meanwhile (DELETE /devices/me), so nothing is uploaded.
    const updated = await tx`update scans set screenshot_path = ${chosen} where id = ${scan.id} returning id`;
    if (updated.length === 0) return { gone: true };
    if (reuse) return { reuse };
    await addTombstones(tx, [path]);
    return { upload: path };
  });
}

/** Clears the path on every scan of the owner that points at it: dedupe may have reused it meanwhile. */
export async function clearScreenshotPath(sql: Sql, ownerId: string, path: string): Promise<void> {
  await sql`update scans set screenshot_path = null where owner_id = ${ownerId} and screenshot_path = ${path}`;
}

/** False once the scan row is gone (e.g. DELETE /devices/me ran during the upload). */
export async function scanExists(sql: Sql, id: string): Promise<boolean> {
  const rows = await sql`select 1 from scans where id = ${id}`;
  return rows.length > 0;
}

type Q = Sql | TransactionSql;

// Original uploads only: the path names the scan's own id. Must match the predicate of index
// scans_original_shot verbatim (migration 20261022130000) for the planner to use it.
const ORIGINAL = "(screenshot_path = owner_id || '/' || id || '.jpg' or screenshot_path = owner_id || '/' || id || '.png')";

/**
 * Dedupe (R3 §4): a screenshot of the same owner + domain from the last 24 h. Only the scan that
 * uploaded it counts (its path names its own id), so reuse never chains past that scan's age and
 * an object is gone at most 15 days after upload (D-alief-B12, privacy page).
 */
export async function recentScreenshot(sql: Q, ownerId: string, domain: string): Promise<string | undefined> {
  const [row] = await sql<{ path: string }[]>`
    select screenshot_path as path from scans
    where owner_id = ${ownerId} and domain = ${domain} and screenshot_path is not null
      and ${sql.unsafe(ORIGINAL)}
      and created_at > now() - interval '24 hours'
    order by created_at desc limit 1`;
  return row?.path;
}

/** Quota (R3 §4): screenshots this owner uploaded in the last 24 h (reuses are not new objects). */
export async function screenshotsToday(sql: Q, ownerId: string): Promise<number> {
  const [row] = await sql<{ n: number }[]>`
    select count(*)::int as n from scans
    where owner_id = ${ownerId} and created_at > now() - interval '24 hours' and ${sql.unsafe(ORIGINAL)}`;
  return row!.n;
}

/** Global quota: screenshots everyone uploaded in the last 24 h (index-only on scans_original_shot). */
export async function allScreenshotsToday(sql: Q): Promise<number> {
  const [row] = await sql<{ n: number }[]>`
    select count(*)::int as n from scans
    where created_at > now() - interval '24 hours' and ${sql.unsafe(ORIGINAL)}`;
  return row!.n;
}

export interface ScanRow {
  id: string;
  ownerId: string;
  ownerName: string;
  url: string;
  domain: string;
  pageTitle: string | null;
  faviconUrl: string | null;
  score: number;
  status: "warning" | "blocked";
  signals: unknown[];
  screenshotPath: string | null;
  detectedAt: string;
  /** detected_at with microseconds, for the cursor. */
  cursorAt: string;
  verdict: { value: "safe" | "not_safe"; byDeviceId: string; byName: string; decidedAt: string } | null;
}

export const ISO_MS = `'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'`;

// Columns shared by list and detail. ownerName is the owner's current name; the verdict
// (per owner + domain) is joined only for blocked scans (schema: warnings keep null).
function selectScans(sql: Sql) {
  return sql`
    select s.id, s.owner_id as "ownerId", d.name as "ownerName", s.url, s.domain,
           s.page_title as "pageTitle", s.favicon_url as "faviconUrl", s.score, s.status, s.signals,
           s.screenshot_path as "screenshotPath",
           to_char(s.detected_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}) as "detectedAt",
           to_char(s.detected_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as "cursorAt",
           case when s.status = 'blocked' and v.owner_id is not null then json_build_object(
             'value', v.value, 'byDeviceId', v.by_device_id, 'byName', v.by_name,
             'decidedAt', to_char(v.decided_at at time zone 'UTC', ${sql.unsafe(ISO_MS)})
           ) end as verdict
    from scans s
    join devices d on d.id = s.owner_id
    left join verdicts v on v.owner_id = s.owner_id and v.domain = s.domain`;
}

export interface ListQuery {
  owners: string[];
  status: "warning" | "blocked" | null;
  cursor: { at: string; id: string } | null;
  limit: number;
}

/** Newest first, keyset paging on (detected_at, id). Returns up to limit + 1 rows. */
export async function listScans(sql: Sql, q: ListQuery): Promise<ScanRow[]> {
  return sql<ScanRow[]>`
    ${selectScans(sql)}
    where s.owner_id in ${sql(q.owners)}
      ${q.status ? sql`and s.status = ${q.status}` : sql``}
      ${q.cursor ? sql`and (s.detected_at, s.id) < (${q.cursor.at}::text::timestamptz, ${q.cursor.id})` : sql``}
    order by s.detected_at desc, s.id desc
    limit ${q.limit + 1}`;
}

/** A scan the viewer may see: their own, or a member's while the family link exists (T1, T12). */
export async function findVisibleScan(sql: Sql, id: string, viewerId: string): Promise<ScanRow | undefined> {
  const [row] = await sql<ScanRow[]>`
    ${selectScans(sql)}
    where s.id = ${id}
      and (s.owner_id = ${viewerId}
           or exists (select 1 from family_links l where l.protected_id = s.owner_id and l.guardian_id = ${viewerId}))`;
  return row;
}

export async function memberIds(sql: Sql, guardianId: string): Promise<string[]> {
  const rows = await sql<{ id: string }[]>`select protected_id as id from family_links where guardian_id = ${guardianId}`;
  return rows.map((r) => r.id);
}

/** The screenshot path while the viewer owns the scan or is the owner's current guardian (D-alief-B08). */
export async function screenshotPathForViewer(sql: Sql, id: string, viewerId: string): Promise<string | undefined> {
  const [row] = await sql<{ path: string }[]>`
    select s.screenshot_path as path from scans s
    where s.id = ${id} and s.screenshot_path is not null
      and (s.owner_id = ${viewerId}
           or exists (select 1 from family_links l where l.protected_id = s.owner_id and l.guardian_id = ${viewerId}))`;
  return row?.path;
}
