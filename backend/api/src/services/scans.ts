import type { Sql } from "postgres";
import type { Env } from "../env";
import { clearScreenshotPath, reserveScreenshot, scanExists, type ScanRow } from "../db/repo/scans";
import { decodeBase64, sniffImage } from "./images";
import { screenshotLink } from "./screenshotLinks";
import { screenshotStore } from "./screenshots";

const MAX_SIDE = 1280;
const DAILY_QUOTA = 50;
const DEFAULT_MAX_BYTES = 150 * 1024;

/** ScanResult (contracts/scan-result.schema.json). pageTitle is omitted when unknown. */
export function toScanResult(row: ScanRow, screenshotUrl: string | null) {
  return {
    id: row.id,
    url: row.url,
    domain: row.domain,
    ...(row.pageTitle !== null ? { pageTitle: row.pageTitle } : {}),
    faviconUrl: row.faviconUrl,
    score: row.score,
    status: row.status,
    signals: row.signals,
    screenshotUrl,
    ownerDeviceId: row.ownerId,
    ownerName: row.ownerName,
    detectedAt: row.detectedAt,
    verdict: row.verdict,
  };
}

type Drop = "invalid" | "too_large" | "not_image" | "too_wide" | "bad_size" | "quota" | "no_storage" | "upload_failed";

const dropped = (reason: Drop) => console.log(JSON.stringify({ event: "screenshot_dropped", reason }));

/**
 * R3 §4: decode, check size/type/pixels, dedupe per owner + domain (24 h), quota 50/24 h, upload.
 * Any failure drops the screenshot only; the scan is already stored.
 */
export async function attachScreenshot(
  sql: Sql,
  env: Env,
  scan: { id: string; ownerId: string; domain: string },
  base64: string,
): Promise<void> {
  const maxBytes = Number(env.SCREENSHOT_MAX_BYTES) || DEFAULT_MAX_BYTES;
  const bytes = decodeBase64(base64, maxBytes);
  if (!bytes) return dropped(/^[A-Za-z0-9+/]*={0,2}$/.test(base64) && base64.length % 4 === 0 ? "too_large" : "invalid");
  const image = sniffImage(bytes);
  if (!image) return dropped("not_image");
  if (image.width === 0 || image.height === 0) return dropped("bad_size");
  if (Math.max(image.width, image.height) > MAX_SIDE) return dropped("too_wide");

  const store = screenshotStore(env);
  if (!store) return dropped("no_storage");

  const path = `${scan.ownerId}/${scan.id}.${image.type === "png" ? "png" : "jpg"}`;
  const slot = await reserveScreenshot(sql, scan, path, DAILY_QUOTA);
  if ("reuse" in slot) return;
  if ("quota" in slot) return dropped("quota");

  try {
    await store.put(path, bytes, image.type === "png" ? "image/png" : "image/jpeg");
  } catch (err) {
    console.error(JSON.stringify({ event: "screenshot_dropped", reason: "upload_failed", error: String(err) }));
    // A timed-out upload may still land in Storage: remove it so no object is left without a row.
    await store.remove([path]).catch(() => undefined);
    await clearScreenshotPath(sql, scan.ownerId, path);
    return;
  }
  // The scan may have been deleted meanwhile (DELETE /devices/me): never leave an orphan object.
  if (!(await scanExists(sql, scan.id))) await store.remove([path]).catch(() => undefined);
}

/**
 * Detail's screenshotUrl: a 1-hour Worker link for this viewer (D-alief-B08), never a Storage URL,
 * so no CDN copy can outlive a delete or disconnect. Null without a screenshot or without the secret.
 */
export async function screenshotUrl(
  env: Env,
  scan: { id: string; screenshotPath: string | null },
  viewerId: string,
): Promise<string | null> {
  if (!scan.screenshotPath) return null;
  if (!env.SCREENSHOT_URL_SECRET) {
    console.error(JSON.stringify({ event: "screenshot_link_unavailable", reason: "no_secret" }));
    return null;
  }
  // Pinned Worker URL, not the request Host (a custom domain without HTTPS would leak the link).
  const origin = env.INVITE_BASE_URL.replace(/\/+$/, "");
  return screenshotLink(env.SCREENSHOT_URL_SECRET, origin, scan.id, viewerId, Date.now() / 1000);
}
