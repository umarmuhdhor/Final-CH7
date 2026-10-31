import { base64url, fromBase64url } from "../http/crypto";

/**
 * Screenshot links (D-alief-B08): `GET /screenshots/{scanId}?v=<viewer>&exp=<unix>&sig=<HMAC>`.
 * Favicon links (PR-05) are the same with `/favicons/`, replica links (EX-07) with `/replicas/`; the
 * kind is part of the signed message, so a link of one kind never opens another.
 * The link only proves who asked and until when; the route checks in the DB on every request
 * that the scan still exists and the viewer may still see it, so delete and disconnect apply at once.
 */
export const LINK_TTL_SECONDS = 3600;
const SKEW_SECONDS = 60;
const encoder = new TextEncoder();

const hmacKey = (secret: string, usage: "sign" | "verify") =>
  crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [usage]);
export type LinkKind = "screenshot" | "favicon" | "replica";
const message = (kind: LinkKind, scanId: string, viewerId: string, exp: number) =>
  encoder.encode(`${kind}:v1|${scanId}|${viewerId}|${exp}`);
type LinkQuery = { v?: string; exp?: string; sig?: string };

export async function signedLink(
  kind: LinkKind,
  secret: string,
  origin: string,
  scanId: string,
  viewerId: string,
  nowSeconds: number,
): Promise<string> {
  const exp = Math.floor(nowSeconds) + LINK_TTL_SECONDS;
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(secret, "sign"), message(kind, scanId, viewerId, exp)));
  const query = new URLSearchParams({ v: viewerId, exp: String(exp), sig: base64url(sig) });
  return `${origin}/${kind}s/${scanId}?${query}`;
}

export const screenshotLink = (secret: string, origin: string, scanId: string, viewerId: string, nowSeconds: number) =>
  signedLink("screenshot", secret, origin, scanId, viewerId, nowSeconds);
export const faviconLink = (secret: string, origin: string, scanId: string, viewerId: string, nowSeconds: number) =>
  signedLink("favicon", secret, origin, scanId, viewerId, nowSeconds);

export const replicaLink = (secret: string, origin: string, scanId: string, viewerId: string, nowSeconds: number) =>
  signedLink("replica", secret, origin, scanId, viewerId, nowSeconds);

export const verifyScreenshotLink = (secret: string, scanId: string, query: LinkQuery, nowSeconds: number) =>
  verifySignedLink("screenshot", secret, scanId, query, nowSeconds);
export const verifyFaviconLink = (secret: string, scanId: string, query: LinkQuery, nowSeconds: number) =>
  verifySignedLink("favicon", secret, scanId, query, nowSeconds);

export const verifyReplicaLink = (secret: string, scanId: string, query: LinkQuery, nowSeconds: number) =>
  verifySignedLink("replica", secret, scanId, query, nowSeconds);

/** The viewer device id of a valid, unexpired link of this kind for this scan, else undefined. */
export async function verifySignedLink(
  kind: LinkKind,
  secret: string,
  scanId: string,
  query: LinkQuery,
  nowSeconds: number,
): Promise<string | undefined> {
  const { v, exp, sig } = query;
  if (!v || v.length > 64 || !exp || !/^\d{1,12}$/.test(exp) || !sig || sig.length !== 43) return undefined;
  const expiry = Number(exp);
  if (expiry <= nowSeconds || expiry > nowSeconds + LINK_TTL_SECONDS + SKEW_SECONDS) return undefined;
  const bytes = fromBase64url(sig);
  // Only the canonical encoding: the last character has 2 spare bits, so 4 spellings decode alike.
  if (!bytes || base64url(bytes) !== sig) return undefined;
  // subtle.verify compares in constant time.
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret, "verify"), bytes, message(kind, scanId, v, expiry));
  return ok ? v : undefined;
}
