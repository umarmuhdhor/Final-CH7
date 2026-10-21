import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { screenshotLink } from "../src/services/screenshotLinks";
import { b64, jpeg, png } from "./helpers/images";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
beforeEach(() => resetDb(sql));

const body = (extra: Record<string, unknown> = {}) =>
  ({ ...blocked92, id: undefined, verdict: undefined, screenshotUrl: undefined, ...extra });
const postShot = async (d: Created, image = jpeg(320, 240, 500), domain = blocked92.domain) => {
  const res = await call("/scans", {
    method: "POST", token: d.token,
    json: body({ domain, url: `https://${domain}/login`, screenshotBase64: b64(image) }),
  });
  expect(res.status).toBe(201);
  return ((await res.json()) as { id: string }).id;
};
/** The screenshotUrl from GET /scans/{id}, as path + query for call(). */
const linkFor = async (viewer: Created, id: string) => {
  const res = await call(`/scans/${id}`, { token: viewer.token });
  expect(res.status).toBe(200);
  const u = new URL(((await res.json()) as { screenshotUrl: string }).screenshotUrl);
  return `${u.pathname}${u.search}`;
};
const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};
const get = (link: string) => call(link);

describe("GET /screenshots/{scanId} (D-alief-B08)", () => {
  it("serves the image with no-store, no auth header needed", async () => {
    const p = await createDevice("Mom");
    const shot = jpeg(320, 240, 500);
    const id = await postShot(p, shot);
    const res = await get(await linkFor(p, id));
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/jpeg");
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(shot);
  });

  it("PNG is served as image/png", async () => {
    const p = await createDevice("Mom");
    const id = await postShot(p, png(200, 100));
    const res = await get(await linkFor(p, id));
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/png");
  });

  it("guardian of the owner can open it; after disconnect the same link → 404", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await connect(g, p);
    const id = await postShot(p);
    const link = await linkFor(g, id);
    expect((await get(link)).status).toBe(200);

    expect((await call("/family/guardian", { method: "DELETE", token: p.token })).status).toBe(200);
    const res = await get(link);
    expect(res.status).toBe(404);
    expect(res.headers.get("cache-control")).toBe("private, no-store");
  });

  it("after DELETE /devices/me the owner's link → 404 at once", async () => {
    const p = await createDevice("Mom");
    const id = await postShot(p);
    const link = await linkFor(p, id);
    expect((await get(link)).status).toBe(200);
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect((await get(link)).status).toBe(404);
  });

  it("a deleted scan (retention) → 404 even with a valid link", async () => {
    const p = await createDevice("Mom");
    const id = await postShot(p);
    const link = await linkFor(p, id);
    await sql`delete from scans where id = ${id}`;
    expect((await get(link)).status).toBe(404);
  });

  it("bad, tampered or missing signature → 404", async () => {
    const p = await createDevice("Mom");
    const id = await postShot(p);
    const link = new URL(`http://x${await linkFor(p, id)}`);
    const sig = link.searchParams.get("sig")!;
    const variants: Array<(u: URL) => void> = [
      (u) => u.searchParams.set("sig", `${sig.slice(0, -1)}${sig.endsWith("A") ? "B" : "A"}`),
      (u) => u.searchParams.delete("sig"),
      (u) => u.searchParams.set("sig", "x"),
      (u) => u.searchParams.set("exp", String(Number(u.searchParams.get("exp")) + 60)),
      (u) => u.searchParams.set("v", "dev_someone_else"),
      (u) => u.searchParams.delete("v"),
    ];
    for (const change of variants) {
      const u = new URL(link);
      change(u);
      expect((await get(`${u.pathname}${u.search}`)).status, u.search).toBe(404);
    }
  });

  it("a non-canonical encoding of the right signature → 404", async () => {
    const p = await createDevice("Mom");
    const id = await postShot(p);
    const u = new URL(`http://x${await linkFor(p, id)}`);
    const sig = u.searchParams.get("sig")!;
    // The last of 43 base64url characters carries 2 unused bits: flip one, same bytes.
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    u.searchParams.set("sig", sig.slice(0, -1) + alphabet[alphabet.indexOf(sig.at(-1)!) ^ 1]);
    expect((await get(`${u.pathname}${u.search}`)).status).toBe(404);
  });

  it("rate limits 120 per minute per viewer", async () => {
    const p = await createDevice("Mom");
    const id = await postShot(p);
    const link = await linkFor(p, id);
    const hash = await keyHash(`screenshots_view:${p.deviceId}`);
    await sql`insert into rate_limit_hits (bucket, key_hash) select 'screenshots_view', ${hash} from generate_series(1, 120)`;
    const res = await get(link);
    expect(res.status).toBe(429);
    expect(res.headers.get("cache-control")).toBe("private, no-store");
  });

  it("expired link → 404", async () => {
    const p = await createDevice("Mom");
    const id = await postShot(p);
    const old = await screenshotLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, p.deviceId, Date.now() / 1000 - 3601);
    const u = new URL(old);
    expect((await get(`${u.pathname}${u.search}`)).status).toBe(404);
  });

  it("a link for one scan cannot open another scan, even of the same viewer", async () => {
    const p = await createDevice("Mom");
    const a = await postShot(p, jpeg(320, 240, 500), "a-scam.example");
    const b = await postShot(p, jpeg(320, 240, 600), "b-scam.example");
    const link = new URL(`http://x${await linkFor(p, a)}`);
    expect((await get(`/screenshots/${b}${link.search}`)).status).toBe(404);
  });

  it("a viewer who is neither owner nor guardian → 404 even with a correctly signed link", async () => {
    const p = await createDevice("Mom");
    const stranger = await createDevice("X", "guardian");
    const id = await postShot(p);
    const forged = new URL(await screenshotLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, stranger.deviceId, Date.now() / 1000));
    expect((await get(`${forged.pathname}${forged.search}`)).status).toBe(404);
  });

  it("scan without a screenshot, unknown id, bad id → 404", async () => {
    const p = await createDevice("Mom");
    const res = await call("/scans", { method: "POST", token: p.token, json: body() });
    const { id } = (await res.json()) as { id: string };
    const signed = new URL(await screenshotLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, p.deviceId, Date.now() / 1000));
    expect((await get(`${signed.pathname}${signed.search}`)).status).toBe(404);
    expect((await get("/screenshots/00000000-0000-4000-8000-000000000000?v=a&exp=1&sig=x")).status).toBe(404);
    expect((await get("/screenshots/not-a-uuid")).status).toBe(404);
  });
});
