import { Hono } from "hono";
import type { AppEnv } from "../env";
import { pageLanguage } from "./privacy";
import { ICON_LINKS } from "./site-icons";
import shooImage from "../assets/safari-check-shoo.png";

// ON-04 "Jadikan Safari Default" (Figma 2497:4919, screen 8 "Browser utama · halaman cek"). The app's
// "Cek & lanjutkan" opens this page with UIApplication.open, so iOS shows it in the DEFAULT browser. In Safari
// the Shoo extension reports in (heartbeat with `allSites`) on its own; the page only says what to do next.
// Static, no script, no outside resources, no user data. Not a universal link: the AASA lists only /j/*.

const IMAGE_PATH = "/safari-check/shoo.png";

type Text = { title: string; lead: string; askTitle: string; askBody: string; back: string; imageAlt: string };

const TEXT: Record<"en" | "id", Text> = {
  en: {
    title: "Almost done!",
    lead: "This page opened in your main browser. If it's Safari, Shoo has already checked. Go back to Shoo to see the result.",
    askTitle: "Is Safari asking about Shoo?",
    askBody: "Tap aA in the address bar → Shoo → Always Allow → Always Allow on Every Website. Don't choose \"Allow for One Day\".",
    back: "Back to Shoo",
    imageAlt: "Shoo the owl waving",
  },
  id: {
    title: "Hampir selesai!",
    lead: "Halaman ini terbuka di browser utamamu. Kalau ini Safari, Shoo sudah mengecek. Kembali ke Shoo untuk lihat hasilnya.",
    askTitle: "Safari bertanya soal Shoo?",
    askBody: "Ketuk aA di bilah alamat → Shoo → Selalu Izinkan → Izinkan di Semua Situs Web. Jangan pilih \"Izinkan Satu Hari\".",
    back: "Kembali ke Shoo",
    imageAlt: "Shoo si burung hantu melambai",
  },
};

const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

// Colours from the app's onboarding theme (OnboardingStyle.swift): background F5F8FC, ink 191D2F, body 6A717E,
// button gradient 446EB4 → 214889.
const STYLE = `*{box-sizing:border-box}body{margin:0;font:17px/1.45 -apple-system,system-ui,sans-serif;color:#191d2f;background:#f5f8fc}
.hero{display:flex;justify-content:center;align-items:flex-end;height:260px;background:linear-gradient(180deg,#3d8fe0 0%,#8cc4f2 70%,#f5f8fc 100%)}
.hero img{width:184px;height:224px;margin-bottom:-8px}
main{max-width:480px;margin:0 auto;padding:24px 20px 40px;text-align:center}
h1{font-size:26px;line-height:1.2;margin:8px 0 10px}p{margin:0}.lead{color:#6a717e;font-size:16px}
.card{margin:24px 0;padding:16px;border-radius:18px;background:#fff;box-shadow:0 6px 20px rgba(13,26,51,.08);text-align:left}
.card h2{font-size:16px;margin:0 0 6px}.card p{color:#6a717e;font-size:15px}
.btn{display:block;padding:16px;border-radius:999px;background:linear-gradient(180deg,#446eb4,#214889);color:#fff;font-weight:600;text-decoration:none}
@media (prefers-color-scheme:dark){body{color:#f2f4f8;background:#0e1116}.lead,.card p{color:#a3a9b3}
.hero{background:linear-gradient(180deg,#1d4f8c 0%,#163a66 70%,#0e1116 100%)}.card{background:#1b1f26;box-shadow:none}}`;

export const safariCheck = new Hono<AppEnv>();

safariCheck.get("/safari-check", (c) => {
  const lang = pageLanguage(c);
  const t = TEXT[lang];
  const html = `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>${t.title} · Shoo</title>${ICON_LINKS}<style>${STYLE}</style></head><body>
<div class="hero"><img src="${IMAGE_PATH}" alt="${t.imageAlt}" width="184" height="224"></div>
<main><h1>${t.title}</h1><p class="lead">${t.lead}</p>
<section class="card"><h2>${t.askTitle}</h2><p>${t.askBody}</p></section>
<a class="btn" href="shoo://">${t.back}</a></main></body></html>`;
  c.header("Content-Security-Policy", CSP);
  return c.html(html);
});

safariCheck.get(IMAGE_PATH, (c) => {
  c.header("Content-Type", "image/png");
  c.header("Cache-Control", "public, max-age=604800");
  return c.body(shooImage);
});
