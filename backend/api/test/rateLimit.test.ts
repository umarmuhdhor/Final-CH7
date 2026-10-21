import { describe, expect, it } from "vitest";
import { clientIp } from "../src/http/rateLimit";

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
