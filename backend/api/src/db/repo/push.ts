import type { Sql } from "postgres";

/**
 * One push_log row per send: who, which scan, the result code. No text (D-alief-B11). Skipped when
 * the scan or the guardian was deleted meanwhile (DELETE /devices/me, disconnect cascade), so a
 * late send never brings a reference back. FOR KEY SHARE makes a concurrent delete wait for this
 * insert (its cascade then removes the row); a delete that commits first leaves nothing to select.
 */
export async function recordPush(sql: Sql, toDeviceId: string, scanId: string | undefined, result: string): Promise<void> {
  try {
    if (scanId === undefined) {
      // Family push (reminder, disconnect): no scan to reference.
      await sql`
        insert into push_log (to_device_id, result)
        select d.id, ${result} from devices d where d.id = ${toDeviceId} for key share of d`;
      return;
    }
    await sql`
      insert into push_log (to_device_id, scan_id, result)
      select d.id, s.id, ${result} from devices d, scans s
      where d.id = ${toDeviceId} and s.id = ${scanId}
      for key share of d, s`;
  } catch (err) {
    // Parent deleted between snapshot and FK check: same outcome as the guard, no row.
    if ((err as { code?: string })?.code !== "23503") throw err;
  }
}

/** Compare-and-clear: a token the device registered after this send stays (R3 §6). */
export async function clearApnsToken(sql: Sql, deviceId: string, token: string): Promise<void> {
  await sql`update devices set apns_token = null where id = ${deviceId} and apns_token = ${token}`;
}
