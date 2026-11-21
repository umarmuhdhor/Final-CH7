import { describe, expect, it } from "vitest";
import { call } from "./helpers/seed";

// Search: each legal page has a description, a canonical on shoo.ai.id for its own language, and hreflang
// links between the Indonesian and English copies (the bare path is the x-default).
describe("legal pages: description, canonical, hreflang", () => {
  for (const path of ["/privacy", "/support", "/terms"]) {
    it(`${path}: one canonical per language, both languages linked`, async () => {
      for (const lang of ["id", "en"] as const) {
        const html = await (await call(`${path}?lang=${lang}`)).text();
        expect(html).toMatch(/<meta name="description" content="[^"]{60,}">/);
        expect(html).toContain(`<link rel="canonical" href="https://shoo.ai.id${path}?lang=${lang}">`);
        expect(html).toContain(`<link rel="alternate" hreflang="id" href="https://shoo.ai.id${path}?lang=id">`);
        expect(html).toContain(`<link rel="alternate" hreflang="en" href="https://shoo.ai.id${path}?lang=en">`);
        expect(html).toContain(`<link rel="alternate" hreflang="x-default" href="https://shoo.ai.id${path}">`);
        expect(html).not.toContain("<script");
      }
    });
  }

  it("the bare path names the language it served as canonical", async () => {
    const html = await (await call("/privacy")).text();
    expect(html).toContain('<html lang="en">');
    expect(html).toContain('<link rel="canonical" href="https://shoo.ai.id/privacy?lang=en">');
  });
});
