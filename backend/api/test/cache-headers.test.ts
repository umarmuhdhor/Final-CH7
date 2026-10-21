import { beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));

// SECURITY §3 P13 (D-alief-40): no client, proxy or CDN may keep a copy of user data.
describe("Cache-Control on user data", () => {
  it("every API response defaults to private, no-store (success and error)", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const created = await call("/devices", { method: "POST", json: { name: "X", mode: "protected" } });
    const code = await call("/family/code", { method: "POST", token: g.token });
    const { code: c } = (await code.clone().json()) as { code: string };
    const join = await call("/family/join", { method: "POST", token: p.token, json: { code: c } });
    const scan = await call("/scans", {
      method: "POST", token: p.token,
      json: { ...blocked92, id: undefined, verdict: undefined, screenshotUrl: undefined },
    });
    const { id } = (await scan.clone().json()) as { id: string };

    const responses: Array<[string, Response]> = [
      ["POST /devices", created],
      ["POST /family/code", code],
      ["POST /family/join", join],
      ["POST /scans", scan],
      ["GET /devices/me", await call("/devices/me", { token: p.token })],
      ["GET /family/members", await call("/family/members", { token: g.token })],
      ["GET /scans?owner=family", await call("/scans?owner=family", { token: g.token })],
      ["GET /scans/{id}", await call(`/scans/${id}`, { token: g.token })],
      ["401", await call("/scans")],
      ["404", await call("/nope")],
      ["GET /healthz", await call("/healthz")],
    ];
    for (const [name, res] of responses) {
      expect(res.status, name).toBeLessThan(500);
      expect(res.headers.get("cache-control"), name).toBe("private, no-store");
    }
  });

  it("the global blocklist (no user data) keeps its short private cache", async () => {
    const p = await createDevice("Mom");
    expect((await call("/blocklist", { token: p.token })).headers.get("cache-control")).toBe("private, max-age=300");
  });
});
