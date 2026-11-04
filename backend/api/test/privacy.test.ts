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
    for (const s of ["14 days", "Delete account", "iPhone 15 · iOS 26", "numbers only, no addresses", "decisions", "No ads, no analytics, no tracking", "Cloudflare", "Supabase", "Apple", "1 day",
      "15 days", "never its text", "last used Shoo", "30 minutes", "not deleted automatically", "retried daily"]) {
      expect(html).toContain(s);
    }
    expect(html).not.toContain("<script");
  });

  it("discloses the AI layer 4 summary, the RDAP domain-age lookup and cache, what is never sent, and unknown retention (#97)", async () => {
    const en = await (await call("/privacy")).text();
    for (const s of ["third-party AI provider", "the page title", "form fields", "never send the page's text", "full web address",
      "anything you type", "your Shoo name", "can still contain what the site itself shows", "cannot guarantee how long", "5 November 2026",
      "public domain registry (RDAP)", "registration date, for up to 7 days", "Public domain registries (RDAP) receive",
      "Apart from the short domain-age cache"]) {
      expect(en).toContain(s);
    }
    const id = await (await call("/privacy?lang=id")).text();
    for (const s of ["penyedia AI pihak ketiga", "judul halaman", "kolom formulir", "tidak pernah mengirim isi teks halaman",
      "alamat web lengkap", "yang kamu ketik", "nama Shoo-mu", "tetap bisa berisi apa yang ditampilkan situs", "tidak bisa menjamin berapa lama",
      "5 November 2026", "registry domain publik (RDAP)", "maksimal 7 hari", "Registry domain publik (RDAP) menerima",
      "Selain cache umur domain singkat"]) {
      expect(id).toContain(s);
    }
    expect(en).not.toContain("or any name,");
    expect(en).not.toContain("not stored by us. We keep no other browsing history");
  });

  it("discloses the stored site icon: downloaded by our server, deleted with the page (PR-05)", async () => {
    const en = await (await call("/privacy")).text();
    for (const s of ["Site icons", "our server downloads it once", "never sees your IP address", "with their page copy, screenshot and site icon",
      "page copies, screenshots, site icons, decisions", "Page copy, screenshot and icon links stop working"]) {
      expect(en).toContain(s);
    }
    const id = await (await call("/privacy?lang=id")).text();
    for (const s of ["Ikon situs", "server kami mengunduhnya sekali", "tidak pernah melihat alamat IP-mu", "bersama salinan halaman, screenshot, dan ikon situsnya",
      "salinan halaman, screenshot, ikon situs, keputusan", "Link salinan halaman, screenshot, dan ikon langsung berhenti bekerja"]) {
      expect(id).toContain(s);
    }
  });

  it("discloses the page copy honestly: typed input removed, shown text copied, stored at Cloudflare R2 (EX-07, K17)", async () => {
    const en = await (await call("/privacy")).text();
    for (const s of ["Copy of the page", "a copy of the page", "What you typed into the page's fields is removed",
      "The text the page shows is copied, including text the site itself shows back", "Only you can open it, and your Guardian too while you are connected in a family",
      "14 days", "Cloudflare (runs our API and stores page copies and site icons in Cloudflare R2)",
      "Supabase (database, and storage of older screenshots and site icons"]) {
      expect(en).toContain(s);
    }
    // No overclaim: the copy is not "without what you typed" in general, and R2's location is only a hint.
    // Disconnect ends access at once; the copy itself goes with the scan (14 days or delete), say so (P13).
    // 5 Nov 2026: a copy is made without a family too, so the owner sees the evidence in Personal mode.
    expect(en).toContain("We make a copy with or without a family.");
    expect(en).not.toContain("We only make a copy while");
    expect(en).toContain("When you disconnect, your Guardian can no longer open it.");
    expect(en).not.toContain("We keep a copy only while");
    expect(en).not.toContain("without anything you typed");
    expect(en).toContain("in Cloudflare R2)");
    expect(en).not.toMatch(/R2[^)]*(Singapore|Asia|APAC|region)/);
    const id = await (await call("/privacy?lang=id")).text();
    for (const s of ["Salinan halaman", "salinan halaman", "Isian yang kamu ketik di kolom halaman dihapus",
      "Teks yang tampil di halaman ikut disalin, termasuk teks yang ditampilkan ulang oleh situs itu", "Hanya kamu yang bisa membukanya, dan Guardian-mu juga selama kamu terhubung dalam keluarga",
      "Cloudflare (menjalankan API kami dan menyimpan salinan halaman serta ikon situs di Cloudflare R2)",
      "Supabase (database, dan penyimpanan screenshot serta ikon situs lama",
      "Salinan dibuat dengan atau tanpa keluarga.", "Saat kamu memutus hubungan, Guardian-mu tidak bisa membukanya lagi."]) {
      expect(id).toContain(s);
    }
    expect(id).not.toContain("Salinan hanya disimpan selama");
  });

  it("discloses the admin dashboard: risky domains kept for good, learning labels, masked addresses, page copy for the team (ADM-02a, D7)", async () => {
    const en = await (await call("/privacy")).text();
    for (const s of ["Apart from the short domain-age cache, the list of risky website domains and the record of flagged pages described below, we keep no other browsing history.",
      "Risky website domains that Shoo flagged", "kept with counts and detection signals, to improve detection",
      "no link to you, your device or the page address, and are not deleted",
      "A few people on the Shoo team can see the address of pages Shoo flagged, without the part after",
      "without your device name",
      "A person on the Shoo team may view the copy of a page reported as a scam, without knowing whose device it came from.",
      "The copy can include text the page showed you.",
      "A copy used to improve detection (the domain, Safe or Not safe, Shoo's risk score for the page at that time",
      "cannot be traced back to your devices without our key", "is deleted when you disconnect or delete your data",
      "A person on the Shoo team can also view it once at least two families have reported the same website, without seeing which device it came from (logged)."]) {
      expect(en).toContain(s);
    }
    // Old R8 wording is false while learning labels keep a keyed code (owner_ref): never claim "without any link".
    expect(en).not.toContain("without any link to you or your device");
    expect(en).not.toContain("we keep no other browsing history, except");
    const id = await (await call("/privacy?lang=id")).text();
    for (const s of ["Selain cache umur domain singkat, daftar domain situs berisiko, dan catatan halaman yang ditandai yang dijelaskan di bawah, kami tidak menyimpan riwayat browsing lain.",
      "Domain situs berisiko yang ditandai Shoo", "disimpan bersama jumlah dan sinyal deteksinya, untuk memperbaiki deteksi",
      "tidak terkait denganmu, device-mu, atau alamat halaman, dan tidak dihapus",
      "Beberapa orang di tim Shoo dapat melihat alamat halaman yang ditandai Shoo, tanpa bagian setelah",
      "tanpa nama perangkatmu",
      "Tim Shoo dapat melihat salinan halaman yang dilaporkan sebagai penipuan, tanpa mengetahui dari perangkat siapa salinan itu berasal.",
      "Salinan bisa memuat teks yang ditampilkan halaman itu kepadamu.",
      "Salinan yang dipakai untuk memperbaiki deteksi (domain, Aman atau Tidak aman, skor risiko Shoo untuk halaman itu saat itu",
      "tidak bisa dilacak ke device kalian tanpa kunci kami", "dihapus saat kamu memutus hubungan atau menghapus datamu",
      "Seseorang di tim Shoo juga bisa melihatnya setelah minimal dua keluarga melaporkan situs yang sama, tanpa melihat dari perangkat mana salinan itu berasal (tercatat)."]) {
      expect(id).toContain(s);
    }
  });

  it("discloses the scan archive: flagged parts sent without a family, code instead of name, kept until deletion, stripped after (ADM-07, D-dash-17)", async () => {
    const en = await (await call("/privacy")).text();
    for (const s of ["the parts of the page that made Shoo flag it (for example a form that asks for an OTP), with the page's styling",
      "This is sent with or without a family.",
      "see a code instead of your name (for example \"User a3f9c2e1\")",
      "A record of each flagged page", "is kept to improve detection until you delete your data.",
      "that record loses every link to you", "the time is rounded to the hour",
      "kept only for sites shown to be a scam and are deleted for other sites",
      "When you disconnect, the Guardian's decisions in the record are removed.",
      "replaced with random characters",
      "The record of flagged pages loses its link to you at once"]) {
      expect(en).toContain(s);
    }
    // The archive keeps a keyed code while the account exists: never claim it has no link before deletion.
    expect(en).not.toContain("record of flagged pages has no link to you");
    const id = await (await call("/privacy?lang=id")).text();
    for (const s of ["bagian halaman yang membuat Shoo menandainya (misalnya formulir yang meminta OTP), beserta tampilan halamannya",
      "Ini dikirim baik kamu terhubung dalam keluarga maupun tidak.",
      "melihat kode, bukan namamu (misalnya \"User a3f9c2e1\")",
      "Catatan setiap halaman yang ditandai", "disimpan untuk memperbaiki deteksi sampai kamu menghapus datamu.",
      "catatan itu kehilangan semua kaitan denganmu", "waktunya dibulatkan ke jam",
      "hanya disimpan untuk situs yang terbukti penipuan dan dihapus untuk situs lain",
      "Saat kamu memutus hubungan, keputusan Guardian di catatan itu dihapus.",
      "diganti dengan karakter acak",
      "Catatan halaman yang ditandai langsung kehilangan kaitan denganmu"]) {
      expect(id).toContain(s);
    }
  });

  it("Indonesian by ?lang=id or Accept-Language", async () => {
    for (const res of [await call("/privacy?lang=id"), await call("/privacy", { headers: { "accept-language": "id-ID,id;q=0.9" } })]) {
      const html = await res.text();
      expect(html).toContain('<html lang="id">');
      expect(html).toContain("14 hari");
      expect(html).toContain("Hapus akun");
      expect(html).toContain("15 hari");
    }
    expect(await (await call("/privacy?lang=xx", { headers: { "accept-language": "id" } })).text()).toContain('lang="id"');
  });
});
