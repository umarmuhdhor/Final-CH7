import type { Sql, TransactionSql } from "postgres";
import type { Language } from "../../env";
import { dropVerdicts } from "./verdicts";

export const FAMILY_MAX = 3;

export interface DeviceSummary {
  deviceId: string;
  name: string;
  avatarId: string;
}

export async function guardianOf(sql: Sql | TransactionSql, protectedId: string): Promise<DeviceSummary | null> {
  const [row] = await sql<DeviceSummary[]>`
    select d.id as "deviceId", d.name, d.avatar_id as "avatarId"
    from family_links l join devices d on d.id = l.guardian_id
    where l.protected_id = ${protectedId}`;
  return row ?? null;
}

/** Same advisory lock as the family_links trigger (I3), held until the transaction ends. */
export async function lockGuardian(tx: TransactionSql, guardianId: string): Promise<void> {
  await tx`select pg_advisory_xact_lock(hashtext(${guardianId}))`;
}

export async function memberCount(tx: TransactionSql, guardianId: string): Promise<number> {
  const [row] = await tx<{ n: number }[]>`select count(*)::int as n from family_links where guardian_id = ${guardianId}`;
  return row!.n;
}

export async function insertLink(tx: TransactionSql, protectedId: string, guardianId: string): Promise<void> {
  await tx`insert into family_links (protected_id, guardian_id) values (${protectedId}, ${guardianId})`;
}

export interface MemberRow extends DeviceSummary {
  extensionActive: boolean;
  lastScan: { status: "warning" | "blocked"; score: number; url: string; detectedAt: string } | null;
  // PF-01 member detail (proposed contract additions, see backend/API.md).
  connectedAt: string;
  /** Last extension heartbeat ("aktif 2 mnt lalu"), null before the first one. */
  lastSeenAt: string | null;
  deviceModel: string | null;
  osVersion: string | null;
  /** "Kabari saya": this guardian gets a push for the member's scans. */
  notify: boolean;
  /** Last "Ingatkan" push, so the button can show "Terkirim". */
  remindedAt: string | null;
  stats: { blocked: number; warnings: number };
}

const iso = (col: string) => `to_char(${col} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`;

/**
 * Members of a guardian, read from family_links at request time (SECURITY T12).
 * extensionActive: heartbeat within 24 h, or no heartbeat yet (contract: never
 * "Not connected" without evidence).
 */
export async function listMembers(sql: Sql, guardianId: string): Promise<MemberRow[]> {
  return sql<MemberRow[]>`
    select d.id as "deviceId", d.name, d.avatar_id as "avatarId",
           (d.ext_last_seen_at is null or d.ext_last_seen_at > now() - interval '24 hours') as "extensionActive",
           case when s.id is null then null else json_build_object(
             'status', s.status, 'score', s.score, 'url', s.url,
             'detectedAt', ${sql.unsafe(iso("s.detected_at"))}
           ) end as "lastScan",
           ${sql.unsafe(iso("l.created_at"))} as "connectedAt",
           ${sql.unsafe(iso("d.ext_last_seen_at"))} as "lastSeenAt",
           d.device_model as "deviceModel", d.os_version as "osVersion",
           l.notify, ${sql.unsafe(iso("l.reminded_at"))} as "remindedAt",
           json_build_object('blocked', d.blocked_total, 'warnings', d.warning_total) as stats
    from family_links l
    join devices d on d.id = l.protected_id
    left join lateral (
      select id, status, score, url, detected_at from scans
      where owner_id = d.id order by detected_at desc, id desc limit 1
    ) s on true
    where l.guardian_id = ${guardianId}
    order by l.created_at, d.id`;
}

/** "Kabari saya" on or off for one member. False when the device is not this guardian's member. */
export async function setMemberNotify(sql: Sql, guardianId: string, protectedId: string, notify: boolean): Promise<boolean> {
  const rows = await sql`
    update family_links set notify = ${notify}
    where guardian_id = ${guardianId} and protected_id = ${protectedId} returning 1`;
  return rows.length > 0;
}

export const REMIND_EVERY_HOURS = 6;

export type RemindTarget =
  | { kind: "notMember" }
  | { kind: "noPush" }
  | { kind: "tooSoon"; retryAfter: number }
  | { kind: "ok"; deviceId: string; apnsToken: string; language: Language };

/**
 * Claims the member's "Ingatkan" slot (one per REMIND_EVERY_HOURS) when it has an APNs token.
 * The claim and the check are one UPDATE, so two taps at once send one push.
 */
export async function claimReminder(sql: Sql, guardianId: string, protectedId: string): Promise<RemindTarget> {
  const [row] = await sql<{ apnsToken: string | null; language: Language; wait: number | null }[]>`
    select d.apns_token as "apnsToken", d.language,
           case when l.reminded_at > now() - make_interval(hours => ${REMIND_EVERY_HOURS})
                then ceil(extract(epoch from l.reminded_at + make_interval(hours => ${REMIND_EVERY_HOURS}) - now()))::int
           end as wait
    from family_links l join devices d on d.id = l.protected_id
    where l.guardian_id = ${guardianId} and l.protected_id = ${protectedId}`;
  if (!row) return { kind: "notMember" };
  if (!row.apnsToken) return { kind: "noPush" };
  if (row.wait !== null) return { kind: "tooSoon", retryAfter: Math.max(1, row.wait) };
  const [claimed] = await sql<{ apnsToken: string | null; language: Language }[]>`
    update family_links l set reminded_at = now()
    from devices d
    where l.guardian_id = ${guardianId} and l.protected_id = ${protectedId} and d.id = l.protected_id
      and (l.reminded_at is null or l.reminded_at <= now() - make_interval(hours => ${REMIND_EVERY_HOURS}))
    returning d.apns_token as "apnsToken", d.language`;
  if (!claimed) return { kind: "tooSoon", retryAfter: REMIND_EVERY_HOURS * 3600 };
  if (!claimed.apnsToken) return { kind: "noPush" };
  return { kind: "ok", deviceId: protectedId, apnsToken: claimed.apnsToken, language: claimed.language };
}

/** The removed member's push address (for "Adhella stopped protecting you"), or undefined when no link was removed. */
export interface RemovedMember {
  apnsToken: string | null;
  language: Language;
}

/** The link is removed; the guardian's verdicts for that member go with it (P13). */
export async function deleteMember(sql: Sql, guardianId: string, protectedId: string): Promise<RemovedMember | undefined> {
  return sql.begin(async (tx) => {
    const rows = await tx`delete from family_links where guardian_id = ${guardianId} and protected_id = ${protectedId} returning 1`;
    if (rows.length === 0) return undefined;
    await dropVerdicts(tx, { ownerId: protectedId, byDeviceId: guardianId });
    const [d] = await tx<RemovedMember[]>`select apns_token as "apnsToken", language from devices where id = ${protectedId}`;
    return d ?? { apnsToken: null, language: "en" };
  });
}

export async function deleteGuardianLink(sql: Sql, protectedId: string): Promise<boolean> {
  return sql.begin(async (tx) => {
    const [row] = await tx<{ guardianId: string }[]>`
      delete from family_links where protected_id = ${protectedId} returning guardian_id as "guardianId"`;
    if (!row) return false;
    await dropVerdicts(tx, { ownerId: protectedId, byDeviceId: row.guardianId });
    return true;
  });
}
