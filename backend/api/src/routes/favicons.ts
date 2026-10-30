import { Hono } from "hono";
import type { AppEnv } from "../env";
import { faviconPathForViewer } from "../db/repo/scans";
import { usableSecret } from "../http/crypto";
import { errors } from "../http/errors";
import { errorInfo } from "../http/logError";
import { hit, limits } from "../http/rateLimit";
import { UUID } from "../http/validate";
import { faviconContentType } from "../services/favicons";
import { verifyFaviconLink } from "../services/screenshotLinks";
import { storeFor } from "../services/screenshots";

const NO_STORE = "private, no-store";

export const favicons = new Hono<AppEnv>();

/**
 * PR-05: the only way to see a stored favicon, exactly like GET /screenshots/{id} (D-alief-B08).
 * The signed link names the viewer; access is re-checked in the DB on every request and nothing is
 * cached, so DELETE /devices/me, retention and disconnect hide the icon at once.
 */
favicons.get("/favicons/:id", async (c) => {
  c.header("Cache-Control", NO_STORE);
  const id = c.req.param("id");
  const secret = usableSecret(c.env.SCREENSHOT_URL_SECRET);
  if (!secret || !UUID.test(id)) throw errors.notFound();
  const viewerId = await verifyFaviconLink(secret, id, c.req.query(), Date.now() / 1000);
  if (!viewerId) throw errors.notFound();
  await hit(c.get("sql"), limits.viewFavicon, viewerId);

  const path = await faviconPathForViewer(c.get("sql"), id, viewerId);
  // New favicons in R2, old ones in Supabase until they expire (D-alief-C27).
  const store = path ? storeFor(c.env, path) : undefined;
  const contentType = path ? faviconContentType(path) : undefined;
  if (!path || !store || !contentType) throw errors.notFound();
  let object: Response | undefined;
  try {
    object = await store.get(path);
  } catch (err) {
    console.error(JSON.stringify({ event: "favicon_read_failed", error: errorInfo(err) }));
  }
  if (!object) throw errors.notFound();

  return new Response(object.body, {
    headers: {
      "content-type": contentType,
      "cache-control": NO_STORE,
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'; sandbox",
      "referrer-policy": "no-referrer",
      "x-request-id": c.get("requestId"),
    },
  });
});
