import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { app } from "../src/app";
import { runRetention } from "../src/cron/retention";
import { deleteDevice } from "../src/db/repo/devices";
import { recentScreenshot, reserveScreenshot } from "../src/db/repo/scans";
import { keyHash, RateKeySecretMissing, useRateKeySecret } from "../src/http/keyHash";
import { screenshotUrl } from "../src/services/scans";
import { discardScreenshot, type ScreenshotStore } from "../src/services/screenshots";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";

// Fase 12 security review fixes (D-alief-B12).
const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => {
  useRateKeySecret(env.RATE_KEY_SECRET);
  vi.restoreAllMocks();
});

/** Records removes; fails while `failing` is set. */
function fakeStore() {
  const removed: string[] = [];
  const store = {
    failing: false as boolean,
    removed,
    put: async () => undefined,
    get: async () => undefined,
    remove: async (paths: string[]) => {
      if (store.failing) throw new Error("storage remove 503");
      removed.push(...paths);
    },
  } satisfies ScreenshotStore & { failing: boolean; removed: string[] };
  return store;
}
const tombstones = async () =>
  (await sql<{ path: string }[]>`select path from storage_tombstones order by path`).map((r) => r.path);
async function scanRow(id: string, owner: string, path: string | null, ageHours = 0, domain = "x.example") {
  await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, created_at, screenshot_path)
    values (${id}, ${owner}, ${`https://${domain}/`}, ${domain}, 92, 'blocked', now(),
            now() - make_interval(hours => ${ageHours}), ${path})`;
}

describe("RATE_KEY_SECRET is required (M2, L14)", () => {
  it("keyHash fails closed without a secret or with one shorter than 32 characters", async () => {
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    useRateKeySecret(undefined);
    await expect(keyHash("devices_create:203.0.113.1")).rejects.toBeInstanceOf(RateKeySecretMissing);
    useRateKeySecret("short-secret");
    await expect(keyHash("devices_create:203.0.113.1")).rejects.toBeInstanceOf(RateKeySecretMissing);
  });

  it("a request that rate-limits is a 500 with nothing stored when the secret is too short", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const res = await app.request(
      "/devices",
      { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: "A", mode: "guardian" }) },
      { ...env, RATE_KEY_SECRET: "too-short" },
    );
    expect(res.status).toBe(500);
    expect((await sql`select 1 from devices`).length).toBe(0);
    expect((await sql`select 1 from rate_limit_hits`).length).toBe(0);
    expect(error.mock.calls.flat().join(" ")).toContain("RateKeySecretMissing");
  });

  it("a SCREENSHOT_URL_SECRET shorter than 32 characters gives no screenshot link", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const short = { ...env, SCREENSHOT_URL_SECRET: "short" } as typeof env;
    expect(await screenshotUrl(short, { id: "s1", screenshotPath: "dev/s1.jpg" }, "dev")).toBeNull();
    expect(await screenshotUrl(env, { id: "s1", screenshotPath: "dev/s1.jpg" }, "dev")).not.toBeNull();
  });
});

describe("storage tombstones (M3, SECURITY §3 P13)", () => {
  it("DELETE /devices/me tombstones the paths in its transaction", async () => {
    const p = await createDevice("Mom");
    await scanRow("s1", p.deviceId, `${p.deviceId}/s1.jpg`);
    await scanRow("s2", p.deviceId, `${p.deviceId}/s1.jpg`);
    await scanRow("s3", p.deviceId, `${p.deviceId}/s3.png`);
    const paths = await deleteDevice(sql, p.deviceId);
    expect(paths.sort()).toEqual([`${p.deviceId}/s1.jpg`, `${p.deviceId}/s3.png`]);
    expect(await tombstones()).toEqual(paths.sort());
  });

  it("DELETE /devices/me drops the tombstones once Storage confirmed", async () => {
    const p = await createDevice("Mom");
    const res = await call("/devices/me", { method: "DELETE", token: p.token });
    expect(res.status).toBe(200);
    expect(await tombstones()).toEqual([]);
  });

  it("a failed remove keeps the tombstone; the cron removes it and drops it", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const store = fakeStore();
    store.failing = true;
    await discardScreenshot(sql, store, "dev_a/s1.jpg");
    expect(await tombstones()).toEqual(["dev_a/s1.jpg"]);

    await expect(runRetention(sql, env, { store })).rejects.toThrow("storage remove 503");
    expect(await tombstones()).toEqual(["dev_a/s1.jpg"]);

    store.failing = false;
    const result = await runRetention(sql, env, { store });
    expect(result.tombstones).toBe(1);
    expect(store.removed).toEqual(["dev_a/s1.jpg"]);
    expect(await tombstones()).toEqual([]);
  });

  it("a discarded object that Storage removed leaves no tombstone", async () => {
    const store = fakeStore();
    await discardScreenshot(sql, store, "dev_a/s2.png");
    expect(store.removed).toEqual(["dev_a/s2.png"]);
    expect(await tombstones()).toEqual([]);
  });
});

describe("global caps (M5)", () => {
  it("POST /devices stops at 1000 new devices per day for all callers together", async () => {
    const key = await keyHash("devices_create_all:all");
    await sql`insert into rate_limit_hits (bucket, key_hash) select 'devices_create_all', ${key} from generate_series(1, 1000)`;
    const res = await call("/devices", { method: "POST", json: { name: "A", mode: "guardian" }, ip: "203.0.113.200" });
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).not.toBeNull();
    expect((await sql`select 1 from devices`).length).toBe(0);
  });

  it("the screenshot quota also counts every owner together", async () => {
    const a = await createDevice("A");
    const b = await createDevice("B");
    await scanRow("a1", a.deviceId, `${a.deviceId}/a1.jpg`, 0, "a1.example");
    await scanRow("a2", a.deviceId, `${a.deviceId}/a2.jpg`, 0, "a2.example");
    await scanRow("b1", b.deviceId, null, 0, "b1.example");
    const slot = await reserveScreenshot(sql, { id: "b1", ownerId: b.deviceId, domain: "b1.example" },
      `${b.deviceId}/b1.jpg`, { owner: 50, global: 2 });
    expect(slot).toEqual({ quota: "global" });
    expect((await sql`select screenshot_path from scans where id = 'b1'`)[0]!.screenshot_path).toBeNull();
  });

  it("past the global quota the scan is stored without a screenshot", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);
    const p = await createDevice("Mom");
    const others = await createDevice("Others");
    // Someone else's 300 screenshots today: Mom is far under her own quota of 50.
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, screenshot_path)
      select ${others.deviceId}, 'https://g' || g || '.example/', 'g' || g || '.example', 85, 'blocked', now(),
             ${others.deviceId} || '/seed' || g || '.jpg'
      from generate_series(1, 300) g`;
    const { b64, jpeg } = await import("./helpers/images");
    const res = await call("/scans", { method: "POST", token: p.token, json: {
      url: blocked92.url, domain: blocked92.domain, pageTitle: blocked92.pageTitle, faviconUrl: blocked92.faviconUrl,
      score: blocked92.score, status: blocked92.status, signals: blocked92.signals, detectedAt: blocked92.detectedAt,
      screenshotBase64: b64(jpeg(100, 100)),
    } });
    expect(res.status).toBe(201);
    const { id } = (await res.json()) as { id: string };
    expect((await sql`select screenshot_path from scans where id = ${id}`)[0]!.screenshot_path).toBeNull();
    expect(log.mock.calls.flat().join(" ")).toContain("global_quota");
  });
});

describe("dedupe reuse is bounded (L10)", () => {
  it("reuses only the original upload, so an object never outlives its first scan by more than 24 h", async () => {
    const p = await createDevice("Mom");
    const original = `${p.deviceId}/orig.jpg`;
    await scanRow("orig", p.deviceId, original, 23);
    await scanRow("reuse", p.deviceId, original, 1);
    expect(await recentScreenshot(sql, p.deviceId, "x.example")).toBe(original);

    // The original is now past 24 h: the younger scan that reused it does not extend the chain.
    await sql`update scans set created_at = now() - interval '25 hours' where id = 'orig'`;
    expect(await recentScreenshot(sql, p.deviceId, "x.example")).toBeUndefined();
  });
});
