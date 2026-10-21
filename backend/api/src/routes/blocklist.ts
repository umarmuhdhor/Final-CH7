import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { blocklistEvents } from "../db/repo/blocklist";
import { requireDevice } from "../http/auth";
import { parse } from "../http/validate";

const query = z.object({ since: z.iso.datetime({ offset: true }).optional() });

export const blocklist = new Hono<AppEnv>();

/** Global layer-1 list: manually approved domains only (contracts/api.md Blocklist, R2 §5). */
blocklist.get("/blocklist", requireDevice, async (c) => {
  const { since } = parse(query, { since: c.req.query("since") || undefined });
  const events = await blocklistEvents(c.get("sql"), since ?? null);

  const domains = events.filter((e) => e.kind === "added").map((e) => ({ domain: e.domain, addedAt: e.at }));
  const removed = events.filter((e) => e.kind === "removed").map((e) => ({ domain: e.domain, removedAt: e.at }));
  // Empty page: echo the cursor so the client sees it is caught up.
  const nextSince = events.at(-1)?.at ?? since ?? null;

  c.header("Cache-Control", "private, max-age=300");
  return c.json(since === undefined ? { domains, nextSince } : { domains, removed, nextSince });
});
