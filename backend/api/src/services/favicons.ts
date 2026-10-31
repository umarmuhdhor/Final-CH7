import type { Sql } from "postgres";
import type { Env } from "../env";
import { clearFaviconPath, reserveFavicon, scanExists } from "../db/repo/scans";
import { usableSecret } from "../http/crypto";
import { ApiError } from "../http/errors";
import { errorInfo } from "../http/logError";
import { hit, hitLight, limits } from "../http/rateLimit";
import { downloadFavicon, type DownloadOptions, FAVICON_CONTENT_TYPE, FAVICON_EXT, type FetchFail } from "./faviconFetch";
import { faviconLink } from "./screenshotLinks";
import { abandonUpload, r2Store } from "./screenshots";

type Drop = FetchFail | "quota" | "no_storage" | "scan_gone" | "upload_failed";

// Reason only: the URL is a page the user visited (SECURITY §3 P6).
const dropped = (reason: Drop) => console.log(JSON.stringify({ event: "favicon_dropped", reason }));

/**
 * PR-05: store the scam site's favicon, so the app only talks to this Worker (SECURITY P9). New
 * favicons go to R2 as `<owner>/<scan>-icon.<ext>` (D-alief-C27: most-viewed object, free egress, no
 * external subrequest per view); old `-favicon.<ext>` objects stay in Supabase until they expire.
 * Runs in waitUntil after POST /scans answered; any failure drops the favicon only. Order: reuse the owner's favicon of this domain from the last 24 h (no download),
 * else spend the download quota, download with the guards of faviconFetch, reserve + tombstone the
 * path (D-alief-B12), upload. Same cleanup as attachScreenshot when the upload fails or the scan
 * was deleted meanwhile.
 */
export async function attachFavicon(
  sql: Sql,
  env: Env,
  scan: { id: string; ownerId: string; domain: string },
  faviconUrl: string,
  opts: DownloadOptions = {},
): Promise<void> {
  // Only the binding, like deletes: favicons are not behind the replica kill-switch.
  const store = r2Store(env);
  if (!store) return dropped("no_storage");

  const early = await reserveFavicon(sql, scan, null);
  if ("reuse" in early) return;
  if ("gone" in early) return dropped("scan_gone");

  try {
    await hit(sql, limits.fetchFavicon, scan.ownerId);
    await hitLight(sql, limits.fetchFaviconAll, "all");
  } catch (err) {
    if (err instanceof ApiError) return dropped("quota");
    throw err;
  }

  const download = await downloadFavicon(faviconUrl, opts);
  if (!download.ok) return dropped(download.reason);
  const { type, bytes } = download.favicon;

  const path = `${scan.ownerId}/${scan.id}-icon.${FAVICON_EXT[type]}`;
  // A parallel scan of the same domain may have stored one meanwhile: then that one is reused.
  const slot = await reserveFavicon(sql, scan, path);
  if ("reuse" in slot || "none" in slot) return;
  if ("gone" in slot) return dropped("scan_gone");

  try {
    await store.put(path, bytes, FAVICON_CONTENT_TYPE[type]);
  } catch (err) {
    console.error(JSON.stringify({ event: "favicon_dropped", reason: "upload_failed", error: errorInfo(err) }));
    await clearFaviconPath(sql, scan.ownerId, path).catch(() => undefined);
    await abandonUpload(sql, store, path);
    return;
  }
  if (!(await scanExists(sql, scan.id))) await abandonUpload(sql, store, path);
}

/**
 * The scan's faviconUrl: a 1-hour Worker link for this viewer, like screenshotUrl, or null without a
 * stored favicon or a usable secret. The scam site's own URL is never returned (SECURITY P9).
 */
export async function faviconUrl(env: Env, scan: { id: string; faviconPath: string | null }, viewerId: string): Promise<string | null> {
  if (!scan.faviconPath) return null;
  const secret = usableSecret(env.SCREENSHOT_URL_SECRET);
  if (!secret) return null;
  const origin = env.INVITE_BASE_URL.replace(/\/+$/, "");
  return faviconLink(secret, origin, scan.id, viewerId, Date.now() / 1000);
}

/** Served content type from the stored path's extension (both `-favicon.<ext>` and `-icon.<ext>`). */
export function faviconContentType(path: string): string | undefined {
  const ext = path.slice(path.lastIndexOf(".") + 1);
  const type = (Object.keys(FAVICON_EXT) as (keyof typeof FAVICON_EXT)[]).find((t) => FAVICON_EXT[t] === ext);
  return type ? FAVICON_CONTENT_TYPE[type] : undefined;
}
