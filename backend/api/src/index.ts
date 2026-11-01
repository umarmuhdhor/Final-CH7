import { app } from "./app";
import { runNotifications } from "./cron/notifications";
import { runRetention } from "./cron/retention";
import { createSql } from "./db/client";
import type { Env } from "./env";
import { errorInfo } from "./http/logError";
import { logReplicaUsage } from "./services/replicas";

/** wrangler.jsonc triggers.crons. */
export const CRONS = { retention: "0 19 * * *", notifications: "5 * * * *" } as const;

export default {
  fetch: app.fetch,
  // Daily retention (R4 §5) and hourly PF-01 notifications (protection off, weekly summary).
  // Awaited, not waitUntil: a failed run then fails the Cron event (dashboard, alerts).
  async scheduled(controller, env) {
    if (controller.cron === CRONS.notifications) {
      const sql = createSql(env);
      try {
        await runNotifications(sql, env);
      } finally {
        // Fase 19 K5.2 gauge: its own failure never fails the notifications run, and it runs even
        // when notifications failed (a missing gauge for 2 h = the cron is down).
        await logReplicaUsage(sql).catch((err: unknown) =>
          console.error(JSON.stringify({ event: "replica_usage_failed", error: errorInfo(err) })));
      }
      return;
    }
    await runRetention(createSql(env), env);
  },
} satisfies ExportedHandler<Env>;
