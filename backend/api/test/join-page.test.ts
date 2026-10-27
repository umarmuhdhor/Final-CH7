import { describe, expect, it } from "vitest";
import { storeUrl } from "../src/routes/join-page";
import { call } from "./helpers/seed";

const page = async (path: string, lang?: string) => {
  const res = await call(path, { headers: lang ? { "accept-language": lang } : {} });
  return { res, html: await res.text() };
};

const nonceOf = (res: Response) => /script-src 'nonce-([A-Za-z0-9_-]+)'/.exec(res.headers.get("content-security-policy") ?? "")?.[1];

describe("GET /j/:code", () => {
  it("valid code: shoo:// button and the code in large text, strict headers", async () => {
    const { res, html } = await page("/j/482193");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/^text\/html; charset=utf-8/i);
    const csp = res.headers.get("content-security-policy")!;
    expect(csp).toContain("default-src 'none'");
    expect(csp).toContain("style-src 'unsafe-inline'");
    expect(csp).not.toContain("unsafe-eval");
    expect(csp).not.toMatch(/script-src[^;]*unsafe-inline/);
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(html).toContain('href="shoo://join?code=482193"');
    expect(html).toContain(">482193<");
    expect(html).toContain('lang="en"');
    expect(html).toContain("Open Shoo");
  });

  it("Install copies the invite link, then goes to the store; the only script carries the header's nonce", async () => {
    const { res, html } = await page("/j/482193");
    const nonce = nonceOf(res)!;
    expect(nonce.length).toBeGreaterThanOrEqual(16);
    expect(html).toContain('id="install" href="https://apps.apple.com/"');
    expect(html).toContain('data-invite="http://localhost:8787/j/482193"');
    expect(html.match(/<script/g)).toHaveLength(1);
    expect(html).toContain(`<script nonce="${nonce}">`);
    expect(html).toContain("navigator.clipboard.writeText");
    expect(html).not.toMatch(/fetch\(|XMLHttpRequest|sendBeacon|document\.cookie|localStorage/);
  });

  it("a new nonce on every request", async () => {
    const a = nonceOf((await page("/j/482193")).res);
    const b = nonceOf((await page("/j/482193")).res);
    expect(a).not.toBe(b);
  });

  it("Indonesian for Accept-Language id", async () => {
    const { html } = await page("/j/482193", "id-ID,id;q=0.9,en;q=0.8");
    expect(html).toContain('lang="id"');
    expect(html).toContain("Belum punya Shoo?");
  });

  it.each([
    "/j/%3Cscript%3Ealert(1)%3C%2Fscript%3E",
    "/j/123456%22onclick%3D",
    "/j/12345",
    "/j/1234567",
    "/j/4821",
    "/j/12a456",
  ])("no code, no button and no script for %s, input never reflected", async (path) => {
    const { res, html } = await page(path);
    expect(res.status).toBe(200);
    expect(html).not.toContain("shoo://");
    expect(html).not.toContain("<script");
    expect(html).not.toContain("onclick");
    expect(html).not.toContain("12345");
    expect(html).not.toContain("4821");
    expect(html).toContain("no valid code");
  });

  it("does not reveal whether a code exists (no DB lookup)", async () => {
    const strip = (html: string) => html.replace(/nonce="[^"]+"/, "");
    const a = await page("/j/000000");
    const b = await page("/j/999999");
    expect(strip(a.html).replaceAll("000000", "")).toBe(strip(b.html).replaceAll("999999", ""));
  });

  it("link preview: static Open Graph tags with an absolute image URL, no code in them", async () => {
    const { html } = await page("/j/482193");
    expect(html).toContain('<meta property="og:title" content="Join a family on Shoo">');
    expect(html).toContain('<meta property="og:image" content="http://localhost:8787/og/invite.jpg">');
    expect(html).toContain('<meta name="twitter:card" content="summary_large_image">');
    const og = html.match(/<meta (?:property|name)="(?:og|twitter):[^>]*>/g)!;
    expect(og.length).toBeGreaterThanOrEqual(8);
    for (const tag of og) expect(tag).not.toContain("482193");
  });

  it("link preview in Indonesian for Accept-Language id, and also on the no-code page", async () => {
    expect((await page("/j/482193", "id")).html).toContain('<meta property="og:title" content="Bergabung ke keluarga di Shoo">');
    expect((await page("/j/12345")).html).toContain('<meta property="og:image" content="http://localhost:8787/og/invite.jpg">');
  });

  it("the old /join?code= page is gone (4-digit codes removed)", async () => {
    expect((await call("/join?code=4821")).status).toBe(404);
  });
});

describe("GET /og/invite.jpg", () => {
  it("serves the preview image, cacheable (no user data), under WhatsApp's 300 KB limit", async () => {
    const res = await call("/og/invite.jpg");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/jpeg");
    expect(res.headers.get("cache-control")).toBe("public, max-age=86400");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    const bytes = new Uint8Array(await res.arrayBuffer());
    expect([...bytes.slice(0, 3)]).toEqual([0xff, 0xd8, 0xff]);
    expect(bytes.length).toBeLessThan(300 * 1024);
  });
});

describe("storeUrl", () => {
  it("keeps https TestFlight and App Store links only", () => {
    expect(storeUrl("https://testflight.apple.com/join/AbCd1234")).toBe("https://testflight.apple.com/join/AbCd1234");
    expect(storeUrl("https://apps.apple.com/app/id123")).toBe("https://apps.apple.com/app/id123");
  });

  it.each([undefined, "", "not a url", "http://testflight.apple.com/join/x", "https://evil.example/", "javascript:alert(1)",
    "https://testflight.apple.com.evil.example/"])("falls back to apps.apple.com for %s", (v) => {
    expect(storeUrl(v)).toBe("https://apps.apple.com/");
  });
});
