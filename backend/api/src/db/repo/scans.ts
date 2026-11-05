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
  /** Thresholds version the extension used (dashboard phase 05); null for older extensions. */
  thresholdsVersion: number | null;
  /** RDAP registration date `YYYY-MM-DD` (#270); null when unknown. */
  rdapRegisteredAt: string | null;
}

/**
 * One Activity row per site: when the owner still has a scan of this domain, that row is kept
 * (`created: false`) instead of a new one. Its time moves to the newest visit, and a higher score
 * replaces url, title, score, status and signals; its evidence stays. Locked per owner + domain, so
 * two parallel scans of one site cannot both insert. Every scan still counts in the owner's
 * lifetime totals (profile stats, PF-01). `escalated`: this visit moved the kept row from warning to
 * blocked, which the guardian has to hear about.
 */
export async function recordScan(sql: Sql, s: NewScan): Promise<{ id: string; created: boolean; escalated: boolean }> {
  return sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(7, hashtext(${`${s.ownerId}|${s.domain}`}))`;
    const [kept] = await tx<{ id: string; escalated: boolean }[]>`
      with previous as (
        select id, status from scans where owner_id = ${s.ownerId} and domain = ${s.domain}
        order by created_at desc, id desc limit 1
      ), kept as (
        update scans set
          detected_at = greatest(detected_at, ${s.detectedAt}::text::timestamptz),
          rdap_registered_at = coalesce(rdap_registered_at, ${s.rdapRegisteredAt}::date),
          url = case when ${s.score} > score then ${s.url} else url end,
          page_title = case when ${s.score} > score then ${s.pageTitle} else page_title end,
          signals = case when ${s.score} > score then ${tx.json(s.signals as never)} else signals end,
          status = case when ${s.score} > score then ${s.status} else status end,
          score = greatest(score, ${s.score})
        where id = (select id from previous)
        returning id, status
      ), counted as (
        update devices d set
          blocked_total = d.blocked_total + (${s.status} = 'blocked')::int,
          warning_total = d.warning_total + (${s.status} = 'warning')::int
        where d.id = ${s.ownerId} and exists (select 1 from kept)
      )
      select kept.id, previous.status = 'warning' and kept.status = 'blocked' as escalated
      from kept join previous using (id)`;
    if (kept) return { id: kept.id, created: false, escalated: kept.escalated };
    return { id: await insertScan(tx, s), created: true, escalated: false };
  });
}

/** Also counts the scan in the owner's lifetime totals (profile stats, PF-01), in the same statement. */
async function insertScan(sql: Sql | TransactionSql, s: NewScan): Promise<string> {
  const [row] = await sql<{ id: string }[]>`
    with ins as (
      insert into scans (owner_id, url, domain, page_title, favicon_url, score, status, signals, detected_at, thresholds_version,
                         rdap_registered_at)
      values (${s.ownerId}, ${s.url}, ${s.domain}, ${s.pageTitle}, ${s.faviconUrl}, ${s.score}, ${s.status},
              ${sql.json(s.signals as never)}, ${s.detectedAt}::text::timestamptz, ${s.thresholdsVersion},
              ${s.rdapRegisteredAt}::date)
      returning id, owner_id, status
    ), counted as (
      update devices d set
        blocked_total = d.blocked_total + (ins.status = 'blocked')::int,
        warning_total = d.warning_total + (ins.status = 'warning')::int
      from ins where d.id = ins.owner_id
    )
    select id from ins`;
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

export type FaviconSlot = { reuse: string } | { upload: string } | { gone: true } | { none: true };

// Original favicon uploads only: the path names the scan's own id (like ORIGINAL for screenshots).
// `-favicon.` = Supabase (before 18a), `-icon.` = R2 (D-alief-C27); both until the old ones expire.
const ORIGINAL_FAVICON =
  "(starts_with(favicon_path, owner_id || '/' || id || '-favicon.') or starts_with(favicon_path, owner_id || '/' || id || '-icon.'))";

/**
 * PR-05, like reserveScreenshot: in one transaction locked per owner, point the scan at the owner's
 * favicon of this domain from the last 24 h (reuse), else, when `path` is given, reserve it. The path
 * is written and tombstoned before the upload (D-alief-B12); clearFaviconPath undoes it on failure.
 * `path` null only looks for a reuse ({ none } when there is nothing to reuse).
 */
export async function reserveFavicon(
  sql: Sql,
  scan: { id: string; ownerId: string; domain: string },
  path: string | null,
): Promise<FaviconSlot> {
  return sql.begin(async (tx): Promise<FaviconSlot> => {
    await tx`select pg_advisory_xact_lock(4, hashtext(${scan.ownerId}))`;
    const reuse = await recentFavicon(tx, scan.ownerId, scan.domain);
    const chosen = reuse ?? path;
    if (!chosen) return { none: true };
    // Zero rows: the scan was deleted meanwhile (DELETE /devices/me), so nothing is uploaded.
    const updated = await tx`update scans set favicon_path = ${chosen} where id = ${scan.id} returning id`;
    if (updated.length === 0) return { gone: true };
    if (reuse) return { reuse };
    await addTombstones(tx, [chosen]);
    return { upload: chosen };
  });
}

/** Clears the path on every scan of the owner that points at it: a reuse may have picked it up meanwhile. */
export async function clearFaviconPath(sql: Sql, ownerId: string, path: string): Promise<void> {
  await sql`update scans set favicon_path = null where owner_id = ${ownerId} and favicon_path = ${path}`;
}

/**
 * Reuse: a favicon of the same owner + domain from the last 24 h. Only the scan that uploaded it
 * counts, so an object is gone at most 15 days after upload, as for screenshots.
 */
export async function recentFavicon(sql: Q, ownerId: string, domain: string): Promise<string | undefined> {
  const [row] = await sql<{ path: string }[]>`
    select favicon_path as path from scans
    where owner_id = ${ownerId} and domain = ${domain} and favicon_path is not null
      and ${sql.unsafe(ORIGINAL_FAVICON)}
      and created_at > now() - interval '24 hours'
    order by created_at desc limit 1`;
  return row?.path;
}

export type ReplicaQuotaReason = "owner" | "family" | "family_bytes" | "global" | "global_bytes" | "reserve";

export type ReplicaSlot =
  | { reuse: string }
  | { upload: string }
  | { quota: ReplicaQuotaReason }
  | { gone: true }
  | { none: true };

export interface ReplicaQuota {
  /** Uploads per owner per 24 h. */
  owner: number;
  /** Uploads per family (Guardian + members, fase 19 C1) per 24 h. */
  family: number;
  /** sum(replica_bytes) per family per 24 h. */
  familyBytes: number;
  /** Uploads by everyone per 24 h. */
  global: number;
  /** sum(replica_bytes) of everyone's uploads per 24 h. */
  globalBytes: number;
  /** The last part of `global` / `globalBytes`, kept for light families (fase 19 K3). */
  reserveUploads: number;
  reserveBytes: number;
  /** A family with fewer uploads than this in 24 h is light. */
  lightFamily: number;
}

/**
 * EX-07 pre-check before the IP limit and the inflate (cheap first, K5): the owner's replica of this
 * domain from the last 24 h to reuse. A device without a family link keeps its replicas too: Detail
 * shows the owner the evidence in Personal mode (5 Nov 2026; was dropped as no_family), and its quota
 * family is the device itself (replicaCountsQuery).
 * Fase 22 K12 (D-alief-B15): in the same statement, the quota counts of reserveReplica; when a quota
 * is already full for an upload of `bytes`, `quota` names it, so the caller drops the replica before
 * it spends an IP slot or inflate CPU. Not under any lock: reserveReplica under (6, 0) stays the final
 * word, so a race costs at most one inflate, as before.
 * Not under the owner lock: family_links changes under other locks (families.ts), so a pairing at
 * the same moment may keep or drop one replica.
 */
export async function precheckReplica(
  sql: Sql,
  scan: { ownerId: string; domain: string },
  bytes: number,
  quota: ReplicaQuota,
): Promise<{ reuse: string | undefined; quota: ReplicaQuotaReason | undefined }> {
  const [row] = await sql<({ reuse: string | null } & ReplicaCounts)[]>`
    select (${recentReplicaQuery(sql, scan.ownerId, scan.domain)}) as reuse, c.*
    from (${replicaCountsQuery(sql, scan.ownerId)}) c`;
  // An aggregate without group by: always exactly one row. The counts also run for a reuse, where
  // they are not used: one index-only pass, cheaper than a second trip.
  const r = row!;
  const reuse = r.reuse ?? undefined;
  return { reuse, quota: reuse ? undefined : quotaFull(r, bytes, quota) };
}

/**
 * Like reserveScreenshot, for replicas (D-alief-C25/C26): in one transaction locked per owner (advisory
 * class 6; 3–5 are taken), reuse the owner's replica of this domain from the last 24 h, else reserve
 * `upload.path` if every quota of the last 24 h has room (original rows only, index scans_original_replica).
 * Fase 19 (D-alief-B14): the counts for owner, family and everyone are one statement under the global
 * key (6, 0). Every new upload takes that key, so uploads by different members of one family cannot
 * overshoot the family quota either (a pairing or unpairing at the same moment does not take the key,
 * so the family may still change by one member in between); held for milliseconds, the R2 put runs
 * after commit. Order of the checks (fase 19 K4): owner → family → family_bytes → global →
 * global_bytes → reserve; the first that applies is the reason.
 *
 * The family is the current one: the owner's Guardian (or the owner itself) plus that Guardian's
 * members, from family_links at this moment, with no column that remembers it (fase 19 K1, P13).
 * A member that leaves takes its uploads along, and deleting a device frees its share at once while
 * the objects wait for the tombstone cron (C4, accepted: bounded by the owner quota, replicaIp 300/day
 * per IP, POST /devices 10/hour per IP and the bucket's 17-day lifecycle). replica_bytes is written on
 * the uploading row only. The path is tombstoned before the upload (D-alief-B12).
 * `upload` null only looks for a reuse ({ none } when there is nothing to reuse).
 */
export async function reserveReplica(
  sql: Sql,
  scan: { id: string; ownerId: string; domain: string },
  upload: { path: string; bytes: number } | null,
  quota: ReplicaQuota,
): Promise<ReplicaSlot> {
  return sql.begin(async (tx): Promise<ReplicaSlot> => {
    await tx`select pg_advisory_xact_lock(6, hashtext(${scan.ownerId}))`;
    const [found] = await tx<{ path: string }[]>`select (${recentReplicaQuery(tx, scan.ownerId, scan.domain)}) as path`;
    const reuse = found?.path ?? undefined;
    if (!reuse && !upload) return { none: true };
    if (!reuse) {
      await tx`select pg_advisory_xact_lock(6, 0)`;
      const full = quotaFull(await replicaCounts(tx, scan.ownerId), upload!.bytes, quota);
      if (full) return { quota: full };
    }
    // Zero rows: the scan was deleted meanwhile (DELETE /devices/me), so nothing is uploaded.
    const updated = reuse
      ? await tx`update scans set replica_path = ${reuse}, replica_bytes = null where id = ${scan.id} returning id`
      : await tx`update scans set replica_path = ${upload!.path}, replica_bytes = ${upload!.bytes} where id = ${scan.id} returning id`;
    if (updated.length === 0) return { gone: true };
    if (reuse) return { reuse };
    await addTombstones(tx, [upload!.path]);
    return { upload: upload!.path };
  });
}

interface ReplicaCounts {
  mine: number;
  family: number;
  familyBytes: number;
  all: number;
  allBytes: number;
}

/**
 * Original uploads of the last 24 h for one owner, its family and everyone, in one pass over
 * scans_original_replica (owner_id and replica_bytes are included columns, so index-only). The family
 * comes from family_links in SQL, never as a JS array parameter (fetch_types: false, db/client.ts).
 */
async function replicaCounts(sql: Q, ownerId: string): Promise<ReplicaCounts> {
  const [r] = await sql<ReplicaCounts[]>`${replicaCountsQuery(sql, ownerId)}`;
  return r!;
}

/** The statement of replicaCounts as a fragment, so precheckReplica can run it as a subquery. */
const replicaCountsQuery = (sql: Q, ownerId: string) => sql`
    with root as (
      select coalesce((select guardian_id from family_links where protected_id = ${ownerId}), ${ownerId}) as id
    ), members as (
      select id from root
      union
      select protected_id from family_links where guardian_id = (select id from root)
    )
    select count(*) filter (where s.owner_id = ${ownerId})::int as mine,
           count(*) filter (where s.owner_id in (select id from members))::int as family,
           coalesce(sum(s.replica_bytes) filter (where s.owner_id in (select id from members)), 0)::float8 as "familyBytes",
           count(*)::int as "all",
           coalesce(sum(s.replica_bytes), 0)::float8 as "allBytes"
    from scans s
    where s.replica_bytes is not null and s.created_at > now() - interval '24 hours'`;

/** Fase 19 K4 order. The reserve (K3) is the last part of the global quota, open to light families only. */
function quotaFull(c: ReplicaCounts, bytes: number, q: ReplicaQuota): ReplicaQuotaReason | undefined {
  if (c.mine >= q.owner) return "owner";
  if (c.family >= q.family) return "family";
  if (c.familyBytes + bytes > q.familyBytes) return "family_bytes";
  if (c.all >= q.global) return "global";
  if (c.allBytes + bytes > q.globalBytes) return "global_bytes";
  const inReserve = c.all >= q.global - q.reserveUploads || c.allBytes + bytes > q.globalBytes - q.reserveBytes;
  if (inReserve && c.family >= q.lightFamily) return "reserve";
  return undefined;
}

/** Fase 19 K5.2: aggregate state of the replica quotas over the last 24 h. Numbers only, no id (P6). */
export interface ReplicaUsage {
  /** full = a full-size replica no longer fits the global quota; reserve = in the last 20 %; else ok. A state, not a drop. */
  level: "ok" | "reserve" | "full";
  uploads: number;
  bytes: number;
  uploadsMax: number;
  bytesMax: number;
  /** Family roots with at least one upload. */
  families: number;
  /** Families where the next full-size replica no longer fits. */
  familiesAtCap: number;
  topFamilyUploads: number;
  topFamilyBytes: number;
}

/** One query for the hourly gauge (fase 19 K5.2) and GET /ops/status (fase 21c). `maxBytes` = largest replica. */
export async function replicaUsage(sql: Sql, q: ReplicaQuota, maxBytes: number): Promise<ReplicaUsage> {
  const [r] = await sql<Omit<ReplicaUsage, "level" | "uploadsMax" | "bytesMax">[]>`
    with up as (
      select coalesce(f.guardian_id, s.owner_id) as root, s.replica_bytes as b
      from scans s left join family_links f on f.protected_id = s.owner_id
      where s.replica_bytes is not null and s.created_at > now() - interval '24 hours'
    ), fam as (
      select count(*)::int as n, sum(b)::float8 as b from up group by root
    )
    select coalesce(sum(n), 0)::int as uploads, coalesce(sum(b), 0)::float8 as bytes,
           count(*)::int as families,
           count(*) filter (where n >= ${q.family} or b + ${maxBytes} > ${q.familyBytes})::int as "familiesAtCap",
           coalesce(max(n), 0)::int as "topFamilyUploads", coalesce(max(b), 0)::float8 as "topFamilyBytes"
    from fam`;
  const u = r!;
  // `reserve` = usage has entered the reserve zone (K5.2). quotaFull also adds the size of the upload
  // at hand, so a full-size upload from a heavy family is refused slightly before the gauge says
  // `reserve` (at most MAX_REPLICA_BYTES early). Deliberate: the gauge reports usage, not one upload.
  const level = u.uploads >= q.global || u.bytes + maxBytes > q.globalBytes ? "full"
    : u.uploads >= q.global - q.reserveUploads || u.bytes > q.globalBytes - q.reserveBytes ? "reserve"
    : "ok";
  // Field order = the log line of fase 19 K5.2.
  return {
    level, uploads: u.uploads, bytes: u.bytes, uploadsMax: q.global, bytesMax: q.globalBytes, families: u.families,
    familiesAtCap: u.familiesAtCap, topFamilyUploads: u.topFamilyUploads, topFamilyBytes: u.topFamilyBytes,
  };
}

/**
 * Reuse source: the newest original replica (replica_bytes set) of the owner + domain from the last
 * 24 h. Only originals count, so reuse never chains and an object is gone 15 days after upload.
 */
function recentReplicaQuery(sql: Q, ownerId: string, domain: string) {
  return sql`
    select replica_path from scans
    where owner_id = ${ownerId} and domain = ${domain} and replica_bytes is not null
      and created_at > now() - interval '24 hours'
    order by created_at desc limit 1`;
}

/**
 * Clears path and bytes on every scan of the owner that points at it (reuses too). Under the owner's
 * replica lock, so a reserveReplica that just picked this path as its reuse cannot commit after it.
 */
export async function clearReplicaPath(sql: Sql, ownerId: string, path: string): Promise<void> {
  await sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(6, hashtext(${ownerId}))`;
    await tx`update scans set replica_path = null, replica_bytes = null where owner_id = ${ownerId} and replica_path = ${path}`;
  });
}

export interface ScanRow {
  id: string;
  ownerId: string;
  ownerName: string;
  url: string;
  domain: string;
  pageTitle: string | null;
  score: number;
  status: "warning" | "blocked";
  signals: unknown[];
  screenshotPath: string | null;
  /** The stored favicon (PR-05). The scam site's own favicon_url is never read back. */
  faviconPath: string | null;
  /** The stored page replica (EX-07), in R2. */
  replicaPath: string | null;
  detectedAt: string;
  /** detected_at with microseconds, for the cursor. */
  cursorAt: string;
  verdict: { value: "safe" | "not_safe"; byDeviceId: string; byName: string; decidedAt: string } | null;
}

export const ISO_MS = `'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'`;

// Columns shared by list and detail. ownerName is the owner's current name; the verdict
// (per owner + domain) is joined for warning and blocked scans alike (GD-07).
function selectScans(sql: Sql) {
  return sql`
    select s.id, s.owner_id as "ownerId", d.name as "ownerName", s.url, s.domain,
           s.page_title as "pageTitle", s.score, s.status, s.signals,
           s.screenshot_path as "screenshotPath", s.favicon_path as "faviconPath",
           s.replica_path as "replicaPath",
           to_char(s.detected_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}) as "detectedAt",
           to_char(s.detected_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as "cursorAt",
           case when v.owner_id is not null then json_build_object(
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

/** The favicon path while the viewer owns the scan or is the owner's current guardian (as screenshots). */
export async function faviconPathForViewer(sql: Sql, id: string, viewerId: string): Promise<string | undefined> {
  const [row] = await sql<{ path: string }[]>`
    select s.favicon_path as path from scans s
    where s.id = ${id} and s.favicon_path is not null
      and (s.owner_id = ${viewerId}
           or exists (select 1 from family_links l where l.protected_id = s.owner_id and l.guardian_id = ${viewerId}))`;
  return row?.path;
}

/** The replica path while the viewer owns the scan or is the owner's current guardian (as screenshots). */
export async function replicaPathForViewer(sql: Sql, id: string, viewerId: string): Promise<string | undefined> {
  const [row] = await sql<{ path: string }[]>`
    select s.replica_path as path from scans s
    where s.id = ${id} and s.replica_path is not null
      and (s.owner_id = ${viewerId}
           or exists (select 1 from family_links l where l.protected_id = s.owner_id and l.guardian_id = ${viewerId}))`;
  return row?.path;
}
