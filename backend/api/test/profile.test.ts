import { beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { REMIND_EVERY_HOURS } from "../src/db/repo/families";
import { guardianPush } from "../src/services/push/notify";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";

// PF-01 profile redesign: proposed contract additions (backend/API.md "PF-01 profile").
const sql = testSql();
beforeEach(() => resetDb(sql));

const TOKEN = "b".repeat(64);
const { id: _id, verdict: _v, screenshotUrl: _s, ownerDeviceId: _o, ownerName: _n, ...scanBody } = blocked92;

const link = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};
const patchMe = (d: Created, json: unknown) => call("/devices/me", { method: "PATCH", token: d.token, json });
const me = async (d: Created) => (await (await call("/devices/me", { token: d.token })).json()) as Record<string, unknown>;
const members = async (g: Created) =>
  ((await (await call("/family/members", { token: g.token })).json()) as { members: Record<string, unknown>[] }).members;
const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

/** Push rows are written in waitUntil after the response. */
async function pushRows(toDeviceId: string, expected: number) {
  const read = () => sql<{ scan_id: string | null; result: string }[]>`
    select scan_id, result from push_log where to_device_id = ${toDeviceId}`;
  for (let i = 0; i < 20; i++) {
    const r = await read();
    if (r.length >= expected) return r;
    await new Promise((res) => setTimeout(res, 50));
  }
  return read();
}

describe("stats on GET /devices/me", () => {
  it("counts blocked and warning scans for life, past the 14-day retention", async () => {
    const p = await createDevice("Mom");
    expect((await me(p)).stats).toEqual({ blocked: 0, warnings: 0, since: expect.stringMatching(/Z$/) });
    for (const status of ["blocked", "blocked", "warning"] as const) {
      const res = await call("/scans", { method: "POST", token: p.token, json: { ...scanBody, status, score: status === "blocked" ? 92 : 50 } });
      expect(res.status).toBe(201);
    }
    // Retention removing every row does not lower the counters.
    await sql`delete from scans where owner_id = ${p.deviceId}`;
    expect((await me(p)).stats).toMatchObject({ blocked: 2, warnings: 1 });
  });
});

describe("PATCH /devices/me { deviceModel, osVersion }", () => {
  it("stores a marketing name and a major version, shown to the guardian", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await link(g, p);
    expect((await patchMe(p, { deviceModel: "iPhone 15", osVersion: "26" })).status).toBe(200);
    expect((await members(g))[0]).toMatchObject({ deviceModel: "iPhone 15", osVersion: "26" });
  });

  it("rejects anything else (422)", async () => {
    const p = await createDevice("Mom");
    for (const json of [{ deviceModel: "" }, { deviceModel: "x".repeat(41) }, { deviceModel: "<b>" }, { osVersion: "26.1" }, { osVersion: "abc" }]) {
      expect((await patchMe(p, json)).status).toBe(422);
    }
  });
});

describe("GET /family/members (PF-01 fields)", () => {
  it("connectedAt, lastSeenAt, notify, remindedAt, stats", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await link(g, p);
    const [m] = await members(g);
    expect(m).toMatchObject({
      connectedAt: expect.stringMatching(/Z$/), lastSeenAt: null, deviceModel: null, osVersion: null,
      notify: true, remindedAt: null, stats: { blocked: 0, warnings: 0 },
    });
    const seen = new Date(Date.now() - 120_000).toISOString();
    await patchMe(p, { extensionLastSeenAt: seen });
    expect((await members(g))[0]!.lastSeenAt).toBe(seen);
  });
});

describe("PATCH /family/members/{deviceId} { notify }", () => {
  it("off skips the guardian's push; the scan is still stored", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await patchMe(g, { apnsToken: TOKEN });
    await link(g, p);
    const principal = { deviceId: p.deviceId, name: "Mom", mode: "protected", language: "en" } as const;
    const scan = { id: "00000000-0000-4000-8000-000000000002", status: "blocked" as const, score: 92 };
    expect(await guardianPush(sql, principal, scan)).toBeDefined();

    const res = await call(`/family/members/${p.deviceId}`, { method: "PATCH", token: g.token, json: { notify: false } });
    expect(res.status).toBe(200);
    expect((await members(g))[0]!.notify).toBe(false);
    expect(await guardianPush(sql, principal, scan)).toBeUndefined();
    expect((await call("/scans", { method: "POST", token: p.token, json: scanBody })).status).toBe(201);
  });

  it("404 for a device that is not my member; 422 for a bad body; 403 for a protected caller", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    expect((await call(`/family/members/${p.deviceId}`, { method: "PATCH", token: g.token, json: { notify: false } })).status).toBe(404);
    await link(g, p);
    for (const json of [{}, { notify: "no" }, { notify: true, extra: 1 }]) {
      expect((await call(`/family/members/${p.deviceId}`, { method: "PATCH", token: g.token, json })).status).toBe(422);
    }
    expect((await call(`/family/members/${p.deviceId}`, { method: "PATCH", token: p.token, json: { notify: false } })).status).toBe(403);
  });
});

describe("POST /family/members/{deviceId}/remind", () => {
  const remind = (g: Created, p: Created) => call(`/family/members/${p.deviceId}/remind`, { method: "POST", token: g.token });

  it("pushes to the member once per 6 h; remindedAt shows it", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await link(g, p);
    await patchMe(p, { apnsToken: TOKEN });

    expect((await remind(g, p)).status).toBe(200);
    expect(await pushRows(p.deviceId, 1)).toEqual([{ scan_id: null, result: "logged" }]);
    expect((await members(g))[0]!.remindedAt).toEqual(expect.stringMatching(/Z$/));

    const again = await remind(g, p);
    expect(again.status).toBe(429);
    expect(Number(again.headers.get("retry-after"))).toBeGreaterThan(REMIND_EVERY_HOURS * 3600 - 60);
    expect(await errorCode(again)).toBe("remind_too_soon");

    await sql`update family_links set reminded_at = now() - make_interval(hours => ${REMIND_EVERY_HOURS}) where protected_id = ${p.deviceId}`;
    expect((await remind(g, p)).status).toBe(200);
  });

  it("409 push_unavailable without a member token (slot not used); 404 for a stranger", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    expect((await remind(g, p)).status).toBe(404);
    await link(g, p);
    const res = await remind(g, p);
    expect(res.status).toBe(409);
    expect(await errorCode(res)).toBe("push_unavailable");
    expect((await members(g))[0]!.remindedAt).toBeNull();
  });
});

describe("DELETE /family/members/{deviceId} tells the member", () => {
  it("one push to the removed member when it has a token, none otherwise", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const q = await createDevice("Dad");
    await patchMe(p, { apnsToken: TOKEN });
    await link(g, p);
    await link(g, q);
    expect((await call(`/family/members/${p.deviceId}`, { method: "DELETE", token: g.token })).status).toBe(200);
    expect((await call(`/family/members/${q.deviceId}`, { method: "DELETE", token: g.token })).status).toBe(200);
    expect(await pushRows(p.deviceId, 1)).toEqual([{ scan_id: null, result: "logged" }]);
    expect(await pushRows(q.deviceId, 0)).toEqual([]);
  });
});
