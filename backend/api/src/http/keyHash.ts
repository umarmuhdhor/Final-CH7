import { usableSecret } from "./crypto";

const encoder = new TextEncoder();
let secret: string | undefined;
let key: Promise<CryptoKey> | undefined;

/**
 * Called per request with env.RATE_KEY_SECRET. The secret is fixed per deployment, so the
 * imported key is cached per isolate and only re-imported when the value changes.
 */
export function useRateKeySecret(value: string | undefined): void {
  if (value === secret) return;
  secret = value;
  const usable = usableSecret(value);
  key = usable
    ? crypto.subtle.importKey("raw", encoder.encode(usable), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
    : undefined;
}

/**
 * Hash for rate-limit keys and join attempt IPs (D-alief-B12, D-alief-40). HMAC-SHA256 with
 * RATE_KEY_SECRET: a plain sha256 of an IPv4 address can be reversed by trying all 2^32.
 * Fails closed without a secret of at least 32 characters: no request that stores a key runs
 * with a reversible hash (set it in .dev.vars for local dev).
 */
export async function keyHash(input: string): Promise<Uint8Array> {
  if (!key) throw new RateKeySecretMissing();
  return new Uint8Array(await crypto.subtle.sign("HMAC", await key, encoder.encode(input)));
}

export class RateKeySecretMissing extends Error {
  override name = "RateKeySecretMissing";
}
