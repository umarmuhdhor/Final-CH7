import { describe, expect, it } from "vitest";
import { call } from "./helpers/seed";

// Shoo's own icons (Figma "LOGO FIX" 227:3954) for the browser tab and the iPhone home screen.
// Static, no user data, so browsers and CDNs may cache them.
describe("site icons", () => {
  it.each([
    ["/favicon.ico", "image/x-icon", [0x00, 0x00, 0x01, 0x00]],
    ["/icon-192.png", "image/png", [0x89, 0x50, 0x4e, 0x47]],
    ["/apple-touch-icon.png", "image/png", [0x89, 0x50, 0x4e, 0x47]],
  ])("serves %s as a cacheable %s", async (path, type, magic) => {
    const res = await call(path);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe(type);
    expect(res.headers.get("cache-control")).toBe("public, max-age=604800");
    const bytes = new Uint8Array(await res.arrayBuffer());
    expect([...bytes.slice(0, 4)]).toEqual(magic);
  });

  it.each(["/privacy", "/terms", "/support", "/j/482193"])("%s links the icons and allows them in its CSP", async (path) => {
    const res = await call(path);
    const html = await res.text();
    expect(html).toContain('<link rel="icon" href="/favicon.ico" sizes="48x48">');
    expect(html).toContain('<link rel="icon" href="/icon-192.png" type="image/png" sizes="192x192">');
    expect(html).toContain('<link rel="apple-touch-icon" href="/apple-touch-icon.png">');
    expect(res.headers.get("content-security-policy")).toMatch(/img-src 'self'/);
  });
});
