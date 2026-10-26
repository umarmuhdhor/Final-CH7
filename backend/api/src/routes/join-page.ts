import { Hono } from "hono";
import type { AppEnv } from "../env";
import { base64url, randomBytes } from "../http/crypto";
import ogImage from "../assets/og-invite.jpg";

// Invite page behind `inviteUrl` (R3 §4, SECURITY T13, PR-03 issue #128). No auth, no DB lookup:
// it never tells whether a code is active. Only a strict 6-digit code is echoed.
// With the app installed the link is a Universal Link (issue #129) and this page never shows.

const TEXT = {
  en: {
    title: "Join a family on Shoo",
    lead: "Someone invited you to their Shoo family.",
    open: "Open Shoo",
    manual: "Or type this code in Shoo:",
    noCode: "This invite link has no valid code. Ask for a new one.",
    install: "Don't have Shoo yet? Install it",
    installHint: "We copy the invite, so Shoo can paste it after you install.",
    preview: "Tap to join and get protected from scam sites.",
    imageAlt: "Shoo logo",
  },
  id: {
    title: "Bergabung ke keluarga di Shoo",
    lead: "Seseorang mengundang kamu ke keluarga Shoo-nya.",
    open: "Buka Shoo",
    manual: "Atau ketik kode ini di Shoo:",
    noCode: "Link undangan ini tidak berisi kode yang valid. Minta kode baru.",
    install: "Belum punya Shoo? Install dulu",
    installHint: "Undangan kami salin, jadi Shoo bisa menempelnya setelah kamu install.",
    preview: "Ketuk untuk bergabung dan terlindungi dari situs penipuan.",
    imageAlt: "Logo Shoo",
  },
} as const;

/** Fallback while `APP_STORE_URL` is unset. */
const DEFAULT_STORE_URL = "https://apps.apple.com/";

/** Only an https link to Apple's TestFlight or App Store is used; anything else falls back. */
export function storeUrl(value: string | undefined): string {
  try {
    const url = new URL(value ?? "");
    const ok = url.protocol === "https:" && (url.hostname === "testflight.apple.com" || url.hostname === "apps.apple.com");
    return ok ? url.href : DEFAULT_STORE_URL;
  } catch {
    return DEFAULT_STORE_URL;
  }
}

const csp = (nonce: string) =>
  `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;

const STYLE = `body{font:17px/1.4 -apple-system,system-ui,sans-serif;margin:0;padding:32px 20px;text-align:center;color:#111;background:#fff}
main{max-width:420px;margin:0 auto}.code{font-size:48px;font-weight:700;letter-spacing:.15em;margin:8px 0 24px}
a.btn{display:block;padding:16px;border-radius:14px;background:#0a66ff;color:#fff;text-decoration:none;font-weight:600;margin:24px 0}
.hint{font-size:14px;color:#666}
@media (prefers-color-scheme:dark){body{color:#f2f2f2;background:#000}.hint{color:#999}}`;

// Copies the invite link before going to the store, so the app can offer "Paste invite" on first launch
// (UIPasteControl, PR-03). The link is the only thing copied; nothing else runs and nothing is sent.
const INSTALL_SCRIPT = `document.getElementById("install").addEventListener("click",function(e){var a=this,l=a.dataset.invite;
if(!l||!navigator.clipboard)return;e.preventDefault();navigator.clipboard.writeText(l).finally(function(){location.href=a.href})})`;

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]!);

/** Link preview image (Open Graph): what WhatsApp, Messages and Telegram show above the invite text. */
const OG_IMAGE_PATH = "/og/invite.jpg";

// Link preview tags. Static on purpose: no name, no code, the same for every invite (T13).
const ogTags = (base: string, lang: "en" | "id") => {
  const t = TEXT[lang];
  const tag = (property: string, content: string) => `<meta property="${property}" content="${escapeHtml(content)}">`;
  return [
    tag("og:type", "website"),
    tag("og:site_name", "Shoo"),
    tag("og:title", t.title),
    tag("og:description", t.preview),
    tag("og:image", `${base}${OG_IMAGE_PATH}`),
    tag("og:image:type", "image/jpeg"),
    tag("og:image:width", "1200"),
    tag("og:image:height", "628"),
    tag("og:image:alt", t.imageAlt),
    `<meta name="twitter:card" content="summary_large_image">`,
  ].join("\n");
};

export const joinPage = new Hono<AppEnv>();

// Carries no user data, so link preview crawlers and CDNs may cache it.
joinPage.get(OG_IMAGE_PATH, (c) => {
  c.header("Content-Type", "image/jpeg");
  c.header("Cache-Control", "public, max-age=86400");
  return c.body(ogImage);
});

joinPage.get("/j/:code", (c) => {
  const raw = c.req.param("code");
  const code = /^\d{6}$/.test(raw) ? raw : null;
  const lang = /^id\b/i.test(c.req.header("accept-language") ?? "") ? "id" : "en";
  const t = TEXT[lang];
  const nonce = base64url(randomBytes(16));
  const store = escapeHtml(storeUrl(c.env.APP_STORE_URL));

  const body = code
    ? `<p>${t.lead}</p><a class="btn" href="shoo://join?code=${code}">${t.open}</a>
<p>${t.manual}</p><p class="code">${code}</p>
<p><a id="install" href="${store}" data-invite="${escapeHtml(`${c.env.INVITE_BASE_URL}/j/${code}`)}">${escapeHtml(t.install)}</a></p>
<p class="hint">${escapeHtml(t.installHint)}</p><script nonce="${nonce}">${INSTALL_SCRIPT}</script>`
    : `<p>${t.noCode}</p><p><a href="${store}">${escapeHtml(t.install)}</a></p>`;
  const html = `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(t.title)}</title>
${ogTags(c.env.INVITE_BASE_URL.replace(/\/+$/, ""), lang)}
<style>${STYLE}</style></head><body><main><h1>${escapeHtml(t.title)}</h1>${body}</main></body></html>`;

  c.header("Content-Security-Policy", csp(nonce));
  c.header("X-Content-Type-Options", "nosniff");
  c.header("Referrer-Policy", "no-referrer");
  c.header("Cache-Control", "no-store");
  return c.html(html);
});
