import { Hono } from "hono";
import type { AppEnv } from "../env";

// Privacy policy (SECURITY §3 P12): what Shoo stores, for how long, and how to delete it.
// Static, no auth, no DB. Must match the backend: 14-day retention (src/cron/retention.ts),
// DELETE /devices/me, verdicts deleted on disconnect (D-alief-B10), push_log without text (B11).

// TODO(sync:alief): team contact address — replace before external TestFlight / App Store (TODO E).
const CONTACT = "the Shoo team (contact address coming before public release)";

type Section = { h: string; items: string[] };
const TEXT: Record<"en" | "id", { title: string; updated: string; lead: string; sections: Section[] }> = {
  en: {
    title: "Shoo privacy policy",
    updated: "Last updated: 22 October 2026",
    lead: "Shoo blocks scam websites on iPhone and lets a family member (the Guardian) help. We keep as little as we can, only to make that work.",
    sections: [
      { h: "What we store", items: [
        "The first name you choose and a random avatar. No email, phone number or account password.",
        "A random device ID, and an Apple push token if you allow notifications.",
        "Pages the extension flagged as risky (score 30 or more): address, domain, page title, site icon, score, the reasons, the time, and an optional screenshot of the page.",
        "Who is connected to whom in a family, and the Guardian's decisions about a site (Safe or Not safe), with the Guardian's name.",
      ] },
      { h: "What we do not do", items: [
        "No ads, no analytics, no tracking, and we never sell data.",
        "Pages scored below 30 may be analysed but are not stored. We keep no other browsing history.",
      ] },
      { h: "Who can see it", items: [
        "You, and your Guardian while you are connected. When you disconnect, your Guardian loses access at once and their decisions about your sites are deleted.",
      ] },
      { h: "How long we keep it", items: [
        "Flagged pages and screenshots are deleted automatically after 14 days.",
        "A Guardian's decisions stay until you disconnect or delete your data.",
        "A domain that a person on our team reviewed and confirmed as a scam joins a shared blocklist for every user. Only the domain is kept, with no link to you.",
        "Security counters (a keyed hash of your IP address or device, never the address itself) are deleted after 1 day.",
      ] },
      { h: "Delete your data", items: [
        "In the app: Profile → Delete my data. Your device, flagged pages, screenshots, decisions and family links are deleted immediately. Screenshot links stop working at once.",
      ] },
      { h: "Service providers", items: [
        "Cloudflare (runs our API), Supabase (database and screenshot storage, Singapore region) and Apple (push notifications). They process data only to provide these services.",
      ] },
      { h: "Contact", items: [`Questions: ${CONTACT}.`] },
    ],
  },
  id: {
    title: "Kebijakan privasi Shoo",
    updated: "Terakhir diperbarui: 22 Oktober 2026",
    lead: "Shoo memblokir situs penipuan di iPhone dan membiarkan anggota keluarga (Guardian) membantu. Kami menyimpan sesedikit mungkin, hanya supaya itu berjalan.",
    sections: [
      { h: "Yang kami simpan", items: [
        "Nama depan pilihanmu dan avatar acak. Tanpa email, nomor HP, atau kata sandi akun.",
        "ID device acak, dan token push Apple kalau kamu mengizinkan notifikasi.",
        "Halaman yang ditandai berisiko oleh extension (skor 30 atau lebih): alamat, domain, judul halaman, ikon situs, skor, alasannya, waktu, dan screenshot halaman (opsional).",
        "Siapa terhubung dengan siapa dalam keluarga, dan keputusan Guardian tentang suatu situs (Aman atau Tidak aman) beserta nama Guardian.",
      ] },
      { h: "Yang tidak kami lakukan", items: [
        "Tanpa iklan, tanpa analytics, tanpa pelacakan, dan kami tidak pernah menjual data.",
        "Halaman dengan skor di bawah 30 bisa dianalisis tetapi tidak disimpan. Kami tidak menyimpan riwayat browsing lain.",
      ] },
      { h: "Siapa yang bisa melihat", items: [
        "Kamu, dan Guardian-mu selama kalian terhubung. Saat kamu memutus hubungan, Guardian langsung kehilangan akses dan keputusannya tentang situs-situsmu dihapus.",
      ] },
      { h: "Berapa lama disimpan", items: [
        "Halaman yang ditandai dan screenshot dihapus otomatis setelah 14 hari.",
        "Keputusan Guardian disimpan sampai kamu memutus hubungan atau menghapus datamu.",
        "Domain yang sudah diperiksa tim kami dan dipastikan penipuan masuk ke daftar blokir bersama untuk semua pengguna. Hanya domainnya yang disimpan, tanpa kaitan denganmu.",
        "Penghitung keamanan (hash berkunci dari alamat IP atau device, tidak pernah alamatnya sendiri) dihapus setelah 1 hari.",
      ] },
      { h: "Hapus datamu", items: [
        "Di app: Profil → Hapus dataku. Device, halaman yang ditandai, screenshot, keputusan, dan hubungan keluarga dihapus seketika. Link screenshot langsung berhenti bekerja.",
      ] },
      { h: "Penyedia layanan", items: [
        "Cloudflare (menjalankan API kami), Supabase (database dan penyimpanan screenshot, region Singapura), dan Apple (notifikasi push). Mereka memproses data hanya untuk menyediakan layanan itu.",
      ] },
      { h: "Kontak", items: [`Pertanyaan: ${CONTACT}.`] },
    ],
  },
};

const CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const STYLE = `body{font:17px/1.5 -apple-system,system-ui,sans-serif;margin:0;padding:32px 20px;color:#111;background:#fff}
main{max-width:640px;margin:0 auto}h2{font-size:20px;margin-top:28px}li{margin:6px 0}.muted{color:#666}
@media (prefers-color-scheme:dark){body{color:#f2f2f2;background:#000}.muted{color:#aaa}}`;

export const privacy = new Hono<AppEnv>();

privacy.get("/privacy", (c) => {
  const q = c.req.query("lang");
  const lang = q === "id" || q === "en" ? q : /^id\b/i.test(c.req.header("accept-language") ?? "") ? "id" : "en";
  const t = TEXT[lang];
  const sections = t.sections
    .map((s) => `<h2>${s.h}</h2><ul>${s.items.map((i) => `<li>${i}</li>`).join("")}</ul>`)
    .join("\n");
  const html = `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${t.title}</title>
<style>${STYLE}</style></head><body><main><h1>${t.title}</h1><p class="muted">${t.updated}</p>
<p>${t.lead}</p>${sections}
<p class="muted"><a href="?lang=${lang === "en" ? "id" : "en"}">${lang === "en" ? "Bahasa Indonesia" : "English"}</a></p></main></body></html>`;
  c.header("Content-Security-Policy", CSP);
  return c.html(html);
});
