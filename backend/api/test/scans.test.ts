import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import activityFamily from "../../../contracts/fixtures/activity-family.json";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import markedSafe from "../../../contracts/fixtures/blocked-marked-safe.json";
import verifiedScam from "../../../contracts/fixtures/blocked-verified-scam.json";
import warning41 from "../../../contracts/fixtures/warning-41.json";
import warning63 from "../../../contracts/fixtures/warning-63.json";
import { clearScreenshotPath, ISO_MS, listScans, type ListQuery, type ScanRow } from "../src/db/repo/scans";
import { lockedUntilSql } from "../src/db/repo/verdictLock";
import { sha256 } from "../src/http/crypto";
import { b64, jpeg, png } from "./helpers/images";
import { resetDb, testSql } from "./helpers/resetDb";
import { seedScreenshot } from "./helpers/screenshots";
import { expectScanResult } from "./helpers/schema";
import { call, createDevice, type Created } from "./helpers/seed";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

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
/** Another site, so a scan gets its own Activity row. */
const site = (name: string) => ({ url: `https://${name}.example/`, domain: `${name}.example` });
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

  it("a host with a trailing dot (bca-verifikasi.site.) → 201, as GET /verdicts accepts it (BH-04)", async () => {
    const p = await createDevice("Mom");
    await postOk(p, extensionBody(blocked92, { url: "https://bca-verifikasi.site./login" }));
    await postOk(p, extensionBody(blocked92, { url: "https://login.bca-verifikasi.site./x" }));
    const res = await post(p, extensionBody(blocked92, { url: "https://evilbca-verifikasi.site./" }));
    expect(res.status).toBe(422);
  });

  it("signal layers follow the schema enum [1,2,3,4,6] (BH-18)", async () => {
    const p = await createDevice("Mom");
    await postOk(p, extensionBody(blocked92, { signals: [{ ...blocked92.signals[0]!, layer: 6 }] }));
  });

  it.each([
    ["score below 30", { score: 29, status: "warning" }],
    // Dashboard phase 05: without thresholdsVersion only the fence applies (scans-thresholds.test.ts).
    ["blocked under 50", { score: 45, status: "blocked" }],
    ["non-http url", { url: "javascript:alert(1)" }],
    ["21 signals", { signals: Array.from({ length: 21 }, () => blocked92.signals[0]) }],
    ["signal without labelSimple", { signals: [{ id: "x", layer: 1, weight: 5, label: { en: "a", id: "b" } }] }],
    ["signal label missing id", { signals: [{ ...blocked92.signals[0]!, label: { en: "a" } }] }],
    // Layer 5 is Guardian feedback and emits no Signal (scan-result.schema.json).
    ["layer 5", { signals: [{ ...blocked92.signals[0]!, layer: 5 }] }],
    ["layer 7", { signals: [{ ...blocked92.signals[0]!, layer: 7 }] }],
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
    const id2 = await postOk(p, extensionBody(warning63, { faviconUrl: "https://a.example/\u202E.ico" }));
    const rows = await sql`select favicon_url from scans where id in (${id}, ${id2})`;
    expect(rows.map((r) => r.favicon_url)).toEqual([null, null]);
  });

  it("signal ids follow the contract (any string), not a stricter pattern", async () => {
    const p = await createDevice("Mom");
    const signals = [{ ...(blocked92.signals[0] as object), id: "Lookalike-Domain" }];
    await postOk(p, extensionBody(blocked92, { signals }));
  });
});

describe("POST /scans notified (#377)", () => {
  const TOKEN = "a".repeat(64);
  const postBody = async (d: Created, json: unknown) => {
    const res = await post(d, json);
    expect(res.status, await res.clone().text()).toBe(201);
    return (await res.json()) as { id: string; notified?: { name: string } | null };
  };
  const withGuardian = async () => {
    const g = await createDevice("Adhella", "guardian");
    const p = await createDevice("Maria");
    await connect(g, p);
    expect((await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN } })).status).toBe(200);
    return { g, p };
  };

  it("names the Guardian whose push this scan queued", async () => {
    const { p } = await withGuardian();
    expect((await postBody(p, extensionBody(blocked92))).notified).toEqual({ name: "Adhella" });
  });

  it("null without a Guardian, for the Guardian's own scan, and once the Guardian is gone", async () => {
    const alone = await createDevice("Solo");
    expect((await postBody(alone, extensionBody(blocked92))).notified).toBeNull();
    const { g, p } = await withGuardian();
    expect((await postBody(g, extensionBody(blocked92))).notified).toBeNull();
    expect((await call("/devices/me", { method: "DELETE", token: g.token })).status).toBe(200);
    expect((await postBody(p, extensionBody(warning63))).notified).toBeNull();
  });

  it("null when the Guardian's push is off or the Guardian has no APNs token", async () => {
    const g = await createDevice("Adhella", "guardian");
    const p = await createDevice("Maria");
    await connect(g, p);
    expect((await postBody(p, extensionBody(blocked92))).notified).toBeNull();
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: TOKEN } });
    await sql`update devices set notify_family = false where id = ${g.deviceId}`;
    expect((await postBody(p, extensionBody(warning63))).notified).toBeNull();
  });

  it("null for a repeat visit that sends no push", async () => {
    const { p } = await withGuardian();
    await postBody(p, extensionBody(blocked92));
    expect((await postBody(p, extensionBody(blocked92))).notified).toBeNull();
  });

  it("null for another page of a site that already pushed (#241)", async () => {
    const { p } = await withGuardian();
    await postBody(p, extensionBody(blocked92));
    expect((await postBody(p, extensionBody(blocked92, { url: "https://bca-verifikasi.site/otp" }))).notified).toBeNull();
  });
});

describe("POST /scans: one Activity row per link (#241)", () => {
  const at = (minutes: number) => new Date(Date.parse("2026-11-03T04:00:00.000Z") + minutes * 60_000).toISOString();

  it("a repeat visit keeps the first row and moves its time to the newest visit", async () => {
    const p = await createDevice("Mom");
    const first = await postOk(p, extensionBody(blocked92, { detectedAt: at(0) }));
    for (const m of [1, 2, 3]) expect(await postOk(p, extensionBody(blocked92, { detectedAt: at(m) }))).toBe(first);
    const { body } = await list(p);
    expect(body.items.map((i) => i.id)).toEqual([first]);
    expect(body.items[0]!.detectedAt).toBe(at(3));
    // A late report of an older visit never moves the time back.
    await postOk(p, extensionBody(blocked92, { detectedAt: at(-5) }));
    expect((await list(p)).body.items[0]!.detectedAt).toBe(at(3));
  });

  it("the same link with another query or fragment is the same row; another page, a subdomain or another site gets its own", async () => {
    const p = await createDevice("Mom");
    const first = await postOk(p, extensionBody(blocked92));
    expect(await postOk(p, extensionBody(blocked92, { url: "https://bca-verifikasi.site/login?ref=sms#top" }))).toBe(first);
    expect(await postOk(p, extensionBody(blocked92, { url: "https://BCA-verifikasi.site:443/login" }))).toBe(first);
    const page = await postOk(p, extensionBody(blocked92, { url: "https://bca-verifikasi.site/otp" }));
    const sub = await postOk(p, extensionBody(blocked92, { url: "https://login.bca-verifikasi.site/login" }));
    const other = await postOk(p, extensionBody(warning63));
    expect(new Set([first, page, sub, other]).size).toBe(4);
    expect((await list(p)).body.items).toHaveLength(4);
  });

  it("each device keeps its own row for a site", async () => {
    const a = await createDevice("Mom");
    const b = await createDevice("Dad");
    expect(await postOk(a, extensionBody(blocked92))).not.toBe(await postOk(b, extensionBody(blocked92)));
  });

  it("a higher score replaces status, score and signals; a lower one leaves them", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(warning63));
    const blocked = { score: 90, status: "blocked", signals: blocked92.signals, url: "https://bansos-kemensos.site/cek?step=2" };
    expect(await postOk(p, extensionBody(warning63, blocked))).toBe(id);
    expect(await postOk(p, extensionBody(warning63, { score: 41 }))).toBe(id);
    const [row] = await sql`select url, score, status, signals from scans where id = ${id}`;
    expect(row).toMatchObject({ url: blocked.url, score: 90, status: "blocked" });
    expect(row!.signals).toEqual(blocked92.signals);
  });

  // B-02 (fase 28, K14). The admins lower blockAt (GET /config/public) while a warning row is open:
  // the same link at 75 was a warning, at 72 it is blocked now.
  const warning75 = { url: "https://hadiah.example/a", domain: "hadiah.example", score: 75, status: "warning" };
  const blocked72 = { ...warning75, score: 72, status: "blocked", signals: blocked92.signals };

  it("BUG B-02a: a block on a row without a verdict replaces its warning, even at a lower score", async () => {
    const g = await createDevice("Gita", "guardian");
    const p = await createDevice("Ibu");
    await connect(g, p);
    const id = await postOk(p, extensionBody(warning63, warning75));
    expect(await postOk(p, extensionBody(warning63, { ...blocked72, url: "https://hadiah.example/a?step=2" }))).toBe(id);
    const row = (await list(g, "?owner=family")).body.items[0]!;
    expect([row.status, row.score]).toEqual(["blocked", 72]);
    expect(row).toMatchObject({ url: "https://hadiah.example/a?step=2", signals: blocked92.signals });
    // A later warning never undoes the block, at a lower or a higher score (old thresholds).
    for (const score of [70, 80]) expect(await postOk(p, extensionBody(warning63, { ...warning75, score }))).toBe(id);
    const [after] = await sql`select status, score from scans where id = ${id}`;
    expect(after).toEqual({ status: "blocked", score: 72 });
  });

  it("BUG B-02a: a not_safe on another page of a shared host is no verdict for this row", async () => {
    const g = await createDevice("Gita", "guardian");
    const p = await createDevice("Ibu");
    await connect(g, p);
    const shared = { domain: "google.com", score: 75, status: "warning" };
    const other = await postOk(p, extensionBody(warning63, { ...shared, url: "https://sites.google.com/view/sekolah" }));
    expect((await call("/verdicts", { method: "POST", token: g.token, json: { scanId: other, value: "not_safe" } })).status).toBe(200);
    const id = await postOk(p, extensionBody(warning63, { ...shared, url: "https://sites.google.com/view/hadiah" }));
    await postOk(p, extensionBody(warning63, { ...shared, url: "https://sites.google.com/view/hadiah", score: 72, status: "blocked" }));
    const [row] = await sql`select status, score from scans where id = ${id}`;
    expect(row).toEqual({ status: "blocked", score: 72 });
  });

  // Guard until Q4 of fase 27 (27b) is answered: a row with a verdict keeps main's behaviour.
  it("a block at a lower score leaves a warning row that has a verdict as it was (until fase 27 Q4)", async () => {
    const g = await createDevice("Gita", "guardian");
    const p = await createDevice("Ibu");
    await connect(g, p);
    const id = await postOk(p, extensionBody(warning63, warning75));
    expect((await call("/verdicts", { method: "POST", token: g.token, json: { scanId: id, value: "safe" } })).status).toBe(200);
    expect(await postOk(p, extensionBody(warning63, blocked72))).toBe(id);
    const row = (await list(g, "?owner=family")).body.items[0]!;
    expect([row.status, row.score]).toEqual(["warning", 75]);
    expect(row.verdict).toMatchObject({ value: "safe" });
  });

  it("a not_safe on another link of the domain is a verdict for this row too: it stays as it was (until fase 27 Q4)", async () => {
    const g = await createDevice("Gita", "guardian");
    const p = await createDevice("Ibu");
    await connect(g, p);
    const other = await postOk(p, extensionBody(warning63, { ...warning75, url: "https://hadiah.example/b" }));
    expect((await call("/verdicts", { method: "POST", token: g.token, json: { scanId: other, value: "not_safe" } })).status).toBe(200);
    const id = await postOk(p, extensionBody(warning63, warning75));
    expect(await postOk(p, extensionBody(warning63, blocked72))).toBe(id);
    const [row] = await sql`select status, score from scans where id = ${id}`;
    expect(row).toEqual({ status: "warning", score: 75 });
  });

  it("parallel reports of one link still make one row", async () => {
    const p = await createDevice("Mom");
    const ids = await Promise.all(Array.from({ length: 5 }, () => postOk(p, extensionBody(blocked92))));
    expect(new Set(ids).size).toBe(1);
    expect((await sql`select count(*)::int as n from scans where owner_id = ${p.deviceId}`)[0]!.n).toBe(1);
  });

  it("every report still counts in the profile totals", async () => {
    const p = await createDevice("Mom");
    await postOk(p, extensionBody(blocked92));
    await postOk(p, extensionBody(blocked92));
    const [d] = await sql`select blocked_total from devices where id = ${p.deviceId}`;
    expect(d!.blocked_total).toBe(2);
  });

  it("POST /scans takes up to 1 MiB (EX-07 page replica + ADM-07 evidence fragments); 413 above it", async () => {
    const p = await createDevice("Mom");
    // 300 KB passed the old 256 KB limit only with a replica-sized body; the replica itself is checked later.
    expect((await post(p, extensionBody(blocked92, { pageReplicaBase64: "A".repeat(300 * 1024) }))).status).toBe(201);
    // 600 KB passed the old 512 KB limit only with a replica and fragments.
    expect((await post(p, extensionBody(blocked92, { pageReplicaBase64: "A".repeat(600 * 1024) }))).status).toBe(201);
    const over = await post(p, extensionBody(blocked92, { pageReplicaBase64: "A".repeat(1024 * 1024) }));
    expect(over.status).toBe(413);
    expect(await errorCode(over)).toBe("too_large");
  });

  it("the 1 MiB limit is POST /scans exactly: /scans/, /scans/{id} and other routes stay at 256 KB", async () => {
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

describe("POST /scans stores the URL in its normal form (B-04, A-09, A-03 backend half; fase 28 K12)", () => {
  // The extension sends origin + pathname from the WHATWG parser, so it never sends these forms. A crafted
  // client with a connected member's token can. The stored URL is new URL(url).href: the form GET /verdicts
  // reads, public.verdict_link() expects, and Foundation decodes in the app.
  const toko = (url: string, extra: Record<string, unknown> = {}) => extensionBody(blocked92, { url, domain: "toko.example", ...extra });
  const storedUrl = async (id: string) => (await sql`select url from scans where id = ${id}`)[0]!.url as string;
  /** RFC 3986 characters only: no space, backslash, raw non-ASCII or control character (Foundation's URL decodes it). */
  const RFC3986 = /^[A-Za-z0-9\-._~:/?#[\]@!$&'()*+,;=%]+$/;

  it.each([
    ["dot segment", "https://toko.example/x/../a", "https://toko.example/a"],
    ["empty port", "https://toko.example:/a", "https://toko.example/a"],
    ["unicode path", "https://toko.example/päth", "https://toko.example/p%C3%A4th"],
    ["backslash for slash", "https://toko.example\\path", "https://toko.example/path"],
    ["leading and trailing space", " https://toko.example/a ", "https://toko.example/a"],
  ])("%s → 201, stored and listed as the normal form", async (_name, url, normal) => {
    const g = await createDevice("Gita", "guardian");
    const p = await createDevice("Mom");
    await connect(g, p);
    const id = await postOk(p, toko(url));
    expect(await storedUrl(id)).toBe(normal);
    const listed = (await list(g, "?owner=family")).body.items[0]!.url as string;
    const members = (await (await call("/family/members", { token: g.token })).json()) as { members: { lastScan: { url: string } | null }[] };
    expect([listed, members.members[0]!.lastScan!.url]).toEqual([normal, normal]);
    expect(listed).toMatch(RFC3986);
  });

  it.each([
    ["dot segment", "https://toko.example/x/../a"],
    ["empty port", "https://toko.example:/a"],
  ])("%s is the same Activity row as the plain link", async (_name, url) => {
    const p = await createDevice("Mom");
    const first = await postOk(p, toko("https://toko.example/a"));
    expect(await postOk(p, toko(url))).toBe(first);
    expect(await postOk(p, toko(url))).toBe(first);
    expect((await list(p)).body.items).toHaveLength(1);
  });

  it.each([["tab inside", "https://toko.example/a\tb"], ["newline at the end", "https://toko.example/a\n"]])(
    "%s → 422 invalid_body (control characters are refused, not stripped)",
    async (_name, url) => {
      const p = await createDevice("Mom");
      const res = await post(p, toko(url));
      expect(res.status).toBe(422);
      expect(await errorCode(res)).toBe("invalid_body");
    },
  );

  it("an IPv6 host → 422 invalid_body (no registrable domain; public.verdict_link() has no IPv6 form)", async () => {
    const p = await createDevice("Mom");
    for (const [url, domain] of [["https://[2001:db8::1]/a", "toko.example"], ["http://[::1]/a", "toko.example"]] as const) {
      const res = await post(p, extensionBody(blocked92, { url, domain }));
      expect(res.status, url).toBe(422);
      expect(await errorCode(res)).toBe("invalid_body");
    }
  });

  it("a raw non-ASCII path ≤ 2048 characters that is > 2048 once encoded → 422 invalid_body; exactly 2048 encoded → 201", async () => {
    const p = await createDevice("Mom");
    const over = `https://toko.example/${"ä".repeat(400)}`; // 421 raw, 2421 encoded
    expect(over.length).toBeLessThanOrEqual(2048);
    const res = await post(p, toko(over));
    expect(res.status).toBe(422);
    expect(await errorCode(res)).toBe("invalid_body");
    expect((await sql`select count(*)::int as n from scans`)[0]!.n).toBe(0);
    const at = `https://toko.example/${"ä".repeat(337)}aaaaa`; // 363 raw, 2048 encoded
    const id = await postOk(p, toko(at));
    expect((await storedUrl(id)).length).toBe(2048);
  });
});

describe("POST /scans screenshotBase64 (ignored since fase 20a, K3 a)", () => {
  const ignoredLines = (spy: { mock: { calls: unknown[][] } }) =>
    spy.mock.calls.map((a) => a.map(String).join(" ")).filter((l) => l.includes("screenshot_ignored"));

  it("a valid screenshot → 201, nothing stored, one screenshot_ignored log line without id or domain", async () => {
    const log = vi.spyOn(console, "log");
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(800, 600, 1000)) }));
    expect(await pathOf(id)).toBeNull();
    expect(await storageHas(`${p.deviceId}/${id}.jpg`)).toBe(false);
    // No reservation either: a reserved upload always leaves a tombstone (D-alief-B12).
    expect(await sql`select path from storage_tombstones`).toHaveLength(0);
    const lines = ignoredLines(log);
    expect(lines).toHaveLength(1);
    expect(JSON.parse(lines[0]!)).toEqual({ event: "screenshot_ignored" });
    for (const leak of [id, p.deviceId, blocked92.domain]) expect(lines[0]).not.toContain(leak);
  });

  it.each([
    ["a number", 12345],
    ["an object", { image: "abc" }],
    ["an array", ["abc"]],
    ["true", true],
  ])("a non-string screenshotBase64 (%s) → 201, nothing stored", async (_name, shot) => {
    const log = vi.spyOn(console, "log");
    const p = await createDevice("Mom");
    const id = await postOk(p, extensionBody(blocked92, { screenshotBase64: shot }));
    expect(await pathOf(id)).toBeNull();
    expect(ignoredLines(log)).toHaveLength(1);
  });

  it("an empty, null, 0 or false screenshotBase64 logs nothing", async () => {
    const log = vi.spyOn(console, "log");
    const p = await createDevice("Mom");
    await postOk(p, extensionBody(blocked92, { screenshotBase64: "" }));
    await postOk(p, extensionBody(warning41, { screenshotBase64: null }));
    // Repeat visits: still 201, still no log line.
    await postOk(p, extensionBody(blocked92, { screenshotBase64: 0 }));
    await postOk(p, extensionBody(warning41, { screenshotBase64: false }));
    expect(ignoredLines(log)).toHaveLength(0);
  });

  it("a repeat visit keeps the screenshot stored before fase 20a", async () => {
    const p = await createDevice("Mom");
    const first = await postOk(p, extensionBody(blocked92));
    await seedScreenshot(sql, { id: first, ownerId: p.deviceId, domain: blocked92.domain }, b64(jpeg(100, 100)));
    expect(await postOk(p, extensionBody(blocked92, { screenshotBase64: b64(jpeg(200, 200)) }))).toBe(first);
    expect(await pathOf(first)).toBe(`${p.deviceId}/${first}.jpg`);
    expect((await sql`select count(*)::int as n from scans where owner_id = ${p.deviceId}`)[0]!.n).toBe(1);
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
});

// DT-04 (#497): optional signals[].host { marks, official } for the address card.
describe("POST /scans signals[].host (DT-04, #497)", () => {
  const hostSig = (host: unknown) => ({
    id: "brand_plus_keyword",
    layer: 2,
    weight: 14,
    label: { en: "Brand name plus a bait word", id: "Nama merek plus kata pancingan" },
    labelSimple: { en: "Looks like BCA but is not", id: "Mirip BCA tapi bukan" },
    evidence: "bca · level 2 · verifikasi",
    host,
  });

  it("survives POST /scans → GET /scans/{id} and GET /scans", async () => {
    const p = await createDevice("Mom");
    const withHost = hostSig({ marks: ["bca", "verifikasi"], official: "bca.co.id" });
    const cheap = { ...hostSig({ marks: [".site"] }), id: "cheap_tld", evidence: undefined };
    const old = blocked92.signals[0]!;
    const id = await postOk(p, extensionBody(blocked92, { signals: [withHost, cheap, old] }));
    const item = (await (await call(`/scans/${id}`, { token: p.token })).json()) as Item & { signals: unknown[] };
    expectScanResult(item);
    expect(item.signals).toEqual([
      expect.objectContaining({ id: "brand_plus_keyword", host: { marks: ["bca", "verifikasi"], official: "bca.co.id" } }),
      expect.objectContaining({ id: "cheap_tld", host: { marks: [".site"] } }),
      old,
    ]);
    expect(item.signals[2]).not.toHaveProperty("host");
    const { body } = await list(p);
    expect(body.items[0]!.signals).toEqual(item.signals);
  });

  it("only marks and official are kept, text is cleaned; bad shapes → 422", async () => {
    const p = await createDevice("Mom");
    const id = await postOk(
      p,
      extensionBody(blocked92, {
        signals: [hostSig({ marks: ["bca\u202E", "verifikasi"], official: "bca.co.id\u0007", extra: "x" })],
      }),
    );
    const [row] = await sql`select signals from scans where id = ${id}`;
    expect(row!.signals[0].host).toEqual({ marks: ["bca", "verifikasi"], official: "bca.co.id" });

    for (const host of [
      { marks: [] },
      { marks: ["a", "b", "c", "d", "e"] },
      { marks: [""] },
      { marks: ["\u202E"] },
      { marks: ["x".repeat(254)] },
      { official: "" },
      { official: "x".repeat(254) },
      { marks: "bca" },
      "bca.co.id",
    ]) {
      const res = await post(p, extensionBody(blocked92, { signals: [hostSig(host)] }));
      expect(res.status, JSON.stringify(host)).toBe(422);
    }
  });
});

// The service POST /scans called until fase 20a. It still stores the seeds that the screenshot
// serving, deletion and retention tests use; 20b removes it with this block.
describe("attachScreenshot (until fase 20b)", () => {
  /** A scan without a screenshot, as POST /scans stores it now. */
  const scanOf = async (p: Created, extra: Record<string, unknown> = {}) => {
    const body = extensionBody(blocked92, extra);
    return { id: await postOk(p, body), ownerId: p.deviceId, domain: body.domain as string };
  };

  it("stores a valid JPEG at <owner>/<scan>.jpg in the private bucket", async () => {
    const p = await createDevice("Mom");
    const scan = await scanOf(p);
    await seedScreenshot(sql, scan, b64(jpeg(800, 600, 1000)));
    const path = await pathOf(scan.id);
    expect(path).toBe(`${p.deviceId}/${scan.id}.jpg`);
    expect(await storageHas(path!)).toBe(true);
  });

  it("stores a PNG as .png", async () => {
    const p = await createDevice("Mom");
    const scan = await scanOf(p);
    await seedScreenshot(sql, scan, b64(png(390, 844)));
    expect(await pathOf(scan.id)).toBe(`${p.deviceId}/${scan.id}.png`);
  });

  it.each([
    ["over 150 KB", () => b64(jpeg(800, 600, 150 * 1024))],
    ["not an image", () => b64(new TextEncoder().encode("<html>not an image</html>"))],
    ["data: prefix", () => `data:image/jpeg;base64,${b64(jpeg(10, 10))}`],
    ["broken base64", () => "!!!not-base64!!!"],
    ["longest side over 1280 px", () => b64(jpeg(1281, 400))],
    ["PNG over 1280 px", () => b64(png(400, 2000))],
  ])("drops the screenshot (%s); the scan stays", async (_name, shot) => {
    const p = await createDevice("Mom");
    const scan = await scanOf(p);
    await seedScreenshot(sql, scan, shot());
    expect(await pathOf(scan.id)).toBeNull();
  });

  it("dedupe: a second scan of the site within 24 h reuses the first screenshot", async () => {
    const p = await createDevice("Mom");
    const scan = await scanOf(p);
    await seedScreenshot(sql, scan, b64(jpeg(100, 100)));
    // A second row of the same site from before one row per site.
    const [{ id: b }] = await sql<[{ id: string }]>`
      insert into scans (owner_id, url, domain, score, status, detected_at)
      values (${p.deviceId}, ${blocked92.url}, ${blocked92.domain}, 92, 'blocked', now()) returning id`;
    await seedScreenshot(sql, { ...scan, id: b }, b64(jpeg(200, 200)));
    expect([await pathOf(scan.id), await pathOf(b)]).toEqual([`${p.deviceId}/${scan.id}.jpg`, `${p.deviceId}/${scan.id}.jpg`]);
  });

  it("a failed upload clears the path on every scan that reused it (dedupe)", async () => {
    const p = await createDevice("Mom");
    const a = await postOk(p, extensionBody(blocked92));
    // A second row of the same site from before one row per site.
    const [{ id: b }] = await sql<[{ id: string }]>`
      insert into scans (owner_id, url, domain, score, status, detected_at)
      values (${p.deviceId}, ${blocked92.url}, ${blocked92.domain}, 92, 'blocked', now()) returning id`;
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
    const scans = await Promise.all(
      Array.from({ length: 6 }, (_, i) => scanOf(p, { url: `https://p${i}.example/`, domain: `p${i}.example` })),
    );
    await Promise.all(scans.map((s) => seedScreenshot(sql, s, b64(jpeg(100, 100)))));
    const paths = await Promise.all(scans.map((s) => pathOf(s.id)));
    expect(paths.filter(Boolean)).toHaveLength(2);
  });

  it("quota: at most 50 uploads per owner per 24 h", async () => {
    const p = await createDevice("Mom");
    // Original uploads: the path names the scan's own id (reuses do not count, D-alief-B12).
    await sql`insert into scans (id, owner_id, url, domain, score, status, detected_at, screenshot_path)
      select 'seed' || g, ${p.deviceId}, 'https://d' || g || '.example/', 'd' || g || '.example', 85, 'blocked', now(),
             ${p.deviceId} || '/seed' || g || '.jpg'
      from generate_series(1, 50) g`;
    const scan = await scanOf(p);
    await seedScreenshot(sql, scan, b64(jpeg(100, 100)));
    expect(await pathOf(scan.id)).toBeNull();
  });
});

describe("GET /scans", () => {
  it("owner=me (default): newest first, schema-valid, screenshotUrl null in lists", async () => {
    const p = await createDevice("Mom");
    await postOk(p, extensionBody(warning41));
    const shot = await postOk(p, extensionBody(blocked92));
    await seedScreenshot(sql, { id: shot, ownerId: p.deviceId, domain: blocked92.domain }, b64(jpeg(100, 100)));
    expect(await pathOf(shot)).not.toBeNull();
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
      // One Activity row per site: each round is another site.
      await postOk(p, extensionBody(blocked92, { detectedAt: at, ...site(`b${i}`) }));
      await postOk(p, extensionBody(warning41, { detectedAt: at, ...site(`w${i}`) }));
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
    for (let i = 0; i < 5; i++) await postOk(p, extensionBody(blocked92, { detectedAt: at, ...site(`s${i}`) }));
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

  it("the domain's verdict shows on warning and blocked scans alike (GD-07)", async () => {
    const g = await createDevice("Adhella", "guardian");
    const mom = await createDevice("Mom");
    await connect(g, mom);
    await postOk(mom, extensionBody(blocked92));
    // A warning row of the same site from before one row per site.
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at)
      values (${mom.deviceId}, 'https://bca-verifikasi.site/promo', 'bca-verifikasi.site', 41, 'warning', now())`;
    await sql`insert into verdicts (owner_id, domain, value, by_device_id, by_name, decided_at)
      values (${mom.deviceId}, 'bca-verifikasi.site', 'not_safe', ${g.deviceId}, 'Adhella', '2026-10-21T04:06:00Z')`;
    const { body } = await list(g, `?owner=${mom.deviceId}`);
    const blocked = body.items.find((i) => i.status === "blocked")!;
    const warning = body.items.find((i) => i.status === "warning")!;
    // A verdict inserted without url gets the backfill's link (verdicts_default_url).
    expect(blocked.verdict).toEqual({
      value: "not_safe", byDeviceId: g.deviceId, byName: "Adhella", decidedAt: "2026-10-21T04:06:00.000Z",
      url: "https://bca-verifikasi.site/",
    });
    expect(warning.verdict).toEqual(blocked.verdict);
    expectScanResult(blocked);
    expectScanResult(warning);
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
    // here and left out of the comparison. Verdict.url (optional in the schema, BH-19) is checked the same way.
    for (const item of body.items) expect(Object.hasOwn(item, "pageReplicaUrl") && item.pageReplicaUrl === null).toBe(true);
    for (const item of body.items) {
      const v = item.verdict as { url?: unknown } | null;
      if (v) {
        expect(typeof v.url).toBe("string");
        delete v.url;
      }
    }
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
    const id = await postOk(p, extensionBody(blocked92));
    await seedScreenshot(sql, { id, ownerId: p.deviceId, domain: blocked92.domain }, b64(jpeg(320, 240, 500)));
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

/**
 * Fase 28o (OPT-01, K17) guard: listScans pages must stay byte-identical to the statement it had
 * before the rewrite (one join of every owner's scans, verdict lateral on every row, then limit).
 * `legacyListScans` is that statement, copied verbatim; it is the oracle, not product code.
 */
function legacyListScans(q: ListQuery): Promise<ScanRow[]> {
  return sql<ScanRow[]>`
    select s.id, s.owner_id as "ownerId", d.name as "ownerName", s.url, s.domain,
           s.page_title as "pageTitle", s.score, s.status, s.signals,
           s.screenshot_path as "screenshotPath", case when s.favicon_ready_at is not null then s.favicon_path end as "faviconPath",
           case when s.replica_ready_at is not null then s.replica_path end as "replicaPath",
           to_char(s.detected_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}) as "detectedAt",
           to_char(s.detected_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as "cursorAt",
           case when v.owner_id is not null then jsonb_build_object(
             'value', v.value, 'byDeviceId', v.by_device_id, 'byName', v.by_name,
             'decidedAt', to_char(v.decided_at at time zone 'UTC', ${sql.unsafe(ISO_MS)}), 'url', v.url
           ) || jsonb_strip_nulls(jsonb_build_object(
             'lockedUntil', ${lockedUntilSql(sql, "v.value", "v.decided_at")}
           )) end as verdict
    from scans s
    join devices d on d.id = s.owner_id
    left join lateral (
      select v.* from (select public.verdict_link(s.url) as link) k, verdicts v
      where v.owner_id = s.owner_id
        and (v.url = k.link
             or (v.domain = s.domain and v.value = 'not_safe' and not public.verdict_shared(k.link, s.domain)))
      order by (v.url = k.link) desc, v.decided_at desc
      limit 1
    ) v on true
    where s.owner_id in ${sql(q.owners)}
      ${q.status ? sql`and s.status = ${q.status}` : sql``}
      ${q.cursor ? sql`and (s.detected_at, s.id) < (${q.cursor.at}::text::timestamptz, ${q.cursor.id})` : sql``}
    order by s.detected_at desc, s.id desc
    limit ${q.limit + 1}`;
}

describe("listScans: same pages as the statement before fase 28o (OPT-01)", () => {
  /**
   * Guardian + 3 members + a stranger. 46 scans: the heavy member has most (top-N per owner must cut
   * it), pairs of rows from different owners share one detected_at (id breaks the tie), some times
   * carry microseconds (the cursor keeps them), statuses mix. Verdicts: a locked safe link verdict
   * that also has a domain not_safe (link wins), an old safe one, two not_safe on the domain (newest
   * covers the other links), a not_safe on a shared host (sites.google.com: covers its own link only),
   * one member's verdict that must not reach another member, and the stranger's rows and verdicts.
   */
  async function seedFamily() {
    const g = await createDevice("Adhella", "guardian");
    const m1 = await createDevice("Mom");
    const m2 = await createDevice("Dad");
    const m3 = await createDevice("Oma");
    const stranger = await createDevice("Stranger");
    await sql`insert into family_links (protected_id, guardian_id)
      values (${m1.deviceId}, ${g.deviceId}), (${m2.deviceId}, ${g.deviceId}), (${m3.deviceId}, ${g.deviceId})`;
    const cycle = [m1, m1, m2, m1, g, m1, m2, m3, m1, m2, m1, stranger];
    const urls = [
      "https://alpha.example/p0?q=1#f", "https://ALPHA.example:443/p1", "https://alpha.example/p2", "https://user@alpha.example/p3",
      "https://alpha.example/p4", "https://sites.google.com/view/x0", "https://sites.google.com/view/x1?y=2",
      "https://beta.example", "https://beta.example/deep/page", "https://shop.example/cart",
    ];
    const domainOf = (u: string) => (u.includes("google.com") ? "google.com" : new URL(u).hostname);
    for (let i = 0; i < 46; i++) {
      const owner = cycle[i % cycle.length]!;
      const url = urls[(i * 7) % urls.length]!;
      const sec = 3600 - Math.floor(i / 2) * 37;
      const micro = i % 5 === 0 ? "123456" : i % 5 === 1 ? "000001" : "000000";
      const at = `2026-11-10T${String(Math.floor(sec / 3600)).padStart(2, "0")}:${String(Math.floor((sec % 3600) / 60)).padStart(2, "0")}:${String(sec % 60).padStart(2, "0")}.${micro}Z`;
      const score = i % 3 === 0 ? 80 + (i % 20) : 30 + (i % 50);
      await sql`insert into scans (owner_id, url, domain, page_title, score, status, signals, detected_at,
                                   favicon_path, favicon_ready_at, replica_path, replica_ready_at)
        values (${owner.deviceId}, ${url}, ${domainOf(url)}, ${i % 4 === 0 ? null : `Page ${i}`}, ${score},
                ${score >= 80 ? "blocked" : "warning"}, ${sql.json([{ id: `s${i}`, layer: 1 }] as never)}, ${at},
                ${i % 6 === 0 ? `${owner.deviceId}/fav${i}.png` : null}, ${i % 12 === 0 ? sql`now()` : null},
                ${i % 7 === 0 ? `${owner.deviceId}/rep${i}.html` : null}, ${i % 14 === 0 ? sql`now()` : null})`;
    }
    const verdict = (owner: Created, url: string, domain: string, value: string, decidedAt: unknown) =>
      sql`insert into verdicts (owner_id, url, domain, value, by_device_id, by_name, decided_at)
        values (${owner.deviceId}, ${url}, ${domain}, ${value}, ${g.deviceId}, 'Adhella', ${decidedAt as string})`;
    await verdict(m1, "https://alpha.example/p0", "alpha.example", "safe", sql`now()`);
    await verdict(m1, "https://alpha.example/p1", "alpha.example", "safe", "2026-10-01T08:00:00.000Z");
    await verdict(m1, "https://alpha.example/p2", "alpha.example", "not_safe", "2026-11-01T08:00:00.000Z");
    await verdict(m1, "https://alpha.example/p3", "alpha.example", "not_safe", "2026-11-05T08:00:00.000Z");
    await verdict(m1, "https://sites.google.com/view/x0", "google.com", "not_safe", "2026-11-06T08:00:00.000Z");
    await verdict(m2, "https://beta.example/", "beta.example", "not_safe", "2026-11-02T08:00:00.000Z");
    await verdict(m2, "https://alpha.example/p1", "alpha.example", "safe", "2026-11-03T08:00:00.000Z");
    await verdict(g, "https://shop.example/cart", "shop.example", "safe", "2026-09-01T08:00:00.000Z");
    await verdict(stranger, "https://alpha.example/p4", "alpha.example", "not_safe", "2026-11-04T08:00:00.000Z");
    return { g, m1, m2, m3, stranger };
  }

  /** Walks every page the way GET /scans does (cursor = last row of a full page) and compares each one. */
  async function samePages(q: Omit<ListQuery, "cursor">): Promise<ScanRow[][]> {
    const pages: ScanRow[][] = [];
    let cursor: ListQuery["cursor"] = null;
    for (;;) {
      const now: ScanRow[] = [...(await listScans(sql, { ...q, cursor }))];
      const old = [...(await legacyListScans({ ...q, cursor }))];
      expect(JSON.stringify(now), `page ${pages.length + 1}`).toBe(JSON.stringify(old));
      const page: ScanRow[] = now.slice(0, q.limit);
      pages.push(page);
      if (now.length <= q.limit) return pages;
      cursor = { at: page.at(-1)!.cursorAt, id: page.at(-1)!.id };
    }
  }

  it("owner=family, multi-owner with verdicts: every page (first, cursor pages) is byte-identical", async () => {
    const { g, m1, m2, m3, stranger } = await seedFamily();
    const owners = [g.deviceId, m1.deviceId, m2.deviceId, m3.deviceId];
    // limit 1: every row is a page boundary, so each detected_at tie between owners meets the cursor.
    expect((await samePages({ owners, status: null, limit: 1 })).flat()).toHaveLength(43);
    const pages = await samePages({ owners, status: null, limit: 5 });
    const rows = pages.flat();
    // The fixture really exercises what the rewrite could break.
    expect(pages.length).toBeGreaterThanOrEqual(3);
    expect(rows).toHaveLength(43);
    expect(new Set(rows.map((r) => r.id)).size).toBe(43);
    expect(rows.some((r) => r.ownerId === stranger.deviceId)).toBe(false);
    expect(new Set(pages[0]!.map((r) => r.ownerId)).size).toBeGreaterThan(1);
    expect(rows.some((r, i) => i > 0 && r.cursorAt === rows[i - 1]!.cursorAt && r.ownerId !== rows[i - 1]!.ownerId)).toBe(true);
    const verdicts = rows.map((r) => r.verdict);
    expect(verdicts.some((v) => v?.value === "safe" && v.lockedUntil)).toBe(true);
    expect(verdicts.some((v) => v?.value === "safe" && !v.lockedUntil)).toBe(true);
    expect(rows.some((r) => r.verdict?.value === "not_safe" && (r.verdict as unknown as { url: string }).url === "https://alpha.example/p3"
      && !r.url.includes("/p3"))).toBe(true);
    expect(rows.some((r) => r.url.includes("/view/x1") && r.ownerId === m1.deviceId && r.verdict === null)).toBe(true);
    expect(rows.some((r) => r.url.includes("/view/x0") && r.ownerId === m1.deviceId && r.verdict?.value === "not_safe")).toBe(true);
    expect(rows.some((r) => r.faviconPath !== null) && rows.some((r) => r.replicaPath !== null)).toBe(true);
  });

  it("status=blocked and status=warning: every page (with cursor) is byte-identical", async () => {
    const { g, m1, m2, m3 } = await seedFamily();
    const owners = [g.deviceId, m1.deviceId, m2.deviceId, m3.deviceId];
    const blocked = await samePages({ owners, status: "blocked", limit: 4 });
    expect(blocked.length).toBeGreaterThanOrEqual(3);
    expect(blocked.flat().every((r) => r.status === "blocked")).toBe(true);
    const warning = await samePages({ owners, status: "warning", limit: 5 });
    expect(warning.length).toBeGreaterThanOrEqual(3);
    expect(blocked.flat().length + warning.flat().length).toBe(43);
  });

  it("one owner (owner=me / owner=<member>), limit 1 to 50, and a repeated owner id: byte-identical", async () => {
    const { m1, m2 } = await seedFamily();
    for (const limit of [1, 2, 20, 50]) await samePages({ owners: [m1.deviceId], status: null, limit });
    await samePages({ owners: [m2.deviceId], status: "warning", limit: 2 });
    await samePages({ owners: [m1.deviceId, m1.deviceId], status: null, limit: 3 });
  });
});
