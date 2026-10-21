import type { Sql } from "postgres";
import type { Env } from "../env";
import { errorInfo } from "../http/logError";
import { type ScreenshotStore, screenshotStore } from "../services/screenshots";

/**
 * 100 scans per batch = one Storage DELETE (REMOVE_BATCH) per batch; 10 batches keep a run far
 * under the 50 subrequests a Cron may make on Workers Free (D-alief-B12).
 */
const BATCH = 100;
const MAX_BATCHES = 10;

export interface RetentionResult {
  scans: number;
  objects: number;
  backlog: boolean;
  familyCodes: number;
  joinAttempts: number;
  pushLog: number;
  rateLimitHits: number;
}

export interface RetentionOptions {
  batch?: number;
  maxBatches?: number;
  /** Overrides screenshotStore(env); tests only. */
  store?: ScreenshotStore;
  lockTimeoutMs?: number;
}

/**
 * Daily retention (R4 §5, R2 §6): scans + screenshots after 14 days, then the small tables.
 * Verdicts stay (D-alief-14). The heartbeat is written first, so the anti-pause signal never
 * depends on retention succeeding. Each step runs on its own; the first error is rethrown at the
 * end so the Cron event shows the failure. Logs carry counts only.
 */
export async function runRetention(sql: Sql, env: Env, opts: RetentionOptions = {}): Promise<RetentionResult> {
  const result: RetentionResult = {
    scans: 0, objects: 0, backlog: false, familyCodes: 0, joinAttempts: 0, pushLog: 0, rateLimitHits: 0,
  };
  const errors: unknown[] = [];
  const step = async (name: string, run: () => Promise<void>) => {
    try {
      await run();
    } catch (err) {
      errors.push(err);
      console.error(JSON.stringify({ event: "retention_step_failed", step: name, error: errorInfo(err) }));
    }
  };

  await step("heartbeat", async () => {
    await sql`insert into ops_heartbeat (source, at) values ('cron', now()) on conflict (source) do update set at = now()`;
  });
  await step("scans", () => deleteOldScans(sql, opts.store ?? screenshotStore(env), opts, result));
  await step("family_codes", async () => {
    result.familyCodes = (await sql`delete from family_codes where expires_at < now() - interval '1 hour'`).count;
  });
  await step("join_attempts", async () => {
    result.joinAttempts = (await sql`delete from join_attempts where attempted_at < now() - interval '1 day'`).count;
  });
  await step("push_log", async () => {
    // The push cap (notify.ts PUSH_CAP) only looks back 10 minutes.
    result.pushLog = (await sql`delete from push_log where created_at < now() - interval '14 days'`).count;
  });
  await step("rate_limit_hits", async () => {
    // The longest window in limits is 1 h. Chunked: GET /verdicts polling writes many rows.
    for (let i = 0; i < 5; i++) {
      const n = (await sql`
        delete from rate_limit_hits where id in (
          select id from rate_limit_hits where hit_at < now() - interval '1 day' limit 20000)`).count;
      result.rateLimitHits += n;
      if (n < 20000) break;
    }
  });

  console.log(JSON.stringify({ event: "retention", ...result, failed: errors.length }));
  if (errors.length) throw errors[0];
  return result;
}

async function deleteOldScans(
  sql: Sql,
  store: ScreenshotStore | undefined,
  opts: RetentionOptions,
  result: RetentionResult,
): Promise<void> {
  const batch = opts.batch ?? BATCH;
  const maxBatches = opts.maxBatches ?? MAX_BATCHES;
  const lockTimeout = `${opts.lockTimeoutMs ?? 3000}ms`;

  for (let b = 0; b < maxBatches; b++) {
    // No transaction is open across the Storage call. Oldest first (index scans_created).
    const rows = await sql<{ id: string }[]>`
      select id from scans where created_at < now() - interval '14 days'
      order by created_at, id limit ${batch}`;
    if (rows.length === 0) return;
    const ids = rows.map((r) => r.id);

    // Dedupe shares one object between scans of the same owner. Only paths no scan outside this
    // batch points at are removed. No new scan can start sharing them: recentScreenshot reuses
    // paths of scans younger than 24 h only.
    const paths = (
      await sql<{ path: string }[]>`
        select distinct s.screenshot_path as path from scans s
        where s.id in ${sql(ids)} and s.screenshot_path is not null
          and not exists (
            select 1 from scans o
            where o.owner_id = s.owner_id and o.screenshot_path = s.screenshot_path and o.id not in ${sql(ids)})`
    ).map((r) => r.path);

    if (paths.length) {
      // Objects first: if Storage fails the rows stay and the batch is retried tomorrow,
      // so an object never outlives its rows unnoticed (SECURITY §3 P13).
      if (!store) throw new Error("storage not configured");
      await store.remove(paths);
      result.objects += paths.length;
    }

    // Lock order verdict → scan, as in decideVerdict and deleteDevice (fase 10 handoff).
    // A lock timeout or deadlock rolls the batch back; the error stops the loop and is retried tomorrow.
    const deleted = await sql.begin(async (tx) => {
      await tx`select set_config('lock_timeout', ${lockTimeout}, true), set_config('statement_timeout', '20s', true)`;
      await tx`update verdicts set scan_id = null where scan_id in ${tx(ids)}`;
      return (await tx`delete from scans where id in ${tx(ids)} and created_at < now() - interval '14 days'`).count;
    });
    result.scans += deleted;
    if (rows.length < batch) return;
    if (b === maxBatches - 1) result.backlog = true;
  }
}
