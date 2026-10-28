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

export interface DevicePatch {
  name?: string;
  apnsToken?: string | null;
  language?: Language;
  extensionLastSeenAt?: Date;
  deviceModel?: string;
  osVersion?: string;
}

/** Only columns present in the patch change. ext_last_seen_at never moves backwards. */
export async function updateDevice(sql: Sql, id: string, p: DevicePatch): Promise<void> {
  const has = (k: keyof DevicePatch) => p[k] !== undefined;
  await sql`
    update devices set
      name             = case when ${has("name")} then ${p.name ?? null}::text else name end,
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
}

export async function findProfile(sql: Sql, id: string): Promise<DeviceProfile | undefined> {
  const [row] = await sql<DeviceProfile[]>`
    select id as "deviceId", name, avatar_id as "avatarId", mode, language,
           json_build_object(
             'blocked', blocked_total, 'warnings', warning_total,
             'since', to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
           ) as stats
    from devices where id = ${id}`;
  return row;
}

/**
 * Deletes the device and, through `on delete cascade`, its family links (either side),
 * codes, join attempts, scans, verdicts on its scans or made by it, and push log rows.
 * Returns the screenshot paths of its scans, to remove from Storage after commit.
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
    const shots = await tx<{ path: string | null }[]>`
      delete from scans where owner_id = ${id} returning screenshot_path as path`;
    await tx`delete from devices where id = ${id}`;
    // Tombstoned with the delete: if removing the objects fails later, the cron retries (D-alief-B12).
    const paths = [...new Set(shots.flatMap((s) => (s.path ? [s.path] : [])))];
    await addTombstones(tx, paths);
    return paths;
  });
}
