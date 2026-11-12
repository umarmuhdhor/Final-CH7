import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { app } from "../src/app";
import { limits } from "../src/http/rateLimit";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
import { JOIN_MAX_FAILURES_IP } from "../src/db/repo/joinAttempts";
import { storeUrl } from "../src/routes/join-page";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";

const sql = testSql();

const page = async (path: string, lang?: string, ip?: string) => {
  const res = await call(path, { headers: lang ? { "accept-language": lang } : {}, ip });
  return { res, html: await res.text() };
};

const addCode = async (code: string, expiresIn: string) => {
  const g = await createDevice("Mom", "guardian");
  await sql`insert into family_codes (code, guardian_id, expires_at) values (${code}, ${g.deviceId}, now() + ${expiresIn}::interval)`;
};

// 482193 is an active code in every test; the page looks codes up (state audit row 7, Figma 1619:7334).
beforeEach(async () => {
  await resetDb(sql);
  await addCode("482193", "30 minutes");
});

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
    expect(html).toContain('<main class="enter">');
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
  ])("invalid page for %s: no join link, input never reflected, only the nonce'd script", async (path) => {
    const { res, html } = await page(path);
    expect(res.status).toBe(200);
    expect(html).not.toContain("shoo://");
    expect(html).not.toContain("onclick");
    expect(html).not.toContain("12345");
    expect(html).not.toContain("4821");
    expect(html).not.toContain("<script>");
    expect(html.match(/<script/g)).toHaveLength(1);
    expect(html).toContain(`<script nonce="${nonceOf(res)}">`);
    expect(html).toContain("no valid code");
    expect(html).not.toContain('class="hero"');
  });

  const strip = (html: string) => html.replace(/nonce="[^"]+"/g, "");

  it.each([
    ["unknown", "/j/000000"],
    ["expired", "/j/111111"],
  ])("%s 6-digit code: the same invalid page as a malformed code, code not echoed", async (_, path) => {
    await addCode("111111", "-1 minute");
    const { html } = await page(path);
    expect(html).not.toContain("shoo://");
    expect(html).not.toContain(path.slice(3));
    expect(strip(html)).toBe(strip((await page("/j/12ab")).html));
  });

  it("Indonesian invalid page matches Figma 1619:7334: badge, copy, a real Minta kode baru button, Unduh", async () => {
    const { html } = await page("/j/000000", "id-ID,id;q=0.9");
    expect(html).toContain('<main class="enter invalid">');
    expect(html).toContain('<div class="badge" aria-hidden="true"><span>!</span></div>');
    expect(html).toContain("<h1>Bergabung ke keluarga di Shoo</h1>");
    expect(html).toContain("Link undangan ini tidak berisi kode yang valid.<");
    expect(html).toMatch(/<button id="request" class="btn" type="button" data-msg="[^"]+" data-label="Minta kode baru" data-done="Pesan tersalin">Minta kode baru<\/button>/);
    expect(html).toContain('Belum punya Shoo?<a href="https://apps.apple.com/">Unduh</a>');
    expect(html).toContain("navigator.share");
    expect(html).not.toMatch(/fetch\(|XMLHttpRequest|sendBeacon|document\.cookie|localStorage/);
  });

  it("a miss is a failed join attempt of the IP (no device); a hit records nothing and never changes the code", async () => {
    await page("/j/000000", undefined, "203.0.113.7");
    await page("/j/482193", undefined, "203.0.113.7");
    const rows = await sql<{ device_id: string | null; success: boolean }[]>`select device_id, success from join_attempts`;
    expect(rows).toEqual([{ device_id: null, success: false }]);
    expect(await sql`select code from family_codes where code = '482193'`).toHaveLength(1);
  });

  it("page and POST /family/join share one per-IP budget: page misses block joins from that IP", async () => {
    const ip = "203.0.113.9";
    for (let i = 0; i < JOIN_MAX_FAILURES_IP; i++) expect((await page("/j/000000", undefined, ip)).html).not.toContain("shoo://");
    // Budget used: the page no longer looks codes up (no oracle), it shows the normal invite.
    const { res, html } = await page("/j/000000", undefined, ip);
    expect(res.status).toBe(200);
    expect(html).toContain('href="shoo://join?code=000000"');
    const p = await createDevice("Kid", "protected");
    const join = await call("/family/join", { method: "POST", token: p.token, ip, json: { code: "482193" } });
    expect(join.status).toBe(429);
    // Another IP still gets the real answer.
    expect((await page("/j/000000")).html).not.toContain("shoo://");
  });

  it("over the global cap the page skips the lookup for everyone", async () => {
    useRateKeySecret(env.RATE_KEY_SECRET);
    const key = await keyHash(`${limits.joinPageAll.bucket}:all`);
    await sql`insert into rate_limit_hits (bucket, key_hash) select ${limits.joinPageAll.bucket}, ${key} from generate_series(1, ${limits.joinPageAll.max})`;
    expect((await page("/j/000000")).html).toContain('href="shoo://join?code=000000"');
    expect(await sql`select 1 from join_attempts`).toHaveLength(0);
  });

  it("motion: entrance, badge attention and press feedback, all off under prefers-reduced-motion", async () => {
    const { html } = await page("/j/000000");
    expect(html).toContain("@keyframes rise{from{opacity:0;transform:translateY(8px)}");
    expect(html).toContain(".enter>*{animation:rise .3s");
    expect(html).toContain(".btn:active{transform:scale(.97)");
    const reduced = /@media \(prefers-reduced-motion:reduce\)\{([^@]*)\}/.exec(html)![1]!;
    for (const sel of [".enter>*", ".badge", ".badge::after", ".badge span", ".hero i"]) expect(reduced).toContain(sel);
    expect(reduced).toContain(".btn:active,.copy:active{transform:none}");
    // Same specificity: the reduced-motion block must come after the press rule to win.
    expect(html.indexOf("@media (prefers-reduced-motion:reduce)")).toBeGreaterThan(html.indexOf(".btn:active{transform:scale(.97)"));
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
