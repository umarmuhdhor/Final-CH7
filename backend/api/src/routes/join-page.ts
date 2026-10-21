import { Hono } from "hono";
import type { AppEnv } from "../env";

// Invite page behind `inviteUrl` (R3 §4, SECURITY T13). No auth, no DB lookup:
// it never tells whether a code is active. Only a strict 4-digit code is echoed.

const TEXT = {
  en: {
    title: "Join a family on Shoo",
    lead: "Someone invited you to their Shoo family.",
    open: "Open Shoo",
    manual: "Or type this code in Shoo:",
    noCode: "This invite link has no valid code. Ask for a new one.",
    install: "Don't have Shoo yet? Install it first",
  },
  id: {
    title: "Bergabung ke keluarga di Shoo",
    lead: "Seseorang mengundang kamu ke keluarga Shoo-nya.",
    open: "Buka Shoo",
    manual: "Atau ketik kode ini di Shoo:",
    noCode: "Link undangan ini tidak berisi kode yang valid. Minta kode baru.",
    install: "Belum punya Shoo? Install dulu",
  },
} as const;

// TODO(sync:alief): App Store link — replace after the app is on the App Store / TestFlight (fase 16).
const APP_STORE_URL = "https://apps.apple.com/";

const CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

const STYLE = `body{font:17px/1.4 -apple-system,system-ui,sans-serif;margin:0;padding:32px 20px;text-align:center;color:#111;background:#fff}
main{max-width:420px;margin:0 auto}.code{font-size:56px;font-weight:700;letter-spacing:.2em;margin:8px 0 24px}
a.btn{display:block;padding:16px;border-radius:14px;background:#0a66ff;color:#fff;text-decoration:none;font-weight:600;margin:24px 0}
@media (prefers-color-scheme:dark){body{color:#f2f2f2;background:#000}}`;

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]!);

export const joinPage = new Hono<AppEnv>();

joinPage.get("/join", (c) => {
  const raw = c.req.queries("code");
  const code = raw?.length === 1 && /^\d{4}$/.test(raw[0]!) ? raw[0]! : null;
  const lang = /^id\b/i.test(c.req.header("accept-language") ?? "") ? "id" : "en";
  const t = TEXT[lang];

  const body = code
    ? `<p>${t.lead}</p><a class="btn" href="shoo://join?code=${code}">${t.open}</a>
<p>${t.manual}</p><p class="code">${code}</p>`
    : `<p>${t.noCode}</p>`;
  const html = `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(t.title)}</title>
<style>${STYLE}</style></head><body><main><h1>${escapeHtml(t.title)}</h1>${body}
<p><a href="${APP_STORE_URL}">${escapeHtml(t.install)}</a></p></main></body></html>`;

  c.header("Content-Security-Policy", CSP);
  c.header("X-Content-Type-Options", "nosniff");
  c.header("Referrer-Policy", "no-referrer");
  c.header("Cache-Control", "no-store");
  return c.html(html);
});
