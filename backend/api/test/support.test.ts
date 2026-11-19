import { describe, expect, it } from "vitest";
import { CONTACT } from "../src/routes/privacy";
import { call } from "./helpers/seed";

// Fase 24c-1 (E6): the Support URL for App Store Connect. Static like /privacy and /terms.

describe("GET /support (E6, fase 24c-1)", () => {
  it("English by default: contact, how to delete everything, links to privacy and terms; same headers as /privacy", async () => {
    const res = await call("/support");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    const html = await res.text();
    expect(html).toContain('<html lang="en">');
    for (const s of [CONTACT, "Profile › Delete account", "tap Disconnect", "ask your Guardian to disconnect you", "disconnects them first", 'href="/privacy?lang=en"', 'href="/terms?lang=en"', "Shoo support"]) {
      expect(html).toContain(s);
    }
    expect(html).not.toContain("<script");
  });

  it("Indonesian with ?lang=id or Accept-Language id", async () => {
    for (const res of [await call("/support?lang=id"), await call("/support", { headers: { "accept-language": "id-ID,id;q=0.9" } })]) {
      const html = await res.text();
      expect(html).toContain('<html lang="id">');
      for (const s of [CONTACT, "Profil › Hapus akun", "ketuk Putuskan koneksi", "minta Guardian memutuskan koneksi", 'href="/privacy?lang=id"', "Bantuan Shoo"]) expect(html).toContain(s);
    }
  });

  it("App Store 1.1 help: the 1.1 flow (Personal first, Guardian from Profile, 6-digit code) and an optional online check", async () => {
    const en = await (await call("/support?lang=en")).text();
    for (const s of ["Getting started", "Modes and family", "Warnings and blocks", "Common problems", "Profile › Account mode", "6-digit invite code", "works for 30 minutes", "up to 3", "30% or more: Shoo shows a warning", "80% or more: the page is blocked", "DeepSeek", "iasc.ojk.go.id"]) {
      expect(en).toContain(s);
    }
    const id = await (await call("/support?lang=id")).text();
    for (const s of ["Memulai", "Mode dan keluarga", "Peringatan dan blokir", "Masalah umum", "Profil › Mode akun", "kode undangan 6 angka", "berlaku 30 menit", "maksimal melindungi 3 orang", "80% ke atas: halaman diblokir", "DeepSeek", "iasc.ojk.go.id"]) {
      expect(id).toContain(s);
    }
    // Guideline 5.1.1(iv): the steps don't make the online check a condition for turning Shoo on.
    expect(id).toContain("Di layar Aktifkan Ekstensi, ketuk Nyalakan.</li>");
    expect(id).toContain("Tanpa centang, halaman hanya dicek di iPhone-mu");
    expect(en).toContain("Without it, pages are checked on your iPhone only");
    // Every link stays on the page's own host (relative), so shoo.ai.id/support keeps the reader on shoo.ai.id.
    for (const html of [en, id]) expect(html).not.toMatch(/workers\.dev/);
  });

  it("the contact is the same on /support and /privacy (one constant, swapped once the team mailbox exists)", async () => {
    expect(await (await call("/privacy")).text()).toContain(CONTACT);
  });
});
