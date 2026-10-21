import type { Sql } from "postgres";

/**
 * One push_log row per send: who, which scan, the result code. No text (D-alief-B11). Skipped when
 * the scan or the guardian was deleted meanwhile (DELETE /devices/me, disconnect cascade), so a
 * late send never brings a reference back.
 */
export async function recordPush(sql: Sql, toDeviceId: string, scanId: string, result: string): Promise<void> {
  await sql`
    insert into push_log (to_device_id, scan_id, result)
    select ${toDeviceId}, ${scanId}, ${result}
    where exists (select 1 from devices where id = ${toDeviceId}) and exists (select 1 from scans where id = ${scanId})`;
}

/** Compare-and-clear: a token the device registered after this send stays (R3 §6). */
export async function clearApnsToken(sql: Sql, deviceId: string, token: string): Promise<void> {
  await sql`update devices set apns_token = null where id = ${deviceId} and apns_token = ${token}`;
}
