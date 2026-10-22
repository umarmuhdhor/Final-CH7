import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { ApiError } from "../src/http/errors";
import { useRateKeySecret } from "../src/http/keyHash";
import { clientIp, hitLight } from "../src/http/rateLimit";
import { resetDb, testSql } from "./helpers/resetDb";

useRateKeySecret(env.RATE_KEY_SECRET);

const key = (ip?: string) => clientIp((n) => (n === "cf-connecting-ip" ? ip : undefined));

describe("clientIp", () => {
  it.each([
    ["203.0.113.7", "203.0.113.7"],
    ["2001:db8:1:2::5", "2001:db8:1:2::/64"],
    ["2001:0db8:0001:0002:aaaa:bbbb:cccc:dddd", "2001:db8:1:2::/64"],
    ["2001:db8::1", "2001:db8:0:0::/64"],
    ["::1", "0:0:0:0::/64"],
    ["::ffff:198.51.100.4", "198.51.100.4"],
    ["::FFFF:198.51.100.4", "198.51.100.4"],
  ])("%s → %s", (ip, expected) => {
    expect(key(ip)).toBe(expected);
  });

  it("malformed IPv6 never throws", () => {
    expect(() => key("1:2:3:4:5:6:7:8:9::1")).not.toThrow();
    expect(() => key(":::")).not.toThrow();
  });
});

describe("hitLight (one statement, best effort)", () => {
  const sql = testSql();
  beforeEach(() => resetDb(sql));

  it("allows max hits per window, then throws rate_limited with Retry-After", async () => {
    const limit = { bucket: "test_light", max: 3, windowSeconds: 10 };
    for (let i = 0; i < 3; i++) await hitLight(sql, limit, "k");
    const err = await hitLight(sql, limit, "k").then(() => undefined, (e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).code).toBe("rate_limited");
    expect((err as ApiError).retryAfter).toBeGreaterThanOrEqual(1);
    expect((err as ApiError).retryAfter).toBeLessThanOrEqual(10);
    // A rejected hit is not recorded; other keys are independent.
    const [n] = await sql<{ n: number }[]>`select count(*)::int as n from rate_limit_hits where bucket = 'test_light'`;
    expect(n!.n).toBe(3);
    await hitLight(sql, limit, "other");
  });
});
