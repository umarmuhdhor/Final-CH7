import type { Sql } from "postgres";
import type { Env, Language, Principal } from "../../env";
import { pushText } from "./messages";
import { pushSender } from "./sender";

/** R4 §3: a protected device's scan notifies its guardian. Guardians' own scans never push. */
export async function notifyGuardian(
  sql: Sql,
  env: Env,
  owner: Principal,
  scan: { id: string; status: "blocked" | "warning"; score: number },
): Promise<void> {
  if (owner.mode !== "protected") return;
  const [g] = await sql<{ id: string; apnsToken: string | null; language: Language }[]>`
    select d.id, d.apns_token as "apnsToken", d.language
    from family_links l join devices d on d.id = l.guardian_id
    where l.protected_id = ${owner.deviceId}`;
  if (!g?.apnsToken) return;
  await pushSender(env).send({
    toDeviceId: g.id,
    apnsToken: g.apnsToken,
    body: pushText(g.language, scan.status, owner.name, scan.score),
    scanId: scan.id,
  });
}
