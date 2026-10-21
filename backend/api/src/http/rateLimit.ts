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
} satisfies Record<string, Limit>;

/**
 * Sliding-window counter in Postgres (R3 §5). Only sha256('<bucket>:<key>') is
 * stored, never the raw IP. Best effort: concurrent requests may slip one over.
 */
export async function hit(sql: Sql, limit: Limit, key: string): Promise<void> {
  const keyHash = await sha256(`${limit.bucket}:${key}`);
  const [row] = await sql<{ n: number; retry: number | null }[]>`
    select count(*)::int as n,
           ceil(extract(epoch from (min(hit_at) + make_interval(secs => ${limit.windowSeconds}) - now())))::int as retry
    from rate_limit_hits
    where bucket = ${limit.bucket} and key_hash = ${keyHash}
      and hit_at > now() - make_interval(secs => ${limit.windowSeconds})`;
  if (row && row.n >= limit.max) throw errors.rateLimited(Math.max(1, row.retry ?? limit.windowSeconds));
  await sql`insert into rate_limit_hits (bucket, key_hash) values (${limit.bucket}, ${keyHash})`;
}

export const clientIp = (header: (name: string) => string | undefined) =>
  header("cf-connecting-ip") ?? "unknown";
