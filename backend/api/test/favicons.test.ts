import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { runRetention } from "../src/cron/retention";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
import { limits } from "../src/http/rateLimit";
import { downloadFavicon, isPublicIp, MAX_FAVICON_BYTES, sniffFavicon } from "../src/services/faviconFetch";
import { faviconLink, screenshotLink } from "../src/services/screenshotLinks";
import { jpeg, png } from "./helpers/images";
import { resetDb, testSql } from "./helpers/resetDb";
import { expectScanResult } from "./helpers/schema";
import { call, createDevice, type Created } from "./helpers/seed";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

// Sample favicons with real magic bytes.
const ascii = (t: string) => [...t].map((ch) => ch.charCodeAt(0));
const ico = (side = 16) => Uint8Array.from([0, 0, 1, 0, 1, 0, side & 0xff, side & 0xff, 0, 0, 1, 0, 32, 0, 8, 0, 0, 0, 22, 0, 0, 0, ...new Array<number>(8).fill(7)]);
const gif = (w = 1, h = 1) => Uint8Array.from([...ascii("GIF89a"), w & 0xff, w >> 8, h & 0xff, h >> 8, 0, 0, 0]);
/** Extended WebP (VP8X): canvas size minus one, 24-bit little endian. */
const webp = (w = 16, h = 16) =>
  Uint8Array.from([...ascii("RIFF"), 22, 0, 0, 0, ...ascii("WEBPVP8X"), 10, 0, 0, 0, 0, 0, 0, 0,
    (w - 1) & 0xff, ((w - 1) >> 8) & 0xff, 0, (h - 1) & 0xff, ((h - 1) >> 8) & 0xff, 0]);
/** Lossless WebP (VP8L): 14-bit width-1 and height-1 after the 0x2f signature. */
const webpLossless = (w: number, h: number) => {
  const bits = ((w - 1) | ((h - 1) << 14)) >>> 0;
  return Uint8Array.from([...ascii("RIFF"), 18, 0, 0, 0, ...ascii("WEBPVP8L"), 5, 0, 0, 0, 0x2f,
    bits & 0xff, (bits >> 8) & 0xff, (bits >> 16) & 0xff, (bits >>> 24) & 0xff]);
};
const svg = () => new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');

const PUBLIC_IP = "93.184.216.34";
const image = (bytes: Uint8Array, type = "image/png", extra: Record<string, string> = {}) =>
  new Response(bytes, { status: 200, headers: { "content-type": type, ...extra } });
const redirect = (to: string, status = 302) => new Response(null, { status, headers: { location: to } });
const doh = (answers: { type: number; data: string }[], status = 0) =>
  new Response(JSON.stringify({ Status: status, Answer: answers }), { headers: { "content-type": "application/dns-json" } });

type Handler = (init: RequestInit) => Response | Promise<Response>;

/**
 * A fake internet for downloadFavicon: `site` answers by exact URL, DNS answers from `dns` (default:
 * every name has one public A record). Records each request the downloader made (DoH excluded).
 */
function fakeWeb(site: Record<string, Handler>, dns: Record<string, string[]> = {}) {
  const requests: { url: string; init: RequestInit }[] = [];
  const answer = async (input: string, init: RequestInit = {}): Promise<Response> => {
    const url = new URL(input);
    if (url.hostname === "cloudflare-dns.com") {
      const name = url.searchParams.get("name")!;
      const type = url.searchParams.get("type");
      const addresses = dns[name] ?? [PUBLIC_IP];
      const v6 = (a: string) => a.includes(":");
      if (type === "A") return doh(addresses.filter((a) => !v6(a)).map((data) => ({ type: 1, data })));
      return doh(addresses.filter(v6).map((data) => ({ type: 28, data })));
    }
    requests.push({ url: url.href, init });
    const handler = site[url.href];
    return handler ? handler(init) : new Response("not found", { status: 404 });
  };
  return { requests, fetch: answer };
}

describe("downloadFavicon guards (PR-05, SECURITY P9)", () => {
  it.each([
    ["png", png(16, 16), "image/png"],
    ["ico", ico(), "image/x-icon"],
    ["ico", ico(), "image/vnd.microsoft.icon"],
    ["jpeg", jpeg(16, 16), "image/jpeg"],
    ["gif", gif(), "image/gif"],
    ["webp", webp(), "image/webp"],
  ] as const)("accepts %s served as %s", async (type, bytes, contentType) => {
    const web = fakeWeb({ "https://scam.example/favicon.ico": () => image(bytes, contentType) });
    const r = await downloadFavicon("https://scam.example/favicon.ico", { fetch: web.fetch });
    expect(r).toEqual({ ok: true, favicon: { type, bytes } });
  });

  it("sends no cookie, no referer, a neutral user agent, and handles redirects itself", async () => {
    const web = fakeWeb({ "https://scam.example/favicon.ico": () => image(png(16, 16)) });
    await downloadFavicon("https://scam.example/favicon.ico", { fetch: web.fetch });
    const [req] = web.requests;
    const headers = new Headers(req!.init.headers);
    expect(req!.init.redirect).toBe("manual");
    expect(headers.get("cookie")).toBeNull();
    expect(headers.get("referer")).toBeNull();
    expect(headers.get("user-agent")).toBe("Mozilla/5.0 (compatible; ShooFavicon/1.0)");
  });

  it.each([
    "http://127.0.0.1/favicon.ico",
    "http://10.0.0.5/favicon.ico",
    "http://192.168.1.1/favicon.ico",
    "http://172.16.0.1/favicon.ico",
    "http://169.254.169.254/latest/meta-data",
    "http://100.64.0.1/favicon.ico",
    "http://0.0.0.0/favicon.ico",
    "http://0x7f.1/favicon.ico",
    "http://2130706433/favicon.ico",
    "http://[::1]/favicon.ico",
    "http://[fe80::1]/favicon.ico",
    "http://[fd00::1]/favicon.ico",
    "http://[::ffff:127.0.0.1]/favicon.ico",
    "http://[64:ff9b::a00:1]/favicon.ico",
    "http://localhost/favicon.ico",
    "http://printer.local/favicon.ico",
    "http://intranet/favicon.ico",
  ])("never requests a private, loopback or link-local host: %s", async (url) => {
    const web = fakeWeb({});
    expect(await downloadFavicon(url, { fetch: web.fetch })).toEqual({ ok: false, reason: "private_address" });
    expect(web.requests).toEqual([]);
  });

  it("a public name that resolves to a private address is not requested", async () => {
    const web = fakeWeb({}, { "rebind.example": ["10.0.0.1"] });
    expect(await downloadFavicon("https://rebind.example/favicon.ico", { fetch: web.fetch })).toEqual({ ok: false, reason: "private_address" });
    const mixed = fakeWeb({}, { "mixed.example": [PUBLIC_IP, "::1"] });
    expect(await downloadFavicon("https://mixed.example/favicon.ico", { fetch: mixed.fetch })).toEqual({ ok: false, reason: "private_address" });
    expect([...web.requests, ...mixed.requests]).toEqual([]);
  });

  it("no address or a failed DoH lookup → dns_failed, nothing requested", async () => {
    const empty = fakeWeb({}, { "gone.example": [] });
    expect(await downloadFavicon("https://gone.example/f.ico", { fetch: empty.fetch })).toEqual({ ok: false, reason: "dns_failed" });
    const broken = async (input: string) =>
      new URL(input).hostname === "cloudflare-dns.com" ? new Response("x", { status: 502 }) : image(png(16, 16));
    expect(await downloadFavicon("https://scam.example/f.ico", { fetch: broken })).toEqual({ ok: false, reason: "dns_failed" });
  });

  it.each([
    "ftp://scam.example/favicon.ico",
    "data:image/png;base64,AAAA",
    "javascript:alert(1)",
    "https://user:pw@scam.example/favicon.ico",
    "https://scam.example:8443/favicon.ico",
    "not a url",
  ])("only http(s) on the default port without credentials: %s", async (url) => {
    const web = fakeWeb({});
    expect(await downloadFavicon(url, { fetch: web.fetch })).toEqual({ ok: false, reason: "bad_url" });
    expect(web.requests).toEqual([]);
  });

  it("follows up to 2 redirects (relative too), re-checking each hop", async () => {
    const web = fakeWeb({
      "https://scam.example/favicon.ico": () => redirect("https://cdn.example/a.ico", 301),
      "https://cdn.example/a.ico": () => redirect("/b.ico", 307),
      "https://cdn.example/b.ico": () => image(ico(), "image/x-icon"),
    });
    const r = await downloadFavicon("https://scam.example/favicon.ico", { fetch: web.fetch });
    expect(r.ok).toBe(true);
    expect(web.requests.map((q) => q.url)).toEqual(["https://scam.example/favicon.ico", "https://cdn.example/a.ico", "https://cdn.example/b.ico"]);
  });

  it("a third redirect → too_many_redirects", async () => {
    const web = fakeWeb({
      "https://scam.example/1": () => redirect("https://scam.example/2"),
      "https://scam.example/2": () => redirect("https://scam.example/3"),
      "https://scam.example/3": () => redirect("https://scam.example/4"),
      "https://scam.example/4": () => image(png(16, 16)),
    });
    expect(await downloadFavicon("https://scam.example/1", { fetch: web.fetch })).toEqual({ ok: false, reason: "too_many_redirects" });
    expect(web.requests).toHaveLength(3);
  });

  it.each([
    ["http://169.254.169.254/latest/meta-data", "private_address"],
    ["http://localhost:8787/healthz", "bad_url"],
    ["file:///etc/passwd", "bad_url"],
  ])("a redirect to %s is not followed", async (to, reason) => {
    const web = fakeWeb({ "https://scam.example/favicon.ico": () => redirect(to) });
    expect(await downloadFavicon("https://scam.example/favicon.ico", { fetch: web.fetch })).toEqual({ ok: false, reason });
    expect(web.requests).toHaveLength(1);
  });

  it("a redirect to a name resolving privately is not followed", async () => {
    const web = fakeWeb({ "https://scam.example/favicon.ico": () => redirect("https://inside.example/x.ico") }, { "inside.example": ["192.168.0.10"] });
    expect(await downloadFavicon("https://scam.example/favicon.ico", { fetch: web.fetch })).toEqual({ ok: false, reason: "private_address" });
    expect(web.requests).toHaveLength(1);
  });

  it("over 64 KB → too_large, by Content-Length or while streaming", async () => {
    const big = new Uint8Array(MAX_FAVICON_BYTES + 1);
    big.set(png(16, 16));
    const declared = fakeWeb({ "https://scam.example/f.png": () => image(png(16, 16), "image/png", { "content-length": String(MAX_FAVICON_BYTES + 1) }) });
    expect(await downloadFavicon("https://scam.example/f.png", { fetch: declared.fetch })).toEqual({ ok: false, reason: "too_large" });

    let cancelled = false;
    const streamed = fakeWeb({
      "https://scam.example/f.png": () => {
        let sent = 0;
        const body = new ReadableStream<Uint8Array>({
          pull(ctrl) {
            // Endless 16 KB chunks without a Content-Length: the reader must stop on its own.
            sent++;
            ctrl.enqueue(sent === 1 ? big.subarray(0, 16 * 1024) : new Uint8Array(16 * 1024));
          },
          cancel() {
            cancelled = true;
          },
        });
        return new Response(body, { headers: { "content-type": "image/png" } });
      },
    });
    expect(await downloadFavicon("https://scam.example/f.png", { fetch: streamed.fetch })).toEqual({ ok: false, reason: "too_large" });
    expect(cancelled).toBe(true);

    const exact = new Uint8Array(MAX_FAVICON_BYTES);
    exact.set(png(16, 16));
    const ok = fakeWeb({ "https://scam.example/f.png": () => image(exact) });
    expect((await downloadFavicon("https://scam.example/f.png", { fetch: ok.fetch })).ok).toBe(true);
  });

  it.each([
    ["image/svg+xml", svg(), "bad_type"],
    ["text/html", png(16, 16), "bad_type"],
    ["application/octet-stream", ico(), "bad_type"],
    ["", png(16, 16), "bad_type"],
    ["image/png", svg(), "bad_magic"],
    ["image/x-icon", new TextEncoder().encode("<html>hello</html>"), "bad_magic"],
    ["image/png", new Uint8Array(), "bad_magic"],
    ["image/x-icon", Uint8Array.from([0, 0, 2, 0, 1, 0, ...new Array<number>(16).fill(0)]), "bad_magic"],
  ])("served as %j → rejected", async (contentType, bytes, reason) => {
    const web = fakeWeb({ "https://scam.example/f": () => image(bytes, contentType) });
    expect(await downloadFavicon("https://scam.example/f", { fetch: web.fetch })).toEqual({ ok: false, reason });
  });

  it.each([
    ["png 513 px", png(513, 16), "image/png"],
    ["png 0 px", png(0, 16), "image/png"],
    ["jpeg 600 px", jpeg(16, 600), "image/jpeg"],
    ["gif 1000 px", gif(1000, 1), "image/gif"],
    ["webp VP8X 4096 px", webp(4096, 16), "image/webp"],
    ["webp VP8L 513 px", webpLossless(513, 513), "image/webp"],
    ["webp without a frame header", Uint8Array.from([...ascii("RIFF"), 4, 0, 0, 0, ...ascii("WEBP")]), "image/webp"],
    ["png cut before IHDR ends", png(16, 16).subarray(0, 20), "image/png"],
  ])("over 512 px per side or no readable size → bad_size: %s", async (_name, bytes, contentType) => {
    const web = fakeWeb({ "https://scam.example/f": () => image(bytes, contentType) });
    expect(await downloadFavicon("https://scam.example/f", { fetch: web.fetch })).toEqual({ ok: false, reason: "bad_size" });
  });

  it("512 px per side is still accepted; ICO entries are at most 256", async () => {
    for (const [bytes, type] of [[png(512, 512), "image/png"], [webpLossless(512, 512), "image/webp"], [ico(0), "image/x-icon"]] as const) {
      const web = fakeWeb({ "https://scam.example/f": () => image(bytes, type) });
      expect((await downloadFavicon("https://scam.example/f", { fetch: web.fetch })).ok).toBe(true);
    }
  });

  it("a non-200 answer → bad_status", async () => {
    const web = fakeWeb({ "https://scam.example/f.ico": () => new Response("x", { status: 403 }) });
    expect(await downloadFavicon("https://scam.example/f.ico", { fetch: web.fetch })).toEqual({ ok: false, reason: "bad_status" });
    expect(await downloadFavicon("https://scam.example/missing.ico", { fetch: web.fetch })).toEqual({ ok: false, reason: "bad_status" });
  });

  it("a host that never answers → timeout", async () => {
    const hang = (_input: string, init: RequestInit) =>
      new URL(_input).hostname === "cloudflare-dns.com"
        ? Promise.resolve(doh([{ type: 1, data: PUBLIC_IP }]))
        : new Promise<Response>((_, reject) => init.signal!.addEventListener("abort", () => reject(init.signal!.reason)));
    expect(await downloadFavicon("https://slow.example/f.ico", { fetch: hang, timeoutMs: 50 })).toEqual({ ok: false, reason: "timeout" });
  });

  it("a body that stalls → timeout", async () => {
    const stall = fakeWeb({
      "https://slow.example/f.ico": (init) =>
        new Response(
          new ReadableStream({
            start(ctrl) {
              ctrl.enqueue(png(16, 16));
              init.signal!.addEventListener("abort", () => ctrl.error(init.signal!.reason));
            },
          }),
          { headers: { "content-type": "image/png" } },
        ),
    });
    expect(await downloadFavicon("https://slow.example/f.ico", { fetch: stall.fetch, timeoutMs: 50 })).toEqual({ ok: false, reason: "timeout" });
  });

  it("isPublicIp: only global unicast", () => {
    for (const ip of ["93.184.216.34", "8.8.8.8", "2606:4700:4700::1111", "2a00:1450:4001::200e"]) expect(isPublicIp(ip), ip).toBe(true);
    for (const ip of [
      "127.0.0.1", "10.1.2.3", "172.31.255.255", "192.168.0.1", "169.254.0.1", "100.100.1.1", "0.1.2.3", "224.0.0.1",
      "255.255.255.255", "192.0.2.1", "198.51.100.1", "203.0.113.9", "198.18.0.1",
      "::", "::1", "fe80::1", "fc00::1", "ff02::1", "::ffff:10.0.0.1", "::ffff:a00:1", "64:ff9b::7f00:1", "2001:db8::1",
      "2002:a00:1::1", "2001::1", "fe80::1%en0", "not-an-ip", "1.2.3", "1::2::3",
    ]) expect(isPublicIp(ip), ip).toBe(false);
    expect(isPublicIp("::ffff:8.8.8.8")).toBe(true);
  });

  it("sniffFavicon never accepts SVG or text", () => {
    expect(sniffFavicon(svg())).toBeUndefined();
    expect(sniffFavicon(new TextEncoder().encode("GIF89"))).toBeUndefined();
    expect(sniffFavicon(png(1, 1))).toBe("png");
  });
});

// ---------------------------------------------------------------------------------------------
// Through the API: POST /scans stores it in waitUntil, GET /favicons/{id} serves it.

const domain = blocked92.domain;
const ICON_URL = `https://${domain}/favicon.ico`;
const realFetch = globalThis.fetch.bind(globalThis);

/** The Worker's fetch, with the scam site faked and Storage (local Supabase) passed through. */
function mockInternet(site: Record<string, Handler>) {
  const web = fakeWeb(site);
  vi.spyOn(globalThis, "fetch").mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const host = new URL(url).hostname;
    if (host === "127.0.0.1" || host === "localhost") return realFetch(input, init);
    return web.fetch(url, init);
  });
  return web;
}

const logs: string[] = [];
beforeEach(() => {
  logs.length = 0;
  vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => void logs.push(a.map(String).join(" ")));
});

const body = (extra: Record<string, unknown> = {}) =>
  ({ ...blocked92, id: undefined, verdict: undefined, screenshotUrl: undefined, faviconUrl: ICON_URL, ...extra });
const postScan = async (d: Created, extra: Record<string, unknown> = {}) => {
  const res = await call("/scans", { method: "POST", token: d.token, json: body(extra) });
  expect(res.status).toBe(201);
  return ((await res.json()) as { id: string }).id;
};
const faviconPath = async (id: string) => (await sql<{ p: string | null }[]>`select favicon_path as p from scans where id = ${id}`)[0]?.p ?? null;

/** waitUntil runs after the response: poll until `done` holds (2 s at most). */
async function until(done: () => Promise<boolean> | boolean): Promise<void> {
  for (let i = 0; i < 80; i++) {
    if (await done()) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error("timed out waiting for waitUntil work");
}
const stored = async (id: string) => {
  await until(async () => (await faviconPath(id)) !== null);
  return (await faviconPath(id))!;
};
const droppedFor = (reason: string) => until(() => logs.some((l) => l.includes(`"event":"favicon_dropped"`) && l.includes(`"reason":"${reason}"`)));

const objectExists = (path: string) =>
  realFetch(`${env.SUPABASE_URL}/storage/v1/object/info/screenshots/${path}`, {
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY!, authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
  }).then(async (r) => {
    await r.body?.cancel();
    return r.ok;
  });

const detail = async (viewer: Created, id: string) => {
  const res = await call(`/scans/${id}`, { token: viewer.token });
  expect(res.status).toBe(200);
  return (await res.json()) as { faviconUrl: string | null };
};
/** faviconUrl from GET /scans/{id}, as path + query for call(). */
const linkFor = async (viewer: Created, id: string) => {
  const u = new URL((await detail(viewer, id)).faviconUrl!);
  return `${u.pathname}${u.search}`;
};
const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};

describe("POST /scans stores the favicon (PR-05)", () => {
  it("downloads once in waitUntil and stores <owner>/<scan>-favicon.<ext>; scan answers 201 first", async () => {
    const web = mockInternet({ [ICON_URL]: () => image(ico(), "image/x-icon") });
    const p = await createDevice("Mom");
    const id = await postScan(p);
    expect(await stored(id)).toBe(`${p.deviceId}/${id}-favicon.ico`);
    expect(await objectExists(`${p.deviceId}/${id}-favicon.ico`)).toBe(true);
    expect(web.requests.map((r) => r.url)).toEqual([ICON_URL]);
    // The tombstone stays (young): the cron removes the object if the row goes (D-alief-B12).
    expect((await sql`select 1 from storage_tombstones where path = ${`${p.deviceId}/${id}-favicon.ico`}`).length).toBe(1);
  });

  it("a slow or failing favicon never fails the scan", async () => {
    mockInternet({ [ICON_URL]: () => new Response("boom", { status: 500 }) });
    const p = await createDevice("Mom");
    const id = await postScan(p);
    await droppedFor("bad_status");
    expect(await faviconPath(id)).toBeNull();
    expect((await detail(p, id)).faviconUrl).toBeNull();
    // Reason only: the favicon URL is a page the user visited.
    expect(logs.join("\n")).not.toContain(domain);
  });

  it("reuses the owner's favicon of the same domain within 24 h without downloading again", async () => {
    const web = mockInternet({ [ICON_URL]: () => image(png(16, 16)) });
    const p = await createDevice("Mom");
    const first = await postScan(p);
    const path = await stored(first);
    const second = await postScan(p);
    expect(await stored(second)).toBe(path);
    expect(web.requests).toHaveLength(1);

    // Another owner never shares it.
    const other = await createDevice("Dad");
    const third = await postScan(other);
    expect(await stored(third)).toBe(`${other.deviceId}/${third}-favicon.png`);
  });

  it("no reuse past 24 h: downloads again", async () => {
    const web = mockInternet({ [ICON_URL]: () => image(png(16, 16)) });
    const p = await createDevice("Mom");
    const first = await postScan(p);
    await stored(first);
    await sql`update scans set created_at = now() - interval '25 hours' where id = ${first}`;
    const second = await postScan(p);
    expect(await stored(second)).toBe(`${p.deviceId}/${second}-favicon.png`);
    expect(web.requests).toHaveLength(2);
  });

  const fillBucket = async (bucket: string, key: string, n: number) => {
    const k = await keyHash(`${bucket}:${key}`);
    await sql`insert into rate_limit_hits (bucket, key_hash) select ${bucket}, ${k} from generate_series(1, ${n})`;
  };

  it("per-owner download quota: 30 attempts in 24 h, then the favicon is dropped without a request", async () => {
    const web = mockInternet({ [ICON_URL]: () => image(png(16, 16)) });
    const p = await createDevice("Mom");
    await fillBucket(limits.fetchFavicon.bucket, p.deviceId, limits.fetchFavicon.max);
    const id = await postScan(p);
    await droppedFor("quota");
    expect(await faviconPath(id)).toBeNull();
    expect(web.requests).toEqual([]);
  });

  it("global download quota for all devices together", async () => {
    const web = mockInternet({ [ICON_URL]: () => image(png(16, 16)) });
    const p = await createDevice("Mom");
    await fillBucket(limits.fetchFaviconAll.bucket, "all", limits.fetchFaviconAll.max);
    const id = await postScan(p);
    await droppedFor("quota");
    expect(await faviconPath(id)).toBeNull();
    expect(web.requests).toEqual([]);
  });

  it("failed downloads spend the quota too (a junk URL cannot make the Worker fetch without limit)", async () => {
    mockInternet({});
    const p = await createDevice("Mom");
    await postScan(p, { domain: "a.example", url: "https://a.example/", faviconUrl: "https://a.example/nope.ico" });
    await droppedFor("bad_status");
    const k = await keyHash(`${limits.fetchFavicon.bucket}:${p.deviceId}`);
    expect((await sql`select 1 from rate_limit_hits where bucket = ${limits.fetchFavicon.bucket} and key_hash = ${k}`).length).toBe(1);
  });

  it("an SVG favicon is never stored", async () => {
    mockInternet({ [ICON_URL]: () => image(svg(), "image/svg+xml") });
    const p = await createDevice("Mom");
    const id = await postScan(p);
    await droppedFor("bad_type");
    expect(await faviconPath(id)).toBeNull();
  });

  it("the scan deleted during the download → nothing stored, no orphan object", async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    mockInternet({ [ICON_URL]: async () => (await gate, image(png(16, 16))) });
    const p = await createDevice("Mom");
    const id = await postScan(p);
    await until(async () => (await sql`select 1 from rate_limit_hits where bucket = ${limits.fetchFavicon.bucket}`).length === 1);
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    release();
    await droppedFor("scan_gone");
    expect(await objectExists(`${p.deviceId}/${id}-favicon.png`)).toBe(false);
  });
});

describe("faviconUrl in GET /scans and GET /scans/{id} (PR-05)", () => {
  it("is our signed Worker link, never the scam site's URL; null without a stored favicon", async () => {
    mockInternet({ [ICON_URL]: () => image(png(16, 16)) });
    const p = await createDevice("Mom");
    const withIcon = await postScan(p);
    await stored(withIcon);
    const without = await postScan(p, { domain: "b.example", url: "https://b.example/", faviconUrl: null });

    const one = await detail(p, withIcon);
    expectScanResult(one);
    const link = new URL(one.faviconUrl!);
    expect(`${link.origin}${link.pathname}`).toBe(`${env.INVITE_BASE_URL}/favicons/${withIcon}`);
    expect([...link.searchParams.keys()].sort()).toEqual(["exp", "sig", "v"]);
    expect(link.searchParams.get("v")).toBe(p.deviceId);
    expect(Number(link.searchParams.get("exp")) - Date.now() / 1000).toBeGreaterThan(3500);
    expect((await detail(p, without)).faviconUrl).toBeNull();

    const list = (await (await call("/scans", { token: p.token })).json()) as { items: { id: string; faviconUrl: string | null }[] };
    for (const item of list.items) expectScanResult(item);
    const byId = Object.fromEntries(list.items.map((i) => [i.id, i.faviconUrl]));
    expect(new URL(byId[withIcon]!).pathname).toBe(`/favicons/${withIcon}`);
    expect(byId[without]).toBeNull();
    // The raw URL is stored for the download but never returned.
    expect(JSON.stringify(list)).not.toContain(ICON_URL);
    expect(JSON.stringify(one)).not.toContain(ICON_URL);
  });

  it("a guardian's list carries links signed for the guardian", async () => {
    mockInternet({ [ICON_URL]: () => image(png(16, 16)) });
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await connect(g, p);
    const id = await postScan(p);
    await stored(id);
    const list = (await (await call("/scans?owner=family", { token: g.token })).json()) as { items: { faviconUrl: string }[] };
    expect(new URL(list.items[0]!.faviconUrl).searchParams.get("v")).toBe(g.deviceId);
  });
});

describe("GET /favicons/{scanId} (PR-05, like D-alief-B08)", () => {
  const setup = async () => {
    mockInternet({ [ICON_URL]: () => image(ico(), "image/x-icon") });
    const p = await createDevice("Mom");
    const id = await postScan(p);
    await stored(id);
    return { p, id };
  };

  it("serves the bytes to the owner with no-store, nosniff, sandbox CSP, no-referrer", async () => {
    const { p, id } = await setup();
    const res = await call(await linkFor(p, id));
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/x-icon");
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("content-security-policy")).toBe("default-src 'none'; sandbox");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(ico());
  });

  it("guardian can open it; after disconnect the same link → 404", async () => {
    const g = await createDevice("G", "guardian");
    const { p, id } = await setup();
    await connect(g, p);
    const link = await linkFor(g, id);
    expect((await call(link)).status).toBe(200);
    expect((await call("/family/guardian", { method: "DELETE", token: p.token })).status).toBe(200);
    const res = await call(link);
    expect(res.status).toBe(404);
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    // Disconnect only hides it: the owner still sees it.
    expect((await call(await linkFor(p, id))).status).toBe(200);
  });

  it("a stranger → 404, even with a link correctly signed for them", async () => {
    const { id } = await setup();
    const stranger = await createDevice("X");
    const forged = new URL(await faviconLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, stranger.deviceId, Date.now() / 1000));
    expect((await call(`${forged.pathname}${forged.search}`)).status).toBe(404);
  });

  it("a screenshot link for the same scan does not open the favicon", async () => {
    const { p, id } = await setup();
    const shot = new URL(await screenshotLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, p.deviceId, Date.now() / 1000));
    expect((await call(`/favicons/${id}${shot.search}`)).status).toBe(404);
  });

  it("tampered, expired or missing signature → 404", async () => {
    const { p, id } = await setup();
    const link = new URL(`http://x${await linkFor(p, id)}`);
    const sig = link.searchParams.get("sig")!;
    const old = new URL(await faviconLink(env.SCREENSHOT_URL_SECRET!, env.INVITE_BASE_URL, id, p.deviceId, Date.now() / 1000 - 3601));
    expect((await call(`${old.pathname}${old.search}`)).status).toBe(404);
    for (const change of [
      (u: URL) => u.searchParams.set("sig", `${sig.slice(0, -1)}${sig.endsWith("A") ? "B" : "A"}`),
      (u: URL) => u.searchParams.delete("sig"),
      (u: URL) => u.searchParams.set("v", "someone_else"),
      (u: URL) => u.searchParams.set("exp", String(Number(u.searchParams.get("exp")) + 60)),
    ]) {
      const u = new URL(link);
      change(u);
      expect((await call(`${u.pathname}${u.search}`)).status, u.search).toBe(404);
    }
    expect((await call("/favicons/not-a-uuid")).status).toBe(404);
  });

  it("after DELETE /devices/me → 404 at once, and the object is removed from Storage", async () => {
    const { p, id } = await setup();
    const link = await linkFor(p, id);
    const path = `${p.deviceId}/${id}-favicon.ico`;
    expect(await objectExists(path)).toBe(true);
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect((await call(link)).status).toBe(404);
    await until(async () => !(await objectExists(path)));
  });

  it("retention: day 14 removes the scan, the link → 404 and the object is gone", async () => {
    const { p, id } = await setup();
    const link = await linkFor(p, id);
    const path = `${p.deviceId}/${id}-favicon.ico`;
    await sql`update scans set created_at = now() - interval '15 days' where id = ${id}`;
    const r = await runRetention(sql, env);
    expect(r.scans).toBe(1);
    expect(r.objects).toBe(1);
    expect(await faviconPath(id)).toBeNull();
    expect((await call(link)).status).toBe(404);
    expect(await objectExists(path)).toBe(false);
  });

  it("retention keeps a favicon still reused by a younger scan", async () => {
    const { p, id } = await setup();
    const younger = await postScan(p);
    const path = await stored(younger);
    await sql`update scans set created_at = now() - interval '15 days' where id = ${id}`;
    await runRetention(sql, env);
    expect(await objectExists(path)).toBe(true);
    expect((await call(await linkFor(p, younger))).status).toBe(200);
  });

  it("rate limits 600 per minute per viewer", async () => {
    const { p, id } = await setup();
    const k = await keyHash(`${limits.viewFavicon.bucket}:${p.deviceId}`);
    await sql`insert into rate_limit_hits (bucket, key_hash) select ${limits.viewFavicon.bucket}, ${k} from generate_series(1, ${limits.viewFavicon.max})`;
    expect((await call(await linkFor(p, id))).status).toBe(429);
  });
});
