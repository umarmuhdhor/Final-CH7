import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { findVisibleScan, insertScan, listScans, memberIds } from "../db/repo/scans";
import { requireDevice } from "../http/auth";
import { base64url } from "../http/crypto";
import { errors } from "../http/errors";
import { hit, limits } from "../http/rateLimit";
import { hasUnsafe, isoTime, parse, readJson, stripUnsafe } from "../http/validate";
import { guardianPush } from "../services/push/notify";
import { pushSender } from "../services/push/sender";
import { attachScreenshot, signedScreenshotUrl, toScanResult } from "../services/scans";

const MAX_BODY = 256 * 1024;
const FUTURE_SKEW_MS = 5 * 60 * 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const DOMAIN = /^(?!www\.)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;

/** http(s) URL without control or bidi characters (Postgres rejects NUL; the Guardian UI shows the URL). */
const httpUrl = (s: string) => {
  if (hasUnsafe(s)) return undefined;
  try {
    const u = new URL(s);
    return u.protocol === "http:" || u.protocol === "https:" ? u : undefined;
  } catch {
    return undefined;
  }
};

// Text from the detector is stored and shown as plain text; control and bidi characters are removed.
const text = (max: number) => z.string().max(max).transform(stripUnsafe);
const localized = z.strictObject({ en: text(500).pipe(z.string().min(1)), id: text(500).pipe(z.string().min(1)) });
// contracts/scan-result.schema.json $defs.Signal. Unknown keys are dropped.
const signal = z.object({
  id: text(64).pipe(z.string().min(1)),
  layer: z.number().int().min(1).max(5),
  weight: z.number().int().min(0).max(100),
  label: localized,
  labelSimple: localized,
  evidence: text(500).optional(),
});

// ScanResult without id/verdict/screenshotUrl (contracts/api.md). ownerDeviceId/ownerName are
// accepted and ignored: the owner is always the token's device (R3 §4).
const scanBody = z
  .object({
    url: z.string().max(2048).refine((s) => httpUrl(s) !== undefined, "must be an http(s) URL"),
    domain: z.string().max(253).regex(DOMAIN, "must be a lowercase registrable domain without www."),
    pageTitle: z.string().nullish(),
    faviconUrl: z.unknown().optional(),
    score: z.number().int().min(30).max(100),
    status: z.enum(["warning", "blocked"]),
    signals: z.array(signal).max(20),
    detectedAt: isoTime.refine((v) => Date.parse(v) <= Date.now() + FUTURE_SKEW_MS, "must not be in the future"),
    screenshotBase64: z.string().nullish(),
  })
  .refine((b) => b.status === (b.score >= 80 ? "blocked" : "warning"), {
    message: "must be blocked for score >= 80, else warning",
    path: ["status"],
  })
  .refine(
    (b) => {
      const host = httpUrl(b.url)?.hostname;
      return host === b.domain || (host?.endsWith(`.${b.domain}`) ?? false);
    },
    { message: "url host must be the domain or a subdomain of it", path: ["domain"] },
  );

/** Free text from web pages: trimmed, at most 300 code points; empty → null. */
const title = (s: string | null | undefined) => {
  const t = [...stripUnsafe(s ?? "").trim()].slice(0, 300).join("");
  return t ? t : null;
};
/** Only http(s) favicons ≤ 2048 chars are kept; anything else (data:, junk) becomes null. */
const favicon = (v: unknown) => (typeof v === "string" && v.length <= 2048 && httpUrl(v) ? v : null);

const listQuery = z.object({
  owner: z.string().max(64).default("me"),
  status: z.enum(["warning", "blocked"]).optional(),
  cursor: z.string().max(200).optional(),
  limit: z.string().regex(/^\d{1,2}$/).transform(Number).pipe(z.number().int().min(1).max(50)).default(20),
});

const encodeCursor = (at: string, id: string) => base64url(new TextEncoder().encode(`${at}|${id}`));
function decodeCursor(cursor: string): { at: string; id: string } {
  let text = "";
  try {
    text = atob(cursor.replace(/-/g, "+").replace(/_/g, "/"));
  } catch {
    /* falls through to the error below */
  }
  const parts = text.split("|");
  const [at, id] = parts;
  if (parts.length !== 2 || !at || !id || !UUID.test(id) || Number.isNaN(Date.parse(at)) || !isoTime.safeParse(at).success) {
    throw errors.invalidBody("cursor: invalid");
  }
  return { at, id };
}

export const scans = new Hono<AppEnv>();

scans.use("/scans", requireDevice);
scans.use("/scans/*", requireDevice);

/** EX-07, GD-06 (R3 §4, R4 §3). */
scans.post("/scans", async (c) => {
  const sql = c.get("sql");
  const principal = c.get("principal");
  await hit(sql, limits.createScan, principal.deviceId);
  const body = await readJson(c, scanBody, MAX_BODY);

  const id = await insertScan(sql, {
    ownerId: principal.deviceId,
    url: body.url,
    domain: body.domain,
    pageTitle: title(body.pageTitle),
    faviconUrl: favicon(body.faviconUrl),
    score: body.score,
    status: body.status,
    signals: body.signals,
    detectedAt: body.detectedAt,
  });
  if (body.screenshotBase64) {
    try {
      await attachScreenshot(sql, c.env, { id, ownerId: principal.deviceId, domain: body.domain }, body.screenshotBase64);
    } catch (err) {
      // The scan is stored; a screenshot problem must not turn into a 500 that the extension retries.
      console.error(JSON.stringify({ event: "screenshot_dropped", reason: "error", error: String(err) }));
    }
  }
  // DB lookup now, while the request's connection is open; only the send runs after the response.
  // Like the screenshot, a push problem never fails a stored scan (a retry would duplicate it).
  try {
    const push = await guardianPush(sql, principal, { id, status: body.status, score: body.score });
    if (push) {
      const sender = pushSender(c.env);
      c.executionCtx.waitUntil(
        (async () => sender.send(push))().catch((err) =>
          console.error(JSON.stringify({ event: "push_failed", scanId: id, error: String(err) })),
        ),
      );
    }
  } catch (err) {
    console.error(JSON.stringify({ event: "push_lookup_failed", scanId: id, error: String(err) }));
  }
  return c.json({ id }, 201);
});

/** PR-05, GD-05. Owners are resolved from family_links at request time (SECURITY T1, T12). */
scans.get("/scans", async (c) => {
  const q = parse(listQuery, {
    owner: c.req.query("owner") || undefined,
    status: c.req.query("status") || undefined,
    cursor: c.req.query("cursor") || undefined,
    limit: c.req.query("limit") ?? undefined,
  });
  const sql = c.get("sql");
  const { deviceId, mode } = c.get("principal");

  let owners: string[];
  if (q.owner === "me" || q.owner === deviceId) {
    owners = [deviceId];
  } else if (q.owner === "family") {
    if (mode !== "guardian") throw errors.forbidden();
    owners = [deviceId, ...(await memberIds(sql, deviceId))];
  } else {
    if (mode !== "guardian" || !(await memberIds(sql, deviceId)).includes(q.owner)) throw errors.notFound();
    owners = [q.owner];
  }

  const rows = await listScans(sql, {
    owners,
    status: q.status ?? null,
    cursor: q.cursor ? decodeCursor(q.cursor) : null,
    limit: q.limit,
  });
  const page = rows.slice(0, q.limit);
  const last = page.at(-1);
  return c.json({
    // Lists never carry a screenshot URL (D-alief-04).
    items: page.map((r) => toScanResult(r, null)),
    nextCursor: rows.length > q.limit && last ? encodeCursor(last.cursorAt, last.id) : null,
  });
});

/** DT-*: one scan with a 1-hour signed screenshot URL. 404 for anything the caller may not see. */
scans.get("/scans/:id", async (c) => {
  const id = c.req.param("id");
  if (!UUID.test(id)) throw errors.notFound();
  const row = await findVisibleScan(c.get("sql"), id, c.get("principal").deviceId);
  if (!row) throw errors.notFound();
  return c.json(toScanResult(row, await signedScreenshotUrl(c.env, row.screenshotPath)));
});

