import { beforeEach, describe, expect, it, vi } from "vitest";
import { deliverPush } from "../src/services/push/deliver";
import type { PushMessage, PushSender, SendResult } from "../src/services/push/sender";
import { resetDb, testSql } from "./helpers/resetDb";

const sql = testSql();
beforeEach(() => resetDb(sql));

const OLD = "aa".repeat(32);
const NEW = "bb".repeat(32);

async function world() {
  await sql`insert into devices (id, name, mode, avatar_id, token_hash, apns_token)
    values ('dev_g', 'G', 'guardian', 'avatar_01', '\\x01', ${OLD}), ('dev_p', 'Mom', 'protected', 'avatar_02', '\\x02', null)`;
  await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at)
    values ('scan-1', 'dev_p', 'https://x.example/', 'x.example', 92, 'blocked', now())`;
}
const message: PushMessage = { toDeviceId: "dev_g", apnsToken: OLD, body: "Mom hit a blocked site · 92%", scanId: "scan-1" };
const sender = (fn: () => Promise<SendResult>): PushSender => ({ send: fn });
const token = async () => (await sql<{ t: string | null }[]>`select apns_token as t from devices where id = 'dev_g'`)[0]!.t;
const rows = () => sql<{ to_device_id: string; scan_id: string; result: string }[]>`select to_device_id, scan_id, result from push_log`;

describe("deliverPush (send → clear token → push_log)", () => {
  it("records the result without any text", async () => {
    await world();
    expect(await deliverPush(sql, sender(async () => ({ result: "sent" })), message)).toBe("sent");
    expect(await rows()).toEqual([{ to_device_id: "dev_g", scan_id: "scan-1", result: "sent" }]);
    expect(await token()).toBe(OLD);
  });

  it("410 clears the token it was sent to", async () => {
    await world();
    await deliverPush(sql, sender(async () => ({ result: "failed:410 Unregistered", clearToken: true })), message);
    expect(await token()).toBeNull();
    expect((await rows())[0]!.result).toBe("failed:410 Unregistered");
  });

  it("410 keeps a token the guardian registered meanwhile (compare-and-clear)", async () => {
    await world();
    await deliverPush(sql, sender(async () => {
      await sql`update devices set apns_token = ${NEW} where id = 'dev_g'`;
      return { result: "failed:410 ExpiredToken", clearToken: true };
    }), message);
    expect(await token()).toBe(NEW);
  });

  it("400 BadDeviceToken keeps the token", async () => {
    await world();
    await deliverPush(sql, sender(async () => ({ result: "failed:400 BadDeviceToken" })), message);
    expect(await token()).toBe(OLD);
  });

  it("a throwing sender is recorded as failed:network and never throws", async () => {
    await world();
    vi.spyOn(console, "error").mockImplementation(() => {});
    expect(await deliverPush(sql, sender(async () => { throw new Error(`boom ${OLD}`); }), message)).toBe("failed:network");
    expect((await rows())[0]!.result).toBe("failed:network");
  });

  it("scan or guardian deleted before the send finished → no row, no error (P13)", async () => {
    await world();
    await deliverPush(sql, sender(async () => {
      await sql`delete from scans where id = 'scan-1'`;
      return { result: "sent" };
    }), message);
    expect(await rows()).toEqual([]);
  });
});
