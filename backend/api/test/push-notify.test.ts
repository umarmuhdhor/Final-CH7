import { beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { guardianPush } from "../src/services/push/notify";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));

const principal = (d: Created, name: string, mode: "guardian" | "protected") =>
  ({ deviceId: d.deviceId, name, mode }) as Parameters<typeof guardianPush>[1];
const scan = { id: "00000000-0000-4000-8000-000000000001", status: "blocked" as const, score: 92 };
const TOKEN = "a".repeat(64);

describe("guardianPush (R4 §3)", () => {
  it("protected device with a guardian that has an APNs token → message in the guardian's language", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN, language: "id" } });
    const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
    await call("/family/join", { method: "POST", token: p.token, json: { code } });

    expect(await guardianPush(sql, principal(p, "Mom", "protected"), scan)).toEqual({
      toDeviceId: g.deviceId, apnsToken: TOKEN, body: "Mom membuka situs yang diblokir · 92%", scanId: scan.id,
    });
  });

  it("no push: guardian without token, no guardian, or the guardian's own scan", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    expect(await guardianPush(sql, principal(p, "Mom", "protected"), scan)).toBeUndefined();
    const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
    await call("/family/join", { method: "POST", token: p.token, json: { code } });
    expect(await guardianPush(sql, principal(p, "Mom", "protected"), scan)).toBeUndefined();
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN } });
    expect(await guardianPush(sql, principal(g, "G", "guardian"), scan)).toBeUndefined();
  });
});

describe("guardianPush cap (security review fase 11 M1)", () => {
  it("at most 10 pushes per guardian per 10 min; older rows do not count", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN } });
    const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
    await call("/family/join", { method: "POST", token: p.token, json: { code } });
    const mom = principal(p, "Mom", "protected");

    await sql`insert into push_log (to_device_id, result, created_at)
      select ${g.deviceId}, 'sent', now() - interval '11 minutes' from generate_series(1, 20)`;
    await sql`insert into push_log (to_device_id, result) select ${g.deviceId}, 'sent' from generate_series(1, 9)`;
    expect(await guardianPush(sql, mom, scan)).toBeDefined();
    await sql`insert into push_log (to_device_id, result) values (${g.deviceId}, 'failed:400 BadDeviceToken')`;
    expect(await guardianPush(sql, mom, scan)).toBeUndefined();
  });
});

describe("POST /scans → push_log (LogSender without APNs secrets)", () => {
  const { id: _id, verdict: _v, screenshotUrl: _s, ownerDeviceId: _o, ownerName: _n, ...scanBody } = blocked92;
  const pushRows = async (expected: number) => {
    // The push runs in waitUntil after the response.
    for (let i = 0; i < 20; i++) {
      const r = await sql<{ to_device_id: string; scan_id: string; result: string }[]>`select to_device_id, scan_id, result from push_log`;
      if (r.length >= expected) return r;
      await new Promise((res) => setTimeout(res, 50));
    }
    return sql<{ to_device_id: string; scan_id: string; result: string }[]>`select to_device_id, scan_id, result from push_log`;
  };
  const link = async (g: Created, p: Created) => {
    const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
    await call("/family/join", { method: "POST", token: p.token, json: { code } });
  };

  it("protected scan with a guardian token → one 'logged' row for the guardian", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN } });
    await link(g, p);
    const res = await call("/scans", { method: "POST", token: p.token, json: scanBody });
    expect(res.status).toBe(201);
    const { id } = (await res.json()) as { id: string };
    expect(await pushRows(1)).toEqual([{ to_device_id: g.deviceId, scan_id: id, result: "logged" }]);
  });

  it("no row for the guardian's own scan, no guardian, or a guardian without a token", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    expect((await call("/scans", { method: "POST", token: p.token, json: scanBody })).status).toBe(201);
    await link(g, p);
    expect((await call("/scans", { method: "POST", token: p.token, json: scanBody })).status).toBe(201);
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN } });
    expect((await call("/scans", { method: "POST", token: g.token, json: scanBody })).status).toBe(201);
    await new Promise((res) => setTimeout(res, 300));
    expect(await pushRows(0)).toEqual([]);
  });
});
