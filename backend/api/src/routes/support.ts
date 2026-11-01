import { Hono } from "hono";
import type { AppEnv } from "../env";
import { CONTACT, legalPage, pageLanguage, type LegalText } from "./privacy";

// Fase 24c-1 (E6): the Support URL for App Store Connect. How to reach us and how to delete
// everything. Static, no auth, no DB, same page shell and headers as /privacy and /terms.

const TEXT: Record<"en" | "id", LegalText> = {
  en: {
    title: "Shoo support",
    updated: "Last updated: 1 November 2026",
    lead: "Shoo blocks scam websites in Safari on iPhone and lets a family member (the Guardian) help. This page says how to reach us and how to remove your data.",
    sections: [
      { h: "Contact", items: [`Questions or problems: ${CONTACT}.`] },
      { h: "Leave a family", items: [
        "Guardian: open the family member in the app and tap Disconnect. You lose access to their flagged pages at once, and your decisions about their sites are deleted.",
        "Protected person: ask your Guardian to disconnect you, or delete your account (below).",
      ] },
      { h: "Delete everything", items: [
        "In the app: Profile → Delete account. Your device, flagged pages, page copies, screenshots, site icons, decisions and family links are removed from our server right away.",
        "A Guardian who still protects someone disconnects them first; the app asks for it.",
        "Deleting only the app leaves your account on our server until you delete it in the app first or contact us.",
      ] },
      { h: "More", items: [
        `What we store and for how long: <a href="/privacy?lang=en">privacy policy</a>. Rules for using Shoo: <a href="/terms?lang=en">terms of use</a>.`,
      ] },
    ],
  },
  id: {
    title: "Bantuan Shoo",
    updated: "Terakhir diperbarui: 1 November 2026",
    lead: "Shoo memblokir situs penipuan di Safari iPhone dan membiarkan anggota keluarga (Guardian) membantu. Halaman ini menjelaskan cara menghubungi kami dan cara menghapus datamu.",
    sections: [
      { h: "Kontak", items: [`Pertanyaan atau masalah: ${CONTACT}.`] },
      { h: "Keluar dari keluarga", items: [
        "Guardian: buka anggota keluarga di app lalu ketuk Putuskan koneksi. Kamu langsung kehilangan akses ke halaman yang ditandai miliknya, dan keputusanmu tentang situsnya dihapus.",
        "Orang yang dilindungi: minta Guardian memutuskan koneksi, atau hapus akunmu (di bawah).",
      ] },
      { h: "Hapus semuanya", items: [
        "Di app: Profil → Hapus akun. Device, halaman yang ditandai, salinan halaman, screenshot, ikon situs, keputusan, dan hubungan keluarga langsung dihapus dari server kami.",
        "Guardian yang masih melindungi seseorang memutuskan koneksinya dulu; app akan memintanya.",
        "Menghapus app saja membuat akunmu tetap ada di server kami sampai kamu menghapusnya di app dulu atau menghubungi kami.",
      ] },
      { h: "Lainnya", items: [
        `Apa yang kami simpan dan berapa lama: <a href="/privacy?lang=id">kebijakan privasi</a>. Aturan memakai Shoo: <a href="/terms?lang=id">syarat penggunaan</a>.`,
      ] },
    ],
  },
};

export const support = new Hono<AppEnv>();

support.get("/support", (c) => {
  const lang = pageLanguage(c);
  return legalPage(c, lang, TEXT[lang]);
});
