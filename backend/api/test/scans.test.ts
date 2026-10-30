import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import activityFamily from "../../../contracts/fixtures/activity-family.json";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import markedSafe from "../../../contracts/fixtures/blocked-marked-safe.json";
import verifiedScam from "../../../contracts/fixtures/blocked-verified-scam.json";
import warning41 from "../../../contracts/fixtures/warning-41.json";
import warning63 from "../../../contracts/fixtures/warning-63.json";
import { clearScreenshotPath } from "../src/db/repo/scans";
import { sha256 } from "../src/http/crypto";
import { b64, jpeg, png } from "./helpers/images";
import { resetDb, testSql } from "./helpers/resetDb";
import { expectScanResult } from "./helpers/schema";
import { call, createDevice, type Created } from "./helpers/seed";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
beforeEach(() => resetDb(sql));

type Fixture = {
  id: string; url: string; domain: string; pageTitle: string; faviconUrl: string | null; score: number;
  status: string; signals: unknown[]; screenshotUrl: string | null; ownerDeviceId: string; ownerName: string;
  detectedAt: string; verdict: unknown;
};
type Item = Record<string, unknown> & { id: string; ownerDeviceId: string; screenshotUrl: string | null };
const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

/** What the extension sends (ios/ShooExtension/Resources/report.js scanBody + background.js owner fields). */
function extensionBody(f: Fixture | typeof blocked92, extra: Record<string, unknown> = {}) {
  return {
    url: f.url,
    domain: f.domain,
    pageTitle: f.pageTitle,
    faviconUrl: f.faviconUrl,
    score: f.score,
    status: f.status,
    signals: f.signals,
    detectedAt: f.detectedAt,
    ownerDeviceId: "dev_someone_else",
    ownerName: "Spoofed",
    ...extra,
  };
}
const post = (d: Created, json: unknown) => call("/scans", { method: "POST", token: d.token, json });
const postOk = async (d: Created, json: unknown) => {
  const res = await post(d, json);
  expect(res.status, await res.clone().text()).toBe(201);
  return ((await res.json()) as { id: string }).id;
};
const list = async (d: Created, q = "") => {
  const res = await call(`/scans${q}`, { token: d.token });
  return { res, body: (await res.json()) as { items: Item[]; nextCursor: string | null } };
};
const pathOf = async (id: string) =>
  ((await sql`select screenshot_path from scans where id = ${id}`)[0]!.screenshot_path as string | null) ?? null;
const storageHas = async (path: string) => {
  const res = await fetch(`${env.SUPABASE_URL}/storage/v1/object/info/screenshots/${path}`, {
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY!, authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
  });
  return res.ok;
};
const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};

describe("POST /scans", () => {
  it("accepts the extension body; owner comes from the token, not the body", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(warning63));
    expect(id).toMatch(/^[0-9a-f-]{36}$/);
    const [row] = await sql`select owner_id, domain, score, status, page_title, signals from scans where id = ${id}`;
    expect(row).toMatchObject({ owner_id: p.deviceId, domain: "bansos-kemensos.site", score: 63, status: "warning" });
    expect(row!.signals).toEqual(warning63.signals);
  });

  it("guardians can post their own scans too", async () => {
    const g = await createDevice("G", "guardian");
    await postOk(g, extensionBody(blocked92));
  });

  it("subdomain of the registrable domain → 201; other domain → 422", async () => {
    const p = await createDevice("Mom");
    await postOk(p, extensionBody(blocked92, { url: "https://login.bca-verifikasi.site/x" }));
    for (const domain of ["other.site", "verifikasi.site.evil", "Bca-Verifikasi.site", "www.bca-verifikasi.site"]) {
      const res = await post(p, extensionBody(blocked92, { url: "https://login.bca-verifikasi.site/x", domain }));
      expect(res.status, domain).toBe(422);
    }
    // A host that only ends with the domain string is not a subdomain.
    const res = await post(p, extensionBody(blocked92, { url: "https://evilbca-verifikasi.site/" }));
    expect(res.status).toBe(422);
  });

  it.each([
    ["score below 30", { score: 29, status: "warning" }],
    ["status inconsistent with score", { score: 85, status: "warning" }],
    ["blocked under 80", { score: 79, status: "blocked" }],
    ["non-http url", { url: "javascript:alert(1)" }],
    ["21 signals", { signals: Array.from({ length: 21 }, () => blocked92.signals[0]) }],
    ["signal without labelSimple", { signals: [{ id: "x", layer: 1, weight: 5, label: { en: "a", id: "b" } }] }],
    ["signal label missing id", { signals: [{ ...blocked92.signals[0]!, label: { en: "a" } }] }],
    ["layer 6", { signals: [{ ...blocked92.signals[0]!, layer: 6 }] }],
    ["detectedAt far future", { detectedAt: new Date(Date.now() + 3_600_000).toISOString() }],
    ["detectedAt not ISO", { detectedAt: "yesterday" }],
  ])("422 invalid_body: %s", async (_name, extra) => {
    const p = await createDevice("Mom");
    const res = await post(p, extensionBody(blocked92, extra));
    expect(res.status).toBe(422);
    expect(await errorCode(res)).toBe("invalid_body");
  });

  it("pageTitle may be missing; a non-http faviconUrl is stored as null", async () => {
    const p = await createDevice("Mom");
    const body = extensionBody(warning41, { faviconUrl: "data:image/png;base64,AAAA" });
    delete (body as Record<string, unknown>).pageTitle;
    const id = await postOk(p, body);
    const [row] = await sql`select page_title, favicon_url from scans where id = ${id}`;
    expect(row).toEqual({ page_title: null, favicon_url: null });
  });

  it.each([["NUL", "\u0000"], ["bidi", "\u202E"], ["newline", "\n"]])("url with %s → 422", async (_, ch) => {
    const p = await createDevice("Mom");
    const res = await post(p, extensionBody(blocked92, { url: `${blocked92.url}${ch}x` }));
    expect(res.status).toBe(422);
  });

  it("faviconUrl with control or bidi characters is stored as null; screenshotBase64 null is accepted", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(warning41, { faviconUrl: "https://a.example/\u0000.ico", screenshotBase64: null }));
    const id2 = await postOk(p, extensionBody(warning41, { faviconUrl: "https://a.example/\u202E.ico" }));
    const rows = await sql`select favicon_url from scans where id in (${id}, ${id2})`;
    expect(rows.map((r) => r.favicon_url)).toEqual([null, null]);
  });

  it("signal ids follow the contract (any string), not a stricter pattern", async () => {
    const p = await createDevice("Mom");
    const signals = [{ ...(blocked92.signals[0] as object), id: "Lookalike-Domain" }];
    await postOk(p, extensionBody(blocked92, { signals }));
  });

  it("POST /scans takes up to 512 KB (EX-07 page replica); 413 above it", async () => {
    const p = await createDevice("Mom");
    // 300 KB passed the old 256 KB limit only with a replica-sized body; the replica itself is checked later.
    expect((await post(p, extensionBody(blocked92, { pageReplicaBase64: "A".repeat(300 * 1024) }))).status).toBe(201);
    const over = await post(p, extensionBody(blocked92, { pageReplicaBase64: "A".repeat(512 * 1024) }));
    expect(over.status).toBe(413);
    expect(await errorCode(over)).toBe("too_large");
  });

  it("the 512 KB limit is POST /scans exactly: /scans/, /scans/{id} and other routes stay at 256 KB", async () => {
    const p = await createDevice("Mom");
    const big = JSON.stringify(extensionBody(blocked92, { pageReplicaBase64: "A".repeat(300 * 1024) }));
    const headers = { "content-type": "application/json" };
    for (const [method, path] of [
      ["POST", "/scans/"],
      ["POST", `/scans/${crypto.randomUUID()}`],
      ["PATCH", "/scans"],
      ["POST", "/verdicts"],
    ] as const) {
      const res = await call(path, { method, token: p.token, headers, body: big });
      expect(res.status, `${method} ${path}`).toBe(413);
    }
    // Declared length alone, before auth: GET /replicas with a 300 KB content-length.
    const res = await call(`/replicas/${crypto.randomUUID()}`, { headers: { "content-length": String(300 * 1024) } });
    expect(res.status).toBe(413);
  });

  it("rate limits 120 per hour per device", async () => {
    const p = await createDevice("Mom");
    const hash = await keyHash(`scans_create:${p.deviceId}`);
    await sql`insert into rate_limit_hits (bucket, key_hash) select 'scans_create', ${hash} from generate_series(1, 120)`;
    const res = await post(p, extensionBody(blocked92));
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("rate_limited");
  });

  it("401 without token", async () => {
    expect((await call("/scans", { method: "POST", json: extensionBody(blocked92) })).status).toBe(401);
  });
});

describe("POST /scans screenshot", () => {
  it("stores a valid JPEG at <owner>/<scan>.jpg in the private bucket", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(800, 600, 1000)) }));
    const path = await pathOf(id);
    expect(path).toBe(`${p.deviceId}/${id}.jpg`);
    expect(await storageHas(path!)).toBe(true);
  });

  it("stores a PNG as .png", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(png(390, 844)) }));
    expect(await pathOf(id)).toBe(`${p.deviceId}/${id}.png`);
  });

  it.each([
    ["over 150 KB", () => b64(jpeg(800, 600, 150 * 1024))],
    ["not an image", () => b64(new TextEncoder().encode("<html>not an image</html>"))],
    ["data: prefix", () => `data:image/jpeg;base64,${b64(jpeg(10, 10))}`],
    ["broken base64", () => "!!!not-base64!!!"],
    ["longest side over 1280 px", () => b64(jpeg(1281, 400))],
    ["PNG over 1280 px", () => b64(png(400, 2000))],
  ])("drops the screenshot (%s) and still stores the scan", async (_name, shot) => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(blocked92, { screenshotBase64: shot() }));
    expect(await pathOf(id)).toBeNull();
  });

  it("dedupe: same owner + domain within 24 h reuses the first screenshot", async () => {
    const p = await createDevice("Mom");
    const first = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(100, 100)) }));
    const second = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(200, 200)) }));
    expect(await pathOf(second)).toBe(await pathOf(first));
    expect(await storageHas(`${p.deviceId}/${second}.jpg`)).toBe(false);

    // Older than 24 h → a new upload.
    await sql`update scans set created_at = now() - interval '25 hours' where id in (${first}, ${second})`;
    const third = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(100, 100)) }));
    expect(await pathOf(third)).toBe(`${p.deviceId}/${third}.jpg`);
  });

  it("a failed upload clears the path on every scan that reused it (dedupe)", async () => {
    const p = await createDevice("Mom");
    const a = await postOk(p, extensionBody(blocked92));
    const b = await postOk(p, extensionBody(blocked92));
    const path = `${p.deviceId}/${a}.jpg`;
    await sql`update scans set screenshot_path = ${path} where id in (${a}, ${b})`;
    await clearScreenshotPath(sql, p.deviceId, path);
    expect([await pathOf(a), await pathOf(b)]).toEqual([null, null]);
  });

  it("quota holds under parallel uploads", async () => {
    const p = await createDevice("Mom");
    // Original uploads: the path names the scan's own id (reuses do not count, D-alief-B12).
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, screenshot_path)
      select 'seed' || g, ${p.deviceId}, 'https://d' || g || '.example/', 'd' || g || '.example', 85, 'blocked', now(),
             ${p.deviceId} || '/seed' || g || '.jpg'
      from generate_series(1, 48) g`;
    const ids = await Promise.all(
      Array.from({ length: 6 }, (_, i) =>
        postOk(p, extensionBody(blocked92, {
          url: `https://p${i}.example/`, domain: `p${i}.example`, screenshotBase64: b64(jpeg(100, 100)),
        })),
      ),
    );
    const paths = await Promise.all(ids.map(pathOf));
    expect(paths.filter(Boolean)).toHaveLength(2);
  });

  it("control and bidi characters are stripped from page text", async () => {
    const p = await createDevice("Mom");
    const sig = { ...blocked92.signals[0]!, evidence: "pin\u202E\u0007", label: { en: "A\u202Eb", id: "c" } };
    const id = await postOk(p, extensionBody(blocked92, { pageTitle: "Klik\u202EBCA\u0000\u0007 ", signals: [sig] }));
    const [row] = await sql`select page_title, signals from scans where id = ${id}`;
    expect(row!.page_title).toBe("KlikBCA");
    expect(row!.signals[0].evidence).toBe("pin");
    expect(row!.signals[0].label.en).toBe("Ab");
  });

  it("quota: at most 50 uploads per owner per 24 h", async () => {
    const p = await createDevice("Mom");
    // Original uploads: the path names the scan's own id (reuses do not count, D-alief-B12).
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, screenshot_path)
      select 'seed' || g, ${p.deviceId}, 'https://d' || g || '.example/', 'd' || g || '.example', 85, 'blocked', now(),
             ${p.deviceId} || '/seed' || g || '.jpg'
      from generate_series(1, 50) g`;
    const id = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(100, 100)) }));
    expect(await pathOf(id)).toBeNull();
  });
});

describe("GET /scans", () => {
  it("owner=me (default): newest first, schema-valid, screenshotUrl null in lists", async () => {
    const p = await createDevice("Mom");
    await postOk(p, extensionBody(warning41));
    await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(100, 100)) }));
    await postOk(p, extensionBody(warning63));
    const { res, body } = await list(p);
    expect(res.status).toBe(200);
    expect(body.items.map((i) => i.domain)).toEqual(["bca-verifikasi.site", "bansos-kemensos.site", "promo-undian-shopee.click"]);
    expect(body.nextCursor).toBeNull();
    for (const item of body.items) {
      expectScanResult(item);
      expect(item.screenshotUrl).toBeNull();
      expect(item.ownerDeviceId).toBe(p.deviceId);
      expect(item.ownerName).toBe("Mom");
      expect(item.verdict).toBeNull();
    }
    expect((await list(p, "?owner=me")).body).toEqual(body);
  });

  it("status filter and cursor paging without gaps or repeats", async () => {
    const p = await createDevice("Mom");
    for (let i = 0; i < 5; i++) {
      const at = new Date(Date.UTC(2026, 9, 21, 4, 0, i)).toISOString();
      await postOk(p, extensionBody(blocked92, { detectedAt: at }));
      await postOk(p, extensionBody(warning41, { detectedAt: at }));
    }
    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const { res, body } = await list(p, `?status=blocked&limit=2${cursor ? `&cursor=${cursor}` : ""}`);
      expect(res.status).toBe(200);
      expect(body.items.length).toBeLessThanOrEqual(2);
      for (const item of body.items) expect(item.status).toBe("blocked");
      seen.push(...body.items.map((i) => i.id));
      cursor = body.nextCursor;
    } while (cursor);
    expect(seen).toHaveLength(5);
    expect(new Set(seen).size).toBe(5);
  });

  it("paging is stable when several scans share the same detectedAt", async () => {
    const p = await createDevice("Mom");
    const at = "2026-10-21T04:00:00.123Z";
    for (let i = 0; i < 5; i++) await postOk(p, extensionBody(blocked92, { detectedAt: at }));
    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const { body } = await list(p, `?limit=2${cursor ? `&cursor=${cursor}` : ""}`);
      seen.push(...body.items.map((i) => i.id));
      cursor = body.nextCursor;
    } while (cursor);
    expect(new Set(seen).size).toBe(5);
    expect(seen).toHaveLength(5);
  });

  const cursorOf = (s: string) => btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  it.each([
    "?limit=0", "?limit=51", "?limit=x", "?status=normal", "?cursor=bad", "?cursor=" + btoa("x|y"),
    "?cursor=" + cursorOf("2026-10-21T04:00:00.000000Z|00000000-0000-4000-8000-000000000000|junk"),
  ])(
    "422 for %s",
    async (q) => {
      const p = await createDevice("Mom");
      expect((await list(p, q)).res.status).toBe(422);
    },
  );

  it("owner=family = guardian's own scans + linked members; protected → 403", async () => {
    const g = await createDevice("Adhella", "guardian");
    const mom = await createDevice("Mom");
    const stranger = await createDevice("Stranger");
    await connect(g, mom);
    await postOk(g, extensionBody(warning63));
    await postOk(mom, extensionBody(blocked92));
    await postOk(stranger, extensionBody(warning41));

    const { body } = await list(g, "?owner=family");
    expect(body.items.map((i) => i.ownerName).sort()).toEqual(["Adhella", "Mom"]);
    expect((await list(mom, "?owner=family")).res.status).toBe(403);
  });

  it("owner={deviceId}: own id or a linked member; anyone else → 404 (IDOR)", async () => {
    const gA = await createDevice("A", "guardian");
    const gB = await createDevice("B", "guardian");
    const momA = await createDevice("MomA");
    const momB = await createDevice("MomB");
    await connect(gA, momA);
    await connect(gB, momB);
    await postOk(momB, extensionBody(blocked92));

    expect((await list(gA, `?owner=${momA.deviceId}`)).res.status).toBe(200);
    expect((await list(gA, `?owner=${gA.deviceId}`)).res.status).toBe(200);
    expect((await list(gA, `?owner=${momB.deviceId}`)).res.status).toBe(404);
    expect((await list(gA, `?owner=${gB.deviceId}`)).res.status).toBe(404);
    expect((await list(momA, `?owner=${gA.deviceId}`)).res.status).toBe(404);
    expect((await list(momA, `?owner=${momA.deviceId}`)).res.status).toBe(200);
  });

  it("after disconnect the guardian loses access at once (T12)", async () => {
    const g = await createDevice("G", "guardian");
    const mom = await createDevice("Mom");
    await connect(g, mom);
    const id = await postOk(mom, extensionBody(blocked92));
    expect((await call(`/scans/${id}`, { token: g.token })).status).toBe(200);

    await call(`/family/members/${mom.deviceId}`, { method: "DELETE", token: g.token });
    expect((await call(`/scans/${id}`, { token: g.token })).status).toBe(404);
    expect((await list(g, `?owner=${mom.deviceId}`)).res.status).toBe(404);
    expect((await list(g, "?owner=family")).body.items).toEqual([]);
  });

  it("verdict only on blocked scans; warning scans keep verdict null", async () => {
    const g = await createDevice("Adhella", "guardian");
    const mom = await createDevice("Mom");
    await connect(g, mom);
    await postOk(mom, extensionBody(blocked92));
    await postOk(mom, extensionBody(warning41, { domain: "bca-verifikasi.site", url: "https://bca-verifikasi.site/promo" }));
    await sql`insert into verdicts (owner_id, domain, value, by_device_id, by_name, decided_at)
      values (${mom.deviceId}, 'bca-verifikasi.site', 'not_safe', ${g.deviceId}, 'Adhella', '2026-10-21T04:06:00Z')`;
    const { body } = await list(g, `?owner=${mom.deviceId}`);
    const blocked = body.items.find((i) => i.status === "blocked")!;
    const warning = body.items.find((i) => i.status === "warning")!;
    expect(blocked.verdict).toEqual({ value: "not_safe", byDeviceId: g.deviceId, byName: "Adhella", decidedAt: "2026-10-21T04:06:00.000Z" });
    expect(warning.verdict).toBeNull();
    expectScanResult(blocked);
  });

  it("matches contracts/fixtures/activity-family.json for the seeded family", async () => {
    // Fixture world: dev_me (guardian Adhella), dev_mom, dev_dad (protected).
    const token = (id: string) => `shoo_fixture_${id}_token_padding`;
    for (const [id, name, mode] of [["dev_me", "Adhella", "guardian"], ["dev_mom", "Mom", "protected"], ["dev_dad", "Dad", "protected"]] as const) {
      await sql`insert into devices (id, name, mode, avatar_id, token_hash)
        values (${id}, ${name}, ${mode}, 'avatar_01', ${await sha256(token(id))})`;
    }
    await sql`insert into family_links (protected_id, guardian_id) values ('dev_mom', 'dev_me'), ('dev_dad', 'dev_me')`;
    const fixtures = [blocked92, warning63, warning41, verifiedScam, markedSafe] as unknown as Fixture[];
    for (const f of fixtures) {
      await sql`insert into scans (id, owner_id, url, domain, page_title, favicon_url, score, status, signals, detected_at)
        values (${f.id}, ${f.ownerDeviceId}, ${f.url}, ${f.domain}, ${f.pageTitle}, ${f.faviconUrl}, ${f.score},
                ${f.status}, ${sql.json(f.signals as never)}, ${f.detectedAt})`;
      const v = f.verdict as { value: string; byDeviceId: string; byName: string; decidedAt: string } | null;
      if (v) {
        await sql`insert into verdicts (owner_id, domain, value, scan_id, by_device_id, by_name, decided_at)
          values (${f.ownerDeviceId}, ${f.domain}, ${v.value}, ${f.id}, ${v.byDeviceId}, ${v.byName}, ${v.decidedAt})`;
      }
    }

    const res = await call("/scans?owner=family", { token: token("dev_me") });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { items: Item[]; nextCursor: string | null };
    expect(Object.keys(body).sort()).toEqual(["items", "nextCursor"]);
    expect(body.nextCursor).toBe(activityFamily.nextCursor);

    // Times are compared as instants; lists never carry a screenshot URL (D-alief-04). EX-07: every
    // item has pageReplicaUrl null (contracts/api.md); the fixture predates the key, so it is checked
    // here and left out of the comparison.
    for (const item of body.items) expect(Object.hasOwn(item, "pageReplicaUrl") && item.pageReplicaUrl === null).toBe(true);
    const normal = (x: unknown) =>
      JSON.parse(JSON.stringify(x), (k, v) =>
        k === "pageReplicaUrl" ? undefined
          : typeof v === "string" && /At$/.test(k) ? new Date(v).toISOString() : k === "screenshotUrl" ? null : v,
      );
    expect(normal(body.items)).toEqual(normal(fixtures));
    for (const item of body.items) expectScanResult(item);
  });
});

describe("GET /scans/{id}", () => {
  it("owner gets a 1-hour Worker URL for the screenshot (D-alief-B08)", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(320, 240, 500)) }));
    const res = await call(`/scans/${id}`, { token: p.token });
    expect(res.status).toBe(200);
    const item = (await res.json()) as Item;
    expectScanResult(item);
    expect(item.id).toBe(id);
    const url = new URL(item.screenshotUrl!);
    // Pinned base URL, never the request Host (D-alief-B08).
    expect(`${url.origin}${url.pathname}`).toBe(`${env.INVITE_BASE_URL}/screenshots/${id}`);
    expect(url.searchParams.get("v")).toBe(p.deviceId);
    const ttl = Number(url.searchParams.get("exp")) - Date.now() / 1000;
    expect(ttl).toBeGreaterThan(3590);
    expect(ttl).toBeLessThanOrEqual(3600);
    expect(url.searchParams.get("sig")).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it("no screenshot → screenshotUrl null", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(warning41));
    const item = (await (await call(`/scans/${id}`, { token: p.token })).json()) as Item;
    expect(item.screenshotUrl).toBeNull();
    expect(item.pageTitle).toBe(warning41.pageTitle);
  });

  it("IDOR: other guardian, protected reading its guardian's scan, unknown id → 404", async () => {
    const gA = await createDevice("A", "guardian");
    const gB = await createDevice("B", "guardian");
    const mom = await createDevice("Mom");
    await connect(gA, mom);
    const momScan = await postOk(mom, extensionBody(blocked92));
    const guardianScan = await postOk(gA, extensionBody(warning63));

    expect((await call(`/scans/${momScan}`, { token: gA.token })).status).toBe(200);
    expect((await call(`/scans/${momScan}`, { token: gB.token })).status).toBe(404);
    expect((await call(`/scans/${guardianScan}`, { token: mom.token })).status).toBe(404);
    expect((await call(`/scans/00000000-0000-4000-8000-000000000000`, { token: gA.token })).status).toBe(404);
    expect((await call(`/scans/not-a-uuid`, { token: gA.token })).status).toBe(404);
  });
});
