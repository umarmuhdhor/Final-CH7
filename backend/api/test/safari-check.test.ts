import { describe, expect, it } from "vitest";
import { call } from "./helpers/seed";

// ON-04 "Cek & lanjutkan": the page the app opens in the default browser (Figma 2497:4919, screen 8).

describe("GET /safari-check (ON-04)", () => {
  it("Indonesian: title, permission card, a link back to the app; static and locked down", async () => {
    const res = await call("/safari-check?lang=id");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    const csp = res.headers.get("content-security-policy") ?? "";
    expect(csp).toContain("default-src 'none'");
    expect(csp).toContain("img-src 'self'");
    const html = await res.text();
    expect(html).toContain('<html lang="id">');
    for (const s of [
      "Hampir selesai!",
      "Halaman ini terbuka di browser utamamu. Kalau ini Safari, Shoo sudah mengecek.",
      "Safari bertanya soal Shoo?",
      "Izinkan di Semua Situs Web",
      'Jangan pilih "Izinkan Satu Hari"',
      '<a class="btn" href="shoo://">Kembali ke Shoo</a>',
      'src="/safari-check/shoo.png"',
      '<meta name="robots" content="noindex">',
    ]) expect(html).toContain(s);
    expect(html).not.toContain("<script");
  });

  it("English with ?lang=en or Accept-Language; English by default", async () => {
    for (const res of [await call("/safari-check?lang=en"), await call("/safari-check")]) {
      const html = await res.text();
      expect(html).toContain('<html lang="en">');
      for (const s of ["Almost done!", "Is Safari asking about Shoo?", "Always Allow on Every Website", "Back to Shoo"]) expect(html).toContain(s);
    }
    const id = await (await call("/safari-check", { headers: { "accept-language": "id-ID,id;q=0.9" } })).text();
    expect(id).toContain("Kembali ke Shoo");
  });

  it("the mascot is a cacheable PNG", async () => {
    const res = await call("/safari-check/shoo.png");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/png");
    expect(res.headers.get("cache-control")).toBe("public, max-age=604800");
    expect([...new Uint8Array(await res.arrayBuffer()).slice(0, 4)]).toEqual([0x89, 0x50, 0x4e, 0x47]);
  });

  it("is not a Universal Link path, so iOS opens it in the browser, not in Shoo", async () => {
    const aasa = JSON.stringify(await (await call("/.well-known/apple-app-site-association")).json());
    expect(aasa).not.toContain("safari-check");
  });
});
