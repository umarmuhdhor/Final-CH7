import { describe, expect, it } from "vitest";
import { call } from "./helpers/seed";

describe("GET /privacy (SECURITY §3 P12)", () => {
  it("English by default: retention, deletion, verdicts, no tracking, processors", async () => {
    const res = await call("/privacy");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    const html = await res.text();
    expect(html).toContain('<html lang="en">');
    for (const s of ["14 days", "Delete my data", "decisions", "No ads, no analytics, no tracking", "Cloudflare", "Supabase", "Apple", "1 day",
      "15 days", "never its text", "last used Shoo", "60 seconds", "retried daily"]) {
      expect(html).toContain(s);
    }
    expect(html).not.toContain("<script");
  });

  it("discloses the AI layer 4 summary to a third party, what is never sent, and unknown retention (#97)", async () => {
    const en = await (await call("/privacy")).text();
    for (const s of ["third-party AI provider", "the page title", "form fields", "never send the page's text", "full web address",
      "anything you type", "device ID", "cannot guarantee how long", "25 October 2026"]) {
      expect(en).toContain(s);
    }
    const id = await (await call("/privacy?lang=id")).text();
    for (const s of ["penyedia AI pihak ketiga", "judul halaman", "kolom formulir", "tidak pernah mengirim isi teks halaman",
      "alamat web lengkap", "yang kamu ketik", "ID device", "tidak bisa menjamin berapa lama", "25 Oktober 2026"]) {
      expect(id).toContain(s);
    }
  });

  it("Indonesian by ?lang=id or Accept-Language", async () => {
    for (const res of [await call("/privacy?lang=id"), await call("/privacy", { headers: { "accept-language": "id-ID,id;q=0.9" } })]) {
      const html = await res.text();
      expect(html).toContain('<html lang="id">');
      expect(html).toContain("14 hari");
      expect(html).toContain("Hapus dataku");
      expect(html).toContain("15 hari");
    }
    expect(await (await call("/privacy?lang=xx", { headers: { "accept-language": "id" } })).text()).toContain('lang="id"');
  });
});
