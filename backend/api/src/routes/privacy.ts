import { Hono, type Context } from "hono";
import type { AppEnv } from "../env";

// Privacy policy (SECURITY §3 P12): what Shoo stores, for how long, and how to delete it.
// Static, no auth, no DB. Must match the backend: 14-day retention (src/cron/retention.ts),
// DELETE /devices/me, verdicts deleted on disconnect (D-alief-B10), push_log without text (B11),
// dedupe reuse bounded to 15 days and storage tombstones (D-alief-B12), and what AI layer 4 sends to a
// third-party LLM provider (ai/src/layer4/reality.js buildInput, issue #97), and the RDAP domain-age lookup with its
// 7-day KV cache of domain + registration date (ai/src/rdap/, D-imelda-40).

// TODO(sync:alief): team contact address — replace before external TestFlight / App Store (TODO E).
const CONTACT = "the Shoo team (contact address coming before public release)";

type Section = { h: string; items: string[] };
const TEXT: Record<"en" | "id", LegalText> = {
  en: {
    title: "Shoo privacy policy",
    updated: "Last updated: 29 October 2026",
    lead: "Shoo blocks scam websites on iPhone and lets a family member (the Guardian) help. We keep as little as we can, only to make that work.",
    sections: [
      { h: "What we store", items: [
        "The first name you choose and your avatar. No email, phone number or account password.",
        "A random device ID, and an Apple push token if you allow notifications.",
        "When your device last used Shoo, so your Guardian can see whether protection is on.",
        "Your iPhone or iPad model and main iOS version (for example \"iPhone 15 · iOS 26\"), shown only to your Guardian.",
        "How many sites Shoo has blocked or warned you about in total: numbers only, no addresses.",
        "Your notification choices, quiet hours and your phone's time zone (for example \"Asia/Jakarta\"), so pushes respect them.",
        "Pages the extension flagged as risky (score 30 or more): address, domain, page title, site icon, score, the reasons, the time, and a copy of the page (older app versions sent a screenshot instead).",
        "Who is connected to whom in a family, and the Guardian's decisions about a site (Safe or Not safe), with the Guardian's name.",
      ] },
      { h: "What we do not do", items: [
        "No ads, no analytics, no tracking, and we never sell data.",
        "Pages scored below 30 may be analysed but are not stored by us. Apart from the short domain-age cache described below, we keep no other browsing history.",
      ] },
      { h: "Who can see it", items: [
        "You, and your Guardian while you are connected. When you disconnect, your Guardian loses access at once and their decisions about your sites are deleted.",
      ] },
      { h: "How long we keep it", items: [
        "Flagged pages are deleted automatically after 14 days, with their page copy, screenshot and site icon. A page copy, screenshot or icon reused for repeat visits to the same site within a day goes with the last of them, at most 15 days after it was taken.",
        "A note that a notification was sent (time and result, never its text) is deleted after 14 days.",
        "Family codes stop working after 30 minutes, or as soon as a new one is made, and are deleted within a day.",
        "Your device's name, avatar and push token stay until you delete your data in the app. Devices that stop using Shoo are not deleted automatically yet.",
        "A Guardian's decisions stay until you disconnect or delete your data.",
        "A domain that a person on our team reviewed and confirmed as a scam joins a shared blocklist for every user. Only the domain is kept, with no link to you.",
        "Security counters (a keyed hash of your IP address or device, never the address itself) are deleted after 1 day.",
      ] },
      { h: "Delete your data", items: [
        "In the app: Profile → Delete account. Your device, flagged pages, page copies, screenshots, site icons, decisions and family links are deleted immediately. Page copy, screenshot and icon links stop working at once, and the files are removed from storage right after (retried daily if storage is unreachable).",
      ] },
      { h: "Copy of the page", items: [
        "When the extension blocks a page or warns you about it, it keeps a copy of the page as you saw it, so your Guardian can see what the page looked like. The copy has no scripts and loads nothing from the internet.",
        "What you typed into the page's fields is removed before the copy is made. The text the page shows is copied, including text the site itself shows back (for example your name or email on a page where you are logged in), and this can include a page wrongly flagged as risky.",
        "We only make a copy while you are connected in a family, and only your Guardian and you can open it. When you disconnect, your Guardian can no longer open it. It is deleted with the flagged page after 14 days, or right away when you delete your data.",
      ] },
      { h: "Site icons", items: [
        "To show a flagged site's icon, our server downloads it once from that site and stores a copy with the flagged page. Your phone only ever loads the copy from our server, so the site never sees your IP address. The site sees a request from our server, with no cookies and nothing about you.",
      ] },
      { h: "Site age check", items: [
        "To check how old a site is, our server asks the public domain registry (RDAP) about the site's domain. We keep only the domain name and its registration date, for up to 7 days, not linked to you or your device.",
      ] },
      { h: "AI check of suspicious pages", items: [
        "When a page already looks suspicious and has a form, Shoo's server may send a small summary of it to a third-party AI provider, to check whether the data the page asks for fits that kind of page.",
        "The summary is only: the site's domain (for example bank-prize.xyz, without the rest of the address), the page title, the names of up to 12 form fields (for example \"OTP\" or \"card number\") with their type (such as text or password), and which of our own checks fired. Emails and runs of 4 or more digits in the title and field names are hidden first.",
        "We never send the page's text, the full web address, anything you type, or your Shoo name, device ID or token. The page title can still contain what the site itself shows, such as a name. The request comes from our server, so the provider does not see your IP address. We do not store the request or the answer.",
        "We cannot guarantee how long the AI provider keeps this summary.",
      ] },
      { h: "Service providers", items: [
        "Cloudflare (runs our API and stores page copies and site icons in Cloudflare R2), Supabase (database, and storage of older screenshots and site icons, Singapore region) and Apple (push notifications). They process data only to provide these services.",
        "Public domain registries (RDAP) receive the domain of a site we check, to tell us when it was registered.",
        "A third-party AI provider receives the page summary described above.",
      ] },
      { h: "Contact", items: [`Questions: ${CONTACT}.`] },
    ],
  },
  id: {
    title: "Kebijakan privasi Shoo",
    updated: "Terakhir diperbarui: 29 Oktober 2026",
    lead: "Shoo memblokir situs penipuan di iPhone dan membiarkan anggota keluarga (Guardian) membantu. Kami menyimpan sesedikit mungkin, hanya supaya itu berjalan.",
    sections: [
      { h: "Yang kami simpan", items: [
        "Nama depan pilihanmu dan avatarmu. Tanpa email, nomor HP, atau kata sandi akun.",
        "ID device acak, dan token push Apple kalau kamu mengizinkan notifikasi.",
        "Kapan device-mu terakhir memakai Shoo, supaya Guardian bisa melihat apakah perlindungan aktif.",
        "Model iPhone atau iPad dan versi utama iOS-mu (misalnya \"iPhone 15 · iOS 26\"), hanya terlihat oleh Guardian-mu.",
        "Berapa banyak situs yang pernah diblokir atau diberi peringatan oleh Shoo: hanya angka, tanpa alamat.",
        "Pilihan notifikasimu, jam tenang, dan zona waktu ponselmu (misalnya \"Asia/Jakarta\"), supaya push mengikutinya.",
        "Halaman yang ditandai berisiko oleh extension (skor 30 atau lebih): alamat, domain, judul halaman, ikon situs, skor, alasannya, waktu, dan salinan halaman (versi app lama mengirim screenshot).",
        "Siapa terhubung dengan siapa dalam keluarga, dan keputusan Guardian tentang suatu situs (Aman atau Tidak aman) beserta nama Guardian.",
      ] },
      { h: "Yang tidak kami lakukan", items: [
        "Tanpa iklan, tanpa analytics, tanpa pelacakan, dan kami tidak pernah menjual data.",
        "Halaman dengan skor di bawah 30 bisa dianalisis tetapi tidak kami simpan. Selain cache umur domain singkat yang dijelaskan di bawah, kami tidak menyimpan riwayat browsing lain.",
      ] },
      { h: "Siapa yang bisa melihat", items: [
        "Kamu, dan Guardian-mu selama kalian terhubung. Saat kamu memutus hubungan, Guardian langsung kehilangan akses dan keputusannya tentang situs-situsmu dihapus.",
      ] },
      { h: "Berapa lama disimpan", items: [
        "Halaman yang ditandai dihapus otomatis setelah 14 hari, bersama salinan halaman, screenshot, dan ikon situsnya. Salinan halaman, screenshot, atau ikon yang dipakai ulang untuk kunjungan berulang ke situs yang sama dalam sehari ikut terhapus bersama yang terakhir, paling lambat 15 hari setelah diambil.",
        "Catatan bahwa notifikasi terkirim (waktu dan hasil, tidak pernah isinya) dihapus setelah 14 hari.",
        "Kode keluarga berhenti berlaku setelah 30 menit, atau begitu kode baru dibuat, dan dihapus dalam sehari.",
        "Nama, avatar, dan token push device-mu disimpan sampai kamu menghapus datamu di app. Device yang berhenti memakai Shoo belum dihapus otomatis.",
        "Keputusan Guardian disimpan sampai kamu memutus hubungan atau menghapus datamu.",
        "Domain yang sudah diperiksa tim kami dan dipastikan penipuan masuk ke daftar blokir bersama untuk semua pengguna. Hanya domainnya yang disimpan, tanpa kaitan denganmu.",
        "Penghitung keamanan (hash berkunci dari alamat IP atau device, tidak pernah alamatnya sendiri) dihapus setelah 1 hari.",
      ] },
      { h: "Hapus datamu", items: [
        "Di app: Profil → Hapus akun. Device, halaman yang ditandai, salinan halaman, screenshot, ikon situs, keputusan, dan hubungan keluarga dihapus seketika. Link salinan halaman, screenshot, dan ikon langsung berhenti bekerja, dan filenya dihapus dari penyimpanan sesaat kemudian (dicoba ulang setiap hari kalau penyimpanan tidak bisa dihubungi).",
      ] },
      { h: "Salinan halaman", items: [
        "Saat extension memblokir halaman atau memberi peringatan, extension menyimpan salinan halaman seperti yang kamu lihat, supaya Guardian bisa melihat tampilan halaman itu. Salinan ini tanpa script dan tidak memuat apa pun dari internet.",
        "Isian yang kamu ketik di kolom halaman dihapus sebelum salinan dibuat. Teks yang tampil di halaman ikut disalin, termasuk teks yang ditampilkan ulang oleh situs itu (misalnya nama atau emailmu di halaman tempat kamu sedang login), dan ini bisa termasuk halaman yang keliru ditandai berisiko.",
        "Salinan hanya dibuat selama kamu terhubung dalam keluarga, dan hanya Guardian-mu dan kamu yang bisa membukanya. Saat kamu memutus hubungan, Guardian-mu tidak bisa membukanya lagi. Salinan dihapus bersama halaman yang ditandai setelah 14 hari, atau seketika saat kamu menghapus datamu.",
      ] },
      { h: "Ikon situs", items: [
        "Untuk menampilkan ikon situs yang ditandai, server kami mengunduhnya sekali dari situs itu dan menyimpan salinannya bersama halaman yang ditandai. HP-mu hanya memuat salinan itu dari server kami, jadi situs itu tidak pernah melihat alamat IP-mu. Situs itu hanya melihat permintaan dari server kami, tanpa cookie dan tanpa apa pun tentang kamu.",
      ] },
      { h: "Pemeriksaan umur situs", items: [
        "Untuk memeriksa umur sebuah situs, server kami bertanya ke registry domain publik (RDAP) tentang domain situs itu. Kami hanya menyimpan nama domain dan tanggal registrasinya, maksimal 7 hari, tidak terhubung ke kamu atau device-mu.",
      ] },
      { h: "Pemeriksaan AI untuk halaman mencurigakan", items: [
        "Kalau sebuah halaman sudah terlihat mencurigakan dan punya formulir, server Shoo bisa mengirim ringkasan kecil halaman itu ke penyedia AI pihak ketiga, untuk memeriksa apakah data yang diminta wajar untuk jenis halaman itu.",
        "Ringkasannya hanya: domain situs (misalnya bank-hadiah.xyz, tanpa sisa alamatnya), judul halaman, nama maksimal 12 kolom formulir (misalnya \"OTP\" atau \"nomor kartu\") beserta jenisnya (misalnya teks atau password), dan pemeriksaan kami yang terpicu. Email dan deretan 4 angka atau lebih di judul dan nama kolom disembunyikan dulu.",
        "Kami tidak pernah mengirim isi teks halaman, alamat web lengkap, apa pun yang kamu ketik, atau nama Shoo-mu, ID device, maupun token. Judul halaman tetap bisa berisi apa yang ditampilkan situs itu sendiri, misalnya nama. Permintaan dikirim dari server kami, jadi penyedia tidak melihat alamat IP-mu. Kami tidak menyimpan permintaan maupun jawabannya.",
        "Kami tidak bisa menjamin berapa lama penyedia AI menyimpan ringkasan ini.",
      ] },
      { h: "Penyedia layanan", items: [
        "Cloudflare (menjalankan API kami dan menyimpan salinan halaman serta ikon situs di Cloudflare R2), Supabase (database, dan penyimpanan screenshot serta ikon situs lama, region Singapura), dan Apple (notifikasi push). Mereka memproses data hanya untuk menyediakan layanan itu.",
        "Registry domain publik (RDAP) menerima domain situs yang kami periksa, untuk memberi tahu kapan domain itu didaftarkan.",
        "Penyedia AI pihak ketiga menerima ringkasan halaman yang dijelaskan di atas.",
      ] },
      { h: "Kontak", items: [`Pertanyaan: ${CONTACT}.`] },
    ],
  },
};

const CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const STYLE = `body{font:17px/1.5 -apple-system,system-ui,sans-serif;margin:0;padding:32px 20px;color:#111;background:#fff}
main{max-width:640px;margin:0 auto}h2{font-size:20px;margin-top:28px}li{margin:6px 0}.muted{color:#666}
@media (prefers-color-scheme:dark){body{color:#f2f2f2;background:#000}.muted{color:#aaa}}`;

export type LegalText = { title: string; updated: string; lead: string; sections: Section[] };

/** ?lang=en|id, else Accept-Language, else English. */
export const pageLanguage = (c: Context<AppEnv>): "en" | "id" => {
  const q = c.req.query("lang");
  return q === "id" || q === "en" ? q : /^id\b/i.test(c.req.header("accept-language") ?? "") ? "id" : "en";
};

/** Static legal page (privacy, terms): no script, no outside resources. */
export function legalPage(c: Context<AppEnv>, lang: "en" | "id", t: LegalText) {
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
}

export const privacy = new Hono<AppEnv>();

privacy.get("/privacy", (c) => {
  const lang = pageLanguage(c);
  return legalPage(c, lang, TEXT[lang]);
});
