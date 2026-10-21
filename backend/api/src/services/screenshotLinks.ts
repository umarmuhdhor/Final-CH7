import { base64url, fromBase64url } from "../http/crypto";

/**
 * Screenshot links (D-alief-B08): `GET /screenshots/{scanId}?v=<viewer>&exp=<unix>&sig=<HMAC>`.
 * The link only proves who asked and until when; the route checks in the DB on every request
 * that the scan still exists and the viewer may still see it, so delete and disconnect apply at once.
 */
export const LINK_TTL_SECONDS = 3600;
const SKEW_SECONDS = 60;
const encoder = new TextEncoder();

const hmacKey = (secret: string, usage: "sign" | "verify") =>
  crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [usage]);
const message = (scanId: string, viewerId: string, exp: number) =>
  encoder.encode(`screenshot:v1|${scanId}|${viewerId}|${exp}`);

export async function screenshotLink(
  secret: string,
  origin: string,
  scanId: string,
  viewerId: string,
  nowSeconds: number,
): Promise<string> {
  const exp = Math.floor(nowSeconds) + LINK_TTL_SECONDS;
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(secret, "sign"), message(scanId, viewerId, exp)));
  const query = new URLSearchParams({ v: viewerId, exp: String(exp), sig: base64url(sig) });
  return `${origin}/screenshots/${scanId}?${query}`;
}

/** The viewer device id of a valid, unexpired link for this scan, else undefined. */
export async function verifyScreenshotLink(
  secret: string,
  scanId: string,
  query: { v?: string; exp?: string; sig?: string },
  nowSeconds: number,
): Promise<string | undefined> {
  const { v, exp, sig } = query;
  if (!v || v.length > 64 || !exp || !/^\d{1,12}$/.test(exp) || !sig || sig.length !== 43) return undefined;
  const expiry = Number(exp);
  if (expiry <= nowSeconds || expiry > nowSeconds + LINK_TTL_SECONDS + SKEW_SECONDS) return undefined;
  const bytes = fromBase64url(sig);
  if (!bytes) return undefined;
  // subtle.verify compares in constant time.
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret, "verify"), bytes, message(scanId, v, expiry));
  return ok ? v : undefined;
}
