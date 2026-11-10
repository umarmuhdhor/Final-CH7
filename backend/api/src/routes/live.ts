import { Hono } from "hono";
import * as z from "zod";
import type { AppEnv } from "../env";
import { requireDevice } from "../http/auth";
import { hitEdge, limits } from "../http/rateLimit";
import { DOMAIN, readJson } from "../http/validate";
import { relayLive } from "../services/push/live";
import { liveSender } from "../services/push/sender";

const liveBody = z
  .object({
    // Registrable domain only (same rule as verdicts/scans), never a URL.
    domain: z.string().max(253).regex(DOMAIN, "must be a registrable domain"),
    score: z.number().int().min(0).max(100),
    status: z.enum(["normal", "warning", "blocked"]),
    analyzing: z.boolean(),
    open: z.boolean(),
  })
  .strict();

export const live = new Hono<AppEnv>();

/**
 * EX-03 path C (#49): the extension's live score, forwarded to the Dynamic Island. Sent only while
 * the online check is on (the extension's rule, same as /analyze). Domain and score go into the APNs
 * payload only: no table row, and the log line carries kind + result, never the page (#49 decision 3).
 * Answered after the push, so one device's calls stay in order (start before update before end).
 */
live.post("/live", requireDevice, async (c) => {
  const body = await readJson(c, liveBody);
  const sql = c.get("sql");
  const { deviceId } = c.get("principal");
  // Ending the island is never rate limited: a dropped end would leave a stale score on screen.
  // It is cheap to allow: only one end per activity ever reaches APNs (the update token is cleared).
  if (body.open) await hitEdge(c.env.LIVE_PUSH_LIMITER, sql, limits.livePush, deviceId);
  const { kind, result, reason } = await relayLive(sql, liveSender(c.env), deviceId, body);
  console.log(JSON.stringify({ event: "live_push", kind, ...(result ? { result } : {}), ...(reason ? { reason } : {}) }));
  return c.json({ ok: true }, 202);
});
