import { Hono } from "hono";
import type { AppEnv } from "../env";
import { contactLink, legalPage, pageLanguage, type LegalText } from "./privacy";

// Fase 24c-1 (E6): the Support URL for App Store Connect. App Store 1.1: a full help page (questions and
// answers from the "Paket App Store & ASO v1.1" doc, appendix B) that follows the 1.1 flow: everyone starts
// in Personal mode, Guardian is chosen in Profile, 6-digit invite codes. Still covers how to reach us, how to
// leave a family and how to delete everything. Static, no auth, no DB, same page shell and headers as
// /privacy and /terms. shoo.ai.id/support shows this page (the landing Worker passes it through).

/** One question: the question in bold, then the answer. Text parts are lines; `<ol>`/`<ul>` parts are lists. */
const qa = (q: string, ...answer: string[]) =>
  `<strong>${q}</strong>${answer.map((a) => (a.startsWith("<ol") || a.startsWith("<ul") ? a : `<span>${a}</span>`)).join("")}`;
const steps = (...s: string[]) => `<ol>${s.map((x) => `<li>${x}</li>`).join("")}</ol>`;
const points = (...s: string[]) => `<ul>${s.map((x) => `<li>${x}</li>`).join("")}</ul>`;

const TEXT: Record<"en" | "id", LegalText> = {
  en: {
    title: "Shoo support",
    updated: "Last updated: 19 November 2026",
    lead: `A short guide to Shoo on iPhone. Can't find your answer? Email us at ${contactLink}.`,
    sections: [
      { h: "Getting started", items: [
        qa("What do I need?",
          "An iPhone with iOS 17 or later, and Safari. Shoo is free on the App Store. Family members you want to protect also need an iPhone with Shoo."),
        qa("Do I need an account?",
          "No. Pick an avatar and type a name, and you're done. No email, phone number or password. Your family sees this name."),
        qa("How do I turn on the Shoo extension?",
          steps(
            "On Turn on the extension, tap Turn on.",
            "Open Settings › Apps › Safari › Extensions. (iOS 17: Settings › Safari › Extensions.)",
            "Tap Shoo, turn it on, then allow it on all websites.",
            "Go back to Shoo. The app checks by itself whether the extension is on.",
          ),
          `In step 1, tick "I agree to pages being checked online." for stronger protection. Without it, pages are checked on your iPhone only.`,
          "Still stuck? Tap Watch the tutorial. The video keeps playing in a small window while you're in Settings."),
        qa("Why Safari?",
          "Shoo works only in Safari. A link from WhatsApp or SMS that opens in another browser is not checked. To make Safari your default: Settings › Apps › Default Apps › Browser App › Safari. (Older iOS: Settings › Safari › Default Browser App.)"),
      ] },
      { h: "Modes and family", items: [
        qa("What's the difference between Personal, Guardian and Protected?",
          points(
            "Personal: Shoo protects Safari on your own phone. Everyone starts here.",
            "Guardian: you protect up to 3 family members. You get a notification and decide whether a site blocked on their phone is safe.",
            "Protected: a family member connected to a Guardian.",
          ),
          "Change the mode in Profile › Account mode."),
        qa("How do I invite my family?",
          steps(
            "On your phone, open Profile › Account mode, choose Guardian and confirm.",
            "Tap Invite family. You see a QR code and a 6-digit invite code. You can also copy the invite link and send it on WhatsApp.",
            "On the family member's phone, open Profile › Account mode › Have an invite code?, then scan the QR code or type the code.",
          )),
        qa("The invite code doesn't work.",
          "A code works for 30 minutes, and stops right away when the Guardian makes a new one. Ask the Guardian to open Invite family again and use the code on screen."),
        qa("I can't add another member.",
          "One Guardian can protect up to 3 people. Remove someone first, then invite the next person."),
        qa("How do I leave a family?",
          points(
            "Guardian: open the family member in the app and tap Disconnect. You can no longer see their flagged pages, and your decisions about their sites are deleted.",
            "Protected: ask your Guardian to disconnect you, or delete your account.",
          )),
        qa("I got a new phone. Do I connect my family again?",
          "Yes. Shoo has no login, so your account lives on your phone. Install Shoo on the new phone and connect again with an invite code."),
      ] },
      { h: "Warnings and blocks", items: [
        qa("What does the score mean?",
          "How likely the page is to be a scam.",
          points("30% or more: Shoo shows a warning.", "80% or more: the page is blocked."),
          "Detail shows why, for example a domain made a few days ago or a form asking for an OTP."),
        qa("A safe site was blocked.",
          "Open the site's Detail and tap Safe. The page opens again.",
          "If you're Protected, your Guardian taps Safe, and the block screen on your phone opens by itself.",
          "Want the detection fixed? Email us about the wrong block."),
        qa("Can I open a blocked page anyway?",
          "No. A blocked page opens only after it is marked Safe: by you, or by your Guardian if you're Protected."),
        qa("I typed a PIN or OTP on a fake site.",
          "Do this as soon as you can:",
          steps(
            "Call your bank or e-wallet on the official number on your card or in its official app, and ask them to secure your account.",
            "Change every PIN and password you typed.",
            `Report it to OJK's Indonesia Anti-Scam Centre (IASC) at <a href="https://iasc.ojk.go.id">iasc.ojk.go.id</a>.`,
          )),
      ] },
      { h: "Privacy", items: [
        qa("Does Shoo read my chats or SMS?",
          "No. Shoo only checks pages opened in Safari. SMS, chats in the WhatsApp app and photos are not read.",
          "One exception: if you open a chat on the web in Safari while the online check is on, the text shown on that page is checked too."),
        qa("What is the online check?",
          "A closer check of the pages you open, on Shoo's server.",
          points(
            "What you type into a page is never sent.",
            "Your pages are checked by Shoo's own model, never sent to an AI company.",
            "You can turn it off in Profile › About Shoo › Online check. You're less protected then.",
          )),
        qa("How do I delete my data?",
          "Open Profile › Delete account. Your device, flagged pages, page copies, screenshots, site icons, decisions and family links are deleted from the server right away.",
          points(
            "A Guardian who still protects someone disconnects them first.",
            "Deleting only the app does not delete your account.",
            `Some records of risky sites stay, no longer linked to you. The <a href="/privacy?lang=en">privacy policy</a> has the details.`,
          )),
      ] },
      { h: "Common problems", items: [
        qa("The app says the extension is off, but I turned it on.",
          "Shoo has to be allowed on all websites, not only switched on. Open Safari's extension settings again and check its permission."),
        qa("Notifications from my family don't arrive.",
          points(
            "Settings › Notifications › Shoo: notifications must be allowed.",
            "Quiet hours in Shoo's Profile. Blocked-site alerts still come during quiet hours.",
          )),
        qa("Does Shoo work in Chrome, on iPad or on Android?",
          "Not yet. Shoo is for Safari on iPhone only."),
      ] },
      { h: "Contact us", items: [
        `Email ${contactLink}. Reporting a wrong block? Add your iPhone model, iOS version and the site's link.`,
        `What we store and for how long: <a href="/privacy?lang=en">privacy policy</a>. Rules for using Shoo: <a href="/terms?lang=en">terms of use</a>.`,
      ] },
    ],
  },
  id: {
    title: "Bantuan Shoo",
    updated: "Terakhir diperbarui: 19 November 2026",
    lead: `Panduan singkat memakai Shoo di iPhone. Jawabanmu tidak ada di sini? Email kami di ${contactLink}.`,
    sections: [
      { h: "Memulai", items: [
        qa("Apa yang dibutuhkan?",
          "iPhone dengan iOS 17 atau lebih baru, dan Safari. Shoo gratis di App Store. Keluarga yang mau dilindungi juga perlu iPhone dengan Shoo."),
        qa("Perlu bikin akun?",
          "Tidak. Pilih avatar dan isi nama, selesai. Tanpa email, nomor HP, atau kata sandi. Keluargamu akan melihat nama ini."),
        qa("Bagaimana cara menyalakan ekstensi Shoo?",
          steps(
            "Di layar Aktifkan Ekstensi, ketuk Nyalakan.",
            "Buka Pengaturan › App › Safari › Ekstensi. (iOS 17: Pengaturan › Safari › Ekstensi.)",
            "Ketuk Shoo, nyalakan, lalu izinkan di semua situs web.",
            "Kembali ke Shoo. App mengecek sendiri apakah ekstensi sudah aktif.",
          ),
          `Di langkah 1, centang "Saya setuju halaman dicek secara online." supaya perlindungannya lebih kuat. Tanpa centang, halaman hanya dicek di iPhone-mu.`,
          "Masih bingung? Ketuk Tonton Tutorial. Videonya tetap tampil kecil saat kamu pindah ke Pengaturan."),
        qa("Kenapa harus Safari?",
          "Shoo hanya bekerja di Safari. Link dari WhatsApp atau SMS yang terbuka di browser lain tidak diperiksa. Jadikan Safari browser utama: Pengaturan › App › App Default › App Browser › Safari. (iOS lama: Pengaturan › Safari › App Browser Default.)"),
      ] },
      { h: "Mode dan keluarga", items: [
        qa("Apa beda mode Pribadi, Guardian, dan Dilindungi?",
          points(
            "Pribadi: Shoo melindungi Safari di HP-mu sendiri. Semua orang mulai di sini.",
            "Guardian: kamu melindungi sampai 3 anggota keluarga. Kamu dapat notifikasi dan memutuskan apakah situs yang diblokir di HP mereka aman.",
            "Dilindungi: anggota keluarga yang terhubung ke Guardian.",
          ),
          "Ganti mode di Profil › Mode akun."),
        qa("Bagaimana cara mengundang keluarga?",
          steps(
            "Di HP-mu, buka Profil › Mode akun, pilih Guardian, lalu konfirmasi.",
            "Ketuk Undang Keluarga. Muncul kode QR dan kode undangan 6 angka. Link undangannya juga bisa disalin dan dikirim lewat WhatsApp.",
            "Di HP anggota keluarga, buka Profil › Mode akun › Punya kode undangan?, lalu pindai kode QR atau ketik kodenya.",
          )),
        qa("Kode undangan tidak berlaku.",
          "Kode hanya berlaku 30 menit, dan langsung mati kalau Guardian membuat kode baru. Minta Guardian membuka Undang Keluarga lagi, lalu pakai kode yang sedang tampil."),
        qa("Tidak bisa menambah anggota.",
          "Satu Guardian maksimal melindungi 3 orang. Keluarkan satu orang dulu, baru undang yang lain."),
        qa("Bagaimana cara keluar dari keluarga?",
          points(
            "Guardian: buka anggota keluarga di app, lalu ketuk Putuskan koneksi. Kamu langsung tidak bisa melihat halaman yang ditandai milik orang itu, dan keputusanmu tentang situs-situsnya dihapus.",
            "Dilindungi: minta Guardian memutuskan koneksi, atau hapus akunmu.",
          )),
        qa("Saya ganti HP. Keluarga harus disambungkan lagi?",
          "Ya. Shoo tidak memakai login, jadi akunmu terikat ke HP. Pasang Shoo di HP baru, lalu sambungkan lagi dengan kode undangan."),
      ] },
      { h: "Peringatan dan blokir", items: [
        qa("Apa arti skor di Shoo?",
          "Seberapa mungkin halaman itu penipuan.",
          points("30% ke atas: Shoo memberi peringatan.", "80% ke atas: halaman diblokir."),
          "Alasannya ada di Detail, misalnya domain yang baru dibuat beberapa hari lalu atau formulir yang meminta OTP."),
        qa("Situs yang aman ikut diblokir.",
          "Buka Detail situs itu, lalu ketuk Aman. Halamannya bisa dibuka lagi.",
          "Kalau kamu pengguna Dilindungi, Guardian-mu yang mengetuk Aman, lalu layar blokir di HP-mu terbuka sendiri.",
          "Mau deteksinya diperbaiki? Kirim laporan salah blokir lewat email."),
        qa("Halaman yang diblokir bisa dibuka paksa?",
          "Tidak. Halaman yang diblokir hanya terbuka setelah ditandai Aman: oleh kamu sendiri, atau oleh Guardian-mu kalau kamu Dilindungi."),
        qa("Saya terlanjur mengisi PIN atau OTP di situs palsu.",
          "Lakukan ini secepatnya:",
          steps(
            "Telepon bank atau dompet digitalmu lewat nomor resmi di kartu atau di aplikasi resminya, lalu minta akunmu diamankan.",
            "Ganti semua PIN dan kata sandi yang sempat kamu ketik.",
            `Laporkan ke Indonesia Anti-Scam Centre (IASC) OJK di <a href="https://iasc.ojk.go.id">iasc.ojk.go.id</a>.`,
          )),
      ] },
      { h: "Privasi", items: [
        qa("Apakah Shoo membaca chat atau SMS saya?",
          "Tidak. Shoo hanya memeriksa halaman yang dibuka di Safari. SMS, chat di aplikasi WhatsApp, dan foto tidak dibaca.",
          "Satu pengecualian: kalau kamu membuka chat lewat web di Safari saat cek online menyala, teks yang tampil di halaman itu ikut diperiksa."),
        qa("Apa itu cek online?",
          "Pemeriksaan tambahan di server Shoo untuk halaman yang kamu buka.",
          points(
            "Isian yang kamu ketik di halaman tidak pernah dikirim.",
            "Halamanmu dicek oleh model milik Shoo sendiri, tidak pernah dikirim ke perusahaan AI.",
            "Bisa dimatikan di Profil › Tentang Shoo › Cek online, tapi perlindunganmu jadi lebih lemah.",
          )),
        qa("Bagaimana cara menghapus data saya?",
          "Buka Profil › Hapus akun. Device, halaman yang ditandai, salinan halaman, screenshot, ikon situs, keputusan, dan hubungan keluarga langsung dihapus dari server.",
          points(
            "Guardian yang masih melindungi seseorang harus memutuskan koneksinya dulu.",
            "Menghapus app saja tidak menghapus akunmu.",
            `Sebagian catatan situs berisiko tetap disimpan tanpa kaitan denganmu. Rinciannya ada di <a href="/privacy?lang=id">kebijakan privasi</a>.`,
          )),
      ] },
      { h: "Masalah umum", items: [
        qa("App bilang ekstensi mati, padahal sudah dinyalakan.",
          "Shoo harus diizinkan di semua situs web, bukan hanya dinyalakan. Buka lagi pengaturan ekstensi Safari dan cek izinnya."),
        qa("Notifikasi dari keluarga tidak muncul.",
          points(
            "Pengaturan › Notifikasi › Shoo: notifikasi harus diizinkan.",
            "Jam tenang di Profil Shoo. Peringatan situs diblokir tetap dikirim saat jam tenang.",
          )),
        qa("Shoo bisa dipakai di Chrome, iPad, atau Android?",
          "Belum. Saat ini Shoo hanya untuk Safari di iPhone."),
      ] },
      { h: "Hubungi kami", items: [
        `Email ke ${contactLink}. Mau melaporkan salah blokir? Sertakan model iPhone, versi iOS, dan link situsnya.`,
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
