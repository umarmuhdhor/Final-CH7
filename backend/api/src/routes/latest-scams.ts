import { Hono } from "hono";
import type { AppEnv } from "../env";
import { latestScams } from "../db/repo/latestScams";
import { requireDevice } from "../http/auth";

export const latestScamsRoute = new Hono<AppEnv>();

/**
 * Home "Scam terbaru di pengguna Shoo" (PR-04 / GD-01 card). Kinds of scam that several Shoo users
 * were blocked from this week, newest first. Gates and why: db/repo/latestScams.ts and migration
 * 20261117100000_latest_scams_public.sql. No domain, URL, count or device in the answer.
 *
 * Not user data (a category reaches the answer only once 3+ devices hit it), so a client may keep it
 * for 10 minutes. Not in contracts/api.md yet: backend/API.md "GET /scams/latest".
 */
latestScamsRoute.get("/scams/latest", requireDevice, async (c) => {
  const rows = await latestScams(c.get("sql"));
  c.header("Cache-Control", "private, max-age=600");
  return c.json({
    items: rows.map((r) => ({
      category: r.category,
      title: { en: r.labelEn, id: r.labelId },
      lastSeenAt: r.lastSeenAt,
    })),
  });
});
