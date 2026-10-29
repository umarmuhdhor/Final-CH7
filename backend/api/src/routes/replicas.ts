import { Hono } from "hono";
import type { AppEnv } from "../env";
import { replicaPathForViewer } from "../db/repo/scans";
import { usableSecret } from "../http/crypto";
import { errors } from "../http/errors";
import { errorInfo } from "../http/logError";
import { hit, limits } from "../http/rateLimit";
import { UUID } from "../http/validate";
import { replicasEnabled } from "../services/replicas";
import { verifyReplicaLink } from "../services/screenshotLinks";
import { r2Store } from "../services/screenshots";

/**
 * Even if a client renders it: no scripts, forms, frames, remote loads or base URL (K8, K20). The app
 * adds its own CSP on top when it loads the HTML as a string (D-alief-C21), since this header is lost then.
 */
export const REPLICA_CSP =
  "sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'; frame-ancestors 'none'";

export const replicas = new Hono<AppEnv>();

/**
 * EX-07, like GET /screenshots/{id} (D-alief-B08): the only way to read a page replica. The signed
 * link names the viewer; access is re-checked in the DB on every request and nothing is cached, so
 * DELETE /devices/me, retention and disconnect hide it at once (SECURITY §3 P3, P13).
 * The body is the gzip object from R2 byte for byte (`encodeBody: "manual"`, D-alief-C20); URLSession
 * inflates it. HTML written by a device must never open as a page on this origin (K20): browser
 * navigations and frames get 404, and the body is an attachment.
 * No c.header() here: Hono re-wraps a raw Response when headers were set on c.res, and that would
 * drop encodeBody. Every header is in the Response itself.
 */
replicas.get("/replicas/:id", async (c) => {
  const id = c.req.param("id");
  const secret = usableSecret(c.env.SCREENSHOT_URL_SECRET);
  if (!replicasEnabled(c.env) || !secret || !UUID.test(id)) throw errors.notFound();
  // URLSession sends no Sec-Fetch-* headers; browsers always do (K20).
  const mode = c.req.header("sec-fetch-mode");
  const dest = c.req.header("sec-fetch-dest");
  if (mode === "navigate" || (dest !== undefined && dest !== "empty")) throw errors.notFound();
  const viewerId = await verifyReplicaLink(secret, id, c.req.query(), Date.now() / 1000);
  if (!viewerId) throw errors.notFound();
  const sql = c.get("sql");
  await hit(sql, limits.viewReplica, viewerId);
  await hit(sql, limits.viewReplicaDay, viewerId);

  const path = await replicaPathForViewer(sql, id, viewerId);
  const store = r2Store(c.env);
  if (!path || !store) throw errors.notFound();
  let body: ReadableStream<Uint8Array> | undefined;
  try {
    body = await gzipBody(await store.get(path));
  } catch (err) {
    console.error(JSON.stringify({ event: "replica_read_failed", error: errorInfo(err) }));
  }
  if (!body) throw errors.notFound();

  return new Response(body, {
    encodeBody: "manual",
    headers: {
      "content-type": "text/html; charset=utf-8",
      "content-encoding": "gzip",
      "content-disposition": 'attachment; filename="replica.html"',
      "content-security-policy": REPLICA_CSP,
      "x-content-type-options": "nosniff",
      "cache-control": "private, no-store",
      "referrer-policy": "no-referrer",
      "x-request-id": c.get("requestId"),
    },
  });
});

/**
 * The object's stream, or undefined when it is missing or does not start with the gzip magic
 * (1f 8b): only then is `Content-Encoding: gzip` true. The first chunk is read to check and sent first.
 */
async function gzipBody(object: Response | undefined): Promise<ReadableStream<Uint8Array> | undefined> {
  if (!object?.body) return undefined;
  const reader = object.body.getReader();
  const first = await reader.read();
  if (first.done || first.value.length < 2 || first.value[0] !== 0x1f || first.value[1] !== 0x8b) {
    await reader.cancel().catch(() => undefined);
    return undefined;
  }
  let sentFirst = false;
  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      if (!sentFirst) {
        sentFirst = true;
        controller.enqueue(first.value);
        return;
      }
      const next = await reader.read();
      if (next.done) controller.close();
      else controller.enqueue(next.value);
    },
    cancel: (reason) => reader.cancel(reason),
  });
}
