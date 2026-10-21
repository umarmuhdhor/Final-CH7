import type { Sql } from "postgres";
import type { Language, Principal } from "../../env";
import { pushText } from "./messages";
import type { PushMessage } from "./sender";

/**
 * R4 §3: the push for a protected device's scan, addressed to its guardian, or undefined
 * (guardian's own scan, no guardian, or no APNs token). Guardians' own scans never push.
 */
export async function guardianPush(
  sql: Sql,
  owner: Principal,
  scan: { id: string; status: "blocked" | "warning"; score: number },
): Promise<PushMessage | undefined> {
  if (owner.mode !== "protected") return undefined;
  const [g] = await sql<{ id: string; apnsToken: string | null; language: Language }[]>`
    select d.id, d.apns_token as "apnsToken", d.language
    from family_links l join devices d on d.id = l.guardian_id
    where l.protected_id = ${owner.deviceId}`;
  if (!g?.apnsToken) return undefined;
  return {
    toDeviceId: g.id,
    apnsToken: g.apnsToken,
    body: pushText(g.language, scan.status, owner.name, scan.score),
    scanId: scan.id,
  };
}
