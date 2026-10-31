import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { app } from "../src/app";
import { finishJob, opsSnapshot, startJob, type OpsSnapshot } from "../src/db/repo/ops";
import type { Env } from "../src/env";
import { limits } from "../src/http/rateLimit";
import { evaluate } from "../src/services/opsStatus";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { createDevice, freshIp } from "./helpers/seed";

const sql = testSql();
// shoo_api may only queue a domain with (domain, families); first_seen_at is set by a person here.
const admin = adminSql();
beforeEach(() => resetDb(sql));

const TOKEN = env.OPS_STATUS_TOKEN!;
const MB = 1024 * 1024;

/** A healthy snapshot; each test changes one field. */
const healthy = (): OpsSnapshot => ({
  retention: { okAgeHours: 1, ageHours: 1, failed: 0, backlog: false },
  notifications: { okAgeHours: 0.5, ageHours: 0.5 },
  scansOverdue: false,
  tombstonesStuck: 0,
  dbBytes: 50 * MB,
  blocklistQueue: 0,
  blocklistOldestHours: null,
  healthzAgeHours: null,
});
const codes = (s: OpsSnapshot) => evaluate(s).failing;

describe("evaluate: K3 thresholds (fase 21a)", () => {
  it("a healthy snapshot is ok with nothing failing", () => {
    expect(evaluate(healthy())).toEqual({ ok: true, failing: [] });
  });

  it("retention_stale: alert past 26 h since the last clean run, or when it never ran", () => {
    const s = healthy();
    s.retention.okAgeHours = 26 - 1 / 60;
    expect(codes(s)).toEqual([]);
    s.retention.okAgeHours = 26 + 1 / 60;
    expect(codes(s)).toEqual([{ code: "retention_stale", level: "alert" }]);
    s.retention.okAgeHours = null;
    expect(evaluate(s)).toEqual({ ok: false, failing: [{ code: "retention_stale", level: "alert" }] });
  });

  it("retention_failed: alert when the last run had a failed step", () => {
    const s = healthy();
    s.retention.failed = 1;
    expect(codes(s)).toEqual([{ code: "retention_failed", level: "alert" }]);
  });

  it("retention_backlog is a warn only: ok stays true", () => {
    const s = healthy();
    s.retention.backlog = true;
    expect(evaluate(s)).toEqual({ ok: true, failing: [{ code: "retention_backlog", level: "warn" }] });
  });

  it("retention_overdue: alert when a scan is older than 15 days 6 hours", () => {
    const s = healthy();
    s.scansOverdue = true;
    expect(codes(s)).toEqual([{ code: "retention_overdue", level: "alert" }]);
  });

  it("tombstones_stuck: warn from one stuck tombstone", () => {
    const s = healthy();
    s.tombstonesStuck = 1;
    expect(evaluate(s)).toEqual({ ok: true, failing: [{ code: "tombstones_stuck", level: "warn" }] });
  });

  it("notifications_stale: alert past 2 h 15 min, or when it never ran", () => {
    const s = healthy();
    s.notifications.okAgeHours = 2.25 - 1 / 60;
    expect(codes(s)).toEqual([]);
    s.notifications.okAgeHours = 2.25 + 1 / 60;
    expect(codes(s)).toEqual([{ code: "notifications_stale", level: "alert" }]);
    s.notifications.okAgeHours = null;
    expect(codes(s)).toEqual([{ code: "notifications_stale", level: "alert" }]);
  });

  it("db_size_high: warn from 350 MB, alert from 450 MB (Free 500 MB)", () => {
    const s = healthy();
    s.dbBytes = 350 * MB - 1;
    expect(codes(s)).toEqual([]);
    s.dbBytes = 350 * MB;
    expect(evaluate(s)).toEqual({ ok: true, failing: [{ code: "db_size_high", level: "warn" }] });
    s.dbBytes = 450 * MB - 1;
    expect(codes(s)).toEqual([{ code: "db_size_high", level: "warn" }]);
    s.dbBytes = 450 * MB;
    expect(evaluate(s)).toEqual({ ok: false, failing: [{ code: "db_size_high", level: "alert" }] });
  });

  it("blocklist_queue: warn once the oldest undecided domain waits more than 24 h (D9)", () => {
    const s = healthy();
    s.blocklistQueue = 3;
    s.blocklistOldestHours = 24 - 1 / 60;
    expect(codes(s)).toEqual([]);
    s.blocklistOldestHours = 24 + 1 / 60;
    expect(evaluate(s)).toEqual({ ok: true, failing: [{ code: "blocklist_queue", level: "warn" }] });
  });

  it("healthzAgeHours is a number only, never a code", () => {
    const s = healthy();
    s.healthzAgeHours = 500;
    expect(codes(s)).toEqual([]);
  });

  it("several codes are listed together in a fixed order", () => {
    const s = healthy();
    s.retention.failed = 2;
    s.retention.backlog = true;
    s.notifications.okAgeHours = null;
    expect(codes(s).map((f) => f.code)).toEqual(["retention_failed", "retention_backlog", "notifications_stale"]);
  });
});

describe("opsSnapshot + ops_jobs writers", () => {
  it("empty DB: jobs never ran, nothing overdue, DB size read as shoo_api (C11)", async () => {
    const s = await opsSnapshot(sql);
    expect(s.retention).toEqual({ okAgeHours: null, ageHours: null, failed: 0, backlog: false });
    expect(s.notifications).toEqual({ okAgeHours: null, ageHours: null });
    expect(s.scansOverdue).toBe(false);
    expect(s.tombstonesStuck).toBe(0);
    expect(s.dbBytes).toBeGreaterThan(MB);
    expect(s.blocklistQueue).toBe(0);
    expect(s.blocklistOldestHours).toBeNull();
    expect(s.healthzAgeHours).toBeNull();
  });

  it("finishJob with failed = 0 moves ok_at; a failed run keeps the old ok_at and records failed + backlog", async () => {
    await startJob(sql, "retention");
    await finishJob(sql, "retention", { failed: 0, backlog: false });
    await sql`update ops_jobs set ok_at = now() - interval '3 hours', finished_at = now() - interval '3 hours'`;
    await finishJob(sql, "retention", { failed: 2, backlog: true });
    const s = await opsSnapshot(sql);
    expect(s.retention.failed).toBe(2);
    expect(s.retention.backlog).toBe(true);
    expect(s.retention.okAgeHours).toBeCloseTo(3, 1);
    expect(s.retention.ageHours).toBeLessThan(0.1);
  });

  it("counts overdue scans, stuck tombstones and the blocklist queue; ages come from the DB clock", async () => {
    const d = await createDevice("Mom");
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, created_at)
      values (${d.deviceId}, 'https://a.example/', 'a.example', 92, 'blocked', now(), now() - interval '15 days 7 hours')`;
    await sql`insert into storage_tombstones (path, created_at) values ('a/b.jpg', now() - interval '3 days'), ('a/c.jpg', now())`;
    await admin`insert into blocklist_entries (domain, families, first_seen_at) values
      ('q1.example', 1, now() - interval '30 hours'), ('q2.example', 2, now() - interval '1 hour'), ('q3.example', 0, now() - interval '90 hours')`;
    await sql`insert into ops_heartbeat (source, at) values ('healthz', now() - interval '5 hours')`;
    const s = await opsSnapshot(sql);
    expect(s.scansOverdue).toBe(true);
    expect(s.tombstonesStuck).toBe(1);
    expect(s.blocklistQueue).toBe(2);
    expect(s.blocklistOldestHours).toBeCloseTo(30, 0);
    expect(s.healthzAgeHours).toBeCloseTo(5, 0);
  });

  it("a scan 15 days old is not overdue yet (6 h margin for a late Cron)", async () => {
    const d = await createDevice("Mom");
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, created_at)
      values (${d.deviceId}, 'https://a.example/', 'a.example', 92, 'blocked', now(), now() - interval '15 days 5 hours')`;
    expect((await opsSnapshot(sql)).scansOverdue).toBe(false);
  });
});

/** GET /ops/status with an env override (pattern of test/replicas.test.ts callWith). */
async function status(token: string | null, over: Partial<Env> = {}): Promise<Response> {
  const headers = new Headers({ "cf-connecting-ip": freshIp() });
  if (token !== null) headers.set("authorization", `Bearer ${token}`);
  const ctx = createExecutionContext();
  const res = await app.fetch(new Request("http://api.test/ops/status", { headers }), { ...env, ...over }, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}
const opsHits = async () =>
  (await sql<{ n: number }[]>`select count(*)::int as n from rate_limit_hits where bucket = ${limits.opsStatus.bucket}`)[0]!.n;

describe("GET /ops/status (fase 21a, K6)", () => {
  it("no header, a wrong token or a non-Bearer header → 404 not_found, the same body as an unknown path", async () => {
    const unknown = await (await status(null, {})).clone().json();
    for (const res of [await status(null), await status("x".repeat(40)), await status(TOKEN + "x")]) {
      expect(res.status).toBe(404);
      expect(await res.json()).toEqual({ error: { code: "not_found", message: "Not found" } });
    }
    expect(unknown).toEqual({ error: { code: "not_found", message: "Not found" } });
    const basic = await app.fetch(
      new Request("http://api.test/ops/status", { headers: { authorization: `Basic ${TOKEN}`, "cf-connecting-ip": freshIp() } }),
      env, createExecutionContext(),
    );
    expect(basic.status).toBe(404);
    const head = await app.fetch(new Request("http://api.test/ops/status", { method: "HEAD" }), env, createExecutionContext());
    expect(head.status).toBe(404);
    expect((await status(TOKEN.slice(0, 0))).status).toBe(404);
  });

  it("an empty or short secret → 404 even when the header matches it", async () => {
    expect((await status("", { OPS_STATUS_TOKEN: "" })).status).toBe(404);
    expect((await status("short-token", { OPS_STATUS_TOKEN: "short-token" })).status).toBe(404);
    expect((await status("x".repeat(31), { OPS_STATUS_TOKEN: "x".repeat(31) })).status).toBe(404);
    expect((await status("x".repeat(32), { OPS_STATUS_TOKEN: "x".repeat(32) })).status).toBe(200);
  });

  it("the right token → 200 with the documented fields, security headers and no-store", async () => {
    await finishJob(sql, "retention", { failed: 0, backlog: false });
    await finishJob(sql, "notifications", { failed: 0, backlog: false });
    const res = await status(TOKEN);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("content-security-policy")).toBe("default-src 'none'; frame-ancestors 'none'");
    const body = (await res.json()) as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual([
      "blocklistOldestHours", "blocklistQueue", "dbBytes", "failing", "healthzAgeHours", "jobs", "ok", "tombstonesStuck",
    ]);
    expect(body.ok).toBe(true);
    expect(body.failing).toEqual([]);
    expect(body.jobs).toEqual({
      retention: { ageHours: 0, okAgeHours: 0, failed: 0, backlog: false },
      notifications: { ageHours: 0, okAgeHours: 0 },
    });
    expect(typeof body.dbBytes).toBe("number");
  });

  it("failing codes show up; the body never carries ids, domains or object paths (P6)", async () => {
    const d = await createDevice("Mom Secret");
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, created_at, replica_path)
      values (${d.deviceId}, 'https://secret-domain.example/', 'secret-domain.example', 92, 'blocked', now(), now() - interval '20 days',
              ${d.deviceId} || '/x-replica.html.gz')`;
    await sql`insert into storage_tombstones (path, created_at) values (${d.deviceId + "/y-replica.html.gz"}, now() - interval '3 days')`;
    await admin`insert into blocklist_entries (domain, first_seen_at) values ('queued-secret.example', now() - interval '2 days')`;
    const res = await status(TOKEN);
    const text = await res.text();
    const body = JSON.parse(text) as { ok: boolean; failing: { code: string }[] };
    expect(body.ok).toBe(false);
    expect(body.failing.map((f) => f.code)).toEqual([
      "retention_stale", "retention_overdue", "tombstones_stuck", "notifications_stale", "blocklist_queue",
    ]);
    expect(text).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
    for (const leak of [d.deviceId, ".example", "replica.html.gz", "Mom Secret", "http"]) expect(text).not.toContain(leak);
  });

  it("rate limit 30/h counts only calls with the right token: 31st → 429; wrong tokens never write a row", async () => {
    for (let i = 0; i < 40; i++) expect((await status("y".repeat(40))).status).toBe(404);
    expect(await opsHits()).toBe(0);
    for (let i = 0; i < 30; i++) expect((await status(TOKEN)).status).toBe(200);
    const limited = await status(TOKEN);
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBeTruthy();
    expect(await opsHits()).toBe(30);
    // Still hidden from anyone without the token.
    expect((await status(null)).status).toBe(404);
  });
});
