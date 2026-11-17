import { beforeEach, describe, expect, it } from "vitest";
import { ApnsSender, type ApnsConfig } from "../src/services/push/apns";
import { LogSender, type PushMessage } from "../src/services/push/sender";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";

// EX-03 (#555): Shoo dropped the Dynamic Island. contracts/api.md "Live score": POST /live is gone and the
// two device fields are no longer part of PATCH /devices/me. Old app builds may still send them: they are
// stripped silently (200, nothing stored), never a 400/422, so those builds keep saving name, language, …
const sql = testSql();
beforeEach(() => resetDb(sql));

const HEX = "aa".repeat(32);
const OLD_FIELDS = {
  liveActivityStartToken: HEX,
  liveActivityUpdateToken: { activityId: "6F1C2B3A-1111-4222-8333-444455556666", token: "bb".repeat(32) },
};

const row = async (d: Created) => {
  const [r] = await sql<{ j: Record<string, unknown> }[]>`select to_jsonb(d) as j from devices d where id = ${d.deviceId}`;
  return r!.j;
};
/** Columns whose value a PATCH changed. Schema-agnostic, so it holds before and after the column drop. */
async function changedBy(d: Created, json: unknown): Promise<{ status: number; changed: string[] }> {
  const before = await row(d);
  const res = await call("/devices/me", { method: "PATCH", token: d.token, json });
  const after = await row(d);
  const changed = Object.keys(after).filter((k) => JSON.stringify(after[k]) !== JSON.stringify(before[k])).sort();
  return { status: res.status, changed };
}

describe("POST /live is gone (EX-03 removed, #555)", () => {
  it("404 not_found for a valid device and a body the old route accepted", async () => {
    const d = await createDevice("Mom", "protected");
    const res = await call("/live", {
      method: "POST", token: d.token,
      json: { domain: "bca-promo.example", score: 64, status: "warning", analyzing: false, open: true },
    });
    expect(res.status).toBe(404);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe("not_found");
  });
});

describe("PATCH /devices/me from an old build that still sends the Dynamic Island tokens", () => {
  it("200, the other fields are saved, the tokens are stored nowhere", async () => {
    const control = await createDevice("Ctl", "protected");
    const old = await createDevice("Old", "protected");
    const plain = await changedBy(control, { name: "Ibu", language: "id" });
    const withOld = await changedBy(old, { name: "Ibu", language: "id", ...OLD_FIELDS });
    expect(plain.status).toBe(200);
    expect(withOld.status).toBe(200);
    // Same columns move as for the same PATCH without the old fields.
    expect(withOld.changed).toEqual(plain.changed);
    expect(await row(old)).toMatchObject({ name: "Ibu", language: "id" });
  });

  it("values the old route refused (non-hex, bad activity id, extra keys, null) are a 200 too", async () => {
    const d = await createDevice();
    for (const json of [
      { liveActivityStartToken: "not-hex" },
      { liveActivityStartToken: null, liveActivityUpdateToken: null },
      { liveActivityUpdateToken: { activityId: "a/b", token: "zz", domain: "x.example" } },
    ]) {
      const r = await changedBy(d, json);
      expect(r.status).toBe(200);
      expect(r.changed).toEqual((await changedBy(d, {})).changed);
    }
  });
});

describe("APNs: alert pushes only (EX-03 removed, #555)", () => {
  it("no Live Activity send path on ApnsSender or LogSender", () => {
    const config: ApnsConfig = { keyP8B64: "x", keyId: "KEYREMOVED", teamId: "TEAM123456", topic: "com.example.shoo", env: "sandbox" };
    expect("sendLive" in new ApnsSender(config)).toBe(false);
    expect("sendLive" in new LogSender()).toBe(false);
  });

  it("every push is apns-push-type alert on the plain bundle-id topic", async () => {
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
    const armour = (edge: string) => `-----${edge} ${"PRIVATE"} KEY-----`;
    const pem = `${armour("BEGIN")}\n${btoa(String.fromCharCode(...der)).replace(/(.{64})/g, "$1\n")}\n${armour("END")}\n`;
    const config: ApnsConfig = { keyP8B64: btoa(pem), keyId: "KEYREMOVE2", teamId: "TEAM123456", topic: "com.example.shoo", env: "sandbox" };
    const seen: Headers[] = [];
    const fetch = (async (_url: RequestInfo | URL, init?: RequestInit) => {
      seen.push(new Headers(init?.headers));
      return new Response(null, { status: 200 });
    }) as typeof globalThis.fetch;
    const message: PushMessage = { toDeviceId: "dev_g", apnsToken: "ab".repeat(32), body: "x" };
    expect(await new ApnsSender(config, { fetch }).send(message)).toEqual({ result: "sent" });
    expect(seen.map((h) => [h.get("apns-push-type"), h.get("apns-topic")])).toEqual([["alert", "com.example.shoo"]]);
  });
});
