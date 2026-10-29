import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { app } from "../src/app";
import { runRetention } from "../src/cron/retention";
import { addTombstones, dueTombstones } from "../src/db/repo/tombstones";
import type { Env } from "../src/env";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
import { limits } from "../src/http/rateLimit";
import { REPLICA_CSP } from "../src/routes/replicas";
import { faviconLink, replicaLink, screenshotLink } from "../src/services/screenshotLinks";
import { R2ReplicaStore } from "../src/services/replicaStore";
import { type ScreenshotStore, storeFor, storeKind, SupabaseStorageStore } from "../src/services/screenshots";
import {
  decodeReplica, INFLATE_SLICE, MAX_REPLICA_BASE64, MAX_REPLICA_BYTES, MAX_REPLICA_HTML, REPLICA_QUOTA,
} from "../src/services/replicas";
import { b64 } from "./helpers/images";
import { gzip, gzipBase64, SAMPLE_HTML, zeroBomb } from "./helpers/replica";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { expectScanResult } from "./helpers/schema";
import { call, createDevice, type Created, freshIp } from "./helpers/seed";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

/** gzip of incompressible bytes whose output is exactly `size` bytes (stored blocks grow 1:1 with the input). */
async function gzipOfSize(size: number): Promise<Uint8Array> {
  let n = size - 64;
  for (let i = 0; i < 20; i++) {
    const input = new Uint8Array(n);
    for (let o = 0; o < n; o += 65536) crypto.getRandomValues(input.subarray(o, Math.min(n, o + 65536)));
    const out = await gzip(input);
    if (out.length === size) return out;
    n += size - out.length;
  }
  throw new Error(`no gzip of exactly ${size} bytes`);
}

describe("decodeReplica (EX-07, K2: strict base64, gzip magic, streamed inflate ≤ 3 MB)", () => {
  it("limits match the extension (replica-build.js MAX_BASE64, MAX_HTML_BYTES)", () => {
    expect(MAX_REPLICA_BASE64).toBe(409_600);
    expect(MAX_REPLICA_BYTES).toBe(307_200);
    expect(MAX_REPLICA_HTML).toBe(3_145_728);
    expect(INFLATE_SLICE).toBe(4096);
  });

  it("a valid replica: the gzip bytes as sent (stored as is) and the inflated size", async () => {
    const bytes = await gzip(SAMPLE_HTML);
    const r = await decodeReplica(b64(bytes));
    expect(r).toEqual({ ok: true, bytes, htmlBytes: new TextEncoder().encode(SAMPLE_HTML).length });
  });

  it("exactly 409 600 base64 characters (307 200 bytes) passes", async () => {
    const bytes = await gzipOfSize(MAX_REPLICA_BYTES);
    const text = b64(bytes);
    expect(text.length).toBe(MAX_REPLICA_BASE64);
    expect((await decodeReplica(text)).ok).toBe(true);
  });

  it("409 604 characters → too_large; 409 601 characters → invalid (length % 4), before any decode", async () => {
    expect(await decodeReplica("A".repeat(409_604))).toEqual({ ok: false, reason: "too_large" });
    expect(await decodeReplica("A".repeat(409_601))).toEqual({ ok: false, reason: "invalid" });
  });

  it("exactly 3 145 728 inflated bytes passes; 3 145 729 → too_large", async () => {
    const ok = await decodeReplica(await gzipBase64(new Uint8Array(MAX_REPLICA_HTML)));
    expect(ok).toMatchObject({ ok: true, htmlBytes: MAX_REPLICA_HTML });
    expect(await decodeReplica(await gzipBase64(new Uint8Array(MAX_REPLICA_HTML + 1)))).toMatchObject({ ok: false, reason: "too_large" });
  });

  it.each([
    ["not base64", "<html>!!</html>"],
    ["base64 with whitespace", "H4sI AAAA"],
    ["data: prefix", "data:application/gzip;base64,H4sIAAAA"],
    ["empty", ""],
  ])("%s → invalid", async (_name, text) => {
    expect(await decodeReplica(text)).toEqual({ ok: false, reason: "invalid" });
  });

  it("not gzip (plain HTML, other magic) → not_gzip", async () => {
    expect(await decodeReplica(b64(new TextEncoder().encode(SAMPLE_HTML)))).toEqual({ ok: false, reason: "not_gzip" });
    // zlib (deflate) magic, not gzip
    expect(await decodeReplica(b64(Uint8Array.from([0x78, 0x9c, 1, 2, 3, 4])))).toEqual({ ok: false, reason: "not_gzip" });
  });

  it("truncated gzip → invalid", async () => {
    const bytes = await gzip(SAMPLE_HTML);
    expect(await decodeReplica(b64(bytes.subarray(0, bytes.length - 6)))).toMatchObject({ ok: false, reason: "invalid" });
  });

  it("data after the gzip member (garbage or a second member) → invalid", async () => {
    const bytes = await gzip(SAMPLE_HTML);
    expect(await decodeReplica(b64(Uint8Array.from([...bytes, 1, 2, 3])))).toMatchObject({ ok: false, reason: "invalid" });
    expect(await decodeReplica(b64(Uint8Array.from([...bytes, ...(await gzip("<p>more</p>"))])))).toMatchObject({ ok: false, reason: "invalid" });
  });

  it("gzip bomb with a fake ISIZE (claims 100 bytes, inflates past 3 MB) → too_large", async () => {
    const bomb = await gzip(new Uint8Array(4 * 1024 * 1024));
    bomb.set([100, 0, 0, 0], bomb.length - 4);
    expect(await decodeReplica(b64(bomb))).toMatchObject({ ok: false, reason: "too_large" });
  });

  it("zero bomb of 307 200 bytes: aborted after the 4 KB slice that crosses 3 MB, not after a full inflate", async () => {
    // 320 MB of zeros gzip to ≈ 326 KB; the first 307 200 bytes are the largest bomb the extension limit allows.
    const bomb = (await zeroBomb(320)).subarray(0, MAX_REPLICA_BYTES);
    const r = await decodeReplica(b64(bomb));
    expect(r).toMatchObject({ ok: false, reason: "too_large" });
    // ≈ 1 KB of zero-gzip inflates to 1 MB, so the 3 MB limit falls inside the first slice.
    expect((r as { consumed: number }).consumed).toBe(INFLATE_SLICE);
  });
});

describe("R2ReplicaStore (binding REPLICAS, local Miniflare R2)", () => {
  const store = new R2ReplicaStore(env.REPLICAS);
  const key = () => `dev_r2/${crypto.randomUUID()}-replica.html.gz`;

  it("put → get streams the bytes with the content type; remove deletes", async () => {
    const path = key();
    const bytes = await gzip(SAMPLE_HTML);
    await store.put(path, bytes, "application/gzip");
    const head = await env.REPLICAS.head(path);
    expect(head?.httpMetadata?.contentType).toBe("application/gzip");
    const res = await store.get(path);
    expect(new Uint8Array(await res!.arrayBuffer())).toEqual(bytes);
    await store.remove([path]);
    expect(await store.get(path)).toBeUndefined();
    // Idempotent: removing a missing key is fine (retention may retry a path).
    await store.remove([path]);
  });

  it("an object over 307 200 bytes never reaches R2", async () => {
    const path = key();
    const put = vi.spyOn(env.REPLICAS, "put");
    await expect(store.put(path, new Uint8Array(MAX_REPLICA_BYTES + 1), "application/gzip")).rejects.toThrow("too large");
    expect(put).not.toHaveBeenCalled();
    expect(await env.REPLICAS.head(path)).toBeNull();
  });

  it("remove sends at most 100 keys per R2 delete", async () => {
    const del = vi.spyOn(env.REPLICAS, "delete");
    await store.remove(Array.from({ length: 250 }, key));
    expect(del.mock.calls.map(([keys]) => (keys as string[]).length)).toEqual([100, 100, 50]);
  });
});

describe("storeFor: the store is chosen from the path (K6, K23)", () => {
  it("replicas and new favicons → R2; screenshots and old favicons → Supabase", () => {
    expect(storeKind("dev/scan-replica.html.gz")).toBe("r2");
    expect(storeKind("dev/scan-icon.png")).toBe("r2");
    expect(storeKind("dev/scan-favicon.png")).toBe("supabase");
    expect(storeKind("dev/scan.jpg")).toBe("supabase");
    expect(storeKind("dev/scan.png")).toBe("supabase");
    expect(storeFor(env, "dev/scan-replica.html.gz")).toBeInstanceOf(R2ReplicaStore);
    expect(storeFor(env, "dev/scan.jpg")).toBeInstanceOf(SupabaseStorageStore);
  });

  it("R2 needs only the binding, never REPLICAS_ENABLED (deletes run with the kill-switch off)", () => {
    expect(storeFor({ ...env, REPLICAS_ENABLED: "false" }, "dev/scan-replica.html.gz")).toBeInstanceOf(R2ReplicaStore);
    expect(storeFor({ ...env, REPLICAS: undefined }, "dev/scan-replica.html.gz")).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------------------------
// Through the API: POST /scans stores the replica in waitUntil, GET /replicas/{id} serves it.

/** The Worker shares this isolate's globals, so a spy here reaches decodeReplica. */
const streams = globalThis as unknown as { DecompressionStream: () => DecompressionStream };

const logs: string[] = [];
beforeEach(() => {
  logs.length = 0;
  for (const m of ["log", "error"] as const) {
    vi.spyOn(console, m).mockImplementation((...a: unknown[]) => void logs.push(a.map(String).join(" ")));
  }
});

const domain = blocked92.domain;
const scanBody = (extra: Record<string, unknown> = {}) =>
  ({ ...blocked92, id: undefined, verdict: undefined, screenshotUrl: undefined, faviconUrl: null, ...extra });
const postScan = async (d: Created, extra: Record<string, unknown> = {}, ip?: string) => {
  const res = await call("/scans", { method: "POST", token: d.token, json: scanBody(extra), ip });
  expect(res.status, await res.clone().text()).toBe(201);
  return ((await res.json()) as { id: string }).id;
};
const other = (n: number) => ({ domain: `site${n}.example`, url: `https://site${n}.example/login` });
const row = async (id: string) =>
  (await sql<{ path: string | null; bytes: number | null }[]>`select replica_path as path, replica_bytes as bytes from scans where id = ${id}`)[0];

/** waitUntil runs after the response: poll until `done` holds (4 s at most). */
async function until(done: () => Promise<boolean> | boolean): Promise<void> {
  for (let i = 0; i < 160; i++) {
    if (await done()) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error("timed out waiting for waitUntil work");
}
const stored = async (id: string) => {
  await until(async () => (await row(id))?.path != null);
  return (await row(id))!;
};
const droppedFor = (reason: string) =>
  until(() => logs.some((l) => l.includes(`"event":"replica_dropped"`) && l.includes(`"reason":"${reason}"`)));
const r2Keys = async (prefix: string) => (await env.REPLICAS.list({ prefix })).objects.map((o) => o.key);

const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};
/** A Protected device with a Guardian, both with APNs tokens: replicas need a family link (K5). */
const family = async () => {
  const g = await createDevice("G", "guardian");
  const p = await createDevice("Mom");
  await connect(g, p);
  for (const [d, t] of [[g, "ab"], [p, "cd"]] as const) {
    expect((await call("/devices/me", { method: "PATCH", token: d.token, json: { apnsToken: t.repeat(32) } })).status).toBe(200);
  }
  return { g, p };
};
const detail = async (viewer: Created, id: string, over?: Partial<Env>) => {
  const res = over ? await callWith(over, `/scans/${id}`, { token: viewer.token }) : await call(`/scans/${id}`, { token: viewer.token });
  expect(res.status).toBe(200);
  return (await res.json()) as Record<string, unknown> & { pageReplicaUrl: string | null };
};
const linkFor = async (viewer: Created, id: string) => {
  const u = new URL((await detail(viewer, id)).pageReplicaUrl!);
  return `${u.pathname}${u.search}`;
};

/** Like call(), with some env values replaced (kill-switch), waiting for the request's waitUntil work. */
async function callWith(over: Partial<Env>, path: string, init: RequestInit & { token?: string; json?: unknown } = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  if (init.token) headers.set("authorization", `Bearer ${init.token}`);
  headers.set("cf-connecting-ip", freshIp());
  let body = init.body;
  if (init.json !== undefined) {
    headers.set("content-type", "application/json");
    body = JSON.stringify(init.json);
  }
  const ctx = createExecutionContext();
  const res = await app.fetch(new Request(`http://api.test${path}`, { ...init, headers, body }), { ...env, ...over }, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

const fill = async (limit: { bucket: string; max: number }, key: string, n = limit.max) => {
  const k = await keyHash(`${limit.bucket}:${key}`);
  await sql`insert into rate_limit_hits (bucket, key_hash) select ${limit.bucket}, ${k} from generate_series(1, ${n})`;
};
/** Original uploads (replica_bytes set) of `owner` in the last 24 h, without objects: quota fodder. */
const fakeUploads = async (owner: string, n: number, bytes = 1000) => {
  await sql`insert into scans (owner_id, url, domain, score, status, detected_at, replica_path, replica_bytes)
    select ${owner}, 'https://q.example/', 'q.example', 92, 'blocked', now(), ${owner} || '/q' || g || '-replica.html.gz', ${bytes}
    from generate_series(1, ${n}) g`;
};

describe("POST /scans stores the page replica (EX-07, K2–K5)", () => {
  it("201 first, then <owner>/<scan>-replica.html.gz in R2 with the gzip bytes as sent, tombstoned", async () => {
    const { p } = await family();
    const bytes = await gzip(SAMPLE_HTML);
    const id = await postScan(p, { pageReplicaBase64: b64(bytes) });
    const path = `${p.deviceId}/${id}-replica.html.gz`;
    expect(await stored(id)).toEqual({ path, bytes: bytes.length });
    const object = await env.REPLICAS.get(path);
    expect(new Uint8Array(await object!.arrayBuffer())).toEqual(bytes);
    expect(object!.httpMetadata?.contentType).toBe("application/gzip");
    expect((await sql`select 1 from storage_tombstones where path = ${path}`).length).toBe(1);
  });

  it("pageReplicaUrl: a 1-hour Worker link on GET /scans/{id}; the key is always null in GET /scans", async () => {
    const { g, p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    await stored(id);
    const without = await postScan(p, other(1));

    for (const viewer of [p, g]) {
      const one = await detail(viewer, id);
      expectScanResult(one);
      const link = new URL(one.pageReplicaUrl!);
      expect(`${link.origin}${link.pathname}`).toBe(`${env.INVITE_BASE_URL}/replicas/${id}`);
      expect([...link.searchParams.keys()].sort()).toEqual(["exp", "sig", "v"]);
      expect(link.searchParams.get("v")).toBe(viewer.deviceId);
      expect(Number(link.searchParams.get("exp")) - Date.now() / 1000).toBeGreaterThan(3500);
    }
    const none = await detail(p, without);
    expect("pageReplicaUrl" in none && none.pageReplicaUrl === null).toBe(true);

    for (const q of ["", "?owner=family"]) {
      const viewer = q ? g : p;
      const list = (await (await call(`/scans${q}`, { token: viewer.token })).json()) as { items: Record<string, unknown>[] };
      expect(list.items.length).toBe(2);
      for (const item of list.items) {
        expectScanResult(item);
        expect(Object.hasOwn(item, "pageReplicaUrl")).toBe(true);
        expect(item.pageReplicaUrl).toBeNull();
      }
    }
  });

  it.each<[string, () => string | Promise<string>, string]>([
    ["broken base64", () => "!!not base64!!", "invalid"],
    ["not gzip", () => b64(new TextEncoder().encode(SAMPLE_HTML)), "not_gzip"],
    ["409 604 characters", () => "A".repeat(409_604), "too_large"],
    ["409 601 characters", () => "A".repeat(409_601), "invalid"],
    ["3 145 729 inflated bytes", () => gzipBase64(new Uint8Array(MAX_REPLICA_HTML + 1)), "too_large"],
    ["zero bomb", async () => b64((await zeroBomb(320)).subarray(0, MAX_REPLICA_BYTES)), "too_large"],
  ])("%s → 201, replica dropped (%s… reason only in the log), nothing in R2", async (_name, make, reason) => {
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await make() });
    await droppedFor(reason);
    expect(await row(id)).toEqual({ path: null, bytes: null });
    expect(await r2Keys(`${p.deviceId}/`)).toEqual([]);
    const line = logs.find((l) => l.includes(`"replica_dropped"`))!;
    expect(JSON.parse(line)).toEqual({ event: "replica_dropped", reason });
  });

  it("exactly 409 600 characters and exactly 3 145 728 inflated bytes are stored", async () => {
    const { p } = await family();
    const big = await gzipOfSize(MAX_REPLICA_BYTES);
    const a = await postScan(p, { pageReplicaBase64: b64(big) });
    expect((await stored(a)).bytes).toBe(MAX_REPLICA_BYTES);
    const b = await postScan(p, { ...other(2), pageReplicaBase64: await gzipBase64(new Uint8Array(MAX_REPLICA_HTML)) });
    expect((await stored(b)).path).toBe(`${p.deviceId}/${b}-replica.html.gz`);
  });

  it("the Guardian's push goes out before the replica is inflated", async () => {
    const Real = DecompressionStream;
    vi.spyOn(streams, "DecompressionStream").mockImplementation(function (format: "gzip") {
      logs.push("INFLATE");
      return new Real(format);
    } as unknown as () => DecompressionStream);
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    await stored(id);
    const order = logs.filter((l) => l === "INFLATE" || l.includes(`"push_logged"`)).map((l) => (l === "INFLATE" ? "inflate" : "push"));
    // Guardian push + the device's own push, both before the inflate.
    expect(order).toEqual(["push", "push", "inflate"]);
  });

  it("a replica that throws never touches the scan or the push", async () => {
    vi.spyOn(streams, "DecompressionStream").mockImplementation(function () {
      throw new Error("inflate exploded");
    } as unknown as () => DecompressionStream);
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    await droppedFor("error");
    await until(async () => (await sql`select 1 from push_log where scan_id = ${id}`).length >= 1);
    expect(await row(id)).toEqual({ path: null, bytes: null });
  });

  it("an owner without family keeps no replica (nobody could see it), and spends no IP slot", async () => {
    const p = await createDevice("Solo");
    const ip = freshIp();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) }, ip);
    await droppedFor("no_family");
    expect(await row(id)).toEqual({ path: null, bytes: null });
    expect(await r2Keys(`${p.deviceId}/`)).toEqual([]);
    expect((await sql`select 1 from rate_limit_hits where bucket = ${limits.replicaIp.bucket}`).length).toBe(0);
  });

  it("a Guardian with members keeps replicas of its own scans", async () => {
    const { g } = await family();
    const id = await postScan(g, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    expect((await stored(id)).path).toBe(`${g.deviceId}/${id}-replica.html.gz`);
  });

  it("300 uploads per IP per 24 h, then dropped (ip_quota) without a put", async () => {
    const { p } = await family();
    const ip = "203.0.113.77";
    await fill(limits.replicaIp, ip);
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) }, ip);
    await droppedFor("ip_quota");
    expect(await row(id)).toEqual({ path: null, bytes: null });
    expect(await r2Keys(`${p.deviceId}/`)).toEqual([]);
    expect(limits.replicaIp).toMatchObject({ max: 300, windowSeconds: 86400 });
  });

  it("reuses the owner's replica of the same domain within 24 h: no decode, no put, no IP slot, no bytes", async () => {
    const { p } = await family();
    const first = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    const { path } = await stored(first);
    const put = vi.spyOn(R2ReplicaStore.prototype, "put");
    const second = await postScan(p, { pageReplicaBase64: "!!would be invalid!!" });
    expect(await stored(second)).toEqual({ path, bytes: null });
    expect(put).not.toHaveBeenCalled();
    expect((await sql`select 1 from rate_limit_hits where bucket = ${limits.replicaIp.bucket}`).length).toBe(1);
    // Another owner never shares it; past 24 h a new upload is made.
    await sql`update scans set created_at = now() - interval '25 hours' where id = ${first}`;
    const third = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    expect((await stored(third)).path).toBe(`${p.deviceId}/${third}-replica.html.gz`);
  });

  it("per-device quota: 50 uploads in 24 h, reuses not counted", async () => {
    const { p } = await family();
    await fakeUploads(p.deviceId, REPLICA_QUOTA.owner);
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    await droppedFor("quota");
    expect(await row(id)).toEqual({ path: null, bytes: null });
    expect(REPLICA_QUOTA).toEqual({ owner: 50, global: 3000, globalBytes: 500 * 1024 * 1024 });
  });

  it("global quota: 3000 uploads by everyone in 24 h", async () => {
    const { p } = await family();
    const someone = await createDevice("Else");
    await fakeUploads(someone.deviceId, REPLICA_QUOTA.global);
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    await droppedFor("global_quota");
    expect(await row(id)).toEqual({ path: null, bytes: null });
  });

  it("global byte quota: 500 MB of uploads by everyone in 24 h", async () => {
    const { p } = await family();
    const someone = await createDevice("Else");
    // 1706 × 307 200 = 524 083 200 bytes: 204 800 left, less than the next upload needs? No: a small page fits.
    await fakeUploads(someone.deviceId, 1706, MAX_REPLICA_BYTES);
    const small = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    expect((await stored(small)).path).not.toBeNull();
    const big = await postScan(p, { ...other(3), pageReplicaBase64: b64(await gzipOfSize(MAX_REPLICA_BYTES)) });
    await droppedFor("global_bytes");
    expect(await row(big)).toEqual({ path: null, bytes: null });
  });

  it("parallel scans cannot overrun the per-device quota (lock per owner)", async () => {
    const { p } = await family();
    await fakeUploads(p.deviceId, REPLICA_QUOTA.owner - 1);
    const replica = await gzipBase64(SAMPLE_HTML);
    const ids = await Promise.all([4, 5, 6, 7].map((n) => postScan(p, { ...other(n), pageReplicaBase64: replica })));
    await until(async () => logs.filter((l) => l.includes(`"reason":"quota"`)).length === 3);
    const rows = await Promise.all(ids.map(row));
    expect(rows.filter((r) => r?.path !== null)).toHaveLength(1);
  });

  it("parallel scans of different owners cannot overrun the global quota (global key 6, 0)", async () => {
    const owners = await Promise.all([1, 2, 3, 4].map(() => family()));
    const someone = await createDevice("Else");
    await fakeUploads(someone.deviceId, REPLICA_QUOTA.global - 1);
    const replica = await gzipBase64(SAMPLE_HTML);
    const ids = await Promise.all(owners.map(({ p }) => postScan(p, { pageReplicaBase64: replica })));
    await until(async () => logs.filter((l) => l.includes(`"reason":"global_quota"`)).length === 3);
    const rows = await Promise.all(ids.map(row));
    expect(rows.filter((r) => r?.path !== null)).toHaveLength(1);
  });

  it("the scan deleted while the replica is processed → nothing left in R2", async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    const real = R2ReplicaStore.prototype.put;
    vi.spyOn(R2ReplicaStore.prototype, "put").mockImplementation(async function (this: R2ReplicaStore, ...args) {
      await gate;
      return real.apply(this, args);
    });
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    await until(async () => (await row(id))?.path != null);
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    release();
    await until(async () => (await r2Keys(`${p.deviceId}/`)).length === 0 &&
      (await sql`select 1 from scans where id = ${id}`).length === 0);
    // Give a late put a moment, then check again: abandonUpload removed it.
    await new Promise((r) => setTimeout(r, 200));
    expect(await r2Keys(`${p.deviceId}/`)).toEqual([]);
  });
});

describe("kill-switch REPLICAS_ENABLED (K21)", () => {
  const off = { REPLICAS_ENABLED: "false" };

  it("off → no put, pageReplicaUrl null, GET /replicas/{id} 404", async () => {
    const { p } = await family();
    const stored1 = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    await stored(stored1);
    const link = await linkFor(p, stored1);

    const res = await callWith(off, "/scans", { method: "POST", token: p.token, json: scanBody({ ...other(8), pageReplicaBase64: await gzipBase64(SAMPLE_HTML) }) });
    expect(res.status).toBe(201);
    const { id } = (await res.json()) as { id: string };
    expect(await row(id)).toEqual({ path: null, bytes: null });
    expect(await r2Keys(`${p.deviceId}/${id}`)).toEqual([]);
    expect((await detail(p, stored1, off)).pageReplicaUrl).toBeNull();
    expect((await callWith(off, link)).status).toBe(404);
    expect((await call(link)).status).toBe(200);
  });

  it("off still deletes: DELETE /devices/me removes the R2 object", async () => {
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    const { path } = await stored(id);
    expect((await callWith(off, "/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect(await env.REPLICAS.head(path!)).toBeNull();
  });
});

describe("GET /replicas/{scanId} (EX-07, K7, K8, K20)", () => {
  const setup = async () => {
    const { g, p } = await family();
    const bytes = await gzip(SAMPLE_HTML);
    const id = await postScan(p, { pageReplicaBase64: b64(bytes) });
    await stored(id);
    return { g, p, id, bytes };
  };

  it("serves the gzip bytes as stored with the exact headers", async () => {
    const { p, id, bytes } = await setup();
    const res = await callWith({}, await linkFor(p, id));
    expect(res.status).toBe(200);
    expect(Object.fromEntries([...res.headers].filter(([k]) => !["x-request-id", "x-frame-options", "strict-transport-security"].includes(k))))
      .toEqual({
        "content-type": "text/html; charset=utf-8",
        "content-encoding": "gzip",
        "content-disposition": 'attachment; filename="replica.html"',
        "content-security-policy": REPLICA_CSP,
        "x-content-type-options": "nosniff",
        "cache-control": "private, no-store",
        "referrer-policy": "no-referrer",
      });
    expect(REPLICA_CSP).toBe(
      "sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'; base-uri 'none'; frame-ancestors 'none'",
    );
    expect(res.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
    // app.fetch hands back the Response itself: the body is the stored gzip, not re-encoded.
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(bytes);
    // Through the Worker's fetch the client inflates Content-Encoding once and gets the page: the body
    // went out gzip-encoded exactly once (without encodeBody "manual" it would come back as gzip bytes).
    const viaWorker = await call(await linkFor(p, id));
    expect(await viaWorker.text()).toBe(SAMPLE_HTML);
  });

  it.each([
    [{ "sec-fetch-mode": "navigate" }, 404],
    [{ "sec-fetch-mode": "navigate", "sec-fetch-dest": "document" }, 404],
    [{ "sec-fetch-dest": "document" }, 404],
    [{ "sec-fetch-dest": "iframe" }, 404],
    [{ "sec-fetch-dest": "frame" }, 404],
    [{ "sec-fetch-dest": "object" }, 404],
    [{ "sec-fetch-dest": "embed" }, 404],
    [{ "sec-fetch-mode": "cors", "sec-fetch-dest": "empty" }, 200],
    [{}, 200],
  ])("browser request headers %o → %i (never a page on this origin)", async (headers, status) => {
    const { p, id } = await setup();
    const res = await call(await linkFor(p, id), { headers });
    expect(res.status).toBe(status);
    await res.body?.cancel();
  });

  it("guardian can open it; after disconnect the same link → 404; the owner still can", async () => {
    const { g, p, id } = await setup();
    const link = await linkFor(g, id);
    expect((await call(link)).status).toBe(200);
    expect((await call("/family/guardian", { method: "DELETE", token: p.token })).status).toBe(200);
    expect((await call(link)).status).toBe(404);
    expect((await call(await linkFor(p, id))).status).toBe(200);
  });

  it("IDOR: Guardian B cannot open Guardian A's member's replica, even with a link signed for B", async () => {
    const { p, id } = await setup();
    const gB = await createDevice("B", "guardian");
    const pB = await createDevice("PB");
    await connect(gB, pB);
    expect((await call(`/scans/${id}`, { token: gB.token })).status).toBe(404);
    const forged = new URL(await replicaLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, gB.deviceId, Date.now() / 1000));
    expect((await call(`${forged.pathname}${forged.search}`)).status).toBe(404);
    // A's own link with B's id swapped in fails the signature.
    const a = new URL(`http://x${await linkFor(p, id)}`);
    a.searchParams.set("v", gB.deviceId);
    expect((await call(`${a.pathname}${a.search}`)).status).toBe(404);
  });

  it("links of other kinds never open a replica, and a replica link opens nothing else", async () => {
    const { p, id } = await setup();
    const now = Date.now() / 1000;
    for (const make of [screenshotLink, faviconLink]) {
      const u = new URL(await make(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, p.deviceId, now));
      expect((await call(`/replicas/${id}${u.search}`)).status).toBe(404);
    }
    const r = new URL(await replicaLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, p.deviceId, now));
    expect((await call(`/screenshots/${id}${r.search}`)).status).toBe(404);
    expect((await call(`/favicons/${id}${r.search}`)).status).toBe(404);
  });

  it("expired, tampered or missing signature → 404", async () => {
    const { p, id } = await setup();
    const old = new URL(await replicaLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, p.deviceId, Date.now() / 1000 - 3601));
    expect((await call(`${old.pathname}${old.search}`)).status).toBe(404);
    const link = new URL(`http://x${await linkFor(p, id)}`);
    const sig = link.searchParams.get("sig")!;
    for (const change of [
      (u: URL) => u.searchParams.set("sig", `${sig.slice(0, -1)}${sig.endsWith("A") ? "B" : "A"}`),
      (u: URL) => u.searchParams.delete("sig"),
      (u: URL) => u.searchParams.set("exp", String(Number(u.searchParams.get("exp")) + 60)),
    ]) {
      const u = new URL(link);
      change(u);
      expect((await call(`${u.pathname}${u.search}`)).status, u.search).toBe(404);
    }
    expect((await call("/replicas/not-a-uuid")).status).toBe(404);
  });

  it("per viewer: 10 per minute, then 500 per day → 429; no global cap", async () => {
    const { g, p, id } = await setup();
    await fill(limits.viewReplica, p.deviceId);
    expect((await call(await linkFor(p, id))).status).toBe(429);
    // Another viewer is not affected.
    expect((await call(await linkFor(g, id))).status).toBe(200);
    await fill(limits.viewReplicaDay, g.deviceId);
    expect((await call(await linkFor(g, id))).status).toBe(429);
    expect(limits.viewReplica).toMatchObject({ max: 10, windowSeconds: 60 });
    expect(limits.viewReplicaDay).toMatchObject({ max: 500, windowSeconds: 86400 });
    expect(Object.values(limits).some((l) => l.bucket.startsWith("replicas_view_all"))).toBe(false);
  });

  it("an object that is not gzip is never sent with Content-Encoding: gzip → 404", async () => {
    const { p, id } = await setup();
    const { path } = (await row(id))!;
    await env.REPLICAS.put(path!, new TextEncoder().encode("<html>plain</html>"));
    expect((await call(await linkFor(p, id))).status).toBe(404);
  });

  it("after DELETE /devices/me → 404 at once, and the object is gone from R2", async () => {
    const { p, id } = await setup();
    const link = await linkFor(p, id);
    const { path } = (await row(id))!;
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect((await call(link)).status).toBe(404);
    await until(async () => (await env.REPLICAS.head(path!)) === null);
  });

  it("after POST /devices/me/protected the old guardian's replicas are gone", async () => {
    const g = await createDevice("G", "guardian");
    const member = await createDevice("Kid");
    await connect(g, member);
    const id = await postScan(g, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    const { path } = await stored(id);
    expect((await call(`/family/members/${member.deviceId}`, { method: "DELETE", token: g.token })).status).toBe(200);
    const g2 = await createDevice("G2", "guardian");
    const { code } = (await (await call("/family/code", { method: "POST", token: g2.token })).json()) as { code: string };
    expect((await call("/devices/me/protected", { method: "POST", token: g.token, json: { code } })).status).toBe(200);
    await until(async () => (await env.REPLICAS.head(path!)) === null);
  });
});

describe("retention and tombstones with replicas (K6)", () => {
  // shoo_api may only update the retry columns of a tombstone; ageing one is a test-only change.
  const admin = adminSql();
  const ageTombstone = (path: string, age: string) =>
    admin`update storage_tombstones set created_at = now() - ${age}::interval where path = ${path}`;
  it("dueTombstones splits paths by the same rule as storeKind (SQL R2_PATH = TypeScript storeKind)", async () => {
    const paths = [
      "o/s1-replica.html.gz", "o/s2-icon.png", "o/s3-icon.svg", "o/s4-favicon.png", "o/s5.jpg", "o/s6.png",
      "o/s7-icon.PNG", "o/s8-replica.html.gz.jpg", "o/s9-icon.png.jpg", "o/s10-icons.png", "o/s11-replica.html",
    ];
    await addTombstones(sql, paths, { settled: true });
    const r2 = await dueTombstones(sql, 100, "r2");
    const supabase = await dueTombstones(sql, 100, "supabase");
    expect([...r2].sort()).toEqual(paths.filter((p) => storeKind(p) === "r2").sort());
    expect([...supabase].sort()).toEqual(paths.filter((p) => storeKind(p) === "supabase").sort());
    expect(r2.length).toBe(3);
  });

  /** A store that only records: tests that count calls per store. */
  const fakeStore = (failing = false) => {
    const calls: string[][] = [];
    const store: ScreenshotStore & { calls: string[][] } = {
      calls,
      put: async () => undefined,
      get: async () => undefined,
      remove: async (paths: string[]) => {
        calls.push(paths);
        if (failing) throw new Error("store down");
      },
    };
    return store;
  };
  const device = async (id: string) =>
    sql`insert into devices (id, name, mode, avatar_id, token_hash) values (${id}, ${id}, 'protected', 'avatar_01', ${new TextEncoder().encode(id)})`;
  /** n old scans of `owner`, each with its own object path from `pathOf`. */
  const oldScans = async (owner: string, n: number, column: "replica_path" | "screenshot_path", suffix: string) => {
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, created_at, ${sql(column)})
      select ${owner}, 'https://x.example/', 'x.example', 92, 'blocked', now(), now() - interval '15 days',
             ${owner} || '/old' || g || ${suffix}
      from generate_series(1, ${n}) g`;
  };

  it("a live scan's replica survives the tombstone step (10 minutes after upload and later)", async () => {
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    const { path } = await stored(id);
    await ageTombstone(path!, "1 day");
    await runRetention(sql, env);
    expect(await env.REPLICAS.head(path!)).not.toBeNull();
    expect((await call(await linkFor(p, id))).status).toBe(200);
  });

  it("a scan with only a replica goes through the stored-files walk: day 14 removes row, object and link", async () => {
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    const { path } = await stored(id);
    const link = await linkFor(p, id);
    await sql`update scans set created_at = now() - interval '15 days' where id = ${id}`;
    await ageTombstone(path!, "15 days");
    const r = await runRetention(sql, env);
    expect(r).toMatchObject({ scans: 1, plainScans: 0, objects: 1 });
    expect(await env.REPLICAS.head(path!)).toBeNull();
    expect((await call(link)).status).toBe(404);
    expect((await sql`select 1 from storage_tombstones where path = ${path}`).length).toBe(0);
  });

  it("keeps a replica still reused by a younger scan", async () => {
    const { p } = await family();
    const first = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    const { path } = await stored(first);
    const younger = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    expect((await stored(younger)).path).toBe(path);
    await sql`update scans set created_at = now() - interval '15 days' where id = ${first}`;
    await runRetention(sql, env);
    expect(await env.REPLICAS.head(path!)).not.toBeNull();
    expect((await call(await linkFor(p, younger))).status).toBe(200);
  });

  it("kill-switch off: retention still removes R2 objects", async () => {
    const { p } = await family();
    const id = await postScan(p, { pageReplicaBase64: await gzipBase64(SAMPLE_HTML) });
    const { path } = await stored(id);
    await sql`update scans set created_at = now() - interval '15 days' where id = ${id}`;
    await runRetention(sql, { ...env, REPLICAS_ENABLED: "false" });
    expect(await env.REPLICAS.head(path!)).toBeNull();
  });

  it("4000 R2 + 1000 Supabase objects in one run: R2 drains (40 × 100), Supabase stays within its 10 calls", async () => {
    await device("dev_big");
    await oldScans("dev_big", 4000, "replica_path", "-replica.html.gz");
    await oldScans("dev_big", 1000, "screenshot_path", ".jpg");
    const supabase = fakeStore();
    const r2 = fakeStore();
    const r = await runRetention(sql, env, { store: supabase, r2Store: r2 });
    expect(r.scans).toBe(5000);
    expect(r2.calls.flat()).toHaveLength(4000);
    expect(Math.max(...r2.calls.map((c) => c.length))).toBeLessThanOrEqual(100);
    expect(r2.calls.length).toBeLessThanOrEqual(40);
    expect(supabase.calls.length).toBeLessThanOrEqual(10);
    expect(supabase.calls.flat()).toHaveLength(1000);
    expect(r2.calls.flat().every((p) => p.endsWith("-replica.html.gz"))).toBe(true);
    expect(supabase.calls.flat().every((p) => p.endsWith(".jpg"))).toBe(true);
    expect((await sql`select count(*)::int as n from storage_tombstones`)[0]!.n).toBe(0);
  });

  it("R2 missing: its batch fails and keeps its tombstones; the Supabase batch still runs", async () => {
    await device("dev_mix");
    await oldScans("dev_mix", 3, "replica_path", "-replica.html.gz");
    await oldScans("dev_mix", 2, "screenshot_path", ".jpg");
    const supabase = fakeStore();
    await expect(runRetention(sql, { ...env, REPLICAS: undefined as unknown as R2Bucket }, { store: supabase })).rejects.toThrow();
    expect(supabase.calls.flat()).toHaveLength(2);
    const left = (await sql<{ path: string }[]>`select path from storage_tombstones order by path`).map((r) => r.path);
    expect(left).toHaveLength(3);
    expect(left.every((p) => p.endsWith("-replica.html.gz"))).toBe(true);
    // The next run with R2 back drains them through the tombstone step.
    const r2 = fakeStore();
    await runRetention(sql, env, { store: supabase, r2Store: r2 });
    expect(r2.calls.flat().sort()).toEqual(left);
  });

  it("a failing R2 store stops only R2 calls; Supabase keeps going", async () => {
    await device("dev_fail");
    await oldScans("dev_fail", 250, "replica_path", "-replica.html.gz");
    await oldScans("dev_fail", 250, "screenshot_path", ".jpg");
    const supabase = fakeStore();
    const r2 = fakeStore(true);
    await expect(runRetention(sql, env, { store: supabase, r2Store: r2 })).rejects.toThrow("store down");
    expect(r2.calls).toHaveLength(2); // one in the scans step, one retry of due tombstones
    expect(supabase.calls.flat()).toHaveLength(250);
  });
});
