import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { sha256 } from "../src/http/crypto";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
beforeEach(() => resetDb(sql));

const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

describe("POST /devices", () => {
  it("creates a device and returns the token once", async () => {
    const res = await call("/devices", { method: "POST", json: { name: "Adhella", mode: "guardian" } });
    expect(res.status).toBe(201);
    const body = (await res.json()) as { deviceId: string; token: string; avatarId: string };
    expect(Object.keys(body).sort()).toEqual(["avatarId", "deviceId", "token"]);
    expect(body.token).toMatch(/^shoo_[A-Za-z0-9_-]{43}$/);
    expect(body.avatarId).toMatch(/^avatar_(0[1-9]|1[0-2])$/);

    const [row] = await sql<{ token_hash: Uint8Array; name: string; mode: string; language: string }[]>`
      select token_hash, name, mode, language from devices where id = ${body.deviceId}`;
    expect(row).toMatchObject({ name: "Adhella", mode: "guardian", language: "en" });
    expect(Buffer.from(row!.token_hash).equals(Buffer.from(await sha256(body.token)))).toBe(true);
    expect(Buffer.from(row!.token_hash).toString()).not.toContain(body.token);
  });

  it("stores an optional APNs token", async () => {
    const apns = "ab".repeat(32);
    const res = await call("/devices", { method: "POST", json: { name: "Mom", mode: "protected", apnsToken: apns } });
    const { deviceId } = (await res.json()) as { deviceId: string };
    const [row] = await sql`select apns_token from devices where id = ${deviceId}`;
    expect(row!.apns_token).toBe(apns);
  });

  it("accepts 20 emoji (code points, not UTF-16 units)", async () => {
    const res = await call("/devices", { method: "POST", json: { name: "😀".repeat(20), mode: "protected" } });
    expect(res.status).toBe(201);
  });

  it.each([
    [{ name: "", mode: "guardian" }],
    [{ name: "   ", mode: "guardian" }],
    [{ name: "x".repeat(21), mode: "guardian" }],
    [{ name: "Mom", mode: "admin" }],
    [{ name: "Mom" }],
    [{ name: "Mom", mode: "guardian", apnsToken: "not-hex" }],
    [{ name: "Mom", mode: "guardian", apnsToken: null }],
    [{ name: "Mo\u0000m", mode: "guardian" }],
    [{ name: "Mo\u0007m", mode: "guardian" }],
    [{ name: "Mom\u202Egnp.exe", mode: "guardian" }],
    [[]],
  ])("422 invalid_body for %j", async (json) => {
    const res = await call("/devices", { method: "POST", json });
    expect(res.status).toBe(422);
    expect(await errorCode(res)).toBe("invalid_body");
  });

  it("400 bad_json for broken JSON", async () => {
    const res = await call("/devices", { method: "POST", body: "{nope", headers: { "content-type": "application/json" } });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("bad_json");
  });

  it("413 too_large for a huge body", async () => {
    const res = await call("/devices", { method: "POST", json: { name: "Mom", mode: "guardian", pad: "x".repeat(20_000) } });
    expect(res.status).toBe(413);
    expect(await errorCode(res)).toBe("too_large");
  });

  it("413 too_large for a streamed body without content-length", async () => {
    const chunk = new TextEncoder().encode("x".repeat(4096));
    let sent = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(ctrl) {
        if (sent++ < 6) ctrl.enqueue(chunk);
        else ctrl.close();
      },
    });
    const res = await call("/devices", {
      method: "POST",
      body,
      headers: { "content-type": "application/json" },
      duplex: "half",
    } as RequestInit);
    expect(res.status).toBe(413);
    expect(await errorCode(res)).toBe("too_large");
  });

  it("rate limit holds under parallel requests", async () => {
    const ip = "203.0.113.9";
    const results = await Promise.all(
      Array.from({ length: 14 }, (_, i) =>
        call("/devices", { method: "POST", ip, json: { name: `P${i}`, mode: "protected" } }).then((r) => r.status),
      ),
    );
    expect(results.filter((s) => s === 201)).toHaveLength(10);
    expect(results.filter((s) => s === 429)).toHaveLength(4);
  });

  it("IPv6 addresses in one /64 share a bucket", async () => {
    for (let i = 0; i < 10; i++) {
      const ip = `2001:db8:1:2::${(i + 1).toString(16)}`;
      expect((await call("/devices", { method: "POST", ip, json: { name: `V${i}`, mode: "protected" } })).status).toBe(201);
    }
    const res = await call("/devices", { method: "POST", ip: "2001:db8:1:2:ffff::1", json: { name: "V10", mode: "protected" } });
    expect(res.status).toBe(429);
    const other = await call("/devices", { method: "POST", ip: "2001:db8:1:3::1", json: { name: "W", mode: "protected" } });
    expect(other.status).toBe(201);
  });

  it("rate limits 10 per hour per IP with Retry-After", async () => {
    const ip = "203.0.113.7";
    for (let i = 0; i < 10; i++) {
      const ok = await call("/devices", { method: "POST", ip, json: { name: `D${i}`, mode: "protected" } });
      expect(ok.status).toBe(201);
    }
    const res = await call("/devices", { method: "POST", ip, json: { name: "D10", mode: "protected" } });
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("rate_limited");
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);

    const other = await call("/devices", { method: "POST", ip: "203.0.113.8", json: { name: "X", mode: "protected" } });
    expect(other.status).toBe(201);
    // Only keyHash('<bucket>:<ip>') (HMAC) is stored, never the raw IP.
    const hash = await keyHash("devices_create:203.0.113.7");
    const [row] = await sql<{ n: number }[]>`select count(*)::int as n from rate_limit_hits where key_hash = ${hash}`;
    expect(row!.n).toBe(10);
  });
});

describe("PATCH /devices/me", () => {
  const patch = (token: string | undefined, json: unknown) => call("/devices/me", { method: "PATCH", token, json });

  it("401 without or with an unknown token", async () => {
    expect((await patch(undefined, { name: "x" })).status).toBe(401);
    const res = await patch("shoo_" + "A".repeat(43), { name: "x" });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("unauthorized");
    const malformed = await call("/devices/me", { method: "PATCH", json: {}, headers: { authorization: "Basic abc" } });
    expect(malformed.status).toBe(401);
  });

  it("updates only the caller's own row", async () => {
    const me = await createDevice("Mom");
    const other = await createDevice("Dad");
    const res = await patch(me.token, { name: "Mama", language: "id", apnsToken: "cd".repeat(32) });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });

    const rows = await sql`select id, name, language, apns_token from devices order by name`;
    expect(rows.find((r) => r.id === me.deviceId)).toMatchObject({ name: "Mama", language: "id", apns_token: "cd".repeat(32) });
    expect(rows.find((r) => r.id === other.deviceId)).toMatchObject({ name: "Dad", language: "en", apns_token: null });
  });

  it("empty body and unknown fields change nothing", async () => {
    const me = await createDevice("Mom");
    expect((await patch(me.token, {})).status).toBe(200);
    expect((await patch(me.token, { mode: "guardian", avatarId: "avatar_01", foo: 1 })).status).toBe(200);
    const [row] = await sql`select name, mode from devices where id = ${me.deviceId}`;
    expect(row).toMatchObject({ name: "Mom", mode: "protected" });
  });

  it("apnsToken null clears it", async () => {
    const me = await createDevice("Mom");
    await patch(me.token, { apnsToken: "ef".repeat(32) });
    await patch(me.token, { apnsToken: null });
    const [row] = await sql`select apns_token from devices where id = ${me.deviceId}`;
    expect(row!.apns_token).toBeNull();
  });

  it.each([[{ name: "" }], [{ name: "x".repeat(21) }], [{ language: "fr" }], [{ extensionLastSeenAt: "yesterday" }],
    [{ extensionLastSeenAt: "0000-01-01T00:00:00Z" }], [{ name: "a\u0000b" }]])(
    "422 for %j",
    async (json) => {
      const me = await createDevice();
      const res = await patch(me.token, json);
      expect(res.status).toBe(422);
      expect(await errorCode(res)).toBe("invalid_body");
    },
  );

  it("400 bad_json", async () => {
    const me = await createDevice();
    const res = await call("/devices/me", { method: "PATCH", token: me.token, body: "nope" });
    expect(res.status).toBe(400);
  });

  it("extensionLastSeenAt: stored, never moves backwards, future rejected", async () => {
    const me = await createDevice();
    const t1 = new Date(Date.now() - 60_000).toISOString();
    const t0 = new Date(Date.now() - 3_600_000).toISOString();
    expect((await patch(me.token, { extensionLastSeenAt: t1 })).status).toBe(200);
    expect((await patch(me.token, { extensionLastSeenAt: t0 })).status).toBe(200);
    const [row] = await sql<{ ext: Date }[]>`select ext_last_seen_at as ext from devices where id = ${me.deviceId}`;
    expect(row!.ext.toISOString()).toBe(t1);

    const future = new Date(Date.now() + 10 * 60_000).toISOString();
    const res = await patch(me.token, { extensionLastSeenAt: future });
    expect(res.status).toBe(422);

    const small = new Date(Date.now() + 60_000).toISOString(); // within 5 min clock skew
    expect((await patch(me.token, { extensionLastSeenAt: small })).status).toBe(200);
  });
});
