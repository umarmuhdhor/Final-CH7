import type { Sql } from "postgres";
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
 * stays with the old device, which the caller deletes once the new one joined a family.
 */
export async function insertProtectedCopy(sql: Sql, fromId: string, tokenHash: Uint8Array): Promise<{ id: string; avatarId: string } | undefined> {
  const [row] = await sql<{ id: string; avatarId: string }[]>`
    insert into devices (
      name, mode, avatar_id, language, apns_token, token_hash, created_at,
      blocked_total, warning_total, device_model, os_version, time_zone,
      notify_warning, notify_blocked, notify_family, notify_protection_off, weekly_summary,
      quiet_hours, quiet_start, quiet_end
    )
    select name, 'protected', avatar_id, language, apns_token, ${tokenHash}, created_at,
           blocked_total, warning_total, device_model, os_version, time_zone,
           notify_warning, notify_blocked, notify_family, notify_protection_off, weekly_summary,
           quiet_hours, quiet_start, quiet_end
    from devices where id = ${fromId} and mode = 'guardian'
    returning id, avatar_id as "avatarId"`;
  return row;
}

/**
 * Deletes the device and, through `on delete cascade`, its family links (either side),
 * codes, join attempts, scans, verdicts on its scans or made by it, and push log rows.
 * Returns the screenshot, favicon and replica paths of its scans, to remove from Storage/R2 after commit.
 */
export async function deleteDevice(sql: Sql, id: string): Promise<string[]> {
  return sql.begin(async (tx) => {
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
    await tx`delete from devices where id = ${id}`;
    // Tombstoned with the delete: if removing the objects fails later, the cron retries (D-alief-B12).
    const paths = [...new Set(shots.flatMap((s) => [s.path, s.favicon, s.replica].filter((p): p is string => p !== null)))];
    await addTombstones(tx, paths);
    return paths;
  });
}
