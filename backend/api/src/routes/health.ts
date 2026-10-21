import { Hono } from "hono";
import type { AppEnv } from "../env";
import { clientIp, hit, limits } from "../http/rateLimit";

export const health = new Hono<AppEnv>();

health.get("/healthz", (c) => c.json({ ok: true }));

/** Writes ops_heartbeat so the check is real DB activity and keeps Supabase Free awake (R3 §4). */
health.get("/healthz/db", async (c) => {
  const sql = c.get("sql");
  await hit(sql, limits.healthDb, clientIp((n) => c.req.header(n)));
  await sql`insert into ops_heartbeat (source, at) values ('healthz', now())
            on conflict (source) do update set at = now()`;
  return c.json({ ok: true });
});
