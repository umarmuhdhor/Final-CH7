import type { Sql } from "postgres";
import type { Env } from "../env";
import { recentScreenshot, screenshotsToday, setScreenshotPath, type ScanRow } from "../db/repo/scans";
import { decodeBase64, sniffImage } from "./images";
import { screenshotStore } from "./screenshots";

export const SIGNED_URL_TTL = 3600;
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

type Drop = "invalid" | "too_large" | "not_image" | "too_wide" | "quota" | "no_storage" | "upload_failed";

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
  if (Math.max(image.width, image.height) > MAX_SIDE || image.width === 0 || image.height === 0) return dropped("too_wide");

  const reuse = await recentScreenshot(sql, scan.ownerId, scan.domain);
  if (reuse) return setScreenshotPath(sql, scan.id, reuse);
  if ((await screenshotsToday(sql, scan.ownerId)) >= DAILY_QUOTA) return dropped("quota");

  const store = screenshotStore(env);
  if (!store) return dropped("no_storage");
  const path = `${scan.ownerId}/${scan.id}.${image.type === "png" ? "png" : "jpg"}`;
  try {
    await store.put(path, bytes, image.type === "png" ? "image/png" : "image/jpeg");
  } catch (err) {
    console.error(JSON.stringify({ event: "screenshot_dropped", reason: "upload_failed", error: String(err) }));
    return;
  }
  await setScreenshotPath(sql, scan.id, path);
}

/** Signed URL for Detail, or null when there is no screenshot or Storage fails (the scan still shows). */
export async function signedScreenshotUrl(env: Env, path: string | null): Promise<string | null> {
  if (!path) return null;
  try {
    const store = screenshotStore(env);
    return store ? await store.signedUrl(path, SIGNED_URL_TTL) : null;
  } catch (err) {
    console.error(JSON.stringify({ event: "screenshot_sign_failed", error: String(err) }));
    return null;
  }
}
