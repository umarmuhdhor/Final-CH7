import { afterEach, describe, expect, it, vi } from "vitest";
import { signedLink, verifySignedLink, type LinkKind } from "../src/services/screenshotLinks";

// Fase 22 O1: the HMAC key is imported once per secret and usage, not per link.

afterEach(() => vi.restoreAllMocks());

const SECRET = "golden-secret-0123456789abcdef0123456789";
const SCAN = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03";
const NOW = 1_793_000_000;
const query = (link: string) => Object.fromEntries(new URL(link).searchParams) as { v?: string; exp?: string; sig?: string };

describe("signed links with a cached HMAC key (fase 22 O1)", () => {
  // Computed outside the Worker: HMAC-SHA256(secret, "<kind>:v1|scan|viewer|exp"), base64url. Same as main before O1.
  const golden: Record<LinkKind, string> = {
    screenshot: "v42P-CLUUtJzig48kdFUHNYBT2hqMCaAKEj_DSkiGdM",
    favicon: "sMql7LfAhoSp8SSoC010VfeaqpLwsEH5zW28LlPykA0",
    replica: "e_I848jYCZaUv-wCJiS5yOw56URODfQIbhhh7CFjCJI",
  };

  it("golden vectors: the signature is byte-for-byte the same as before", async () => {
    for (const kind of ["screenshot", "favicon", "replica"] as const) {
      const link = await signedLink(kind, SECRET, "https://api.test", SCAN, "dev_viewer_1", NOW);
      expect(link).toBe(`https://api.test/${kind}s/${SCAN}?v=dev_viewer_1&exp=${NOW + 3600}&sig=${golden[kind]}`);
    }
  });

  it("a link signed before the cache verifies; a link of another kind does not", async () => {
    const q = { v: "dev_viewer_1", exp: String(NOW + 3600), sig: golden.replica };
    expect(await verifySignedLink("replica", SECRET, SCAN, q, NOW)).toBe("dev_viewer_1");
    expect(await verifySignedLink("favicon", SECRET, SCAN, q, NOW)).toBeUndefined();
  });

  it("a rotated secret rejects links of the old secret (the cache is per secret)", async () => {
    const old = await signedLink("screenshot", SECRET, "https://api.test", SCAN, "dev_viewer_1", NOW);
    expect(await verifySignedLink("screenshot", SECRET, SCAN, query(old), NOW)).toBe("dev_viewer_1");
    const rotated = "rotated-secret-0123456789abcdef012345678";
    expect(await verifySignedLink("screenshot", rotated, SCAN, query(old), NOW)).toBeUndefined();
    const fresh = await signedLink("screenshot", rotated, "https://api.test", SCAN, "dev_viewer_1", NOW);
    expect(await verifySignedLink("screenshot", rotated, SCAN, query(fresh), NOW)).toBe("dev_viewer_1");
    expect(await verifySignedLink("screenshot", SECRET, SCAN, query(fresh), NOW)).toBeUndefined();
  });

  it("imports the key once for 50 links and once for 50 checks", async () => {
    const secret = "spy-secret-0123456789abcdef0123456789abcd";
    // A secret no other test uses, so no cached key can satisfy the count. signedLink reaches hmacKey
    // before its first await, so the first call caches the promise the other 49 then share.
    const spy = vi.spyOn(crypto.subtle, "importKey");
    const links = await Promise.all(
      Array.from({ length: 50 }, (_, i) => signedLink("favicon", secret, "https://api.test", SCAN, `dev_${i}`, NOW)),
    );
    expect(spy).toHaveBeenCalledTimes(1);
    for (const link of links) expect(await verifySignedLink("favicon", secret, SCAN, query(link), NOW)).toBeDefined();
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it("a failed import is not cached", async () => {
    const secret = "fail-secret-0123456789abcdef0123456789abc";
    const real = crypto.subtle.importKey.bind(crypto.subtle);
    const spy = vi.spyOn(crypto.subtle, "importKey").mockRejectedValueOnce(new DOMException("boom", "OperationError"));
    await expect(signedLink("screenshot", secret, "https://api.test", SCAN, "dev_viewer_1", NOW)).rejects.toThrow("boom");
    spy.mockImplementation(real);
    await expect(signedLink("screenshot", secret, "https://api.test", SCAN, "dev_viewer_1", NOW)).resolves.toContain("sig=");
  });
});
