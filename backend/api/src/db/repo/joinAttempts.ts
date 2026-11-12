import type { TransactionSql } from "postgres";
import { LOCK } from "../locks";

export const JOIN_MAX_FAILURES_DEVICE = 5;
/** Higher than per device: mobile carriers put many households behind one CGNAT IP (D-alief-B06). */
export const JOIN_MAX_FAILURES_IP = 20;
export const JOIN_WINDOW_SECONDS = 600;

/**
 * Serialises join attempts per device and per IP for the rest of the transaction, so
 * parallel guesses cannot overrun the failure budget. Always device first, then IP:
 * nobody holds an IP lock while waiting for a device lock, so no deadlock.
 */
export async function lockAttempts(tx: TransactionSql, deviceId: string, ipHash: Uint8Array): Promise<void> {
  await tx`select pg_advisory_xact_lock(${LOCK.joinDevice}, hashtext(${deviceId}))`;
  await tx`select pg_advisory_xact_lock(${LOCK.joinIp}, hashtext(encode(${ipHash}::bytea, 'hex')))`;
}

/** IP lock only, for GET /j/<code> (no device). Same lock as lockAttempts' second step. */
export async function lockIpAttempts(tx: TransactionSql, ipHash: Uint8Array): Promise<void> {
  await tx`select pg_advisory_xact_lock(${LOCK.joinIp}, hashtext(encode(${ipHash}::bytea, 'hex')))`;
}

/** True when this IP has used up its failure budget (JOIN_MAX_FAILURES_IP in the window). */
export async function ipAttemptsExhausted(tx: TransactionSql, ipHash: Uint8Array): Promise<boolean> {
  const [row] = await tx<{ n: number }[]>`
    select count(*)::int as n from join_attempts
    where not success and attempted_at > now() - make_interval(secs => ${JOIN_WINDOW_SECONDS}) and ip_hash = ${ipHash}`;
  return row!.n >= JOIN_MAX_FAILURES_IP;
}

/** Seconds until the oldest failure leaves the window, or null when under the limit (R3 §5). */
export async function attemptsRetryAfter(
  tx: TransactionSql,
  deviceId: string,
  ipHash: Uint8Array,
): Promise<number | null> {
  const rows = await tx<{ max: number; n: number; retry: number | null }[]>`
    select ${JOIN_MAX_FAILURES_DEVICE}::int as max, count(*)::int as n,
           ceil(extract(epoch from (min(attempted_at) + make_interval(secs => ${JOIN_WINDOW_SECONDS}) - now())))::int as retry
    from join_attempts
    where not success and attempted_at > now() - make_interval(secs => ${JOIN_WINDOW_SECONDS})
      and device_id = ${deviceId}
    union all
    select ${JOIN_MAX_FAILURES_IP}::int, count(*)::int, ceil(extract(epoch from (min(attempted_at) + make_interval(secs => ${JOIN_WINDOW_SECONDS}) - now())))::int
    from join_attempts
    where not success and attempted_at > now() - make_interval(secs => ${JOIN_WINDOW_SECONDS})
      and ip_hash = ${ipHash}`;
  const over = rows.filter((r) => r.n >= r.max);
  if (over.length === 0) return null;
  return Math.max(1, ...over.map((r) => r.retry ?? JOIN_WINDOW_SECONDS));
}

export async function recordAttempt(
  sql: TransactionSql,
  /** null: a lookup by GET /j/<code>, which has no device. It still counts for the IP. */
  deviceId: string | null,
  ipHash: Uint8Array,
  success: boolean,
): Promise<void> {
  await sql`insert into join_attempts (device_id, ip_hash, success) values (${deviceId}, ${ipHash}, ${success})`;
}
