import { beforeEach, describe, expect, it } from "vitest";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));

const me = async (d: Created) => {
  const res = await call("/devices/me", { token: d.token });
  expect(res.status).toBe(200);
  return res.json();
};
const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};

describe("GET /devices/me", () => {
  it("guardian: own profile, guardian always null", async () => {
    const g = await createDevice("Adhella", "guardian");
    await call("/devices/me", { method: "PATCH", token: g.token, json: { language: "id" } });
    expect(await me(g)).toEqual({
      deviceId: g.deviceId, name: "Adhella", avatarId: g.avatarId, mode: "guardian", language: "id", guardian: null,
    });
  });

  it("protected: guardian filled while linked, null after the guardian removes it", async () => {
    const g = await createDevice("Adhella", "guardian");
    const p = await createDevice("Mom");
    expect(await me(p)).toMatchObject({ mode: "protected", language: "en", guardian: null });

    await connect(g, p);
    expect(await me(p)).toEqual({
      deviceId: p.deviceId, name: "Mom", avatarId: p.avatarId, mode: "protected", language: "en",
      guardian: { deviceId: g.deviceId, name: "Adhella", avatarId: g.avatarId },
    });

    expect((await call(`/family/members/${p.deviceId}`, { method: "DELETE", token: g.token })).status).toBe(200);
    expect(((await me(p)) as { guardian: unknown }).guardian).toBeNull();
  });

  it("401 without token", async () => {
    expect((await call("/devices/me")).status).toBe(401);
  });
});

describe("DELETE /devices/me (proposal C19)", () => {
  it("protected: deletes the device, its link, scans, verdicts and attempts; token stops working", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await connect(g, p);
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, screenshot_path)
      values ('s_del', ${p.deviceId}, 'https://x.example/', 'x.example', 92, 'blocked', now(), ${p.deviceId + "/s_del.jpg"})`;
    await sql`insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
      values (${p.deviceId}, 'x.example', 'not_safe', 's_del', ${g.deviceId}, 'G')`;
    await sql`insert into join_attempts (device_id, ip_hash, success) values (${p.deviceId}, '\\x00', false)`;

    const res = await call("/devices/me", { method: "DELETE", token: p.token });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });

    for (const [table, col] of [
      ["devices", "id"], ["family_links", "protected_id"], ["scans", "owner_id"],
      ["verdicts", "owner_id"], ["join_attempts", "device_id"],
    ] as const) {
      const [row] = await sql<{ n: number }[]>`select count(*)::int as n from ${sql(table)} where ${sql(col)} = ${p.deviceId}`;
      expect(row!.n, table).toBe(0);
    }
    expect((await call("/devices/me", { token: p.token })).status).toBe(401);
    // The guardian is untouched.
    expect(((await me(g)) as { deviceId: string }).deviceId).toBe(g.deviceId);
  });

  it("guardian: deletes its links (members are freed) and the verdicts it made", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await connect(g, p);
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at)
      values ('s_keep', ${p.deviceId}, 'https://y.example/', 'y.example', 85, 'blocked', now())`;
    await sql`insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
      values (${p.deviceId}, 'y.example', 'safe', 's_keep', ${g.deviceId}, 'G')`;

    expect((await call("/devices/me", { method: "DELETE", token: g.token })).status).toBe(200);
    expect(((await me(p)) as { guardian: unknown }).guardian).toBeNull();
    const [v] = await sql<{ n: number }[]>`select count(*)::int as n from verdicts where by_device_id = ${g.deviceId}`;
    expect(v!.n).toBe(0);
    // The protected device's own scan stays.
    const [s] = await sql<{ n: number }[]>`select count(*)::int as n from scans where id = 's_keep'`;
    expect(s!.n).toBe(1);
  });

  it("401 without token", async () => {
    expect((await call("/devices/me", { method: "DELETE" })).status).toBe(401);
  });
});
