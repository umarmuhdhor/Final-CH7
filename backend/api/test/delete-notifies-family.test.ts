import { beforeEach, describe, expect, it } from "vitest";
import { familyContacts } from "../src/db/repo/families";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, callWithEnv, createDevice, type Created } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));

const TOKEN_G = "a".repeat(64);
const TOKEN_P = "b".repeat(64);

async function pair(g: Created, p: Created) {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
}

const pushRows = (to: string) =>
  sql<{ result: string; scanId: string | null }[]>`select result, scan_id as "scanId" from push_log where to_device_id = ${to}`;
// LogSender even when a local .dev.vars holds APNs secrets: no call to Apple from a test.
const NO_APNS = { APNS_KEY_ID: undefined };

/** QA 2026-11-10 #6: deleting an account told nobody; the other phone just lost its family. */
describe("DELETE /devices/me tells the other side of the family", () => {
  it("guardian deletes: each member with a token gets one push, members without a token none", async () => {
    const g = await createDevice("Adhella", "guardian");
    const p1 = await createDevice("Maria");
    const p2 = await createDevice("Budi");
    await pair(g, p1);
    await pair(g, p2);
    await call("/devices/me", { method: "PATCH", token: p1.token, json: { apnsToken: TOKEN_P, language: "id" } });

    expect(await familyContacts(sql, g.deviceId)).toEqual([{ deviceId: p1.deviceId, apnsToken: TOKEN_P, language: "id" }]);
    const res = await callWithEnv(NO_APNS, "/devices/me", { method: "DELETE", token: g.token });
    expect(res.status).toBe(200);
    expect(await pushRows(p1.deviceId)).toEqual([{ result: "logged", scanId: null }]);
    expect(await pushRows(p2.deviceId)).toEqual([]);
    // The guardian is gone and the members keep their own devices.
    expect((await call("/devices/me", { token: p1.token })).status).toBe(200);
  });

  it("member deletes: the guardian gets one push", async () => {
    const g = await createDevice("Adhella", "guardian");
    const p = await createDevice("Maria");
    await pair(g, p);
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN_G } });

    expect(await familyContacts(sql, p.deviceId)).toEqual([{ deviceId: g.deviceId, apnsToken: TOKEN_G, language: "en" }]);
    expect((await callWithEnv(NO_APNS, "/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect(await pushRows(g.deviceId)).toEqual([{ result: "logged", scanId: null }]);
  });

  it("no family: no push, delete still works", async () => {
    const p = await createDevice("Maria");
    expect(await familyContacts(sql, p.deviceId)).toEqual([]);
    expect((await callWithEnv(NO_APNS, "/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect((await sql`select count(*)::int as n from push_log`)[0]!.n).toBe(0);
  });
});
