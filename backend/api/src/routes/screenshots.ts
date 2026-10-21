import { Hono } from "hono";
import type { AppEnv } from "../env";
import { screenshotPathForViewer } from "../db/repo/scans";
import { errors } from "../http/errors";
import { UUID } from "../http/validate";
import { verifyScreenshotLink } from "../services/screenshotLinks";
import { screenshotStore } from "../services/screenshots";

const NO_STORE = "private, no-store";

export const screenshots = new Hono<AppEnv>();

/**
 * D-alief-B08: the only way to see a screenshot. No Authorization header (AsyncImage), the signed
 * link names the viewer; access is re-checked in the DB on every request and nothing is cached,
 * so DELETE /devices/me, retention and disconnect hide the image at once (SECURITY §3 P3, T6).
 */
screenshots.get("/screenshots/:id", async (c) => {
  c.header("Cache-Control", NO_STORE);
  const id = c.req.param("id");
  const secret = c.env.SCREENSHOT_URL_SECRET;
  if (!secret || !UUID.test(id)) throw errors.notFound();
  const viewerId = await verifyScreenshotLink(secret, id, c.req.query(), Date.now() / 1000);
  if (!viewerId) throw errors.notFound();

  const path = await screenshotPathForViewer(c.get("sql"), id, viewerId);
  const store = screenshotStore(c.env);
  if (!path || !store) throw errors.notFound();
  let object: Response | undefined;
  try {
    object = await store.get(path);
  } catch (err) {
    console.error(JSON.stringify({ event: "screenshot_read_failed", error: String(err) }));
  }
  if (!object) throw errors.notFound();

  return new Response(object.body, {
    headers: {
      "content-type": path.endsWith(".png") ? "image/png" : "image/jpeg",
      "cache-control": NO_STORE,
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'; sandbox",
      "referrer-policy": "no-referrer",
      "x-request-id": c.get("requestId"),
    },
  });
});
