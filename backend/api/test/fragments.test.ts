import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { runRetention } from "../src/cron/retention";
import { dueTombstones } from "../src/db/repo/tombstones";
import type { Env } from "../src/env";
import { MAX_SCAN_BYTES } from "../src/http/bodyLimit";
import { useRateKeySecret } from "../src/http/keyHash";
import { archiveFavicon, attachFragments, faviconKey, FRAGMENT_QUOTA, fragmentsKey } from "../src/services/fragments";
import { b64 } from "./helpers/images";
import { gzip, gzipBase64 } from "./helpers/replica";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";
useRateKeySecret(env.RATE_KEY_SECRET);

// ADM-07 (dashboard plan fase 07a K5–K7, K12): evidence fragments in the admin archive bucket.
const sql = testSql();
const admin = adminSql();
let logs: string[] = [];
beforeEach(async () => {
  await resetDb(sql);
  logs = [];
  vi.spyOn(console, "error").mockImplementation((...a: unknown[]) => void logs.push(a.join(" ")));
});
afterEach(() => vi.restoreAllMocks());

const FRAGMENTS_HTML =
  '<!doctype html><html><head><meta name="shoo-fragments" content="{&quot;v&quot;:1}"><style>form{color:red}</style></head>' +
  '<body><section data-shoo-fragment data-shoo-signals="asks_otp"><form><input type="text"></form></section></body></html>';

const scanBody = (extra: Record<string, unknown> = {}) => {
  const { id: _id, ownerDeviceId: _o, ownerName: _n, verdict: _v, screenshotUrl: _s, ...rest } = blocked92 as Record<string, unknown>;
  return { ...rest, detectedAt: new Date().toISOString(), ...extra };
};
const postScan = async (d: Created, extra: Record<string, unknown> = {}) => {
  const res = await call("/scans", { method: "POST", token: d.token, json: scanBody(extra) });
  expect(res.status, await res.clone().text()).toBe(201);
  return ((await res.json()) as { id: string }).id;
};

async function until(done: () => Promise<boolean> | boolean): Promise<void> {
  for (let i = 0; i < 160; i++) {
    if (await done()) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error("timed out waiting for waitUntil work");
}
const archived = async (id: string) =>
  (await admin<{ fragments_key: string | null; fragments_bytes: number | null; owner_ref: string | null }[]>`
    select fragments_key, fragments_bytes, owner_ref from admin.scan_archive where scan_id = ${id}`)[0];
const droppedFor = (reason: string) =>
  until(() => logs.some((l) => l.includes(`"event":"fragments_dropped"`) && l.includes(`"reason":"${reason}"`)));

describe("POST /scans evidenceFragmentsBase64 (ADM-07 K5)", () => {
  it("stores the gzip as sent under <scan_id>.fragments.html.gz, without a family; the archive row gets the key", async () => {
    const d = await createDevice("Sendiri");
    const gz = await gzip(FRAGMENTS_HTML);
    const id = await postScan(d, { evidenceFragmentsBase64: b64(gz) });
    await until(async () => (await archived(id))?.fragments_key != null);
    expect(await archived(id)).toMatchObject({ fragments_key: fragmentsKey(id), fragments_bytes: gz.length });
    const object = await env.REPLICA_ARCHIVE.get(fragmentsKey(id));
    expect(new Uint8Array(await object!.arrayBuffer())).toEqual(gz);
    expect(object!.key).not.toContain(d.deviceId);
  });

  it("a scan without fragments has an archive row without a key", async () => {
    const d = await createDevice("Sendiri");
    const id = await postScan(d);
    expect(await archived(id)).toMatchObject({ fragments_key: null, fragments_bytes: null });
    expect((await archived(id))!.owner_ref).toMatch(/^[0-9a-f]{16}$/);
  });

  it("not gzip → dropped, the scan is still stored", async () => {
    const d = await createDevice("Sendiri");
    const id = await postScan(d, { evidenceFragmentsBase64: b64(new TextEncoder().encode(FRAGMENTS_HTML)) });
    await droppedFor("not_gzip");
    expect((await archived(id))!.fragments_key).toBeNull();
    expect(await env.REPLICA_ARCHIVE.head(fragmentsKey(id))).toBeNull();
  });

  it("over 3 MB inflated → too_large", async () => {
    const d = await createDevice("Sendiri");
    await postScan(d, { evidenceFragmentsBase64: await gzipBase64(new Uint8Array(3_145_729)) });
    await droppedFor("too_large");
  });

  it("a body with a full replica and full fragments fits the 1 MiB limit", async () => {
    expect(MAX_SCAN_BYTES).toBe(1_048_576);
    const d = await createDevice("Sendiri");
    const filler = "A".repeat(409_600);
    const res = await call("/scans", {
      method: "POST", token: d.token, json: scanBody({ pageReplicaBase64: filler, evidenceFragmentsBase64: filler }),
    });
    expect(res.status).toBe(201);
  });

  it("quota full → dropped with the reason, no object", async () => {
    const d = await createDevice("Sendiri");
    const id = await postScan(d);
    await attachFragments(sql, env as unknown as Env, { id, ownerId: d.deviceId }, await gzipBase64(FRAGMENTS_HTML), {
      ...FRAGMENT_QUOTA, owner: 0,
    });
    await droppedFor("quota_owner");
    expect(await env.REPLICA_ARCHIVE.head(fragmentsKey(id))).toBeNull();
  });

  it("the kill-switch stops it", async () => {
    const d = await createDevice("Sendiri");
    const id = await postScan(d);
    await attachFragments(sql, { ...(env as unknown as Env), REPLICAS_ENABLED: "false" }, { id, ownerId: d.deviceId }, await gzipBase64(FRAGMENTS_HTML));
    await droppedFor("disabled");
  });
});

describe("favicon copy (ADM-07 K7)", () => {
  it("copies once per domain; a later copy never overwrites", async () => {
    const e = env as unknown as Env;
    await archiveFavicon(e, "ikon.test", Uint8Array.of(1, 2, 3), "image/png");
    await archiveFavicon(e, "ikon.test", Uint8Array.of(9, 9), "image/png");
    const object = await env.REPLICA_ARCHIVE.get(faviconKey("ikon.test"));
    expect(new Uint8Array(await object!.arrayBuffer())).toEqual(Uint8Array.of(1, 2, 3));
  });
});

describe("DELETE /devices/me and the archive (ADM-07 K11, K12)", () => {
  it("strips the rows, tombstones fragments of domains without scam evidence, keeps those of scam domains", async () => {
    const d = await createDevice("Sendiri");
    const plain = await postScan(d, { evidenceFragmentsBase64: await gzipBase64(FRAGMENTS_HTML) });
    await admin`insert into blocklist_entries (domain, approved_at, approved_by) values ('penipu-arsip.test', now(), 'qa')`;
    const scam = await postScan(d, {
      domain: "penipu-arsip.test", url: "https://penipu-arsip.test/masuk", evidenceFragmentsBase64: await gzipBase64(FRAGMENTS_HTML),
    });
    await until(async () => (await archived(plain))?.fragments_key != null && (await archived(scam))?.fragments_key != null);

    expect((await call("/devices/me", { method: "DELETE", token: d.token })).status).toBe(200);
    expect(await archived(plain)).toMatchObject({ owner_ref: null, fragments_key: null });
    expect(await archived(scam)).toMatchObject({ owner_ref: null, fragments_key: fragmentsKey(scam) });

    // The cron removes the tombstoned object once it is 10 minutes old; the scam domain's stays.
    expect(await dueTombstones(sql, 10, "archive")).toEqual([]);
    await admin`update storage_tombstones set created_at = now() - interval '11 minutes' where path = ${fragmentsKey(plain)}`;
    expect(await dueTombstones(sql, 10, "supabase")).not.toContain(fragmentsKey(plain));
    expect(await dueTombstones(sql, 10, "r2")).not.toContain(fragmentsKey(plain));
    await runRetention(sql, env as unknown as Env);
    expect(await env.REPLICA_ARCHIVE.head(fragmentsKey(plain))).toBeNull();
    expect(await env.REPLICA_ARCHIVE.head(fragmentsKey(scam))).not.toBeNull();
    expect((await sql`select 1 from storage_tombstones where path = ${fragmentsKey(plain)}`).length).toBe(0);
  });
});
