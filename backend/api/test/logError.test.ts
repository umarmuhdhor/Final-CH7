import { describe, expect, it } from "vitest";
import { errorInfo } from "../src/http/logError";

describe("errorInfo (SECURITY §3 P6)", () => {
  it("keeps name and SQLSTATE, drops the message", () => {
    const pg = Object.assign(new Error('insert or update on table "push_log" violates key (to_device_id)=(dev_secret)'), { name: "PostgresError", code: "23503" });
    expect(errorInfo(pg)).toEqual({ name: "PostgresError", code: "23503" });
    expect(JSON.stringify(errorInfo(new TypeError("fetch https://api.push.apple.com/3/device/abcdef")))).toBe('{"name":"TypeError"}');
    expect(errorInfo("raw string")).toEqual({ name: "Error" });
    expect(errorInfo(Object.assign(new Error("x"), { code: "ECONNRESET with detail" }))).toEqual({ name: "Error" });
  });
});
