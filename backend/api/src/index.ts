import { app } from "./app";
import { runNotifications } from "./cron/notifications";
import { runRetention } from "./cron/retention";
import { createSql } from "./db/client";
import type { Env } from "./env";

/** wrangler.jsonc triggers.crons. */
export const CRONS = { retention: "0 19 * * *", notifications: "5 * * * *" } as const;

export default {
  fetch: app.fetch,
  // Daily retention (R4 §5) and hourly PF-01 notifications (protection off, weekly summary).
  // Awaited, not waitUntil: a failed run then fails the Cron event (dashboard, alerts).
  async scheduled(controller, env) {
    if (controller.cron === CRONS.notifications) {
      await runNotifications(createSql(env), env);
      return;
    }
    await runRetention(createSql(env), env);
  },
} satisfies ExportedHandler<Env>;
