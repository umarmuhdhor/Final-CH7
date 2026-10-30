import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { findVisibleScan, insertScan, listScans, memberIds } from "../db/repo/scans";
import { requireDevice } from "../http/auth";
import { base64url } from "../http/crypto";
import { errors } from "../http/errors";
import { clientIp, hit, hitLight, limits } from "../http/rateLimit";
import { maxRequestBytes } from "../http/bodyLimit";
import { DOMAIN, hasUnsafe, isoTime, parse, readJson, stripUnsafe, UUID } from "../http/validate";
import { deliverPush } from "../services/push/deliver";
import { guardianPush, ownPush } from "../services/push/notify";
import { pushSender } from "../services/push/sender";
import { attachFavicon, faviconUrl } from "../services/favicons";
import { attachReplica, replicaUrl } from "../services/replicas";
import { attachScreenshot, screenshotUrl, toScanResult } from "../services/scans";
import { errorInfo } from "../http/logError";

const FUTURE_SKEW_MS = 5 * 60 * 1000;

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

// ScanResult without id/verdict/screenshotUrl/pageReplicaUrl (contracts/api.md). ownerDeviceId/ownerName are
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
    // EX-07: gzip + base64 page replica. No .max(): an oversized replica is dropped by
    // decodeReplica, while a 422 would make the extension drop the whole scan.
    pageReplicaBase64: z.string().nullish(),
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
  // 512 KB on the exact path only, like the early check in app.ts (also for chunked bodies).
  const body = await readJson(c, scanBody, maxRequestBytes(c.req.method, c.req.path));
  // After validation, so rejected bodies spend no global budget (accepted trade-off, D-alief-B12 i).
  await hitLight(sql, limits.createScanAll, "all");

  const iconUrl = favicon(body.faviconUrl);
  const id = await insertScan(sql, {
    ownerId: principal.deviceId,
    url: body.url,
    domain: body.domain,
    pageTitle: title(body.pageTitle),
    faviconUrl: iconUrl,
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
      console.error(JSON.stringify({ event: "screenshot_dropped", reason: "error", error: errorInfo(err) }));
    }
  }
  // PR-05: the Worker downloads the favicon once, after the response (a slow scam host never delays
  // or fails the scan), so the app never contacts the scam host (SECURITY P9).
  if (iconUrl) {
    c.executionCtx.waitUntil(
      attachFavicon(sql, c.env, { id, ownerId: principal.deviceId, domain: body.domain }, iconUrl).catch((err) =>
        console.error(JSON.stringify({ event: "favicon_dropped", reason: "error", error: errorInfo(err) })),
      ),
    );
  }
  // Guardian lookup now; the send, the token clear and the push_log row run in waitUntil after the
  // response. The Hyperdrive connection lives for the whole invocation, waitUntil included (checked
  // locally with wrangler dev; cloud check in fase 11 LANGKAH MANUAL step 6).
  // Like the screenshot, a push problem never fails a stored scan (a retry would duplicate it).
  const deliveries: Promise<unknown>[] = [];
  try {
    const scan = { id, status: body.status, score: body.score };
    // PF-01: the guardian's push, then the device's own ("Situs berbahaya" / "Situs diblokir").
    const pushes = [await guardianPush(sql, principal, scan), await ownPush(sql, principal, scan)];
    const sender = pushSender(c.env);
    for (const push of pushes) {
      if (!push) continue;
      const delivery = deliverPush(sql, sender, push).catch((err) =>
        // Name only: a DB error can quote values (D-alief-40).
        console.error(JSON.stringify({ event: "push_failed", requestId: c.get("requestId"), error: errorInfo(err) })),
      );
      deliveries.push(delivery);
      c.executionCtx.waitUntil(delivery);
    }
  } catch (err) {
    console.error(JSON.stringify({ event: "push_lookup_failed", requestId: c.get("requestId"), error: errorInfo(err) }));
  }
  // EX-07 (K2, D-alief-C22 a): the replica only after the pushes went out. Inflating up to 3 MB costs
  // CPU; if the invocation is killed for it, the scan and the Guardian's push are already done.
  // Outside the try above: a failed push lookup does not drop the replica.
  const replica = body.pageReplicaBase64;
  if (replica) {
    const ip = clientIp((n) => c.req.header(n));
    const ref = { id, ownerId: principal.deviceId, domain: body.domain };
    c.executionCtx.waitUntil(
      Promise.allSettled(deliveries)
        .then(() => attachReplica(sql, c.env, ref, replica, ip))
        .catch((err) => console.error(JSON.stringify({ event: "replica_dropped", reason: "error", error: errorInfo(err) }))),
    );
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
    // Lists never carry a screenshot or replica URL (D-alief-04, EX-07); favicons are signed per viewer (PR-05).
    items: await Promise.all(page.map(async (r) => toScanResult(r, null, await faviconUrl(c.env, r, deviceId)))),
    nextCursor: rows.length > q.limit && last ? encodeCursor(last.cursorAt, last.id) : null,
  });
});

/** DT-*: one scan with 1-hour signed screenshot, favicon and replica URLs. 404 for anything the caller may not see. */
scans.get("/scans/:id", async (c) => {
  const id = c.req.param("id");
  if (!UUID.test(id)) throw errors.notFound();
  const viewerId = c.get("principal").deviceId;
  const row = await findVisibleScan(c.get("sql"), id, viewerId);
  if (!row) throw errors.notFound();
  return c.json(
    toScanResult(
      row,
      await screenshotUrl(c.env, row, viewerId),
      await faviconUrl(c.env, row, viewerId),
      await replicaUrl(c.env, row, viewerId),
    ),
  );
});

