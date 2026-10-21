import { app } from "./app";
import { runRetention } from "./cron/retention";
import { createSql } from "./db/client";
import type { Env } from "./env";

export default {
  fetch: app.fetch,
  // Daily retention, wrangler.jsonc triggers.crons (R4 §5).
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil(runRetention(createSql(env), env));
  },
} satisfies ExportedHandler<Env>;
