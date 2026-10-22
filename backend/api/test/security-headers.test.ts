import { beforeEach, describe, expect, it } from "vitest";
import { limits } from "../src/http/rateLimit";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, freshIp } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));

const SECURITY = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "x-frame-options": "DENY",
  "strict-transport-security": "max-age=31536000; includeSubDomains",
};
const expectSecurityHeaders = (res: Response) => {
  for (const [k, v] of Object.entries(SECURITY)) expect(res.headers.get(k), k).toBe(v);
  expect(res.headers.get("access-control-allow-origin")).toBeNull();
};

describe("security headers on every response (fase 12 hardening)", () => {
  it("JSON 200, 401, 404, 422 and 413 carry them plus a deny-all CSP", async () => {
    const d = await createDevice();
    const responses = [
      await call("/healthz"),
      await call("/devices/me", { token: d.token }),
      await call("/devices/me"),
      await call("/nope"),
      await call("/devices", { method: "POST", json: { name: "" } }),
    ];
    expect(responses.map((r) => r.status)).toEqual([200, 200, 401, 404, 422]);
    for (const res of responses) {
      expectSecurityHeaders(res);
      expect(res.headers.get("content-security-policy")).toBe("default-src 'none'; frame-ancestors 'none'");
    }
  });

  it("pages with their own CSP keep it (/join)", async () => {
    const res = await call("/join?code=1234");
    expect(res.status).toBe(200);
    expectSecurityHeaders(res);
    expect(res.headers.get("content-security-policy")).not.toBe("default-src 'none'; frame-ancestors 'none'");
    expect(res.headers.get("content-security-policy")).toContain("default-src 'none'");
  });

  it("CORS is closed: a preflight gets no Access-Control headers (401 behind auth, 404 elsewhere)", async () => {
    const res = await call("/scans", {
      method: "OPTIONS",
      headers: { origin: "https://evil.example", "access-control-request-method": "POST" },
    });
    expect(res.status).toBe(401);
    expect((await call("/healthz", { method: "OPTIONS", headers: { origin: "https://evil.example" } })).status).toBe(404);
    expectSecurityHeaders(res);
    expect([...res.headers.keys()].filter((k) => k.startsWith("access-control-"))).toEqual([]);
  });

  it("a declared body over 256 KB → 413 before any DB work (no rate-limit row)", async () => {
    const res = await call("/devices", {
      method: "POST",
      headers: { "content-type": "application/json", "content-length": String(300 * 1024) },
      body: "x".repeat(300 * 1024),
    });
    expect(res.status).toBe(413);
    expectSecurityHeaders(res);
    expect((await sql`select 1 from rate_limit_hits`).length).toBe(0);
  });
});

describe("repeated unknown tokens per IP (D-alief-B05)", () => {
  it(`after ${limits.authFail.max} unknown tokens from one IP → still 401 but with Retry-After; a valid token from that IP still works`, async () => {
    const ip = freshIp();
    const d = await createDevice();
    for (let i = 0; i < limits.authFail.max; i++) {
      const res = await call("/devices/me", { token: `shoo_unknown${String(i).padStart(8, "0")}`, ip });
      expect(res.status).toBe(401);
      expect(res.headers.get("retry-after")).toBeNull();
    }
    // Over the limit: 401 (a dead token must look dead, not like a retryable 429).
    const blocked = await call("/devices/me", { token: "shoo_unknown_last_one", ip });
    expect(blocked.status).toBe(401);
    expect((await sql`select 1 from rate_limit_hits where bucket = 'auth_fail'`).length).toBe(limits.authFail.max);
    expect(Number(blocked.headers.get("retry-after"))).toBeGreaterThan(0);
    expect((await call("/devices/me", { token: d.token, ip })).status).toBe(200);
    // Another IP is not affected.
    expect((await call("/devices/me", { token: "shoo_unknown_other_ip", ip: freshIp() })).status).toBe(401);
  });

  it("a missing or malformed header is 401 with no DB work", async () => {
    await call("/devices/me", { ip: "203.0.113.9" });
    await call("/devices/me", { headers: { authorization: "Bearer nope" }, ip: "203.0.113.9" });
    expect((await sql`select 1 from rate_limit_hits`).length).toBe(0);
  });
});

describe("rate-limit keys are keyed hashes (D-alief-B12)", () => {
  it("the stored key is HMAC(RATE_KEY_SECRET), not a plain sha256 of the IP", async () => {
    const { env } = await import("cloudflare:workers");
    const { sha256 } = await import("../src/http/crypto");
    const { keyHash, useRateKeySecret } = await import("../src/http/keyHash");
    useRateKeySecret(env.RATE_KEY_SECRET);
    await call("/devices", { method: "POST", json: { name: "A", mode: "guardian" }, ip: "203.0.113.77" });
    const [row] = await sql<{ key_hash: Uint8Array }[]>`select key_hash from rate_limit_hits where bucket = 'devices_create'`;
    const stored = Buffer.from(row!.key_hash);
    expect(stored.equals(Buffer.from(await keyHash("devices_create:203.0.113.77")))).toBe(true);
    expect(stored.equals(Buffer.from(await sha256("devices_create:203.0.113.77")))).toBe(false);
  });
});
