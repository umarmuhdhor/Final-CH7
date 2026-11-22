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

// Safari's page-menu button, left of the site name (at the bottom with the default "Compact" tabs). Its glyph
// differs by iOS version, so both are drawn inline (no image request, CSP stays img-src 'self'): iOS 26 a box
// over two lines, iOS 27 three lines (≡). Checked on simulators 22 Nov 2026 (iOS 26.5 and 27.0, language id).
// The page never says "aA" or "address bar": users don't see either (goldfish F5, 22 Nov 2026).
const ICON_IOS26 =
  '<svg class="ic" viewBox="0 0 20 20" aria-hidden="true"><rect x="3.5" y="2.5" width="13" height="8" rx="2"/><path d="M3.5 14h13M3.5 17.5h9"/></svg>';
const ICON_IOS27 =
  '<svg class="ic" viewBox="0 0 20 20" aria-hidden="true"><path d="M3 5h14M3 10h14M3 15h10"/></svg>';
// One pill, the two looks split by "/": the user sees one of them, never both.
const MENU_BUTTON = `<span class="ics">${ICON_IOS26}<span class="sep">/</span>${ICON_IOS27}</span>`;

// askBody is HTML built only from the constants above (no user input).
type Text = { title: string; lead: string; askTitle: string; askBody: string; back: string; imageAlt: string };

const TEXT: Record<"en" | "id", Text> = {
  en: {
    title: "Almost done!",
    lead: "This page opened in your main browser. If it's Safari, Shoo has already checked. Go back to Shoo to see the result.",
    askTitle: "Is Safari asking about Shoo?",
    // Labels as Safari shows them (iOS 26.5 / 27.0, English).
    askBody: `Tap the ${MENU_BUTTON} button left of the site name (usually at the bottom of the screen) → Shoo → Always Allow… → Always Allow on Every Website.`,
    back: "Back to Shoo",
    imageAlt: "Shoo the owl waving",
  },
  id: {
    title: "Hampir selesai!",
    lead: "Halaman ini terbuka di browser utamamu. Kalau ini Safari, Shoo sudah mengecek. Kembali ke Shoo untuk lihat hasilnya.",
    askTitle: "Safari bertanya soal Shoo?",
    // Label persis seperti di Safari iOS 26.5 / 27.0 berbahasa Indonesia.
    askBody: `Ketuk tombol ${MENU_BUTTON} di kiri nama situs (biasanya di bawah layar) → Shoo → Selalu Izinkan… → Selalu Izinkan di Semua Situs Web.`,
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
.ics{display:inline-flex;gap:2px;padding:1px 5px;border-radius:7px;background:#e9edf3;color:#191d2f;vertical-align:-4px}
.sep{opacity:.45;font-size:14px;line-height:18px}
.ic{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.6;stroke-linecap:round}
.btn{display:block;padding:16px;border-radius:999px;background:linear-gradient(180deg,#446eb4,#214889);color:#fff;font-weight:600;text-decoration:none}
@media (prefers-color-scheme:dark){body{color:#f2f4f8;background:#0e1116}.lead,.card p{color:#a3a9b3}
.hero{background:linear-gradient(180deg,#1d4f8c 0%,#163a66 70%,#0e1116 100%)}.card{background:#1b1f26;box-shadow:none}
.ics{background:#2a303a;color:#f2f4f8}}`;

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
