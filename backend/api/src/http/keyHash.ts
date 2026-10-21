import { sha256 } from "./crypto";

const encoder = new TextEncoder();
let secret: string | undefined;
let key: Promise<CryptoKey> | undefined;
let warned = false;

/**
 * Called per request with env.RATE_KEY_SECRET. The secret is fixed per deployment, so the
 * imported key is cached per isolate and only re-imported when the value changes.
 */
export function useRateKeySecret(value: string | undefined): void {
  if (value === secret) return;
  secret = value;
  key = value
    ? crypto.subtle.importKey("raw", encoder.encode(value), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
    : undefined;
}

/**
 * Hash for rate-limit keys and join attempt IPs (D-alief-B12, D-alief-40). HMAC-SHA256 with
 * RATE_KEY_SECRET: a plain sha256 of an IPv4 address can be reversed by trying all 2^32.
 * Without the secret (local dev) it falls back to sha256 and warns once.
 */
export async function keyHash(input: string): Promise<Uint8Array> {
  if (!key) {
    if (!warned) {
      warned = true;
      console.log(JSON.stringify({ event: "rate_key_secret_missing" }));
    }
    return sha256(input);
  }
  return new Uint8Array(await crypto.subtle.sign("HMAC", await key, encoder.encode(input)));
}
