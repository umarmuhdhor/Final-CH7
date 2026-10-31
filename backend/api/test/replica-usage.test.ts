import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { replicaUsage } from "../src/db/repo/scans";
import { logReplicaUsage, MAX_REPLICA_BYTES, REPLICA_QUOTA } from "../src/services/replicas";
import { resetDb, testSql } from "./helpers/resetDb";

// Fase 19 K5.2 (D-alief-B14): the hourly `replica_quota_usage` gauge, read by fase 21.

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

async function device(id: string, mode: "guardian" | "protected" = "protected") {
  await sql`insert into devices (id, name, mode, avatar_id, token_hash)
    values (${id}, ${id}, ${mode}, 'avatar_01', ${new TextEncoder().encode(id)})`;
}
const link = (p: string, g: string) => sql`insert into family_links (protected_id, guardian_id) values (${p}, ${g})`;
/** Original uploads of `owner` in the last 24 h (rows only, no objects). */
const uploads = (owner: string, n: number, bytes = 1000, ageHours = 1) => sql`
  insert into scans (owner_id, url, domain, score, status, detected_at, created_at, replica_path, replica_bytes)
  select ${owner}, 'https://q.example/', 'q.example', 92, 'blocked', now(), now() - make_interval(hours => ${ageHours}),
         ${owner} || '/q' || g || '-replica.html.gz', ${bytes}
  from generate_series(1, ${n}) g`;

const capture = () => {
  const lines: Record<"log" | "warn" | "error", string[]> = { log: [], warn: [], error: [] };
  for (const m of ["log", "warn", "error"] as const) {
    vi.spyOn(console, m).mockImplementation((...a: unknown[]) => void lines[m].push(a.map(String).join(" ")));
  }
  return lines;
};

describe("replicaUsage (fase 19 K5.2)", () => {
  it("empty: ok with zeros and the quota maxima", async () => {
    expect(await replicaUsage(sql, REPLICA_QUOTA, MAX_REPLICA_BYTES)).toEqual({
      level: "ok", uploads: 0, bytes: 0, uploadsMax: REPLICA_QUOTA.global, bytesMax: REPLICA_QUOTA.globalBytes,
      families: 0, familiesAtCap: 0, topFamilyUploads: 0, topFamilyBytes: 0,
    });
  });

  it("groups by family root (Guardian, or the owner without one); older than 24 h and reuses do not count", async () => {
    await device("g1", "guardian");
    await device("p1");
    await device("p2");
    await device("solo");
    await link("p1", "g1");
    await link("p2", "g1");
    await uploads("g1", 10);
    await uploads("p1", 30);
    await uploads("p2", 20, 2000);
    await uploads("solo", 5);
    await uploads("solo", 7, 1000, 25);
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, replica_path)
      values ('solo', 'https://q.example/', 'q.example', 92, 'blocked', now(), 'solo/q1-replica.html.gz')`;
    const u = await replicaUsage(sql, REPLICA_QUOTA, MAX_REPLICA_BYTES);
    expect(u).toMatchObject({ level: "ok", uploads: 65, bytes: 85_000, families: 2, topFamilyUploads: 60, topFamilyBytes: 80_000 });
    // g1's family has 60 uploads = the family quota.
    expect(u.familiesAtCap).toBe(1);
  });

  it("familiesAtCap also counts a family where the next full-size replica would pass 10 MB", async () => {
    await device("a");
    await device("b");
    // 33 × 307 200 + 40 960 = 10 178 560: a full-size replica still fits exactly. One byte more: at cap.
    await uploads("a", 33, MAX_REPLICA_BYTES);
    await uploads("a", 1, 40_960);
    await uploads("b", 33, MAX_REPLICA_BYTES);
    await uploads("b", 1, 40_961);
    expect((await replicaUsage(sql, REPLICA_QUOTA, MAX_REPLICA_BYTES)).familiesAtCap).toBe(1);
  });

  it("level: reserve from 2400 uploads or past 400 MB, full at 3000 or when a full-size replica no longer fits", async () => {
    await device("x");
    const level = async () => (await replicaUsage(sql, REPLICA_QUOTA, MAX_REPLICA_BYTES)).level;
    await uploads("x", 2399, 1);
    expect(await level()).toBe("ok");
    await uploads("x", 1, 1);
    expect(await level()).toBe("reserve");
    await uploads("x", 600, 1);
    expect(await level()).toBe("full");

    await resetDb(sql);
    await device("y");
    // Rows hold at most 307 200 bytes. 1365 × 307 200 + 102 400 = 419 430 400 = exactly 400 MiB.
    await uploads("y", 1365, MAX_REPLICA_BYTES);
    await uploads("y", 1, 102_400);
    expect(await level()).toBe("ok");
    await uploads("y", 1, 1);
    expect(await level()).toBe("reserve");
    // + 340 × 307 200 + 102 399 = 523 980 800 = 500 MiB − 307 200: a full-size replica still fits.
    await uploads("y", 340, MAX_REPLICA_BYTES);
    await uploads("y", 1, 102_399);
    expect(await level()).toBe("reserve");
    await uploads("y", 1, 1);
    expect(await level()).toBe("full");
  });
});

describe("logReplicaUsage + hourly cron", () => {
  it("one line with exactly the K5.2 fields: log for ok, warn for reserve, error for full; no ids, domains or paths", async () => {
    await device("dev_family_secret");
    await uploads("dev_family_secret", 3);
    let lines = capture();
    await logReplicaUsage(sql);
    expect(lines.log).toHaveLength(1);
    const parsed = JSON.parse(lines.log[0]!) as Record<string, unknown>;
    expect(Object.keys(parsed)).toEqual([
      "event", "level", "uploads", "bytes", "uploadsMax", "bytesMax", "families", "familiesAtCap", "topFamilyUploads", "topFamilyBytes",
    ]);
    expect(parsed).toMatchObject({ event: "replica_quota_usage", level: "ok", uploads: 3 });
    for (const leak of ["dev_family_secret", "q.example", "replica.html.gz"]) expect(lines.log[0]).not.toContain(leak);

    vi.restoreAllMocks();
    await uploads("dev_family_secret", REPLICA_QUOTA.global - REPLICA_QUOTA.reserveUploads, 1);
    lines = capture();
    await logReplicaUsage(sql);
    expect([lines.log.length, lines.warn.length, lines.error.length]).toEqual([0, 1, 0]);

    vi.restoreAllMocks();
    await uploads("dev_family_secret", REPLICA_QUOTA.reserveUploads, 1);
    lines = capture();
    await logReplicaUsage(sql);
    expect([lines.log.length, lines.warn.length, lines.error.length]).toEqual([0, 0, 1]);
    expect(JSON.parse(lines.error[0]!)).toMatchObject({ event: "replica_quota_usage", level: "full" });
  });

  it("the hourly cron logs notifications and the gauge; a failing gauge is replica_usage_failed and notifications still ran", async () => {
    const lines = capture();
    await worker.scheduled!({ cron: "5 * * * *", scheduledTime: Date.now(), noRetry() {} } as ScheduledController, env);
    expect(lines.log.some((l) => l.includes('"event":"notifications"'))).toBe(true);
    expect(lines.log.some((l) => l.includes('"event":"replica_quota_usage"'))).toBe(true);

    vi.restoreAllMocks();
    // The gauge fails after its query (its log line throws); the notifications run before it is untouched.
    const logged: string[] = [];
    const errors: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => {
      const text = a.map(String).join(" ");
      if (text.includes("replica_quota_usage")) throw new TypeError("gauge broke");
      logged.push(text);
    });
    vi.spyOn(console, "error").mockImplementation((...a: unknown[]) => void errors.push(a.map(String).join(" ")));
    await worker.scheduled!({ cron: "5 * * * *", scheduledTime: Date.now(), noRetry() {} } as ScheduledController, env);
    expect(logged.some((l) => l.includes('"event":"notifications"'))).toBe(true);
    expect(errors).toEqual(['{"event":"replica_usage_failed","error":{"name":"TypeError"}}']);
  });

  it("a failing notifications run still logs the gauge, and the cron fails with the original error", async () => {
    // Notifications fail at their own log line (no module mocking in the workers pool).
    const logged: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => {
      const text = a.map(String).join(" ");
      if (text.includes('"event":"notifications"')) throw new RangeError("notifications broke");
      logged.push(text);
    });
    vi.spyOn(console, "error").mockImplementation(() => {});
    await expect(
      worker.scheduled!({ cron: "5 * * * *", scheduledTime: Date.now(), noRetry() {} } as ScheduledController, env),
    ).rejects.toThrow("notifications broke");
    expect(logged.some((l) => l.includes('"event":"replica_quota_usage"'))).toBe(true);
  });
});
