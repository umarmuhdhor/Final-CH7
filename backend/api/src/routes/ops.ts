import { Hono } from "hono";
import type { AppEnv } from "../env";
import { opsSnapshot } from "../db/repo/ops";
import { usableSecret } from "../http/crypto";
import { errors } from "../http/errors";
import { hit, limits } from "../http/rateLimit";
import { evaluate } from "../services/opsStatus";

export const ops = new Hono<AppEnv>();

const encoder = new TextEncoder();
const digest = async (text: string) => crypto.subtle.digest("SHA-256", encoder.encode(text));

/**
 * Constant-time compare of the bearer value with OPS_STATUS_TOKEN (fase 21 K6): both sides are
 * hashed first, so timingSafeEqual always compares 32 bytes and the length leaks nothing. The hashes
 * run even without a usable secret (< 32 characters never matches), so the timing does not tell
 * whether the secret is set.
 */
async function authorized(secret: string | undefined, header: string | undefined): Promise<boolean> {
  const usable = usableSecret(secret);
  const bearer = header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  const [a, b] = await Promise.all([digest(bearer), digest(usable ?? "")]);
  const same = crypto.subtle.timingSafeEqual(a, b);
  return same && usable !== undefined && bearer !== "";
}

const hours = (h: number | null) => (h === null ? null : Math.round(h * 10) / 10);

/**
 * Internal health check for the ops-watch workflow and Alief (fase 21a, B9). Not a client endpoint,
 * not in contracts/. Without the right token it is indistinguishable from an unknown path and
 * touches no table (the rate limit counts only authorized calls, so nobody can use up the 30/h of
 * the workflow). Aggregates only (SECURITY §3 P6).
 */
ops.get("/ops/status", async (c) => {
  if (!(await authorized(c.env.OPS_STATUS_TOKEN, c.req.header("authorization")))) throw errors.notFound();
  const sql = c.get("sql");
  await hit(sql, limits.opsStatus, "all");
  const s = await opsSnapshot(sql);
  const { ok, failing } = evaluate(s);
  return c.json({
    ok,
    failing,
    jobs: {
      retention: {
        ageHours: hours(s.retention.ageHours), okAgeHours: hours(s.retention.okAgeHours),
        failed: s.retention.failed, backlog: s.retention.backlog,
      },
      notifications: { ageHours: hours(s.notifications.ageHours), okAgeHours: hours(s.notifications.okAgeHours) },
    },
    dbBytes: s.dbBytes,
    blocklistQueue: s.blocklistQueue,
    blocklistOldestHours: hours(s.blocklistOldestHours),
    tombstonesStuck: s.tombstonesStuck,
    healthzAgeHours: hours(s.healthzAgeHours),
  });
});
