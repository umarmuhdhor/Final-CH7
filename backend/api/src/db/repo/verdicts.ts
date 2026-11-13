import type { Sql, TransactionSql } from "postgres";
import { LOCK } from "../locks";
import { isProtected } from "./domainLists";
import { ISO_MS } from "./scans";
import { lockedUntilSql, withLock } from "./verdictLock";

export type VerdictValue = "safe" | "not_safe";
export interface Verdict {
  value: VerdictValue;
  byDeviceId: string;
  byName: string;
  decidedAt: string;
  /** The link the verdict was made on (origin + path, #241); tells "this link" from "another page of this site". */
  url: string;
  /** #476: only on a `safe` verdict the Guardian cannot change yet (ISO, the next weekly review). */
  lockedUntil?: string;
}

/** New domains one guardian can put in the review queue per 24 h (SECURITY T5, queue flooding). */
export const QUEUE_CAP_PER_DAY = 10;

export type VerdictResult =
  | { verdict: Verdict }
  | { error: "not_found" | "not_allowed" }
  | { error: "locked"; lockedUntil: string };

const lockDomain = async (tx: TransactionSql, domain: string): Promise<void> => {
  await tx`select pg_advisory_xact_lock(${LOCK.verdictDomain}, hashtext(${domain}))`;
};

/**
 * POST /verdicts (R2 §5, R4 §4) in one transaction. Lock order everywhere: family_links row,
 * then the guardian's queue lock (only here), then domain locks (by lock key). The link row is read `for share`, so a disconnect cannot commit
 * between the check and the insert. The guardian may decide on its own scans and on scans of
 * its currently linked protected members, warning or blocked. Blocklist eligibility is a snapshot taken here.
 */
export async function decideVerdict(
  sql: Sql,
  guardian: { deviceId: string; name: string },
  scanId: string,
  value: VerdictValue,
  notes: string | null = null,
): Promise<VerdictResult> {
  return sql.begin(async (tx) => {
    // The link is the scan's url as origin + path (#241). A scan row always has an http(s) url
    // (POST /scans checks it); the front page is only a guard.
    const [scan] = await tx<{ ownerId: string; domain: string; url: string; status: string; ownerMode: string }[]>`
      select s.owner_id as "ownerId", s.domain, s.status, d.mode as "ownerMode",
             coalesce(public.verdict_link(s.url), 'https://' || s.domain || '/') as url
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
    // Warning scans take a verdict too (GD-07, Figma "Detail Aktivitas Waspada", issue #176 comment).

    let eligible = value === "not_safe" && scan.ownerMode === "protected" && linked;
    if (eligible && (await isProtected(tx, scan.domain))) eligible = false;
    // Serializes this guardian's queue count, so parallel verdicts cannot pass the daily cap.
    if (eligible) await tx`select pg_advisory_xact_lock(${LOCK.verdictQueue}, hashtext(${guardian.deviceId}))`;
    await lockDomain(tx, scan.domain);
    // #476: a safe verdict on this link stays until the weekly review has read it, whatever comes next.
    const [held] = await tx<{ lockedUntil: string | null }[]>`
      select ${lockedUntilSql(tx, "value", "decided_at")} as "lockedUntil"
      from verdicts where owner_id = ${scan.ownerId} and url = ${scan.url} for update`;
    if (held?.lockedUntil) return { error: "locked" as const, lockedUntil: held.lockedUntil };
    if (eligible) {
      // A domain this owner already has queued (on any of its links) is not a new one: keep it.
      const [prev] = await tx<{ e: boolean }[]>`
        select exists (select 1 from verdicts
                       where owner_id = ${scan.ownerId} and domain = ${scan.domain} and global_eligible) as e`;
      if (prev!.e) return upsert(tx, scan, scanId, guardian, value, notes, true);
      const [q] = await tx<{ n: number }[]>`
        select count(distinct domain)::int as n from verdicts
        where by_device_id = ${guardian.deviceId} and global_eligible and value = 'not_safe'
          and decided_at > now() - interval '24 hours' and domain <> ${scan.domain}`;
      eligible = q!.n < QUEUE_CAP_PER_DAY; // count(*) always returns one row
    }
    return upsert(tx, scan, scanId, guardian, value, notes, eligible);
  });
}

async function upsert(
  tx: TransactionSql,
  scan: { ownerId: string; domain: string; url: string },
  scanId: string,
  guardian: { deviceId: string; name: string },
  value: VerdictValue,
  notes: string | null,
  eligible: boolean,
): Promise<VerdictResult> {
  // A new decision replaces the old one on that link, its note included (none sent = none kept).
  const [row] = await tx<Verdict[]>`
    insert into verdicts (owner_id, url, domain, value, notes, scan_id, by_device_id, by_name, decided_at, global_eligible)
    values (${scan.ownerId}, ${scan.url}, ${scan.domain}, ${value}, ${notes}, ${scanId}, ${guardian.deviceId},
            ${guardian.name}, clock_timestamp(), ${eligible})
    on conflict (owner_id, url) do update
      set domain = excluded.domain, value = excluded.value, notes = excluded.notes, scan_id = excluded.scan_id,
          by_device_id = excluded.by_device_id, by_name = excluded.by_name, decided_at = excluded.decided_at,
          global_eligible = excluded.global_eligible
    returning value, by_device_id as "byDeviceId", by_name as "byName",
              to_char(decided_at at time zone 'UTC', ${tx.unsafe(ISO_MS)}) as "decidedAt", url,
              ${lockedUntilSql(tx, "value", "decided_at")} as "lockedUntil"`;
  await recountFamilies(tx, scan.domain);
  return { verdict: withLock(row!) };
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
    // Insert or recount. A new row comes back rejected when the reviewer's last decision on the
    // domain was a reject (fase 27c, F-B7): the function reads admin.review_decisions, which
    // shoo_api cannot (migration 20261111100000_queue_blocklist_domain.sql).
    await tx`select public.queue_blocklist_domain(${domain}, ${c!.n})`;
  } else {
    // A queued domain nobody supports any more is browsing history without a purpose (D-alief-40):
    // drop it, rejected or not. Approved or removed rows are the reviewer's record and stay.
    await tx`delete from blocklist_entries where domain = ${domain} and approved_at is null and removed_at is null`;
    await tx`update blocklist_entries set families = 0 where domain = ${domain} and families <> 0`;
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
      ? tx`(owner_id = ${match.deviceId} or by_device_id = ${match.deviceId})`
      : tx`(owner_id = ${match.ownerId} and by_device_id = ${match.byDeviceId})`;
  // Locked in lock-key order, the same order any other transaction would use.
  const domains = (await tx<{ domain: string }[]>`
    select domain from (select distinct domain from verdicts where ${where}) d order by hashtext(domain), domain`)
    .map((r) => r.domain);
  if (domains.length === 0) return;
  for (const d of domains) await lockDomain(tx, d);
  // Rows in (owner_id, url) order, as retention locks them (database review fase 12).
  await tx`select 1 from verdicts where ${where} order by owner_id, url for update`;
  await tx`delete from verdicts where ${where}`;
  for (const d of domains) await recountFamilies(tx, d);
}

/**
 * GET /verdicts?url=&domain= (contracts/api.md, #241), first match wins: a verdict on exactly this
 * link; else a not_safe by this owner on another link of the domain, unless the link is on a shared
 * host (public.verdict_shared); else null. A safe never reaches past its own link.
 */
export async function findVerdict(sql: Sql, ownerId: string, url: string, domain: string): Promise<Verdict | null> {
  const [row] = await sql<Verdict[]>`
    with k as (select public.verdict_link(${url}) as link)
    select v.value, v.by_device_id as "byDeviceId", v.by_name as "byName",
           to_char(v.decided_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}) as "decidedAt", v.url,
           ${lockedUntilSql(sql, "v.value", "v.decided_at")} as "lockedUntil"
    from verdicts v, k
    where v.owner_id = ${ownerId}
      and (v.url = k.link
           or (v.domain = ${domain} and v.value = 'not_safe' and not public.verdict_shared(k.link, ${domain})))
    order by (v.url = k.link) desc, v.decided_at desc
    limit 1`;
  return row ? withLock(row) : null;
}

/**
 * GET /verdicts?domain= (deprecated, builds from before #241): any not_safe on the domain, else the
 * newest safe. Goes once the last older build is gone.
 */
export async function findDomainVerdict(sql: Sql, ownerId: string, domain: string): Promise<Verdict | null> {
  const [row] = await sql<Verdict[]>`
    select value, by_device_id as "byDeviceId", by_name as "byName",
           to_char(decided_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}) as "decidedAt", url,
           ${lockedUntilSql(sql, "value", "decided_at")} as "lockedUntil"
    from verdicts where owner_id = ${ownerId} and domain = ${domain}
    order by (value = 'not_safe') desc, decided_at desc
    limit 1`;
  return row ? withLock(row) : null;
}
