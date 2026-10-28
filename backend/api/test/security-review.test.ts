import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { app } from "../src/app";
import { runRetention } from "../src/cron/retention";
import { deleteDevice } from "../src/db/repo/devices";
import { recentScreenshot, reserveScreenshot } from "../src/db/repo/scans";
import { keyHash, RateKeySecretMissing, useRateKeySecret } from "../src/http/keyHash";
import { screenshotUrl } from "../src/services/scans";
import { abandonUpload, type ScreenshotStore } from "../src/services/screenshots";
import { b64, jpeg } from "./helpers/images";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";

// Fase 12 security review fixes (D-alief-B12).
const sql = testSql();
const admin = adminSql();
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

  it("an unknown token stays a 401 (not a 500) when the secret is too short; logs name only (fase 12 LOW 1)", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const res = await app.request(
      "/devices/me",
      { headers: { authorization: "Bearer shoo_unknown_no_secret", "cf-connecting-ip": "203.0.113.5" } },
      { ...env, RATE_KEY_SECRET: "too-short" },
    );
    expect(res.status).toBe(401);
    expect((await sql`select 1 from rate_limit_hits`).length).toBe(0);
    const logged = error.mock.calls.flat().join(" ");
    expect(logged).toContain("auth_fail_count_failed");
    expect(logged).not.toContain("shoo_unknown");
  });

  it("a SCREENSHOT_URL_SECRET shorter than 32 characters gives no screenshot link", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const short = { ...env, SCREENSHOT_URL_SECRET: "short" } as typeof env;
    expect(await screenshotUrl(short, { id: "s1", screenshotPath: "dev/s1.jpg" }, "dev")).toBeNull();
    expect(await screenshotUrl(env, { id: "s1", screenshotPath: "dev/s1.jpg" }, "dev")).not.toBeNull();
  });
});

describe("storage tombstones (M3, database review M1–M3, SECURITY §3 P13)", () => {
  const age = (minutes: number) =>
    admin`update storage_tombstones set created_at = now() - make_interval(mins => ${minutes})`;
  const scanBody = (extra: Record<string, unknown> = {}) => ({
    url: blocked92.url, domain: blocked92.domain, pageTitle: blocked92.pageTitle, faviconUrl: blocked92.faviconUrl,
    score: blocked92.score, status: blocked92.status, signals: blocked92.signals, detectedAt: blocked92.detectedAt, ...extra,
  });

  it("an upload is tombstoned before it starts; the cron leaves it while its scan points at it", async () => {
    const p = await createDevice("Mom");
    const res = await call("/scans", { method: "POST", token: p.token, json: scanBody({ screenshotBase64: b64(jpeg(100, 100)) }) });
    const { id } = (await res.json()) as { id: string };
    expect(await tombstones()).toEqual([`${p.deviceId}/${id}.jpg`]);
    await age(60);
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const store = fakeStore();
    await runRetention(sql, env, { store });
    expect(store.removed).toEqual([]);
    expect(await tombstones()).toEqual([`${p.deviceId}/${id}.jpg`]);
  });

  it("DELETE /devices/me tombstones the paths in its transaction", async () => {
    const p = await createDevice("Mom");
    await scanRow("s1", p.deviceId, `${p.deviceId}/s1.jpg`);
    await scanRow("s2", p.deviceId, `${p.deviceId}/s1.jpg`);
    await scanRow("s3", p.deviceId, `${p.deviceId}/s3.png`);
    const paths = await deleteDevice(sql, p.deviceId);
    expect(paths.sort()).toEqual([`${p.deviceId}/s1.jpg`, `${p.deviceId}/s3.png`]);
    expect(await tombstones()).toEqual(paths.sort());
  });

  it("DELETE /devices/me removes the objects and drops their (settled) tombstones", async () => {
    const p = await createDevice("Mom");
    const res = await call("/scans", { method: "POST", token: p.token, json: scanBody({ screenshotBase64: b64(jpeg(100, 100)) }) });
    const { id } = (await res.json()) as { id: string };
    await age(60);
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    await vi.waitFor(async () => expect(await tombstones()).toEqual([]));
    const info = await fetch(`${env.SUPABASE_URL}/storage/v1/object/info/screenshots/${p.deviceId}/${id}.jpg`, {
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY!, authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
    });
    await info.body?.cancel();
    expect(info.ok).toBe(false);
  });

  it("a young tombstone stays after a remove: an upload may still land", async () => {
    const store = fakeStore();
    await abandonUpload(sql, store, "dev_a/s2.png");
    expect(store.removed).toEqual(["dev_a/s2.png"]);
    expect(await tombstones()).toEqual(["dev_a/s2.png"]);
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    await runRetention(sql, env, { store });
    expect(store.removed).toEqual(["dev_a/s2.png"]);
    expect(await tombstones()).toEqual(["dev_a/s2.png"]);
  });

  it("a failed remove keeps the tombstone; the cron retries it once it is 10 minutes old", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const store = fakeStore();
    store.failing = true;
    await abandonUpload(sql, store, "dev_a/s1.jpg");
    await age(11);

    await expect(runRetention(sql, env, { store })).rejects.toThrow("storage remove 503");
    const [tried] = await sql<{ attempts: number }[]>`select attempts from storage_tombstones`;
    expect(tried!.attempts).toBe(1);

    store.failing = false;
    const result = await runRetention(sql, env, { store });
    expect(result.tombstones).toBe(1);
    expect(store.removed).toEqual(["dev_a/s1.jpg"]);
    expect(await tombstones()).toEqual([]);
  });

  it("paths tried before go after paths never tried", async () => {
    await sql`insert into storage_tombstones (path, attempts, last_try_at) values ('dev_a/old.jpg', 3, now())`;
    await sql`insert into storage_tombstones (path) values ('dev_a/new.jpg')`;
    await age(60);
    const { dueTombstones } = await import("../src/db/repo/tombstones");
    expect(await dueTombstones(sql, 1)).toEqual(["dev_a/new.jpg"]);
  });

  it("no upload for a scan deleted before the reservation (no tombstone, no object)", async () => {
    const p = await createDevice("Mom");
    const slot = await reserveScreenshot(sql, { id: "missing", ownerId: p.deviceId, domain: "x.example" },
      `${p.deviceId}/missing.jpg`, { owner: 50, global: 300 });
    expect(slot).toEqual({ gone: true });
    expect(await tombstones()).toEqual([]);
  });
});

describe("retention throughput and lock order (database review M4, M5)", () => {
  it("scans without a screenshot are deleted in large chunks, no Storage call", async () => {
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const p = await createDevice("Mom");
    const g = await createDevice("G", "guardian");
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, created_at)
      select 'plain' || n, ${p.deviceId}, 'https://x.example/', 'x.example', 92, 'blocked', now(), now() - interval '15 days'
      from generate_series(1, 2500) n`;
    await sql`insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
      values (${p.deviceId}, 'x.example', 'safe', 'plain7', ${g.deviceId}, 'G')`;
    const store = fakeStore();
    const result = await runRetention(sql, env, { store, plainChunk: 1000 });
    expect(result.plainScans).toBe(2500);
    expect((await sql`select 1 from scans`).length).toBe(0);
    expect((await sql`select scan_id from verdicts`)[0]!.scan_id).toBeNull();
    expect(store.removed).toEqual([]);
  });

  it("DELETE /devices/me retries once on a deadlock instead of failing", async () => {
    const p = await createDevice("Mom");
    const repo = await import("../src/db/repo/devices");
    const { default: postgres } = await import("postgres");
    let calls = 0;
    vi.spyOn(repo, "deleteDevice").mockImplementation(async () => {
      calls++;
      if (calls === 1) throw Object.assign(Object.create(postgres.PostgresError.prototype), { code: "40P01" });
      return [];
    });
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect(calls).toBe(2);
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

  it("POST /scans stops at 2000 per hour for all devices together", async () => {
    const p = await createDevice("Mom");
    const key = await keyHash("scans_create_all:all");
    await sql`insert into rate_limit_hits (bucket, key_hash) select 'scans_create_all', ${key} from generate_series(1, 2000)`;
    const res = await call("/scans", { method: "POST", token: p.token, json: {
      url: blocked92.url, domain: blocked92.domain, score: blocked92.score, status: blocked92.status,
      signals: blocked92.signals, detectedAt: blocked92.detectedAt,
    } });
    expect(res.status).toBe(429);
    expect((await sql`select 1 from scans`).length).toBe(0);
  });

  it("the screenshot quota also counts every owner together", async () => {
    const a = await createDevice("A");
    const b = await createDevice("B");
    await scanRow("a1", a.deviceId, `${a.deviceId}/a1.jpg`, 0, "a1.example");
    await scanRow("a2", a.deviceId, `${a.deviceId}/a2.jpg`, 0, "a2.example");
    // A reuse is not a new object: it does not count.
    await scanRow("a3", a.deviceId, `${a.deviceId}/a1.jpg`, 0, "a1.example");
    await scanRow("b1", b.deviceId, null, 0, "b1.example");
    const slot = await reserveScreenshot(sql, { id: "b1", ownerId: b.deviceId, domain: "b1.example" },
      `${b.deviceId}/b1.jpg`, { owner: 50, global: 3 });
    expect(slot).toEqual({ upload: `${b.deviceId}/b1.jpg` });
    await scanRow("b2", b.deviceId, null, 0, "b2.example");
    expect(await reserveScreenshot(sql, { id: "b2", ownerId: b.deviceId, domain: "b2.example" },
      `${b.deviceId}/b2.jpg`, { owner: 50, global: 3 })).toEqual({ quota: "global" });
    expect((await sql`select screenshot_path from scans where id = 'b2'`)[0]!.screenshot_path).toBeNull();
  });

  it("past the global quota the scan is stored without a screenshot", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);
    const p = await createDevice("Mom");
    const others = await createDevice("Others");
    // Someone else's 300 screenshots today: Mom is far under her own quota of 50.
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, screenshot_path)
      select 'seed' || g, ${others.deviceId}, 'https://g' || g || '.example/', 'g' || g || '.example', 85, 'blocked', now(),
             ${others.deviceId} || '/seed' || g || '.jpg'
      from generate_series(1, 300) g`;
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
