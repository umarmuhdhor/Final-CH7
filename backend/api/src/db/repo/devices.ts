import type { Sql, TransactionSql } from "postgres";
import type { DeviceMode, Language } from "../../env";
import { addTombstones } from "./tombstones";
import { dropVerdicts } from "./verdicts";

export interface DeviceAuthRow {
  id: string;
  mode: DeviceMode;
  name: string;
  language: Language;
  /** last_seen_at older than 5 minutes. */
  stale: boolean;
}

export async function findByTokenHash(sql: Sql, tokenHash: Uint8Array): Promise<DeviceAuthRow | undefined> {
  const [row] = await sql<DeviceAuthRow[]>`
    select id, mode, name, language, last_seen_at < now() - interval '5 minutes' as stale
    from devices where token_hash = ${tokenHash}`;
  return row;
}

export async function touchLastSeen(sql: Sql, id: string): Promise<void> {
  await sql`update devices set last_seen_at = now()
            where id = ${id} and last_seen_at < now() - interval '5 minutes'`;
}

export interface NewDevice {
  name: string;
  mode: DeviceMode;
  avatarId: string;
  apnsToken: string | null;
  tokenHash: Uint8Array;
}

export async function insertDevice(sql: Sql, d: NewDevice): Promise<string> {
  const [row] = await sql<{ id: string }[]>`
    insert into devices (name, mode, avatar_id, apns_token, token_hash)
    values (${d.name}, ${d.mode}, ${d.avatarId}, ${d.apnsToken}, ${d.tokenHash})
    returning id`;
  return row!.id;
}

/** PF-01 "Pengaturan/Notifikasi" (proposed). Times are minutes after local midnight. */
export interface NotificationSettings {
  warning: boolean;
  blocked: boolean;
  family: boolean;
  protectionOff: boolean;
  weeklySummary: boolean;
  quietHours: boolean;
  quietStart: number;
  quietEnd: number;
}

export interface DevicePatch {
  name?: string;
  apnsToken?: string | null;
  language?: Language;
  extensionLastSeenAt?: Date;
  deviceModel?: string;
  osVersion?: string;
  /** PF-01 "Ubah foto". */
  avatarId?: string;
  /** IANA zone, for quiet hours and the weekly summary. */
  timeZone?: string;
  notifications?: Partial<NotificationSettings>;
  /** EX-03 (#49): push-to-start token of the Live Activity; null clears it. */
  liveActivityStartToken?: string | null;
  /** EX-03 (#49): update token of the running activity; null clears it (the island ended). */
  liveActivityUpdateToken?: { activityId: string; token: string } | null;
}

/** Only columns present in the patch change. ext_last_seen_at never moves backwards. */
export async function updateDevice(sql: Sql, id: string, p: DevicePatch): Promise<void> {
  const has = (k: keyof DevicePatch) => p[k] !== undefined;
  const n = p.notifications ?? {};
  const flag = (k: keyof NotificationSettings) => (n[k] === undefined ? null : Boolean(n[k]));
  const time = (k: "quietStart" | "quietEnd") => n[k] ?? null;
  await sql`
    update devices set
      name             = case when ${has("name")} then ${p.name ?? null}::text else name end,
      avatar_id        = coalesce(${p.avatarId ?? null}::text, avatar_id),
      time_zone        = coalesce(${p.timeZone ?? null}::text, time_zone),
      notify_warning        = coalesce(${flag("warning")}::boolean, notify_warning),
      notify_blocked        = coalesce(${flag("blocked")}::boolean, notify_blocked),
      notify_family         = coalesce(${flag("family")}::boolean, notify_family),
      notify_protection_off = coalesce(${flag("protectionOff")}::boolean, notify_protection_off),
      weekly_summary        = coalesce(${flag("weeklySummary")}::boolean, weekly_summary),
      quiet_hours           = coalesce(${flag("quietHours")}::boolean, quiet_hours),
      quiet_start           = coalesce(${time("quietStart")}::smallint, quiet_start),
      quiet_end             = coalesce(${time("quietEnd")}::smallint, quiet_end),
      apns_token       = case when ${has("apnsToken")} then ${p.apnsToken ?? null}::text else apns_token end,
      language         = case when ${has("language")} then ${p.language ?? null}::text else language end,
      device_model     = case when ${has("deviceModel")} then ${p.deviceModel ?? null}::text else device_model end,
      os_version       = case when ${has("osVersion")} then ${p.osVersion ?? null}::text else os_version end,
      live_start_token  = case when ${has("liveActivityStartToken")} then ${p.liveActivityStartToken ?? null}::text else live_start_token end,
      live_update_token = case when ${has("liveActivityUpdateToken")} then ${p.liveActivityUpdateToken?.token ?? null}::text else live_update_token end,
      live_activity_id  = case when ${has("liveActivityUpdateToken")} then ${p.liveActivityUpdateToken?.activityId ?? null}::text else live_activity_id end,
      ext_last_seen_at = case when ${has("extensionLastSeenAt")}
                              then greatest(ext_last_seen_at, ${p.extensionLastSeenAt ?? null}::timestamptz)
                              else ext_last_seen_at end
    where id = ${id}`;
}

export interface DeviceProfile {
  deviceId: string;
  name: string;
  avatarId: string;
  mode: DeviceMode;
  language: Language;
  /** PF-01 profile stats: lifetime counters and the registration time ("Hari terlindungi"). */
  stats: { blocked: number; warnings: number; since: string };
  /** PF-01 settings (proposed): what the notification page shows. */
  timeZone: string;
  notifications: NotificationSettings;
}

export async function findProfile(sql: Sql, id: string): Promise<DeviceProfile | undefined> {
  const [row] = await sql<DeviceProfile[]>`
    select id as "deviceId", name, avatar_id as "avatarId", mode, language,
           json_build_object(
             'blocked', blocked_total, 'warnings', warning_total,
             'since', to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
           ) as stats,
           time_zone as "timeZone",
           json_build_object(
             'warning', notify_warning, 'blocked', notify_blocked, 'family', notify_family,
             'protectionOff', notify_protection_off, 'weeklySummary', weekly_summary,
             'quietHours', quiet_hours, 'quietStart', quiet_start, 'quietEnd', quiet_end
           ) as notifications
    from devices where id = ${id}`;
  return row;
}

/**
 * PF-01 "Punya kode undangan?": a protected copy of a guardian device (mode never changes, I1).
 * Name, avatar, language, push token, settings, counters and start date carry over; the history
 * stays with the old device, which the caller deletes in the same transaction as the join (fase 27a).
 * The weekly summary starts off: the Protected settings page has no switch for it (fase 27j, F-N4).
 */
export async function insertProtectedCopy(sql: Sql | TransactionSql, fromId: string, tokenHash: Uint8Array): Promise<{ id: string; avatarId: string } | undefined> {
  const [row] = await sql<{ id: string; avatarId: string }[]>`
    insert into devices (
      name, mode, avatar_id, language, apns_token, token_hash, created_at,
      blocked_total, warning_total, device_model, os_version, time_zone,
      notify_warning, notify_blocked, notify_family, notify_protection_off, weekly_summary,
      quiet_hours, quiet_start, quiet_end
    )
    select name, 'protected', avatar_id, language, apns_token, ${tokenHash}, created_at,
           blocked_total, warning_total, device_model, os_version, time_zone,
           notify_warning, notify_blocked, notify_family, notify_protection_off, false,
           quiet_hours, quiet_start, quiet_end
    from devices where id = ${fromId} and mode = 'guardian'
    returning id, avatar_id as "avatarId"`;
  return row;
}

/** E7 (fase 24a-1) thresholds, in days: K1 inactive device, K4 registration never used again. */
export interface InactiveCutoffs {
  inactiveDays: number;
  unusedDays: number;
}

/**
 * Devices the retention step may delete (E7). Activity = last_seen_at only (K2: every request with
 * a token moves it, push delivery does not).
 * - K1 + K3 (b): a family is one unit. A device goes only when it and every other member of its
 *   family (the guardian + all its protected devices) were last seen before the K1 cutoff. The family
 *   root is coalesce(guardian_id, id): one guardian per protected device, and a guardian is never a
 *   protected_id. A device without a family is judged alone.
 * - K4 (b): a registration never used again (last seen within 1 hour of created_at), older than the
 *   K4 cutoff, with no family link on either side.
 * `only` limits the check to one device (the recheck inside deleteDevice, K7).
 */
function inactiveCandidates(sql: Sql | TransactionSql, c: InactiveCutoffs, only?: string) {
  const inactiveBefore = sql`now() - make_interval(days => ${c.inactiveDays}::int)`;
  const unusedBefore = sql`now() - make_interval(days => ${c.unusedDays}::int)`;
  const one = only === undefined ? sql`` : sql`and d.id = ${only}`;
  return sql`
    select d.id from devices d left join family_links l on l.protected_id = d.id
    where d.last_seen_at < ${inactiveBefore} ${one}
      and not exists (select 1 from devices g
        where g.id = coalesce(l.guardian_id, d.id) and g.last_seen_at >= ${inactiveBefore})
      and not exists (select 1 from family_links m join devices p on p.id = m.protected_id
        where m.guardian_id = coalesce(l.guardian_id, d.id) and p.last_seen_at >= ${inactiveBefore})
    union
    select d.id from devices d
    -- The first condition follows from the next two; it is there so the planner can use devices_last_seen.
    where d.last_seen_at < ${unusedBefore} + interval '1 hour' ${one}
      and d.created_at < ${unusedBefore} and d.last_seen_at < d.created_at + interval '1 hour'
      and not exists (select 1 from family_links f where f.protected_id = d.id or f.guardian_id = d.id)`;
}

/** Up to `limit` candidate ids in id order (K6 cap per run). */
export async function inactiveDeviceIds(sql: Sql, c: InactiveCutoffs, limit: number): Promise<string[]> {
  const rows = await sql<{ id: string }[]>`select id from (${inactiveCandidates(sql, c)}) c order by id limit ${limit}`;
  return rows.map((r) => r.id);
}

/** All candidates, without the per-run cap (K8: the number the dry run reports). */
export async function countInactiveDevices(sql: Sql, c: InactiveCutoffs): Promise<number> {
  const [row] = await sql<{ n: number }[]>`select count(*)::int as n from (${inactiveCandidates(sql, c)}) c`;
  return row!.n;
}

export interface DeleteDeviceOptions {
  /**
   * E7 retention (K7): delete only if the device is still a candidate inside the transaction, so a
   * device (or a family member) that came back after the candidate SELECT is kept. Waits at most
   * `lockTimeoutMs` for row locks (55P03), so the cron never queues behind a request.
   */
  onlyIfInactive: InactiveCutoffs;
  lockTimeoutMs?: number;
}

/**
 * Deletes the device and, through `on delete cascade`, its family links (either side),
 * codes, join attempts, scans, verdicts on its scans or made by it, and push log rows.
 * Returns the screenshot, favicon and replica paths of its scans, to remove from Storage/R2 after commit.
 * With `onlyIfInactive` (retention, E7): returns null and changes nothing when the device is no
 * longer an inactive-device candidate (or is gone).
 */
export async function deleteDevice(sql: Sql, id: string): Promise<string[]>;
export async function deleteDevice(sql: Sql, id: string, opts: DeleteDeviceOptions): Promise<string[] | null>;
export async function deleteDevice(sql: Sql, id: string, opts?: DeleteDeviceOptions): Promise<string[] | null> {
  return sql.begin(async (tx) => {
    if (opts) {
      await tx`select set_config('lock_timeout', ${`${opts.lockTimeoutMs ?? 3000}ms`}, true)`;
      // Lock the device and every member of its family (in id order) before the recheck: until
      // commit, touchLastSeen on any of them waits, so nobody can become active between the
      // recheck and the delete. FOR SHARE does not block the FOR KEY SHARE of foreign-key inserts.
      // So a join that lands after the recheck is not blocked; it needs a live family code, which an
      // inactive guardian cannot have, and the cascade would only drop that brand-new link (accepted).
      await tx`
        select d.id from devices d
        where d.id in (
          select ${id}::text
          union select guardian_id from family_links where protected_id = ${id}
          union select m.protected_id from family_links m
                where m.guardian_id = coalesce((select guardian_id from family_links where protected_id = ${id}), ${id}))
        order by d.id for share of d`;
      const still = await inactiveCandidates(tx, opts.onlyIfInactive, id);
      if (still.length === 0) return null;
    }
    return (await deleteDeviceInTx(tx, id)).paths;
  });
}

/**
 * The delete itself, inside the caller's transaction (fase 27a: become-protected deletes the old
 * guardian in the same transaction as the join). Same cascade as `deleteDevice`; returns the
 * Storage/R2 paths to remove after commit (already tombstoned here), and whether the device row
 * was still there to delete (false when a concurrent delete committed first).
 */
export async function deleteDeviceInTx(tx: TransactionSql, id: string): Promise<{ deleted: boolean; paths: string[] }> {
  // Links first, then verdicts under their domain locks (lock order of decideVerdict), so the
  // review queue counts drop with the device (D-alief-B10).
  await tx`delete from family_links where protected_id = ${id} or guardian_id = ${id}`;
  await dropVerdicts(tx, { deviceId: id });
  // Deleting the scans first (with returning) leaves no window for an upload to slip in.
  // Locked by id first, the order retention uses, so the two cannot deadlock.
  await tx`select 1 from scans where owner_id = ${id} order by id for update`;
  const shots = await tx<{ path: string | null; favicon: string | null; replica: string | null }[]>`
    delete from scans where owner_id = ${id}
    returning screenshot_path as path, favicon_path as favicon, replica_path as replica`;
  const gone = await tx`delete from devices where id = ${id} returning 1`;
  // Tombstoned with the delete: if removing the objects fails later, the cron retries (D-alief-B12).
  const paths = [...new Set(shots.flatMap((s) => [s.path, s.favicon, s.replica].filter((p): p is string => p !== null)))];
  await addTombstones(tx, paths);
  return { deleted: gone.length > 0, paths };
}
