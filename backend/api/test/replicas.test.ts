import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { R2ReplicaStore } from "../src/services/replicaStore";
import { storeFor, storeKind, SupabaseStorageStore } from "../src/services/screenshots";
import { decodeReplica, INFLATE_SLICE, MAX_REPLICA_BASE64, MAX_REPLICA_BYTES, MAX_REPLICA_HTML } from "../src/services/replicas";
import { b64 } from "./helpers/images";
import { gzip, gzipBase64, SAMPLE_HTML, zeroBomb } from "./helpers/replica";

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
