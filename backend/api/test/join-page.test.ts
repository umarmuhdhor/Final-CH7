import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { app } from "../src/app";
import { storeUrl } from "../src/routes/join-page";
import { call } from "./helpers/seed";

const page = async (path: string, lang?: string) => {
  const res = await call(path, { headers: lang ? { "accept-language": lang } : {} });
  return { res, html: await res.text() };
};

const nonceOf = (res: Response) => /script-src 'nonce-([A-Za-z0-9_-]+)'/.exec(res.headers.get("content-security-policy") ?? "")?.[1];

describe("GET /j/:code", () => {
  it("valid code: shoo:// button and the code in six boxes, strict headers", async () => {
    const { res, html } = await page("/j/482193");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/^text\/html; charset=utf-8/i);
    const csp = res.headers.get("content-security-policy")!;
    expect(csp).toContain("default-src 'none'");
    expect(csp).toContain("style-src 'unsafe-inline'");
    expect(csp).not.toContain("unsafe-eval");
    expect(csp).not.toMatch(/script-src[^;]*unsafe-inline/);
    expect(csp).toContain("img-src 'self'");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(html).toContain('href="shoo://join?code=482193"');
    expect(html).toContain(">482193<");
    expect([...html.matchAll(/class="digit">(\d)</g)].map((m) => m[1]).join("")).toBe("482193");
    expect(html).toContain('lang="en"');
    expect(html).toContain("Open in the Shoo app");
    expect(html).toContain('src="/og/join-hero.png"');
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
    expect(html).toContain('id="copy" class="copy" type="button" data-code="482193"');
    expect(html).not.toMatch(/fetch\(|XMLHttpRequest|sendBeacon|document\.cookie|localStorage/);
  });

  it("a new nonce on every request", async () => {
    const a = nonceOf((await page("/j/482193")).res);
    const b = nonceOf((await page("/j/482193")).res);
    expect(a).not.toBe(b);
  });

  it("the install hint says to open the link again, not to tap Paste (26a cancelled), in English and Indonesian", async () => {
    const { html: en } = await page("/j/482193");
    expect(en).toContain("We copy the invite link. After installing, open it again to join.");
    expect(en).not.toContain("tap Paste");
    const { html: id } = await page("/j/482193", "id-ID,id;q=0.9");
    expect(id).toContain("Link undangan sudah kami salin. Setelah install, buka lagi link itu untuk bergabung.");
    expect(id).not.toContain("Tempel");
  });

  it("Install goes to APP_STORE_URL when it is a TestFlight link (fase 26 Q1, var not set yet)", async () => {
    const link = "https://testflight.apple.com/join/AbCd1234";
    const ctx = createExecutionContext();
    const res = await app.fetch(
      new Request("http://api.test/j/482193", { headers: { "cf-connecting-ip": "198.51.100.77" } }),
      { ...env, APP_STORE_URL: link },
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    expect(await res.text()).toContain(`id="install" href="${link}"`);
  });

  it("Indonesian for Accept-Language id", async () => {
    const { html } = await page("/j/482193", "id-ID,id;q=0.9,en;q=0.8");
    expect(html).toContain('lang="id"');
    expect(html).toContain("Belum punya Shoo?");
    expect(html).toContain("Buka di app Shoo");
    expect(html).toContain("Salin kode");
    expect(html).toContain("Berlaku maks. 30 menit");
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
    const strip = (html: string) => html.replace(/nonce="[^"]+"/, "").replace(/class="digit">\d</g, 'class="digit"><');
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

describe("GET /og/join-hero.png", () => {
  it("serves the page hero as a cacheable PNG (no user data)", async () => {
    const res = await call("/og/join-hero.png");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/png");
    expect(res.headers.get("cache-control")).toBe("public, max-age=86400");
    const bytes = new Uint8Array(await res.arrayBuffer());
    expect([...bytes.slice(0, 4)]).toEqual([0x89, 0x50, 0x4e, 0x47]);
    expect(bytes.length).toBeLessThan(100 * 1024);
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
