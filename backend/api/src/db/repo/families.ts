import type { Sql, TransactionSql } from "postgres";

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
}

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
             'detectedAt', to_char(s.detected_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
           ) end as "lastScan"
    from family_links l
    join devices d on d.id = l.protected_id
    left join lateral (
      select id, status, score, url, detected_at from scans
      where owner_id = d.id order by detected_at desc, id desc limit 1
    ) s on true
    where l.guardian_id = ${guardianId}
    order by l.created_at, d.id`;
}

/** True when a link was removed. */
export async function deleteMember(sql: Sql, guardianId: string, protectedId: string): Promise<boolean> {
  const rows = await sql`delete from family_links where guardian_id = ${guardianId} and protected_id = ${protectedId} returning 1`;
  return rows.length > 0;
}

export async function deleteGuardianLink(sql: Sql, protectedId: string): Promise<boolean> {
  const rows = await sql`delete from family_links where protected_id = ${protectedId} returning 1`;
  return rows.length > 0;
}
