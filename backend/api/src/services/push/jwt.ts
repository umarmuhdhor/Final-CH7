import { base64url } from "../../http/crypto";

const encoder = new TextEncoder();

/** Imports an APNs .p8 key (PEM, PKCS#8, P-256) for ES256 signing. */
export async function importApnsKey(pem: string): Promise<CryptoKey> {
  const b64 = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/**
 * APNs provider token: JWT ES256 with header { alg, kid } and claims { iss: teamId, iat }.
 * WebCrypto ECDSA returns the raw r||s signature, which is what JWS ES256 expects.
 */
export async function apnsJwt(key: CryptoKey, keyId: string, teamId: string, now = Date.now()): Promise<string> {
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: teamId, iat: Math.floor(now / 1000) })));
  const input = `${header}.${claims}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input));
  return `${input}.${base64url(new Uint8Array(sig))}`;
}
