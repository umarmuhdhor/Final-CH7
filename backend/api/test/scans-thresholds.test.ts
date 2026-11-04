// Dashboard phase 05 K1 (D-dash-12): POST /scans checks status against the thresholds version the
// extension used. No version: the fence only (warning >= 30, blocked >= 50), so an extension that
// reads /config/public but sends no version is never refused. Active version: exact match. Another
// version (a stale cache): the fence.
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";
import { NOT_LIVE, readThresholds, setThresholds, type Thresholds } from "./helpers/thresholds";

const sql = testSql();
let p: Created;
beforeEach(async () => {
  await resetDb(sql);
  await setThresholds(NOT_LIVE);
  p = await createDevice("Mom", "protected");
});
let before: Thresholds;
beforeAll(async () => {
  before = await readThresholds();
});
afterAll(() => setThresholds(before));

const body = (score: number, status: string, thresholdsVersion?: unknown) => ({
  url: blocked92.url, domain: blocked92.domain, pageTitle: blocked92.pageTitle, faviconUrl: null,
  score, status, signals: blocked92.signals, detectedAt: new Date().toISOString(),
  ...(thresholdsVersion === undefined ? {} : { thresholdsVersion }),
});
const post = (score: number, status: string, v?: unknown) => call("/scans", { method: "POST", token: p.token, json: body(score, status, v) });
const cases = async (rows: [number, string, unknown, number][]) => {
  for (const [score, status, v, want] of rows) {
    const res = await post(score, status, v);
    expect([score, status, v, res.status], await res.clone().text()).toEqual([score, status, v, want]);
  }
};

describe("POST /scans thresholdsVersion (K1)", () => {
  it("no version: the fence only, as older extensions and ones that read but do not send it", async () => {
    await cases([
      [85, "warning", undefined, 201], [55, "blocked", undefined, 201], [92, "blocked", undefined, 201],
      [45, "blocked", undefined, 422], [29, "warning", undefined, 422],
    ]);
  });

  it("the active version before live (0 = built-in 30/80): exact match", async () => {
    await cases([[85, "blocked", 0, 201], [41, "warning", 0, 201], [79, "blocked", 0, 422], [85, "warning", 0, 422]]);
  });

  it("the active version once live: exact match, including the warn floor", async () => {
    await setThresholds({ live: true, warnAt: 35, blockAt: 70, version: 7 });
    await cases([
      [60, "warning", 7, 201], [72, "blocked", 7, 201],
      [75, "warning", 7, 422], [65, "blocked", 7, 422], [32, "warning", 7, 422],
    ]);
  });

  it("any other version (stale cache, or one never issued): the fence", async () => {
    await setThresholds({ live: true, warnAt: 35, blockAt: 70, version: 7 });
    await cases([[75, "warning", 6, 201], [55, "blocked", 6, 201], [45, "blocked", 6, 422], [75, "warning", 9, 201]]);
  });

  it("thresholdsVersion must be a non-negative integer", async () => {
    await cases([[92, "blocked", -1, 422], [92, "blocked", "7", 422], [92, "blocked", 1.5, 422], [92, "blocked", 2 ** 31, 422]]);
  });

  it("stores the version sent, null when absent (old scans are not recomputed, Q48)", async () => {
    // Two sites: a second scan of the same site only reuses its Activity row (PR-05).
    expect((await post(92, "blocked", 0)).status).toBe(201);
    const other = { ...body(92, "blocked"), url: "https://other-site.test/login", domain: "other-site.test" };
    expect((await call("/scans", { method: "POST", token: p.token, json: other })).status).toBe(201);
    const rows = await sql<{ v: number | null }[]>`select thresholds_version as v from scans order by created_at`;
    expect(rows.map((r) => r.v)).toEqual([0, null]);
  });

  it("a failed thresholds lookup stores the scan under the fence instead of failing it", async () => {
    const admin = adminSql();
    await admin`revoke select on admin.public_config from shoo_api`;
    try {
      await cases([[85, "warning", 0, 201], [45, "blocked", 0, 422]]);
    } finally {
      await admin`grant select on admin.public_config to shoo_api`;
    }
  });

  it("422 names the field", async () => {
    const res = await post(79, "blocked", 0);
    const { error } = (await res.json()) as { error: { code: string; message: string } };
    expect(error.code).toBe("invalid_body");
    expect(error.message).toMatch(/^status: does not match thresholds version 0 \(warning from 30, blocked from 80\)/);
  });
});
