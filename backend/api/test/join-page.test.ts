import { describe, expect, it } from "vitest";
import { call } from "./helpers/seed";

const page = async (q: string, lang?: string) => {
  const res = await call(`/join${q}`, { headers: lang ? { "accept-language": lang } : {} });
  return { res, html: await res.text() };
};

describe("GET /join", () => {
  it("valid code: shoo:// button and the code in large text, strict headers", async () => {
    const { res, html } = await page("?code=4821");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/^text\/html; charset=utf-8/i);
    expect(res.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(res.headers.get("content-security-policy")).toContain("style-src 'unsafe-inline'");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("referrer-policy")).toBe("no-referrer");
    expect(html).toContain('href="shoo://join?code=4821"');
    expect(html).toContain(">4821<");
    expect(html).toContain('lang="en"');
    expect(html).toContain("Open Shoo");
  });

  it("Indonesian for Accept-Language id", async () => {
    const { html } = await page("?code=4821", "id-ID,id;q=0.9,en;q=0.8");
    expect(html).toContain('lang="id"');
    expect(html).toContain("Belum punya Shoo?");
  });

  it.each([
    "?code=%3Cscript%3Ealert(1)%3C%2Fscript%3E",
    "?code=1234%22onclick%3D",
    "?code=12345",
    "?code=",
    "",
    "?code=1234&code=%3Cb%3E",
  ])("no code and no button for %s, input never reflected", async (q) => {
    const { res, html } = await page(q);
    expect(res.status).toBe(200);
    expect(html).not.toContain("shoo://");
    expect(html).not.toContain("<script");
    expect(html).not.toContain("onclick");
    expect(html).not.toContain("12345");
    expect(html).not.toContain("<b>");
  });

  it("does not reveal whether a code exists (no DB lookup)", async () => {
    const a = await page("?code=0000");
    const b = await page("?code=9999");
    expect(a.html.replaceAll("0000", "")).toBe(b.html.replaceAll("9999", ""));
  });
});
