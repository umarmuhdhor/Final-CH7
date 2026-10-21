import type { Sql, TransactionSql } from "postgres";
import { neverQueue } from "../../data/allowlist";

export type VerdictValue = "safe" | "not_safe";
export interface Verdict {
  value: VerdictValue;
  byDeviceId: string;
  byName: string;
  decidedAt: string;
}

const ISO_MS = `'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'`;
/** New domains one guardian can put in the review queue per 24 h (SECURITY T5, queue flooding). */
export const QUEUE_CAP_PER_DAY = 10;

export type VerdictResult =
  | { verdict: Verdict }
  | { error: "not_found" | "not_allowed" | "not_blocked" };

const lockDomain = (tx: TransactionSql, domain: string) => tx`select pg_advisory_xact_lock(4, hashtext(${domain}))`;

/**
 * POST /verdicts (R2 §5, R4 §4) in one transaction. Lock order everywhere: family_links row,
 * then domain locks (sorted). The link row is read `for share`, so a disconnect cannot commit
 * between the check and the insert. The guardian may decide on its own scans and on scans of
 * its currently linked protected members. Blocklist eligibility is a snapshot taken here.
 */
export async function decideVerdict(
  sql: Sql,
  guardian: { deviceId: string; name: string },
  scanId: string,
  value: VerdictValue,
): Promise<VerdictResult> {
  return sql.begin(async (tx) => {
    const [scan] = await tx<{ ownerId: string; domain: string; status: string; ownerMode: string }[]>`
      select s.owner_id as "ownerId", s.domain, s.status, d.mode as "ownerMode"
      from scans s join devices d on d.id = s.owner_id
      where s.id = ${scanId}`;
    if (!scan) return { error: "not_found" as const };
    let linked = false;
    if (scan.ownerId !== guardian.deviceId) {
      const link = await tx`
        select 1 from family_links where protected_id = ${scan.ownerId} and guardian_id = ${guardian.deviceId} for share`;
      if (link.length === 0) return { error: "not_allowed" as const };
      linked = true;
    }
    if (scan.status !== "blocked") return { error: "not_blocked" as const };

    await lockDomain(tx, scan.domain);
    let eligible = value === "not_safe" && scan.ownerMode === "protected" && linked && !neverQueue(scan.domain);
    if (eligible) {
      const [q] = await tx<{ n: number }[]>`
        select count(distinct domain)::int as n from verdicts
        where by_device_id = ${guardian.deviceId} and global_eligible and value = 'not_safe'
          and decided_at > now() - interval '24 hours' and domain <> ${scan.domain}`;
      eligible = q!.n < QUEUE_CAP_PER_DAY;
    }
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
 * Caller holds the domain lock.
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

/**
 * Deletes verdicts when a relationship or device ends (SECURITY §3 P13, D-alief-B10): a former
 * guardian's decision and name must not stay visible to the member, and the review queue must
 * not keep its support. Approved entries stay served (only `families` changes).
 * Call after the family_links rows are gone (lock order).
 */
export async function dropVerdicts(
  tx: TransactionSql,
  match: { ownerId: string; byDeviceId: string } | { deviceId: string },
): Promise<void> {
  const where =
    "deviceId" in match
      ? tx`owner_id = ${match.deviceId} or by_device_id = ${match.deviceId}`
      : tx`owner_id = ${match.ownerId} and by_device_id = ${match.byDeviceId}`;
  const domains = (await tx<{ domain: string }[]>`select distinct domain from verdicts where ${where} order by domain`)
    .map((r) => r.domain);
  if (domains.length === 0) return;
  for (const d of domains) await lockDomain(tx, d);
  await tx`delete from verdicts where ${where}`;
  for (const d of domains) await recountFamilies(tx, d);
}

/** GET /verdicts: the verdict for (owner = me, domain), or null. */
export async function findVerdict(sql: Sql, ownerId: string, domain: string): Promise<Verdict | null> {
  const [row] = await sql<Verdict[]>`
    select value, by_device_id as "byDeviceId", by_name as "byName",
           to_char(decided_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}) as "decidedAt"
    from verdicts where owner_id = ${ownerId} and domain = ${domain}`;
  return row ?? null;
}
