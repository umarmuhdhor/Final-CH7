import type { Sql } from "postgres";

/** Per owner and over all owners, per 24 hours (services/fragments.ts FRAGMENT_QUOTA). */
export interface FragmentQuota {
  owner: number;
  ownerBytes: number;
  global: number;
  globalBytes: number;
}

export type FragmentQuotaReason = "owner" | "owner_bytes" | "global" | "global_bytes";

export type FragmentSlot = { ok: true } | { gone: true } | { taken: true } | { quota: FragmentQuotaReason };

/**
 * ADM-07 (fase 07a K5, K6): sets scans.fragments_bytes for a scan that has none yet, if the 24-hour
 * quotas still have room; the admin_scan_fragments trigger copies the key to admin.scan_archive.
 * One statement reading the index scans_fragments. Two uploads racing may both pass the last slot:
 * the quota is an abuse bound, not an exact count (no per-owner lock on this path).
 */
export async function reserveFragments(
  sql: Sql,
  scan: { id: string; ownerId: string },
  bytes: number,
  q: FragmentQuota,
): Promise<FragmentSlot> {
  const [r] = await sql<{ done: number; present: boolean; empty: boolean; n_owner: number; b_owner: number; n_all: number; b_all: number }[]>`
    with u as (
      select count(*) filter (where owner_id = ${scan.ownerId})::int as n_owner,
             coalesce(sum(fragments_bytes) filter (where owner_id = ${scan.ownerId}), 0)::int as b_owner,
             count(*)::int as n_all,
             coalesce(sum(fragments_bytes), 0)::bigint as b_all
        from scans where fragments_bytes is not null and created_at > now() - interval '24 hours'
    ), upd as (
      update scans s set fragments_bytes = ${bytes}
        from u
       where s.id = ${scan.id} and s.owner_id = ${scan.ownerId} and s.fragments_bytes is null
         and u.n_owner < ${q.owner} and u.b_owner + ${bytes} <= ${q.ownerBytes}
         and u.n_all < ${q.global} and u.b_all + ${bytes} <= ${q.globalBytes}
      returning s.id
    )
    select (select count(*) from upd)::int as done,
           exists (select 1 from scans where id = ${scan.id} and owner_id = ${scan.ownerId}) as present,
           exists (select 1 from scans where id = ${scan.id} and owner_id = ${scan.ownerId} and fragments_bytes is null) as empty,
           u.n_owner, u.b_owner, u.n_all, u.b_all::float8 as b_all
      from u`;
  if (!r) return { gone: true };
  if (r.done > 0) return { ok: true };
  if (!r.present) return { gone: true };
  if (!r.empty) return { taken: true };
  if (r.n_owner >= q.owner) return { quota: "owner" };
  if (r.b_owner + bytes > q.ownerBytes) return { quota: "owner_bytes" };
  if (r.n_all >= q.global) return { quota: "global" };
  return { quota: "global_bytes" };
}

/** After a failed upload: the archive row must not point at an object that is not there. */
export async function clearFragments(sql: Sql, scan: { id: string; ownerId: string }): Promise<void> {
  await sql`update scans set fragments_bytes = null where id = ${scan.id} and owner_id = ${scan.ownerId}`;
}
