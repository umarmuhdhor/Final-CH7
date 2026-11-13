import { Hono } from "hono";
import postgres from "postgres";
import * as z from "zod";
import type { AppEnv } from "../env";
import { decideVerdict, findDomainVerdict, findVerdict, type VerdictResult } from "../db/repo/verdicts";
import { requireDevice, requireMode } from "../http/auth";
import { errors } from "../http/errors";
import { hit, hitEdge, limits } from "../http/rateLimit";
import { codePoints, DOMAIN, hasUnsafe, parse, readJson, stripUnsafe, UUID } from "../http/validate";

/** 280 code points of notes can be up to 1120 bytes of UTF-8, plus JSON escapes. */
const MAX_BODY = 4096;
const MAX_NOTES = 280;

/**
 * #241: why the Guardian decided. Line breaks and tabs become spaces, other control and bidi
 * characters go (the dashboard shows the note); empty after trim = no note. Never logged.
 */
const notes = z
  .string()
  .max(4 * MAX_NOTES)
  .nullish()
  .transform((s) => stripUnsafe((s ?? "").replace(/[\r\n\t]+/g, " ")).trim() || null)
  .refine((s) => s === null || codePoints(s) <= MAX_NOTES, `must be at most ${MAX_NOTES} characters`);

const body = z.strictObject({ scanId: z.string().max(64), value: z.enum(["safe", "not_safe"]), notes });
// The extension sends the registrable domain; tolerate case, spaces and a leading www.
const domainParam = z
  .string()
  .max(260)
  .transform((s) => s.trim().toLowerCase().replace(/\.$/, "").replace(/^www\./, ""))
  .pipe(z.string().max(253).regex(DOMAIN, "must be a registrable domain"));
// The link (origin + path) as the extension's shareableUrl gives it; a query or fragment is dropped.
const linkParam = z
  .string()
  .max(2048)
  .transform((s, ctx) => {
    let u: URL | undefined;
    try {
      u = hasUnsafe(s) ? undefined : new URL(s.trim());
    } catch {
      u = undefined;
    }
    if (!u || (u.protocol !== "http:" && u.protocol !== "https:")) {
      ctx.addIssue({ code: "custom", message: "must be an http(s) URL" });
      return z.NEVER;
    }
    return u;
  });
const lookupQuery = z.union([
  z
    .object({ url: linkParam, domain: domainParam })
    .refine(
      ({ url, domain }) => {
        const host = url.hostname.replace(/\.$/, "");
        return host === domain || host.endsWith(`.${domain}`);
      },
      { message: "url host must be the domain or a subdomain of it", path: ["url"] },
    )
    .transform(({ url, domain }) => ({ link: url.origin + url.pathname, domain })),
  // Deprecated: builds from before #241 send the domain only.
  z.object({ url: z.undefined(), domain: domainParam }).transform(({ domain }) => ({ link: null, domain })),
]);

export const verdicts = new Hono<AppEnv>();

verdicts.use("/verdicts", requireDevice);

/** GD-07 (R2 §5, R4 §4). */
verdicts.post("/verdicts", requireMode("guardian"), async (c) => {
  const sql = c.get("sql");
  const principal = c.get("principal");
  await hit(sql, limits.createVerdict, principal.deviceId);
  const { scanId, value, notes } = await readJson(c, body, MAX_BODY);
  // An id that is not a UUID cannot name a scan.
  if (!UUID.test(scanId)) throw errors.notFound();

  let result: VerdictResult | undefined;
  for (let attempt = 1; !result; attempt++) {
    try {
      result = await decideVerdict(sql, principal, scanId, value, notes);
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
  if (result.error === "locked") throw errors.verdictLocked(result.lockedUntil);
  throw errors.verdictNotAllowed(403, "Not the owner's guardian");
});

/** Fase 25 K7: verdicts seen within this many ms of the decision are logged, to measure EX-06 latency. */
const VERDICT_SEEN_WINDOW_MS = 120_000;

/** EX-06: polled by the extension of either mode while a block screen is open (?url=&domain=, #241). */
verdicts.get("/verdicts", async (c) => {
  const sql = c.get("sql");
  const principal = c.get("principal");
  await hitEdge(c.env.VERDICTS_GET_LIMITER, sql, limits.getVerdict, principal.deviceId);
  const { link, domain } = parse(lookupQuery, { url: c.req.query("url"), domain: c.req.query("domain") });
  const verdict =
    link === null
      ? await findDomainVerdict(sql, principal.deviceId, domain)
      : await findVerdict(sql, principal.deviceId, link, domain);
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
