import type { PendingQuery, Row, Sql } from "postgres";
import { opsWriter, type OpsWriter } from "../db/repo/ops";
import type { Env, Language } from "../env";
import { errorInfo } from "../http/logError";
import { deliverPush } from "../services/push/deliver";
import { protectionOffText, summaryText } from "../services/push/messages";
import { isQuiet, localTime, type QuietHours } from "../services/push/quiet";
import { pushSender, type PushMessage, type PushSender } from "../services/push/sender";

// Ids are passed as one comma-joined text and split in SQL: device ids are UUIDs and days are
// YYYY-MM-DD, neither contains a comma.

/**
 * Pushes per run, both kinds together: each APNs send is a subrequest, and a Cron on Workers Free
 * may make 50. What is left over goes out on the next hourly run (nothing is claimed for it).
 */
const MAX_PUSHES = 40;
/** "Setiap Senin, 08.00" (Figma): Monday from 08:00 local time. */
const SUMMARY_WEEKDAY = 1;
const SUMMARY_FROM = 8 * 60;

export interface NotificationsResult {
  protectionOff: number;
  summaries: number;
}

interface Candidate extends QuietHours {
  id: string;
}

/**
 * Hourly (wrangler.jsonc triggers.crons): "Perlindungan mati" and "Ringkasan mingguan" (PF-01,
 * proposed). Rows are claimed before sending, so an overlapping run never pushes twice; a claimed
 * push that then fails is not retried (same as the scan push).
 */
export async function runNotifications(
  sql: Sql, env: Env, opts: { sender?: PushSender; now?: Date; ops?: OpsWriter } = {},
): Promise<NotificationsResult> {
  const now = opts.now ?? new Date();
  const sender = opts.sender ?? pushSender(env);
  const ops = opts.ops ?? opsWriter;
  await writeOps(() => ops.start(sql, "notifications"));
  const off = await protectionOff(sql, now, MAX_PUSHES);
  const summaries = await weeklySummaries(sql, now, MAX_PUSHES - off.length);
  const messages = [...off, ...summaries];
  // A run fails (fase 21a, ops_jobs) on pushes that threw or found the APNs config broken. An APNs
  // rejection of one device (bad or expired token) is normal and only lands in push_log.
  let failed = 0;
  for (const m of messages) {
    try {
      if ((await deliverPush(sql, sender, m)) === "failed:config") failed++;
    } catch (err) {
      failed++;
      console.error(JSON.stringify({ event: "push_failed", source: "cron", error: errorInfo(err) }));
    }
  }
  const result = { protectionOff: off.length, summaries: summaries.length };
  await writeOps(() => ops.finish(sql, "notifications", { failed, backlog: false }));
  console.log(JSON.stringify({ event: "notifications", ...result }));
  return result;
}

/** A failed status write never fails the pushes (fase 21a): logged, then the run goes on. */
async function writeOps(write: () => Promise<void>): Promise<void> {
  try {
    await write();
  } catch (err) {
    console.error(JSON.stringify({ event: "ops_job_write_failed", job: "notifications", error: errorInfo(err) }));
  }
}

/**
 * isQuiet (services/push/quiet.ts) in SQL, for the device columns of alias `g` at the injected `now`:
 * local minutes in the device's zone, a window that may cross midnight, start = end = all day. An
 * unknown zone falls back to WIB like localTime does, instead of failing the whole query. The name
 * matches without case, as Intl accepts it (PATCH /devices/me stores what Intl took). Lets the cron
 * filter quiet hours before its limit (fase 27k F-N10).
 * The zone map is an uncorrelated subquery, so Postgres builds it once per query (an InitPlan; the
 * pg_timezone_names scan takes ~15 ms), and `offset 0` keeps the local time from being inlined into
 * each comparison. EXPLAIN ANALYZE on 10k rows: one scan, 24 ms in all.
 */
export function quietSql(sql: Sql, now: Date): PendingQuery<Row[]> {
  return sql`(g.quiet_hours and (
    select g.quiet_start = g.quiet_end
        or (g.quiet_start < g.quiet_end and x.m >= g.quiet_start and x.m < g.quiet_end)
        or (g.quiet_start > g.quiet_end and (x.m >= g.quiet_start or x.m < g.quiet_end))
    from (select (extract(hour from t.local) * 60 + extract(minute from t.local))::int as m
          from (select ${now.toISOString()}::timestamptz at time zone coalesce(
                  (select jsonb_object_agg(lower(z.name), z.name) from pg_timezone_names z) ->> lower(g.time_zone),
                  'Asia/Jakarta') as local offset 0) t) x))`;
}

/**
 * A member whose extension has not reported for 24 h ("Ekstensi mati", same rule as
 * GET /family/members) is pushed to the guardian once per off period. The mark clears when the
 * member reports again. A member that never reported is not "off" (contract: no evidence).
 */
async function protectionOff(sql: Sql, now: Date, limit: number): Promise<PushMessage[]> {
  await sql`
    update family_links l set off_notified_at = null
    from devices m
    where m.id = l.protected_id and l.off_notified_at is not null
      and m.ext_last_seen_at > now() - interval '24 hours'`;
  if (limit <= 0) return [];
  // Quiet hours: not claimed, so the next run after the window sends it. Filtered before the limit,
  // so guardians inside their window cannot fill it and starve one outside (F-N10).
  const due = await sql<{ protectedId: string }[]>`
    select l.protected_id as "protectedId"
    from family_links l
    join devices m on m.id = l.protected_id
    join devices g on g.id = l.guardian_id
    where l.off_notified_at is null
      and m.ext_last_seen_at <= now() - interval '24 hours'
      and g.notify_protection_off and g.apns_token is not null
      and not ${quietSql(sql, now)}
    order by m.ext_last_seen_at, l.protected_id
    limit ${limit}`;
  if (due.length === 0) return [];
  const claimed = await sql<{ guardianId: string; apnsToken: string; language: Language; member: string }[]>`
    update family_links l set off_notified_at = now()
    from devices m, devices g, unnest(string_to_array(${due.map((r) => r.protectedId).join(",")}, ',')) as v(id)
    where l.protected_id = v.id and m.id = l.protected_id and g.id = l.guardian_id
      and l.off_notified_at is null
      and m.ext_last_seen_at <= now() - interval '24 hours'
      and g.notify_protection_off and g.apns_token is not null
    returning g.id as "guardianId", g.apns_token as "apnsToken", g.language, m.name as member`;
  return claimed.map((r) => ({ toDeviceId: r.guardianId, apnsToken: r.apnsToken, body: protectionOffText(r.language, r.member) }));
}

/**
 * Monday from 08:00 local (outside quiet hours), once per local Monday: the last 7 days of
 * blocked and warned sites, the guardian's members included. Counts only, no sites.
 */
async function weeklySummaries(sql: Sql, now: Date, limit: number): Promise<PushMessage[]> {
  if (limit <= 0) return [];
  const rows = await sql<(Candidate & { sentOn: string | null })[]>`
    select id, quiet_hours as "quietHours", quiet_start as "quietStart", quiet_end as "quietEnd",
           time_zone as "timeZone", to_char(summary_sent_on, 'YYYY-MM-DD') as "sentOn"
    from devices
    where weekly_summary and apns_token is not null
      and (summary_sent_on is null or summary_sent_on < (now() at time zone 'UTC')::date - 1)`;
  const due: { id: string; day: string }[] = [];
  for (const r of rows) {
    const t = localTime(r.timeZone, now);
    if (t.weekday !== SUMMARY_WEEKDAY || t.minutes < SUMMARY_FROM || r.sentOn === t.date || isQuiet(r, now)) continue;
    due.push({ id: r.id, day: t.date });
    if (due.length >= limit) break;
  }
  if (due.length === 0) return [];
  const claimed = await sql<{ id: string; apnsToken: string; language: Language; blocked: number; warnings: number; family: boolean }[]>`
    update devices d set summary_sent_on = v.day
    from unnest(string_to_array(${due.map((d) => d.id).join(",")}, ','), string_to_array(${due.map((d) => d.day).join(",")}, ',')::date[]) as v(id, day)
    where d.id = v.id and d.weekly_summary and d.apns_token is not null
      and d.summary_sent_on is distinct from v.day
    returning d.id, d.apns_token as "apnsToken", d.language,
      (select count(*)::int from scans s
        where s.status = 'blocked' and s.detected_at > now() - interval '7 days'
          and (s.owner_id = d.id or s.owner_id in (select protected_id from family_links where guardian_id = d.id))) as blocked,
      (select count(*)::int from scans s
        where s.status = 'warning' and s.detected_at > now() - interval '7 days'
          and (s.owner_id = d.id or s.owner_id in (select protected_id from family_links where guardian_id = d.id))) as warnings,
      exists (select 1 from family_links where guardian_id = d.id) as family`;
  return claimed.map((r) => ({ toDeviceId: r.id, apnsToken: r.apnsToken, body: summaryText(r.language, r) }));
}
