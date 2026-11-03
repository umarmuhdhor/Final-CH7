// Dashboard phase 05 (W12, K3, I12): GET /config/public serves admin.public_config to the extension.
// The thresholds are set in the admin dashboard; while thresholds_live is off the view publishes the
// built-in 30/80 with version 0.
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";
import { NOT_LIVE, readThresholds, setThresholds, type Thresholds } from "./helpers/thresholds";

const sql = testSql();
let token: string;

beforeEach(async () => {
  await resetDb(sql);
  await setThresholds(NOT_LIVE);
  token = (await createDevice()).token;
});
let before: Thresholds;
beforeAll(async () => {
  before = await readThresholds();
});
afterAll(() => setThresholds(before));

type Body = { warnAt: number; blockAt: number; version: number; updatedAt: string };
const get = async () => {
  const res = await call("/config/public", { token });
  return { res, body: (await res.json()) as Body };
};

describe("GET /config/public", () => {
  it("401 without a device token", async () => {
    expect((await call("/config/public")).status).toBe(401);
  });

  it("30/80 version 0 while thresholds_live is off, even when other values are stored (I12)", async () => {
    await setThresholds({ live: false, warnAt: 40, blockAt: 70, version: 5 });
    const { res, body } = await get();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ warnAt: 30, blockAt: 80, version: 0 });
    expect(body.updatedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/);
    expect(res.headers.get("cache-control")).toBe("private, max-age=3600");
  });

  it("the stored thresholds and their version once live; a new version shows on the next request", async () => {
    await setThresholds({ live: true, warnAt: 35, blockAt: 70, version: 7 });
    expect((await get()).body).toMatchObject({ warnAt: 35, blockAt: 70, version: 7 });
    await setThresholds({ live: true, warnAt: 35, blockAt: 75, version: 8 });
    expect((await get()).body).toMatchObject({ warnAt: 35, blockAt: 75, version: 8 });
  });

  it("only the four fields, no user data", async () => {
    expect(Object.keys((await get()).body).sort()).toEqual(["blockAt", "updatedAt", "version", "warnAt"]);
  });
});
