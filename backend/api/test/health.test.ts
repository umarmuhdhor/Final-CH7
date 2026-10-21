import { beforeEach, describe, expect, it } from "vitest";
import { resetDb, testSql } from "./helpers/resetDb";
import { call } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));

describe("health", () => {
  it("GET /healthz without DB", async () => {
    const res = await call("/healthz");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(res.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("GET /healthz/db writes ops_heartbeat and is limited to 1/min per IP", async () => {
    const res = await call("/healthz/db", { ip: "192.0.2.1" });
    expect(res.status).toBe(200);
    const rows = await sql`select source from ops_heartbeat`;
    expect(rows.map((r) => r.source)).toEqual(["healthz"]);

    const again = await call("/healthz/db", { ip: "192.0.2.1" });
    expect(again.status).toBe(429);
    expect(again.headers.get("retry-after")).toBeTruthy();
  });

  it("unknown route → contract error shape", async () => {
    const res = await call("/nope");
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "not_found", message: "Not found" } });
  });
});
