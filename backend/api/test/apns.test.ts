import { describe, expect, it } from "vitest";
import { base64url } from "../src/http/crypto";
import { apnsJwt, importApnsKey } from "../src/services/push/jwt";

const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));

async function testPem(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const b64 = btoa(String.fromCharCode(...der)).replace(/(.{64})/g, "$1\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

describe("APNs JWT (ES256)", () => {
  it("signs a verifiable provider token from a PKCS#8 PEM", async () => {
    const { pem, publicKey } = await testPem();
    const key = await importApnsKey(pem);
    const jwt = await apnsJwt(key, "KEY1234567", "TEAM123456", Date.UTC(2026, 9, 21) );
    const [h, p, s] = jwt.split(".");
    expect(decode(h!)).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(decode(p!)).toEqual({ iss: "TEAM123456", iat: Date.UTC(2026, 9, 21) / 1000 });

    const sig = Uint8Array.from(atob(s!.replace(/-/g, "+").replace(/_/g, "/") + "=="), (c) => c.charCodeAt(0));
    expect(sig.byteLength).toBe(64); // raw r||s
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      sig,
      new TextEncoder().encode(`${h}.${p}`),
    );
    expect(ok).toBe(true);
    expect(base64url(new Uint8Array([251, 255]))).toBe("-_8");
  });
});

