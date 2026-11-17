import type { Sql } from "postgres";

/**
 * Gates for the Home card "Scam terbaru di pengguna Shoo" (GET /scams/latest). They keep the card
 * from turning into a spam channel or a way to single someone out:
 * - only domains a named admin approved onto the blocklist, with the admin's category
 *   (admin.v_scam_categories_public): a client can never put a domain, page title or word on the card;
 * - only `blocked` scans, timed by the server (`created_at`), never the client's `detectedAt`;
 * - a device counts once per category, and only after it is a day old (fresh throwaway devices count
 *   for nothing), and a category needs MIN_DEVICES different devices before it shows (k-anonymity);
 * - one row per category, newest first, at most LIMIT rows.
 */
export const LATEST_SCAMS = {
  windowDays: 7,
  minDevices: 3,
  minDeviceAgeHours: 24,
  limit: 4,
} as const;

export interface LatestScamRow {
  category: string;
  labelEn: string;
  labelId: string;
  /** ISO 8601 UTC, rounded down to the hour: the card only says "today" / "yesterday". */
  lastSeenAt: string;
}

export async function latestScams(sql: Sql): Promise<LatestScamRow[]> {
  const { windowDays, minDevices, minDeviceAgeHours, limit } = LATEST_SCAMS;
  return sql<LatestScamRow[]>`
    select v.category, v.label_en as "labelEn", v.label_id as "labelId",
      to_char(date_trunc('hour', max(s.created_at) at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as "lastSeenAt"
    from scans s
    join devices d on d.id = s.owner_id
    join admin.v_scam_categories_public v
      on s.domain = v.domain or right(s.domain, length(v.domain) + 1) = '.' || v.domain
    where s.status = 'blocked'
      and s.created_at > now() - make_interval(days => ${windowDays})
      and d.created_at < now() - make_interval(hours => ${minDeviceAgeHours})
    group by v.category, v.label_en, v.label_id
    having count(distinct s.owner_id) >= ${minDevices}
    order by max(s.created_at) desc, v.category
    limit ${limit}`;
}
