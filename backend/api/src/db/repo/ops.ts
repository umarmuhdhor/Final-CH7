import type { Sql } from "postgres";

export type OpsJob = "retention" | "notifications";

/** Writes ops_jobs (fase 21a). The crons take it as an option so tests can make it fail. */
export interface OpsWriter {
  start(sql: Sql, job: OpsJob): Promise<void>;
  finish(sql: Sql, job: OpsJob, run: { failed: number; backlog: boolean }): Promise<void>;
}

export async function startJob(sql: Sql, job: OpsJob): Promise<void> {
  await sql`insert into ops_jobs (job, started_at) values (${job}, now())
            on conflict (job) do update set started_at = now()`;
}

/** ok_at moves only on a clean run, so a failing job grows stale even while it keeps running. */
export async function finishJob(sql: Sql, job: OpsJob, run: { failed: number; backlog: boolean }): Promise<void> {
  await sql`
    insert into ops_jobs (job, failed, backlog, finished_at, ok_at)
    values (${job}, ${run.failed}, ${run.backlog}, now(), case when ${run.failed} = 0 then now() end)
    on conflict (job) do update set
      failed = excluded.failed, backlog = excluded.backlog, finished_at = excluded.finished_at,
      ok_at = coalesce(excluded.ok_at, ops_jobs.ok_at)`;
}

export const opsWriter: OpsWriter = { start: startJob, finish: finishJob };

/** Aggregate numbers only (SECURITY §3 P6): no id, domain, path or name ever leaves this query. Ages in hours, DB clock. */
export interface OpsSnapshot {
  retention: { okAgeHours: number | null; ageHours: number | null; failed: number; backlog: boolean };
  notifications: { okAgeHours: number | null; ageHours: number | null };
  /** A scan older than 15 days 6 hours exists (retention promises 14 days; 6 h margin for a late Cron). */
  scansOverdue: boolean;
  /** Tombstones older than 2 days: objects retention keeps failing to remove. */
  tombstonesStuck: number;
  dbBytes: number;
  /** Undecided blocklist domains with support (D9, ref/R2-skema-db.md:187). */
  blocklistQueue: number;
  blocklistOldestHours: number | null;
  /** Last /healthz/db (the ops-watch keep-alive): a number for the reader, never an alert. */
  healthzAgeHours: number | null;
}

/** One round trip. `exists` on scans uses the index scans_created. */
export async function opsSnapshot(sql: Sql): Promise<OpsSnapshot> {
  const [r] = await sql<{
    rOk: number | null; rAge: number | null; rFailed: number | null; rBacklog: boolean | null;
    nOk: number | null; nAge: number | null;
    overdue: boolean; stuck: number; dbBytes: number; queue: number; oldest: number | null; healthz: number | null;
  }[]>`
    select
      (extract(epoch from now() - r.ok_at) / 3600)::float8 as "rOk",
      (extract(epoch from now() - r.finished_at) / 3600)::float8 as "rAge",
      r.failed as "rFailed", r.backlog as "rBacklog",
      (extract(epoch from now() - n.ok_at) / 3600)::float8 as "nOk",
      (extract(epoch from now() - n.finished_at) / 3600)::float8 as "nAge",
      exists (select 1 from scans where created_at < now() - interval '15 days 6 hours') as overdue,
      (select count(*)::int from storage_tombstones where created_at < now() - interval '2 days') as stuck,
      pg_database_size(current_database())::float8 as "dbBytes",
      q.n as queue, (extract(epoch from now() - q.oldest) / 3600)::float8 as oldest,
      (select (extract(epoch from now() - at) / 3600)::float8 from ops_heartbeat where source = 'healthz') as healthz
    from (select 1) one
    left join ops_jobs r on r.job = 'retention'
    left join ops_jobs n on n.job = 'notifications'
    cross join (
      -- The D9 review queue (ref/R2-skema-db.md:187 + rejected_at).
      select count(*)::int as n, min(first_seen_at) as oldest from blocklist_entries
      where approved_at is null and rejected_at is null and removed_at is null and families > 0
    ) q`;
  return {
    retention: { okAgeHours: r!.rOk, ageHours: r!.rAge, failed: r!.rFailed ?? 0, backlog: r!.rBacklog ?? false },
    notifications: { okAgeHours: r!.nOk, ageHours: r!.nAge },
    scansOverdue: r!.overdue,
    tombstonesStuck: r!.stuck,
    dbBytes: r!.dbBytes,
    blocklistQueue: r!.queue,
    blocklistOldestHours: r!.oldest,
    healthzAgeHours: r!.healthz,
  };
}
