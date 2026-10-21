import type { TransactionSql } from "postgres";

export const JOIN_MAX_FAILURES = 5;
export const JOIN_WINDOW_SECONDS = 600;

/**
 * Serialises join attempts per device and per IP for the rest of the transaction, so
 * parallel guesses cannot overrun the failure budget. Always device first, then IP:
 * nobody holds an IP lock while waiting for a device lock, so no deadlock.
 */
export async function lockAttempts(tx: TransactionSql, deviceId: string, ipHash: Uint8Array): Promise<void> {
  await tx`select pg_advisory_xact_lock(1, hashtext(${deviceId}))`;
  await tx`select pg_advisory_xact_lock(2, hashtext(encode(${ipHash}::bytea, 'hex')))`;
}

/** Seconds until the oldest failure leaves the window, or null when under the limit (R3 §5). */
export async function attemptsRetryAfter(
  tx: TransactionSql,
  deviceId: string,
  ipHash: Uint8Array,
): Promise<number | null> {
  const rows = await tx<{ n: number; retry: number | null }[]>`
    select count(*)::int as n,
           ceil(extract(epoch from (min(attempted_at) + make_interval(secs => ${JOIN_WINDOW_SECONDS}) - now())))::int as retry
    from join_attempts
    where not success and attempted_at > now() - make_interval(secs => ${JOIN_WINDOW_SECONDS})
      and device_id = ${deviceId}
    union all
    select count(*)::int, ceil(extract(epoch from (min(attempted_at) + make_interval(secs => ${JOIN_WINDOW_SECONDS}) - now())))::int
    from join_attempts
    where not success and attempted_at > now() - make_interval(secs => ${JOIN_WINDOW_SECONDS})
      and ip_hash = ${ipHash}`;
  const over = rows.filter((r) => r.n >= JOIN_MAX_FAILURES);
  if (over.length === 0) return null;
  return Math.max(1, ...over.map((r) => r.retry ?? JOIN_WINDOW_SECONDS));
}

export async function recordAttempt(
  sql: TransactionSql,
  deviceId: string,
  ipHash: Uint8Array,
  success: boolean,
): Promise<void> {
  await sql`insert into join_attempts (device_id, ip_hash, success) values (${deviceId}, ${ipHash}, ${success})`;
}
