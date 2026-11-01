import { Hono } from "hono";
import postgres from "postgres";
import { z } from "zod";
import type { AppEnv } from "../env";
import { decideVerdict, findVerdict, type VerdictResult } from "../db/repo/verdicts";
import { requireDevice, requireMode } from "../http/auth";
import { errors } from "../http/errors";
import { hit, hitLight, limits } from "../http/rateLimit";
import { DOMAIN, parse, readJson, UUID } from "../http/validate";

const MAX_BODY = 1024;

const body = z.strictObject({ scanId: z.string().max(64), value: z.enum(["safe", "not_safe"]) });
// The extension sends the registrable domain; tolerate case, spaces and a leading www.
const lookupQuery = z.object({
  domain: z
    .string()
    .max(260)
    .transform((s) => s.trim().toLowerCase().replace(/\.$/, "").replace(/^www\./, ""))
    .pipe(z.string().max(253).regex(DOMAIN, "must be a registrable domain")),
});

export const verdicts = new Hono<AppEnv>();

verdicts.use("/verdicts", requireDevice);

/** GD-07 (R2 §5, R4 §4). */
verdicts.post("/verdicts", requireMode("guardian"), async (c) => {
  const sql = c.get("sql");
  const principal = c.get("principal");
  await hit(sql, limits.createVerdict, principal.deviceId);
  const { scanId, value } = await readJson(c, body, MAX_BODY);
  // An id that is not a UUID cannot name a scan.
  if (!UUID.test(scanId)) throw errors.notFound();

  let result: VerdictResult | undefined;
  for (let attempt = 1; !result; attempt++) {
    try {
      result = await decideVerdict(sql, principal, scanId, value);
    } catch (err) {
      const code = err instanceof postgres.PostgresError ? err.code : undefined;
      // The scan, its owner or this guardian was deleted mid-request (foreign key gone).
      if (code === "23503") throw errors.notFound();
      // A rare deadlock with a concurrent delete (e.g. retention): Postgres rolled back, retry once.
      if ((code === "40P01" || code === "40001") && attempt < 2) continue;
      throw err;
    }
  }
  if ("verdict" in result) return c.json({ verdict: result.verdict });
  if (result.error === "not_found") throw errors.notFound();
  throw errors.verdictNotAllowed(403, "Not the owner's guardian");
});

/** Fase 25 K7: verdicts seen within this many ms of the decision are logged, to measure EX-06 latency. */
const VERDICT_SEEN_WINDOW_MS = 120_000;

/** EX-06: polled by the extension of either mode while a block screen is open. */
verdicts.get("/verdicts", async (c) => {
  const sql = c.get("sql");
  const principal = c.get("principal");
  await hitLight(sql, limits.getVerdict, principal.deviceId);
  const { domain } = parse(lookupQuery, { domain: c.req.query("domain") });
  const verdict = await findVerdict(sql, principal.deviceId, domain);
  if (verdict) logFreshVerdict(verdict);
  return c.json({ verdict });
});

/**
 * One `verdict_seen` line with the server-side latency from the Guardian's tap to this poll. Numbers and
 * the value only (no domain, ids or names, SECURITY §3 P6). Block screens stop polling after the first
 * verdict, so this is about one line per decision. Clock skew between Postgres and the Worker is
 * clamped to 0.
 */
function logFreshVerdict(verdict: { value: string; decidedAt: string }): void {
  const ageMs = Math.max(0, Date.now() - Date.parse(verdict.decidedAt));
  if (!(ageMs <= VERDICT_SEEN_WINDOW_MS)) return;
  console.log(JSON.stringify({ event: "verdict_seen", ageMs, value: verdict.value }));
}
