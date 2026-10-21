import type { Sql } from "postgres";
import type { Language, Principal } from "../../env";
import { pushText } from "./messages";
import type { PushMessage } from "./sender";

/** Pushes per guardian per 10 min: one paired device cannot flood the guardian's lock screen. */
export const PUSH_CAP = { max: 10, minutes: 10 };

/**
 * R4 §3: the push for a protected device's scan, addressed to its guardian, or undefined
 * (guardian's own scan, no guardian, no APNs token, or PUSH_CAP reached). Guardians' own scans never push.
 */
export async function guardianPush(
  sql: Sql,
  owner: Principal,
  scan: { id: string; status: "blocked" | "warning"; score: number },
): Promise<PushMessage | undefined> {
  if (owner.mode !== "protected") return undefined;
  const [g] = await sql<{ id: string; apnsToken: string | null; language: Language; recent: number }[]>`
    select d.id, d.apns_token as "apnsToken", d.language,
           (select count(*)::int from push_log p
             where p.to_device_id = d.id and p.created_at > now() - make_interval(mins => ${PUSH_CAP.minutes})) as recent
    from family_links l join devices d on d.id = l.guardian_id
    where l.protected_id = ${owner.deviceId}`;
  if (!g?.apnsToken) return undefined;
  if (g.recent >= PUSH_CAP.max) {
    console.log(JSON.stringify({ event: "push_capped" }));
    return undefined;
  }
  return {
    toDeviceId: g.id,
    apnsToken: g.apnsToken,
    body: pushText(g.language, scan.status, owner.name, scan.score),
    scanId: scan.id,
  };
}
