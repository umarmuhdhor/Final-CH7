import { beforeEach, describe, expect, it } from "vitest";
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
