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
    for (const s of [CONTACT, "Profile → Delete account", "tap Disconnect", "ask your Guardian to disconnect you", "disconnects them first", 'href="/privacy?lang=en"', 'href="/terms?lang=en"', "Shoo support"]) {
      expect(html).toContain(s);
    }
    expect(html).not.toContain("<script");
  });

  it("Indonesian with ?lang=id or Accept-Language id", async () => {
    for (const res of [await call("/support?lang=id"), await call("/support", { headers: { "accept-language": "id-ID,id;q=0.9" } })]) {
      const html = await res.text();
      expect(html).toContain('<html lang="id">');
      for (const s of [CONTACT, "Profil → Hapus akun", "ketuk Putuskan koneksi", "minta Guardian memutuskan koneksi", 'href="/privacy?lang=id"', "Bantuan Shoo"]) expect(html).toContain(s);
    }
  });

  it("the contact is the same on /support and /privacy (one constant, swapped once the team mailbox exists)", async () => {
    expect(await (await call("/privacy")).text()).toContain(CONTACT);
  });
});
