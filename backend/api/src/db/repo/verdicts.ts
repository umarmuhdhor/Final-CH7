import type { Sql, TransactionSql } from "postgres";
import { isAllowlisted } from "../../data/allowlist";

export type VerdictValue = "safe" | "not_safe";
export interface Verdict {
  value: VerdictValue;
  byDeviceId: string;
  byName: string;
  decidedAt: string;
}

const ISO_MS = `'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'`;

export type VerdictResult =
  | { verdict: Verdict }
  | { error: "not_found" | "not_allowed" | "not_blocked" };

/**
 * POST /verdicts (R2 §5, R4 §4) in one transaction, locked per domain so `families` counts stay
 * exact under parallel verdicts. The guardian may decide on its own scans and on scans of its
 * currently linked protected members. Blocklist eligibility is a snapshot taken here.
 */
export async function decideVerdict(
  sql: Sql,
  guardian: { deviceId: string; name: string },
  scanId: string,
  value: VerdictValue,
): Promise<VerdictResult> {
  return sql.begin(async (tx) => {
    const [scan] = await tx<{ ownerId: string; domain: string; status: string; ownerMode: string; linked: boolean }[]>`
      select s.owner_id as "ownerId", s.domain, s.status, d.mode as "ownerMode",
             exists (select 1 from family_links l
                     where l.protected_id = s.owner_id and l.guardian_id = ${guardian.deviceId}) as linked
      from scans s join devices d on d.id = s.owner_id
      where s.id = ${scanId}`;
    if (!scan) return { error: "not_found" as const };
    if (scan.ownerId !== guardian.deviceId && !scan.linked) return { error: "not_allowed" as const };
    if (scan.status !== "blocked") return { error: "not_blocked" as const };

    await tx`select pg_advisory_xact_lock(4, hashtext(${scan.domain}))`;
    const eligible = value === "not_safe" && scan.ownerMode === "protected" && scan.linked && !isAllowlisted(scan.domain);
    const [row] = await tx<Verdict[]>`
      insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name, decided_at, global_eligible)
      values (${scan.ownerId}, ${scan.domain}, ${value}, ${scanId}, ${guardian.deviceId}, ${guardian.name},
              clock_timestamp(), ${eligible})
      on conflict (owner_id, domain) do update
        set value = excluded.value, scan_id = excluded.scan_id, by_device_id = excluded.by_device_id,
            by_name = excluded.by_name, decided_at = excluded.decided_at, global_eligible = excluded.global_eligible
      returning value, by_device_id as "byDeviceId", by_name as "byName",
                to_char(decided_at at time zone 'UTC', ${tx.unsafe(ISO_MS)}) as "decidedAt"`;
    await recountFamilies(tx, scan.domain);
    return { verdict: row! };
  });
}

/**
 * R2 §5 butir 2–3: queue a domain once it has an eligible not_safe verdict; otherwise only keep
 * an existing row's count current. Approval and removal stay with the reviewer.
 */
async function recountFamilies(tx: TransactionSql, domain: string): Promise<void> {
  const [c] = await tx<{ n: number }[]>`
    select count(distinct by_device_id)::int as n from verdicts
    where domain = ${domain} and value = 'not_safe' and global_eligible`;
  if (c!.n > 0) {
    await tx`insert into blocklist_entries (domain, families) values (${domain}, ${c!.n})
             on conflict (domain) do update set families = excluded.families`;
  } else {
    await tx`update blocklist_entries set families = 0 where domain = ${domain}`;
  }
}

/** GET /verdicts: the verdict for (owner = me, domain), or null. */
export async function findVerdict(sql: Sql, ownerId: string, domain: string): Promise<Verdict | null> {
  const [row] = await sql<Verdict[]>`
    select value, by_device_id as "byDeviceId", by_name as "byName",
           to_char(decided_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}) as "decidedAt"
    from verdicts where owner_id = ${ownerId} and domain = ${domain}`;
  return row ?? null;
}
