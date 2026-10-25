import { describe, expect, it } from "vitest";
import { appIds } from "../src/routes/app-site-association";
import { call } from "./helpers/seed";

describe("GET /.well-known/apple-app-site-association", () => {
  it("JSON without auth or redirect; no app listed while APPLINKS_APP_IDS is empty", async () => {
    const res = await call("/.well-known/apple-app-site-association");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/^application\/json/);
    expect(res.headers.get("cache-control")).toBe("public, max-age=3600");
    expect(await res.json()).toEqual({ applinks: { details: [] } });
  });
});

describe("appIds", () => {
  it("keeps <Team ID>.<bundle ID> entries, drops malformed ones", () => {
    expect(appIds("ABCDE12345.com.shoo.app, XYZ9876543.id.example.shoo")).toEqual([
      "ABCDE12345.com.shoo.app",
      "XYZ9876543.id.example.shoo",
    ]);
    expect(appIds("abcde12345.com.shoo.app,ABCDE12345,ABCDE12345.shoo,ABCDE12345.com.shoo app,")).toEqual([]);
    expect(appIds(undefined)).toEqual([]);
  });
});
