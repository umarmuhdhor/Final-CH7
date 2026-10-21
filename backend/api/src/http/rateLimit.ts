import type { Sql } from "postgres";
import { keyHash } from "./keyHash";
import { errors } from "./errors";

export interface Limit {
  bucket: string;
  max: number;
  windowSeconds: number;
}

export const limits = {
  createDevice: { bucket: "devices_create", max: 10, windowSeconds: 3600 },
  // All callers together, key "all" (D-alief-B12): rotating IPs cannot fill the free-tier DB.
  // 1000/day is far above a demo's sign-ups; reaching it blocks new devices only, not existing ones.
  createDeviceAll: { bucket: "devices_create_all", max: 1000, windowSeconds: 86400 },
  healthDb: { bucket: "healthz_db", max: 1, windowSeconds: 60 },
  familyCode: { bucket: "family_code", max: 6, windowSeconds: 60 },
  createScan: { bucket: "scans_create", max: 120, windowSeconds: 3600 },
  // All devices together, key "all", checked with hitLight (D-alief-B12): bounds what retention
  // must delete per day (50 000 plain scans/day) far above what a demo produces.
  createScanAll: { bucket: "scans_create_all", max: 2000, windowSeconds: 3600 },
  viewScreenshot: { bucket: "screenshots_view", max: 120, windowSeconds: 60 },
  createVerdict: { bucket: "verdicts_create", max: 60, windowSeconds: 60 },
  // EX-06 polls every 5 s per open block screen (several tabs), plus one lookup per page (SECURITY T10).
  getVerdict: { bucket: "verdicts_get", max: 30, windowSeconds: 10 },
  // Unknown bearer tokens per IP (D-alief-B05): guessing a 256-bit token is hopeless, this caps the DB cost.
  authFail: { bucket: "auth_fail", max: 60, windowSeconds: 600 },
} satisfies Record<string, Limit>;

/**
 * Same sliding window in one statement (one round trip instead of five), for the hot polling
 * path GET /verdicts (R3 §5 "best effort", D-alief-B10): parallel requests may overshoot `max` by
 * a few. Never use it for limits that guard against guessing or abuse; capacity caps such as
 * scans_create_all are fine.
 */
export async function hitLight(sql: Sql, limit: Limit, key: string): Promise<void> {
  const keyHashed = await keyHash(`${limit.bucket}:${key}`);
  const [row] = await sql<{ n: number; retry: number | null }[]>`
    with recent as (
      select count(*)::int as n,
             ceil(extract(epoch from (min(hit_at) + make_interval(secs => ${limit.windowSeconds}) - now())))::int as retry
      from rate_limit_hits
      where bucket = ${limit.bucket} and key_hash = ${keyHashed}
        and hit_at > now() - make_interval(secs => ${limit.windowSeconds})
    ), added as (
      -- Never referenced: Postgres runs data-modifying CTEs anyway, in the same statement.
      insert into rate_limit_hits (bucket, key_hash)
      select ${limit.bucket}, ${keyHashed} from recent where n < ${limit.max}
    )
    select n, retry from recent`;
  if (row && row.n >= limit.max) throw errors.rateLimited(Math.max(1, row.retry ?? limit.windowSeconds));
}

/**
 * Sliding-window counter in Postgres (R3 §5). Only keyHash('<bucket>:<key>') (HMAC, D-alief-B12)
 * is stored, never the raw IP. An advisory lock per key makes count + insert atomic.
 */
export async function hit(sql: Sql, limit: Limit, key: string): Promise<void> {
  const keyHashed = await keyHash(`${limit.bucket}:${key}`);
  const retry = await sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(hashtextextended(encode(${keyHashed}::bytea, 'hex'), 0))`;
    const [row] = await tx<{ n: number; retry: number | null }[]>`
      select count(*)::int as n,
             ceil(extract(epoch from (min(hit_at) + make_interval(secs => ${limit.windowSeconds}) - now())))::int as retry
      from rate_limit_hits
      where bucket = ${limit.bucket} and key_hash = ${keyHashed}
        and hit_at > now() - make_interval(secs => ${limit.windowSeconds})`;
    if (row && row.n >= limit.max) return Math.max(1, row.retry ?? limit.windowSeconds);
    await tx`insert into rate_limit_hits (bucket, key_hash) values (${limit.bucket}, ${keyHashed})`;
    return null;
  });
  if (retry !== null) throw errors.rateLimited(retry);
}

/**
 * Rate-limit key for the caller. IPv6 is cut to its /64, because one subscriber
 * usually holds a whole /64 and could otherwise rotate addresses per request.
 */
export function clientIp(header: (name: string) => string | undefined): string {
  const ip = header("cf-connecting-ip") ?? "unknown";
  return ip.includes(":") ? ipv6Prefix64(ip) : ip;
}

function ipv6Prefix64(ip: string): string {
  const lower = ip.toLowerCase();
  // IPv4-mapped (::ffff:a.b.c.d) is really an IPv4 client.
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/.exec(lower);
  if (mapped) return mapped[1]!;
  const [head = "", tail] = lower.split("::");
  const left = head ? head.split(":") : [];
  const right = tail ? tail.split(":") : [];
  const fill = Math.max(0, 8 - left.length - right.length);
  const groups = tail === undefined ? left : [...left, ...Array<string>(fill).fill("0"), ...right];
  return `${groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, "")).join(":")}::/64`;
}
