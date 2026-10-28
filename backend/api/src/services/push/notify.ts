import type { Sql } from "postgres";
import type { Language, Principal } from "../../env";
import { ownPushText, pushText } from "./messages";
import { isQuiet } from "./quiet";
import type { PushMessage } from "./sender";

/** Pushes per guardian per 10 min: one paired device cannot flood the guardian's lock screen. */
export const PUSH_CAP = { max: 10, minutes: 10 };

type Scan = { id: string; status: "blocked" | "warning"; score: number };

interface Target {
  id: string;
  apnsToken: string | null;
  language: Language;
  recent: number;
  quietHours: boolean;
  quietStart: number;
  quietEnd: number;
  timeZone: string;
}

const targetColumns = (sql: Sql) => sql`
  d.id, d.apns_token as "apnsToken", d.language,
  (select count(*)::int from push_log p
    where p.to_device_id = d.id and p.created_at > now() - make_interval(mins => ${PUSH_CAP.minutes})) as recent,
  d.quiet_hours as "quietHours", d.quiet_start as "quietStart", d.quiet_end as "quietEnd", d.time_zone as "timeZone"`;

/**
 * PF-01 "Jam tenang": only blocked sites (score ≥ 80) still push during the quiet window
 * ("Peringatan Bahaya tetap dikirim saat jam tenang").
 */
function allowed(t: Target, scan: Scan, now: Date): boolean {
  if (!t.apnsToken) return false;
  if (scan.status === "warning" && isQuiet(t, now)) return false;
  if (t.recent >= PUSH_CAP.max) {
    console.log(JSON.stringify({ event: "push_capped" }));
    return false;
  }
  return true;
}

/**
 * R4 §3: the push for a protected device's scan, addressed to its guardian, or undefined
 * (guardian's own scan, no guardian, "Kabari saya" or "Aktivitas orang dilindungi" off,
 * quiet hours for a warning, no APNs token, or PUSH_CAP reached).
 */
export async function guardianPush(sql: Sql, owner: Principal, scan: Scan, now = new Date()): Promise<PushMessage | undefined> {
  if (owner.mode !== "protected") return undefined;
  const [g] = await sql<Target[]>`
    select ${targetColumns(sql)}
    from family_links l join devices d on d.id = l.guardian_id
    where l.protected_id = ${owner.deviceId} and l.notify and d.notify_family`;
  if (!g || !allowed(g, scan, now)) return undefined;
  return {
    toDeviceId: g.id,
    apnsToken: g.apnsToken!,
    body: pushText(g.language, scan.status, owner.name, scan.score),
    scanId: scan.id,
  };
}

/**
 * PF-01 "Situs berbahaya" / "Situs diblokir": a push to the device about its own scan, when that
 * switch is on. Same quiet hours and cap as the guardian push.
 */
export async function ownPush(sql: Sql, owner: Principal, scan: Scan, now = new Date()): Promise<PushMessage | undefined> {
  const [d] = await sql<Target[]>`
    select ${targetColumns(sql)}
    from devices d
    where d.id = ${owner.deviceId}
      and (case when ${scan.status} = 'blocked' then d.notify_blocked else d.notify_warning end)`;
  if (!d || !allowed(d, scan, now)) return undefined;
  return {
    toDeviceId: d.id,
    apnsToken: d.apnsToken!,
    body: ownPushText(d.language, scan.status, scan.score),
    scanId: scan.id,
  };
}
