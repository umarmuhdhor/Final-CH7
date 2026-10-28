import { Hono } from "hono";
import type { AppEnv } from "../env";
import { legalPage, pageLanguage, type LegalText } from "./privacy";
import { storeUrl } from "./join-page";

// PF-01 "Tentang Shoo": terms of use (draft for the team to review before public release) and the
// link that "Bagikan Shoo" shares. Static, no auth, no DB.

const TEXT: Record<"en" | "id", LegalText> = {
  en: {
    title: "Shoo terms of use",
    updated: "Last updated: 28 October 2026",
    lead: "Shoo is a free app that checks the websites you open in Safari and warns you about or blocks scams. By using Shoo you agree to these terms.",
    sections: [
      { h: "What Shoo does", items: [
        "Shoo scores the pages you open and warns you about or blocks the ones that look like scams. It can be wrong in both directions: a scam may get through, and a safe site may be flagged.",
        "Shoo helps you decide; it does not replace your own judgement. Never share a password, OTP or card number with a page you are unsure about.",
      ] },
      { h: "Families", items: [
        "A Guardian sees the sites Shoo flagged for the people they protect, only while connected. Connect only with people who agree to it.",
        "Either side can disconnect at any time in the app.",
      ] },
      { h: "Your account", items: [
        "Shoo has no login. Your profile lives on this device; deleting the app without deleting your account first leaves it on our server until you contact us.",
        "You can delete your account in the app at any time: Profile → Delete account.",
      ] },
      { h: "Fair use", items: [
        "Do not use Shoo to watch someone without their knowledge, to overload our service, or to get around its limits.",
      ] },
      { h: "No warranty", items: [
        "Shoo is provided as is, without warranty. To the extent the law allows, we are not liable for losses from a site Shoo did or did not flag.",
      ] },
      { h: "Changes", items: [
        "We may update these terms. The date at the top shows the latest version; the app links here.",
      ] },
      { h: "Privacy", items: ["What we store and for how long is in the privacy policy (/privacy)."] },
    ],
  },
  id: {
    title: "Syarat & ketentuan Shoo",
    updated: "Terakhir diperbarui: 28 Oktober 2026",
    lead: "Shoo adalah app gratis yang memeriksa situs yang kamu buka di Safari dan memberi peringatan atau memblokir penipuan. Dengan memakai Shoo, kamu setuju dengan syarat ini.",
    sections: [
      { h: "Yang dilakukan Shoo", items: [
        "Shoo memberi skor pada halaman yang kamu buka dan memperingatkan atau memblokir yang terlihat seperti penipuan. Shoo bisa keliru ke dua arah: penipuan bisa lolos, dan situs aman bisa ditandai.",
        "Shoo membantumu memutuskan, bukan menggantikan penilaianmu sendiri. Jangan pernah memberikan kata sandi, OTP, atau nomor kartu ke halaman yang kamu ragukan.",
      ] },
      { h: "Keluarga", items: [
        "Guardian melihat situs yang ditandai Shoo untuk orang yang dilindunginya, hanya selama terhubung. Hubungkan hanya dengan orang yang setuju.",
        "Kedua pihak bisa memutus hubungan kapan saja di app.",
      ] },
      { h: "Akunmu", items: [
        "Shoo tidak memakai login. Profilmu ada di device ini; menghapus app tanpa menghapus akun dulu membuatnya tetap ada di server kami sampai kamu menghubungi kami.",
        "Kamu bisa menghapus akun di app kapan saja: Profil → Hapus akun.",
      ] },
      { h: "Pemakaian yang wajar", items: [
        "Jangan memakai Shoo untuk mengawasi seseorang tanpa sepengetahuannya, membebani layanan kami, atau mengakali batasannya.",
      ] },
      { h: "Tanpa jaminan", items: [
        "Shoo disediakan apa adanya, tanpa jaminan. Sejauh diizinkan hukum, kami tidak bertanggung jawab atas kerugian dari situs yang ditandai atau tidak ditandai Shoo.",
      ] },
      { h: "Perubahan", items: [
        "Kami bisa memperbarui syarat ini. Tanggal di atas menunjukkan versi terbaru; app menautkan ke halaman ini.",
      ] },
      { h: "Privasi", items: ["Apa yang kami simpan dan berapa lama ada di kebijakan privasi (/privacy)."] },
    ],
  },
};

export const terms = new Hono<AppEnv>();

terms.get("/terms", (c) => {
  const lang = pageLanguage(c);
  return legalPage(c, lang, TEXT[lang]);
});

/** "Bagikan Shoo": a stable link that always points at the current TestFlight / App Store page. */
terms.get("/get", (c) => c.redirect(storeUrl(c.env.APP_STORE_URL), 302));
