import { Hono } from "hono";
import type { AppEnv } from "../env";
import { publicThresholds } from "../db/repo/config";
import { requireDevice } from "../http/auth";

export const config = new Hono<AppEnv>();

/**
 * Dashboard phase 05 (W12, K3): the score thresholds the extension applies, set in the admin
 * dashboard. No user data, so the extension may keep it for an hour (like GET /blocklist).
 */
config.get("/config/public", requireDevice, async (c) => {
  const thresholds = await publicThresholds(c.get("sql"));
  c.header("Cache-Control", "private, max-age=3600");
  return c.json(thresholds);
});
