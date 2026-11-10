import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { LIVE_END_EXPIRY_SECONDS, LIVE_EXPIRY_SECONDS, LIVE_STALE_SECONDS, relayLive, type LiveUpdate } from "../src/services/push/live";
import type { LiveMessage, LiveSender, SendResult } from "../src/services/push/sender";
import { atWindowStart } from "./helpers/rateWindow";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, callWithEnv, createDevice, denyingLimiter, type Created } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

const START = "aa".repeat(32);
const UPDATE = "bb".repeat(32);
const ACTIVITY = "6F1C2B3A-1111-4222-8333-444455556666";
const NOW = Date.UTC(2026, 10, 10, 8, 0, 0);
const T = NOW / 1000;

const page = (over: Partial<LiveUpdate> = {}): LiveUpdate => ({
  domain: "very-private-domain.example", score: 42, status: "normal", analyzing: false, open: true, ...over,
});

class Recorder implements LiveSender {
  sent: LiveMessage[] = [];
  constructor(private readonly results: SendResult[] = [{ result: "sent" }]) {}
  async sendLive(m: LiveMessage): Promise<SendResult> {
    this.sent.push(m);
    return this.results.length > 1 ? this.results.shift()! : this.results[0]!;
  }
}

const patch = (d: Created, json: unknown) => call("/devices/me", { method: "PATCH", token: d.token, json });
const tokens = async (d: Created) => {
  const [row] = await sql<{ start: string | null; update: string | null; activity: string | null; startedAt: Date | null }[]>`
    select live_start_token as start, live_update_token as update, live_activity_id as activity, live_started_at as "startedAt"
    from devices where id = ${d.deviceId}`;
  return row!;
};

describe("PATCH /devices/me Live Activity tokens (#49 Q2)", () => {
  it("stores and clears the start token and the update token with its activity id", async () => {
    const d = await createDevice();
    expect((await patch(d, { liveActivityStartToken: START })).status).toBe(200);
    expect((await patch(d, { liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE } })).status).toBe(200);
    expect(await tokens(d)).toMatchObject({ start: START, update: UPDATE, activity: ACTIVITY });

    // Other fields leave them alone.
    expect((await patch(d, { language: "id" })).status).toBe(200);
    expect(await tokens(d)).toMatchObject({ start: START, update: UPDATE });

    expect((await patch(d, { liveActivityUpdateToken: null, liveActivityStartToken: null })).status).toBe(200);
    expect(await tokens(d)).toMatchObject({ start: null, update: null, activity: null });
  });

  it("422 on a non-hex token, a bad activity id or extra keys", async () => {
    const d = await createDevice();
    for (const json of [
      { liveActivityStartToken: "not-hex" },
      { liveActivityUpdateToken: { activityId: ACTIVITY, token: "zz" } },
      { liveActivityUpdateToken: { activityId: "a/b", token: UPDATE } },
      { liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE, domain: "x.example" } },
    ]) {
      expect((await patch(d, json)).status).toBe(422);
    }
  });

  it("DELETE /devices/me removes the tokens with the device", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START, liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE } });
    expect((await call("/devices/me", { method: "DELETE", token: d.token })).status).toBe(200);
    expect(await sql`select 1 from devices where live_start_token = ${START} or live_update_token = ${UPDATE}`).toHaveLength(0);
  });
});

describe("relayLive: start / update / end (#49)", () => {
  it("no tokens: nothing is sent", async () => {
    const d = await createDevice();
    const s = new Recorder();
    expect(await relayLive(sql, s, d.deviceId, page(), NOW)).toEqual({ kind: "none", reason: "no_start_token" });
    expect(s.sent).toHaveLength(0);
  });

  it("start with the push-to-start token: ContentState + attributes, priority 10, stale-date", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START });
    const s = new Recorder();
    expect(await relayLive(sql, s, d.deviceId, page({ status: "warning", score: 64, analyzing: true }), NOW))
      .toEqual({ kind: "start", result: "sent" });
    expect(s.sent).toEqual([{
      token: START, priority: 10, expiresInSeconds: LIVE_EXPIRY_SECONDS,
      payload: { aps: {
        timestamp: T, event: "start",
        "content-state": { domain: "very-private-domain.example", score: 64, isAnalyzing: true, isBlocked: false },
        "attributes-type": "ScoreActivityAttributes", attributes: {},
        "stale-date": T + LIVE_STALE_SECONDS,
      } },
    }]);
    expect((await tokens(d)).startedAt).not.toBeNull();
  });

  it("no second start while the app has not sent the update token yet (no stacked islands)", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START });
    const s = new Recorder();
    await relayLive(sql, s, d.deviceId, page(), NOW);
    expect(await relayLive(sql, s, d.deviceId, page({ domain: "other.example" }), NOW)).toEqual({ kind: "waiting" });
    expect(s.sent).toHaveLength(1);

    // Fallback (#49 Q1): after the wait, the next page starts a new island.
    await sql`update devices set live_started_at = now() - interval '31 seconds' where id = ${d.deviceId}`;
    expect((await relayLive(sql, s, d.deviceId, page(), NOW)).kind).toBe("start");
    expect(s.sent).toHaveLength(2);
  });

  it("parallel calls start at most one island", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START });
    const s = new Recorder();
    const kinds = await Promise.all([1, 2, 3].map(() => relayLive(testSql(), s, d.deviceId, page(), NOW)));
    expect(kinds.filter((k) => k.kind === "start")).toHaveLength(1);
    expect(s.sent).toHaveLength(1);
  });

  it("a failed start can be retried by the next page; 410 clears the start token", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START });
    await relayLive(sql, new Recorder([{ result: "failed:timeout" }]), d.deviceId, page(), NOW);
    expect((await tokens(d)).startedAt).toBeNull();

    await relayLive(sql, new Recorder([{ result: "failed:410 Unregistered", clearToken: true }]), d.deviceId, page(), NOW);
    expect(await tokens(d)).toMatchObject({ start: null, startedAt: null });
  });

  it("update: priority 5 only for a settled normal page; 10 while analyzing (new page) or warning/blocked", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START, liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE } });
    const s = new Recorder();
    expect(await relayLive(sql, s, d.deviceId, page({ score: 12 }), NOW)).toEqual({ kind: "update", result: "sent" });
    await relayLive(sql, s, d.deviceId, page({ score: 81, status: "warning" }), NOW);
    await relayLive(sql, s, d.deviceId, page({ score: 95, status: "blocked" }), NOW);
    // A new page (other domain) starts analyzing: priority 10, so the old risky domain goes away at once.
    await relayLive(sql, s, d.deviceId, page({ domain: "next.example", score: 0, analyzing: true }), NOW);
    expect(s.sent.map((m) => [m.token, m.priority, m.expiresInSeconds])).toEqual([
      [UPDATE, 5, LIVE_EXPIRY_SECONDS], [UPDATE, 10, LIVE_EXPIRY_SECONDS], [UPDATE, 10, LIVE_EXPIRY_SECONDS], [UPDATE, 10, LIVE_EXPIRY_SECONDS],
    ]);
    expect(s.sent[2]!.payload).toEqual({ aps: {
      timestamp: T, event: "update",
      "content-state": { domain: "very-private-domain.example", score: 95, isAnalyzing: false, isBlocked: true },
      "stale-date": T + LIVE_STALE_SECONDS,
    } });
  });

  it("410 on an update clears the update token, so the next page starts again", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START, liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE } });
    await relayLive(sql, new Recorder([{ result: "failed:410 Unregistered", clearToken: true }]), d.deviceId, page(), NOW);
    expect(await tokens(d)).toMatchObject({ start: START, update: null, activity: null });
    const s = new Recorder();
    expect((await relayLive(sql, s, d.deviceId, page(), NOW)).kind).toBe("start");
  });

  it("open: false ends the island now and clears the update token; without one it sends nothing", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START, liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE } });
    const s = new Recorder();
    expect(await relayLive(sql, s, d.deviceId, page({ open: false }), NOW)).toEqual({ kind: "end", result: "sent" });
    expect(s.sent[0]).toMatchObject({ token: UPDATE, priority: 10, expiresInSeconds: LIVE_END_EXPIRY_SECONDS, payload: { aps: { event: "end", "dismissal-date": T } } });
    expect(await tokens(d)).toMatchObject({ start: START, update: null, activity: null });

    expect(await relayLive(sql, s, d.deviceId, page({ open: false }), NOW)).toEqual({ kind: "none", reason: "no_update_token" });
    expect(s.sent).toHaveLength(1);
  });

  it("a token the app sent meanwhile is not cleared (compare-and-clear)", async () => {
    const d = await createDevice();
    await patch(d, { liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE } });
    const newer = "cc".repeat(32);
    const racing: LiveSender = {
      sendLive: async () => {
        await patch(d, { liveActivityUpdateToken: { activityId: ACTIVITY, token: newer } });
        return { result: "failed:410 Unregistered", clearToken: true };
      },
    };
    await relayLive(sql, racing, d.deviceId, page(), NOW);
    expect((await tokens(d)).update).toBe(newer);
  });
});

describe("POST /live (#49)", () => {
  const live = (d: Created, json: unknown) => call("/live", { method: "POST", token: d.token, json });

  it("202 { ok: true }; 401 without token", async () => {
    const d = await createDevice();
    const res = await live(d, page());
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ ok: true });
    expect((await call("/live", { method: "POST", json: page() })).status).toBe(401);
  });

  it("422 on a full URL, bad score or status, or extra keys", async () => {
    const d = await createDevice();
    for (const json of [
      page({ domain: "https://a.example/login" }),
      page({ domain: "A.EXAMPLE" }),
      page({ score: 101 }),
      page({ score: 4.5 }),
      { ...page(), status: "danger" },
      { ...page(), url: "https://a.example/" },
      { domain: "a.example", score: 1 },
    ]) {
      expect((await live(d, json)).status).toBe(422);
    }
  });

  it("forwards, never stores: domain and score land in no table and no log line", async () => {
    const lines: string[] = [];
    for (const m of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, m).mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));
    }
    const d = await createDevice();
    await patch(d, { liveActivityStartToken: START });
    expect((await live(d, page({ score: 77 }))).status).toBe(202);
    await patch(d, { liveActivityUpdateToken: { activityId: ACTIVITY, token: UPDATE } });
    expect((await live(d, page({ score: 78 }))).status).toBe(202);
    expect((await live(d, page({ open: false }))).status).toBe(202);

    const log = lines.join("\n");
    expect(log).toContain('"event":"live_push"');
    expect(log).toContain('"kind":"end"');
    for (const secret of ["very-private-domain", START, UPDATE, ACTIVITY, d.deviceId, d.token]) expect(log).not.toContain(secret);

    // No scan, verdict or push_log row: the live score is not history.
    expect(await sql`select 1 from scans`).toHaveLength(0);
    expect(await sql`select 1 from verdicts`).toHaveLength(0);
    expect(await sql`select 1 from push_log`).toHaveLength(0);
    const dump = JSON.stringify(await sql`select * from devices where id = ${d.deviceId}`);
    expect(dump).not.toContain("very-private-domain");
  });

  it("rate limits open pages to 10 per 10 s per device; an end is never limited", async () => {
    const d = await createDevice();
    await atWindowStart(10);
    for (let i = 0; i < 10; i++) expect((await live(d, page())).status).toBe(202);
    const res = await live(d, page());
    expect(res.status).toBe(429);
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);
    expect((await live(d, page({ open: false }))).status).toBe(202);
    expect(await sql`select 1 from rate_limit_hits where bucket = 'live_push'`).toHaveLength(0);
  }, 15_000);

  it("429 straight from the binding, 202 for an end even then", async () => {
    const d = await createDevice();
    const post = (json: unknown) =>
      callWithEnv({ LIVE_PUSH_LIMITER: denyingLimiter }, "/live", {
        method: "POST", token: d.token, body: JSON.stringify(json), headers: { "content-type": "application/json" },
      });
    expect((await post(page())).status).toBe(429);
    expect((await post(page({ open: false }))).status).toBe(202);
  });
});
