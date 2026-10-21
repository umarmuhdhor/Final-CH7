import type { Sql } from "postgres";
import { sha256 } from "./crypto";
import { errors } from "./errors";

export interface Limit {
  bucket: string;
  max: number;
  windowSeconds: number;
}

export const limits = {
  createDevice: { bucket: "devices_create", max: 10, windowSeconds: 3600 },
  healthDb: { bucket: "healthz_db", max: 1, windowSeconds: 60 },
  familyCode: { bucket: "family_code", max: 6, windowSeconds: 60 },
} satisfies Record<string, Limit>;

/**
 * Sliding-window counter in Postgres (R3 §5). Only sha256('<bucket>:<key>') is
 * stored, never the raw IP. An advisory lock per key makes count + insert atomic.
 */
export async function hit(sql: Sql, limit: Limit, key: string): Promise<void> {
  const keyHash = await sha256(`${limit.bucket}:${key}`);
  const retry = await sql.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(hashtextextended(encode(${keyHash}::bytea, 'hex'), 0))`;
    const [row] = await tx<{ n: number; retry: number | null }[]>`
      select count(*)::int as n,
             ceil(extract(epoch from (min(hit_at) + make_interval(secs => ${limit.windowSeconds}) - now())))::int as retry
      from rate_limit_hits
      where bucket = ${limit.bucket} and key_hash = ${keyHash}
        and hit_at > now() - make_interval(secs => ${limit.windowSeconds})`;
    if (row && row.n >= limit.max) return Math.max(1, row.retry ?? limit.windowSeconds);
    await tx`insert into rate_limit_hits (bucket, key_hash) values (${limit.bucket}, ${keyHash})`;
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
