import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { runRetention } from "../src/cron/retention";
import { opsWriter, type OpsWriter } from "../src/db/repo/ops";
import { screenshotStore } from "../src/services/screenshots";
import { jpeg } from "./helpers/images";
import { resetDb, testSql } from "./helpers/resetDb";

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

const store = screenshotStore(env)!;
const objectExists = (path: string) =>
  fetch(`${env.SUPABASE_URL}/storage/v1/object/info/screenshots/${path}`, {
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY!, authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
  }).then(async (r) => {
    await r.body?.cancel();
    return r.ok;
  });

async function device(id: string, mode: "guardian" | "protected" = "protected") {
  await sql`insert into devices (id, name, mode, avatar_id, token_hash) values (${id}, ${id}, ${mode}, 'avatar_01', ${new Uint8Array([id.length, ...new TextEncoder().encode(id)])})`;
}
async function scan(id: string, owner: string, ageDays: number, path: string | null = null) {
  await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, created_at, screenshot_path)
    values (${id}, ${owner}, 'https://x.example/', 'x.example', 92, 'blocked', now(), now() - make_interval(days => ${ageDays}), ${path})`;
}
const scanIds = async () => (await sql<{ id: string }[]>`select id from scans order by id`).map((r) => r.id);

describe("retention cron (R4 §5, D-alief-B12)", () => {
  it("deletes scans older than 14 days with their screenshot; younger scans stay; verdicts stay with scan_id null", async () => {
    await device("dev_p");
    await device("dev_g", "guardian");
    const oldPath = `dev_p/old-${crypto.randomUUID()}.jpg`;
    await store.put(oldPath, jpeg(10, 10), "image/jpeg");
    await scan("s_old", "dev_p", 15, oldPath);
    await scan("s_new", "dev_p", 13);
    await sql`insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
      values ('dev_p', 'x.example', 'safe', 's_old', 'dev_g', 'G')`;
    await sql`insert into push_log (to_device_id, scan_id, result) values ('dev_g', 's_old', 'sent')`;

    const r = await runRetention(sql, env);
    expect(r.scans).toBe(1);
    expect(await scanIds()).toEqual(["s_new"]);
    expect(await objectExists(oldPath)).toBe(false);
    const [v] = await sql<{ scan_id: string | null }[]>`select scan_id from verdicts`;
    expect(v).toEqual({ scan_id: null });
    expect((await sql`select 1 from push_log where scan_id = 's_old'`).length).toBe(0);
  });

  it("keeps an object still used by a younger scan (dedupe); deletes a path shared only inside the batch once", async () => {
    await device("dev_p");
    // Unique names: the kept object stays in local Storage after the test.
    const shared = `dev_p/shared-${crypto.randomUUID()}.jpg`;
    const both = `dev_p/both-old-${crypto.randomUUID()}.jpg`;
    await store.put(shared, jpeg(10, 10), "image/jpeg");
    await store.put(both, jpeg(10, 10), "image/jpeg");
    await scan("s_a", "dev_p", 15, shared);
    await scan("s_b", "dev_p", 13, shared);
    await scan("s_c", "dev_p", 16, both);
    await scan("s_d", "dev_p", 15, both);
    const removed: string[][] = [];
    const real = store.remove.bind(store);
    const spy = vi.fn(async (paths: string[]) => {
      removed.push(paths);
      await real(paths);
    });

    expect((await runRetention(sql, env, { store: { ...store, remove: spy } })).scans).toBe(3);
    expect(await scanIds()).toEqual(["s_b"]);
    expect(await objectExists(shared)).toBe(true);
    expect(await objectExists(both)).toBe(false);
    expect(removed).toEqual([[both]]);
    await store.remove([shared]);
  });

  it("rows with a screenshot all go on day 14; Storage DELETEs are capped, the rest drains through the tombstone step", async () => {
    await device("dev_p");
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, created_at, screenshot_path)
      select 'bulk_' || lpad(g::text, 4, '0'), 'dev_p', 'https://x.example/', 'x.example', 92, 'blocked', now(),
             now() - interval '20 days' + make_interval(secs => g), 'dev_p/bulk_' || lpad(g::text, 4, '0') || '.jpg'
      from generate_series(1, 25) g`;
    const removed: string[][] = [];
    const spy = vi.fn(async (paths: string[]) => void removed.push(paths));

    const r = await runRetention(sql, env, { batch: 10, maxBatches: 2, store: { ...store, remove: spy } });
    expect(r).toMatchObject({ scans: 25, objects: 20, tombstones: 5, backlog: false });
    expect(await scanIds()).toEqual([]);
    // Oldest first within the budget; the tombstone step takes the 5 left in the same run.
    expect(removed.slice(0, 2).flat()).toEqual(Array.from({ length: 20 }, (_, i) => `dev_p/bulk_${String(i + 1).padStart(4, "0")}.jpg`));
    expect(removed[2]!.sort()).toEqual(["dev_p/bulk_0021.jpg", "dev_p/bulk_0022.jpg", "dev_p/bulk_0023.jpg", "dev_p/bulk_0024.jpg", "dev_p/bulk_0025.jpg"]);
    // Retention's own tombstones are settled: dropped right after the remove, not kept for tomorrow (LOW 6).
    expect((await sql`select 1 from storage_tombstones`).length).toBe(0);
  });

  it("a flood of dedupe reuses cannot hold other users' rows past day 14 (PR #20 review, HIGH)", async () => {
    await device("dev_flood");
    await device("dev_other");
    // One device re-posting the same blocked domain: 3000 old rows share one object, older than everyone else's.
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, created_at, screenshot_path)
      select 'flood_' || lpad(g::text, 5, '0'), 'dev_flood', 'https://x.example/', 'x.example', 92, 'blocked', now(),
             now() - interval '20 days' + make_interval(secs => g), 'dev_flood/flood_00001.jpg'
      from generate_series(1, 3000) g`;
    await scan("s_other", "dev_other", 15, "dev_other/s_other.jpg");
    const removed: string[][] = [];
    const spy = vi.fn(async (paths: string[]) => void removed.push(paths));

    const r = await runRetention(sql, env, { store: { ...store, remove: spy } });
    expect(r).toMatchObject({ scans: 3001, backlog: false });
    expect(await scanIds()).toEqual([]);
    expect(removed.flat().sort()).toEqual(["dev_flood/flood_00001.jpg", "dev_other/s_other.jpg"]);
  });

  it("more old rows than chunks × chunk size: the rest goes on the next run (backlog logged)", async () => {
    await device("dev_p");
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, created_at, screenshot_path)
      select 'many_' || lpad(g::text, 4, '0'), 'dev_p', 'https://x.example/', 'x.example', 92, 'blocked', now(),
             now() - interval '20 days' + make_interval(secs => g), 'dev_p/shared.jpg'
      from generate_series(1, 60) g`;
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));
    const quiet = { ...store, remove: async () => undefined };

    expect(await runRetention(sql, env, { shotChunk: 2, store: quiet })).toMatchObject({ scans: 50, backlog: true });
    // Oldest first.
    expect((await scanIds())[0]).toBe("many_0051");
    expect(lines.some((l) => l.includes('"backlog":true'))).toBe(true);
    expect(await runRetention(sql, env, { shotChunk: 2, store: quiet })).toMatchObject({ scans: 10, backlog: false });
  });

  it("Storage failure still deletes the rows on day 14; the paths stay tombstoned; logs carry no path", async () => {
    await device("dev_p");
    await scan("s_old", "dev_p", 15, "dev_p/old.jpg");
    await scan("s_noshot", "dev_p", 15);
    await sql`insert into family_codes (code, guardian_id, expires_at) values ('123456', 'dev_p', now() - interval '2 hours')`;
    const errorsLogged: string[] = [];
    vi.spyOn(console, "error").mockImplementation((...a: unknown[]) => void errorsLogged.push(a.map(String).join(" ")));
    vi.spyOn(console, "log").mockImplementation(() => {});
    const failing = { ...store, remove: async () => { throw new Error("storage remove 503 dev_p/old.jpg"); } };

    await expect(runRetention(sql, env, { store: failing })).rejects.toThrow("storage remove 503");
    // Rows go anyway (the privacy page promises 14 days); the object stays tracked for a retry.
    expect(await scanIds()).toEqual([]);
    expect((await sql`select path from storage_tombstones`).map((r) => r.path)).toEqual(["dev_p/old.jpg"]);
    expect(errorsLogged.join("\n")).toContain("retention_step_failed");
    expect(errorsLogged.join("\n")).not.toContain("dev_p");
    expect((await sql`select 1 from family_codes`).length).toBe(0);
    expect((await sql`select 1 from ops_heartbeat where source = 'cron'`).length).toBe(1);
  });

  it("a locked verdict rolls the batch back (lock_timeout), nothing half-deleted", async () => {
    await device("dev_p");
    await device("dev_g", "guardian");
    await scan("s_old", "dev_p", 15);
    await sql`insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name)
      values ('dev_p', 'x.example', 'safe', 's_old', 'dev_g', 'G')`;
    vi.spyOn(console, "error").mockImplementation(() => {});
    const other = testSql();
    let release!: () => void;
    const held = new Promise<void>((r) => (release = r));
    let locked!: () => void;
    const isLocked = new Promise<void>((r) => (locked = r));
    const holder = other.begin(async (tx) => {
      await tx`select 1 from verdicts where owner_id = 'dev_p' for update`;
      locked();
      await held;
    });
    await isLocked;
    await expect(runRetention(sql, env, { lockTimeoutMs: 200 })).rejects.toMatchObject({ code: "55P03" });
    release();
    await holder;
    expect(await scanIds()).toEqual(["s_old"]);
    const [v] = await sql<{ scan_id: string | null }[]>`select scan_id from verdicts`;
    expect(v).toEqual({ scan_id: "s_old" });
  });

  it("prunes codes, join attempts, push log and rate-limit hits at their own ages", async () => {
    await device("dev_g", "guardian");
    await sql`insert into family_codes (code, guardian_id, expires_at) values
      ('111111', 'dev_g', now() - interval '2 hours'), ('222222', 'dev_g', now() - interval '30 minutes')`;
    await sql`insert into join_attempts (device_id, ip_hash, success, attempted_at) values
      ('dev_g', '\\x01', false, now() - interval '25 hours'), ('dev_g', '\\x02', false, now() - interval '23 hours')`;
    await sql`insert into push_log (to_device_id, result, created_at) values
      ('dev_g', 'sent', now() - interval '15 days'), ('dev_g', 'sent', now() - interval '9 minutes')`;
    await sql`insert into rate_limit_hits (bucket, key_hash, hit_at) values
      ('x', '\\x01', now() - interval '25 hours'), ('x', '\\x02', now() - interval '59 minutes')`;

    expect(await runRetention(sql, env)).toMatchObject({ familyCodes: 1, joinAttempts: 1, pushLog: 1, rateLimitHits: 1 });
    expect((await sql<{ code: string }[]>`select code from family_codes`).map((r) => r.code)).toEqual(["222222"]);
    expect((await sql`select 1 from join_attempts`).length).toBe(1);
    expect((await sql`select 1 from push_log`).length).toBe(1);
    expect((await sql`select 1 from rate_limit_hits`).length).toBe(1);
  });

  it("writes the cron heartbeat first and leaves the healthz row alone; logs counts only", async () => {
    await sql`insert into ops_heartbeat (source, at) values ('healthz', now() - interval '3 days'), ('cron', now() - interval '2 days')`;
    await device("dev_p");
    await scan("s_old", "dev_p", 15);
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));

    await runRetention(sql, env);
    const rows = await sql<{ source: string; fresh: boolean }[]>`
      select source, at > now() - interval '1 minute' as fresh from ops_heartbeat order by source`;
    expect(rows).toEqual([{ source: "cron", fresh: true }, { source: "healthz", fresh: false }]);
    const all = lines.join("\n");
    expect(all).toContain('"event":"retention"');
    for (const leak of ["dev_p", "s_old", "x.example", "http"]) expect(all).not.toContain(leak);
  });

  it("ops_jobs (fase 21a): a clean run sets failed 0, ok_at and backlog; a failed step keeps ok_at and still throws", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(console, "error").mockImplementation(() => {});
    const job = async () => (await sql<{ failed: number; backlog: boolean; okFresh: boolean | null; finishedFresh: boolean; started: boolean }[]>`
      select failed, backlog, ok_at > now() - interval '1 minute' as "okFresh",
             finished_at > now() - interval '1 minute' as "finishedFresh", started_at is not null as started
      from ops_jobs where job = 'retention'`)[0];

    await device("dev_p");
    await scan("s_a", "dev_p", 15);
    await scan("s_b", "dev_p", 15);
    await runRetention(sql, env, { plainChunk: 1 });
    expect(await job()).toEqual({ failed: 0, backlog: false, okFresh: true, finishedFresh: true, started: true });

    await sql`update ops_jobs set ok_at = now() - interval '2 days', finished_at = now() - interval '2 days'`;
    await scan("s_c", "dev_p", 15, "dev_p/c.jpg");
    const failing = { ...store, remove: async () => { throw new Error("storage remove 503"); } };
    await expect(runRetention(sql, env, { store: failing })).rejects.toThrow("storage remove 503");
    // Two steps fail: the scans step and the tombstone step both call the broken store.
    expect(await job()).toEqual({ failed: 2, backlog: false, okFresh: false, finishedFresh: true, started: true });
  });

  it("ops_jobs: a run with leftover rows records backlog", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await device("dev_p");
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, created_at)
      select 'dev_p', 'https://x.example/', 'x.example', 92, 'blocked', now(), now() - interval '15 days' from generate_series(1, 30)`;
    await runRetention(sql, env, { plainChunk: 1 });
    expect((await sql`select backlog from ops_jobs where job = 'retention'`)[0]).toEqual({ backlog: true });
  });

  it("ops_jobs: a failing status write is one failed step; every other step still runs and the error is rethrown", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const errorsLogged: string[] = [];
    vi.spyOn(console, "error").mockImplementation((...a: unknown[]) => void errorsLogged.push(a.map(String).join(" ")));
    const broken: OpsWriter = { ...opsWriter, finish: async () => { throw Object.assign(new Error("ops down"), { code: "57014" }); } };
    await device("dev_p");
    await scan("s_old", "dev_p", 15);
    await sql`insert into family_codes (code, guardian_id, expires_at) values ('123456', 'dev_p', now() - interval '2 hours')`;

    await expect(runRetention(sql, env, { ops: broken })).rejects.toThrow("ops down");
    expect(await scanIds()).toEqual([]);
    expect((await sql`select 1 from family_codes`).length).toBe(0);
    expect(errorsLogged.join("\n")).toContain('"step":"ops_finish"');
    expect(errorsLogged.join("\n")).not.toContain("ops down");

    const startBroken: OpsWriter = { ...opsWriter, start: async () => { throw new Error("ops down"); } };
    errorsLogged.length = 0;
    await expect(runRetention(sql, env, { ops: startBroken })).rejects.toThrow("ops down");
    expect(errorsLogged.join("\n")).toContain('"step":"ops_start"');
    // The finish write still ran and counts the failed start.
    expect((await sql`select failed from ops_jobs where job = 'retention'`)[0]).toEqual({ failed: 1 });
  });

  it("the Worker's scheduled() handler runs retention", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    // Awaited by the handler itself (no waitUntil), so a failed run fails the Cron event.
    await worker.scheduled!({ cron: "0 19 * * *", scheduledTime: Date.now(), noRetry() {} } as ScheduledController, env);
    expect((await sql`select 1 from ops_heartbeat where source = 'cron'`).length).toBe(1);
  });
});
