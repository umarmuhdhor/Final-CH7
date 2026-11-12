import { Hono, type Context } from "hono";
import type { AppEnv } from "../env";
import { base64url, randomBytes } from "../http/crypto";
import { CODE_TTL_SECONDS, findCode } from "../db/repo/codes";
import { clientIp, hitLight, limits } from "../http/rateLimit";
import { keyHash } from "../http/keyHash";
import { ipAttemptsExhausted, lockIpAttempts, recordAttempt } from "../db/repo/joinAttempts";
import { ApiError } from "../http/errors";
import { errorInfo } from "../http/logError";
import ogImage from "../assets/og-invite.jpg";
import heroImage from "../assets/join-hero.png";

// Invite page behind `inviteUrl` (R3 §4, SECURITY T13, PR-03 issue #128). No auth. Only a strict 6-digit
// code is echoed. A 6-digit code is looked up read-only (the code is never consumed): an unknown or expired
// code shows the same "invalid" page as a malformed one (Figma 1619:7334), so the page says valid or
// invalid and nothing more. Such a miss is a failed join attempt of the IP (no device), so page and
// POST /family/join share one budget of 20 failures per IP per 10 min and the page is no extra oracle.
// The page skips the lookup and shows the normal invite once that budget is used, past the global cap
// `limits.joinPageAll`, or when the DB fails (the app still checks the code on join). Only a top-level
// navigation (Sec-Fetch-Mode navigate, Sec-Fetch-Dest document) is looked up: an <img>, iframe or fetch
// from another site cannot spend a visitor's join budget, it gets the normal invite.
// With the app installed the link is a Universal Link (issue #129) and this page never shows.
// Layout: Figma "Undangan keluarga · Web · Redesign" (1326:12651). The design names the inviter;
// this page never names anyone (T13), so the heading stays generic.

const TTL_MINUTES = CODE_TTL_SECONDS / 60;

const TEXT = {
  en: {
    title: "Join a family on Shoo",
    heading: "You're invited to join a family on Shoo",
    open: "Open in the Shoo app",
    manual: "Enter this code in the app",
    validity: `Valid for up to ${TTL_MINUTES} min`,
    copy: "Copy code",
    copied: "Copied",
    noCode: "This invite link has no valid code.",
    requestNew: "Ask for a new code",
    requestMsg: "The Shoo invite code doesn't work anymore. Could you send me a new one?",
    requested: "Message copied",
    installLead: "Don't have Shoo yet?",
    install: "Install it",
    installHint: "We copy the invite link. After installing, open it again to join.",
    preview: "Tap to join and get protected from scam sites.",
    imageAlt: "Shoo logo",
    heroAlt: "Your family on Shoo, and you",
  },
  id: {
    title: "Bergabung ke keluarga di Shoo",
    heading: "Kamu diajak gabung keluarga di Shoo",
    open: "Buka di app Shoo",
    manual: "masukkan kode ini di app",
    validity: `Berlaku maks. ${TTL_MINUTES} menit`,
    copy: "Salin kode",
    copied: "Tersalin",
    noCode: "Link undangan ini tidak berisi kode yang valid.",
    requestNew: "Minta kode baru",
    requestMsg: "Kode undangan Shoo-nya sudah tidak berlaku. Bisa kirim kode baru?",
    requested: "Pesan tersalin",
    installLead: "Belum punya Shoo?",
    install: "Unduh",
    installHint: "Link undangan sudah kami salin. Setelah install, buka lagi link itu untuk bergabung.",
    preview: "Ketuk untuk bergabung dan terlindungi dari situs penipuan.",
    imageAlt: "Logo Shoo",
    heroAlt: "Keluargamu di Shoo, dan kamu",
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
  `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;

// Figma 1326:12651 tokens. Light only, like the frame. SF Pro Rounded and Geist come from the system
// (ui-rounded); the CSP loads no web fonts.
const STYLE = `*{box-sizing:border-box}
body{margin:0;background:#faf9fb;color:#191d2f;font:17px/22px -apple-system,system-ui,sans-serif;text-align:center;-webkit-text-size-adjust:100%}
main{max-width:402px;margin:0 auto;padding:32px 24px 40px;display:flex;flex-direction:column;align-items:center}
.hero{position:relative;width:232px;height:96px}
.hero img{position:relative;z-index:1;display:block;width:232px;height:96px}
.hero i{position:absolute;pointer-events:none;border-radius:50%;opacity:0}
.hero .glow{left:12px;top:16px;width:64px;height:64px;background:radial-gradient(circle,rgba(68,110,180,.5) 0,rgba(68,110,180,0) 70%);animation:travel 3s ease-in-out infinite}
.hero .beam{left:24px;top:47px;width:40px;height:2px;border-radius:1px;background:linear-gradient(90deg,rgba(24,111,185,0),#186fb9,rgba(24,111,185,0));animation:travel 3s ease-in-out infinite}
.hero .ring{left:86px;top:18px;width:60px;height:60px;border:2px solid rgba(24,111,185,.4);animation:ring 3s ease-out infinite}
@keyframes travel{0%{transform:translateX(0);opacity:0}10%,60%{opacity:1}70%,100%{transform:translateX(144px);opacity:0}}
@keyframes ring{0%,25%{transform:scale(.8);opacity:0}35%{transform:scale(1);opacity:1}55%,100%{transform:scale(1.3);opacity:0}}
@keyframes rise{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
.enter>*{animation:rise .3s cubic-bezier(.2,.8,.2,1) both}
.enter>.actions{animation-delay:.08s}
.badge{position:relative;display:flex;align-items:center;justify-content:center;width:80px;height:80px;border-radius:50%;background:#ef871c;box-shadow:inset 0 0 0 5px rgba(255,255,255,.1),0 10px 27px rgba(127,69,27,.36);color:#fff;font:700 48px/1 ui-rounded,-apple-system,system-ui,sans-serif;animation:pop .45s cubic-bezier(.34,1.56,.64,1) .1s both}
.badge::after{content:"";position:absolute;inset:0;border-radius:50%;border:2px solid #ef871c;opacity:0;animation:halo 1.6s ease-out .6s 3}
.badge span{display:block;animation:nudge .6s ease-in-out .6s 3}
@keyframes pop{from{transform:scale(.6);opacity:0}to{transform:none;opacity:1}}
@keyframes halo{0%{transform:scale(1);opacity:.5}100%{transform:scale(1.5);opacity:0}}
@keyframes nudge{0%,100%{transform:none}25%{transform:rotate(-8deg)}75%{transform:rotate(8deg)}}
h1{margin:20px 0 0;font-size:28px;line-height:34px;font-weight:600;letter-spacing:.02em}
.rounded{font-family:ui-rounded,-apple-system,system-ui,sans-serif}
.label{margin:24px 0 0;color:#6a717e;letter-spacing:-.01em}
.code{display:flex;align-items:center;gap:6px;margin:16px 0 0;padding:0}
.digit{display:flex;align-items:center;justify-content:center;width:44px;height:58px;background:#fff;border:1px solid #e4e8ef;border-radius:12px;font:600 26px/32px ui-rounded,-apple-system,system-ui,sans-serif;color:#151617;font-variant-numeric:tabular-nums}
.dash{width:8px;height:2px;background:#c7c7ce}
.meta{display:flex;align-items:center;justify-content:space-between;width:100%;margin-top:8px}
.ttl{display:flex;align-items:center;gap:6px;color:#6a717e;font-size:13px;line-height:18px;letter-spacing:-.08px}
.copy{display:flex;align-items:center;gap:6px;min-height:44px;padding:0;border:0;background:none;color:#186fb9;font:inherit;letter-spacing:-.01em;cursor:pointer}
.actions{width:100%;margin-top:80px;display:flex;flex-direction:column;gap:10px}
.btn{width:100%;font:inherit;font-weight:600;cursor:pointer;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:transform .12s ease,filter .12s ease;display:flex;align-items:center;justify-content:center;gap:8px;min-height:54px;padding:16px 20px 16px 16px;border:1.5px solid #191d2f;border-radius:999px;background:linear-gradient(180deg,#446eb4 -4%,#214889 75%);color:#fff;font-weight:600;text-decoration:none;text-shadow:0 4px 4px rgba(0,0,0,.2)}
.btn:active{transform:scale(.97);filter:brightness(.92)}
.copy{transition:transform .12s ease}.copy:active{transform:scale(.97)}
.btn svg{flex:none;filter:drop-shadow(0 4px 2px rgba(0,0,0,.2))}
.install{display:flex;align-items:center;justify-content:center;min-height:54px;margin:0;letter-spacing:-.01em}
.install a{margin-left:.25em;color:#186fb9;font-weight:600;text-decoration:none}
.hint{margin:0;color:#6a717e;font-size:13px;line-height:18px}
.invalid{padding-top:88px}
.invalid h1{margin-top:20px;letter-spacing:-.02em;font-weight:700}
.nocode{margin:8px 0 0;color:#6a717e;letter-spacing:-.01em}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
/* Last, so it wins over the motion rules above. */
@media (prefers-reduced-motion:reduce){.hero i,.enter>*,.badge,.badge::after,.badge span{animation:none}.btn,.copy{transition:none}.btn:active,.copy:active{transform:none}}`;

// Hero motion: a soft glow and a thin beam travel behind the image from the inviter's avatar, past the
// Shoo shield (a ring pulses as they cross it), to the "you" circle, so the three read as connecting.
// CSS only (no script), behind the PNG's transparent gaps; off under prefers-reduced-motion.

// Figma "Button" icon (compass, 22pt) and the clock and copy glyphs from "Meta kode", as inline SVG.
const ICON_OPEN = `<svg width="22" height="22" viewBox="0 0 22 22" aria-hidden="true"><path fill="#fff" d="M11 2.06a8.94 8.94 0 1 0 8.94 8.94A8.95 8.95 0 0 0 11 2.06Zm4.43 4.97-2.75 5.5a.34.34 0 0 1-.15.15l-5.5 2.75a.34.34 0 0 1-.46-.46l2.75-5.5a.34.34 0 0 1 .15-.15l5.5-2.75a.34.34 0 0 1 .46.46Z"/></svg>`;
const ICON_CLOCK = `<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="#6a717e" stroke-width="1.4" stroke-linecap="round"><circle cx="8" cy="8" r="6.6"/><path d="M8 4.4V8l2.4 1.6"/></svg>`;
const ICON_COPY = `<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true" fill="none" stroke="#186fb9" stroke-width="1.6" stroke-linejoin="round"><rect x="6" y="6" width="10" height="10" rx="2.2"/><path d="M12 6V4.2A2.2 2.2 0 0 0 9.8 2H4.2A2.2 2.2 0 0 0 2 4.2v5.6A2.2 2.2 0 0 0 4.2 12H6"/></svg>`;

// Copies the invite link before going to the store, so the person can open it again after installing
// (PR-03). The link is the only thing copied; nothing else runs and nothing is sent.
// "Salin kode" copies the 6-digit code the same way (Figma 1326:12651), then shows "Tersalin" for 2 s.
const INSTALL_SCRIPT = `document.getElementById("install").addEventListener("click",function(e){var a=this,l=a.dataset.invite;
if(!l||!navigator.clipboard)return;e.preventDefault();navigator.clipboard.writeText(l).finally(function(){location.href=a.href})});
var c=document.getElementById("copy"),t=document.getElementById("copy-label");
if(!navigator.clipboard)c.hidden=true;else c.addEventListener("click",function(){navigator.clipboard.writeText(c.dataset.code).then(function(){
t.textContent=c.dataset.done;setTimeout(function(){t.textContent=c.dataset.label},2000)})})`;

// "Minta kode baru" (Figma 1619:7334): the visitor cannot make a code, only the guardian can, so the
// button hands a short request to the share sheet (pick the chat the invite came from). Without the
// share sheet it copies the text, else opens Messages with it. Nothing is sent by the page itself.
const REQUEST_SCRIPT = `var r=document.getElementById("request");r.addEventListener("click",function(){var m=r.dataset.msg;
if(navigator.share){navigator.share({text:m}).catch(function(){});return}
if(navigator.clipboard){navigator.clipboard.writeText(m).then(function(){r.textContent=r.dataset.done;setTimeout(function(){r.textContent=r.dataset.label},2000)});return}
location.href="sms:?&body="+encodeURIComponent(m)})`;

// iOS Safari only shows :active (the button press scale) when a touch listener exists.
const ACTIVE_SCRIPT = `document.addEventListener("touchstart",function(){},{passive:true});`;

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]!);

/** Link preview image (Open Graph): what WhatsApp, Messages and Telegram show above the invite text. */
const OG_IMAGE_PATH = "/og/invite.jpg";
/** Page hero (Figma "Hero · Pengundang ↔ Kamu"), 3x of 232×96. */
const HERO_IMAGE_PATH = "/og/join-hero.png";

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

/** Six digit boxes split 3-3, as in Figma "Kode". The code is also there as plain text for screen readers. */
const codeBoxes = (code: string) => {
  const box = (d: string) => `<span class="digit">${d}</span>`;
  const digits = [...code].map(box);
  return `<p class="code" aria-hidden="true">${digits.slice(0, 3).join("")}<span class="dash"></span>${digits.slice(3).join("")}</p><p class="sr">${code}</p>`;
};

export const joinPage = new Hono<AppEnv>();

// Carries no user data, so link preview crawlers and CDNs may cache it.
joinPage.get(OG_IMAGE_PATH, (c) => {
  c.header("Content-Type", "image/jpeg");
  c.header("Cache-Control", "public, max-age=86400");
  return c.body(ogImage);
});

// Same for the hero: static, no user data.
joinPage.get(HERO_IMAGE_PATH, (c) => {
  c.header("Content-Type", "image/png");
  c.header("Cache-Control", "public, max-age=86400");
  return c.body(heroImage);
});

/**
 * False only when the code is known to be unknown or expired; that miss is recorded as a failed join
 * attempt of the IP, under the same IP lock as POST /family/join. Over the IP budget, past the global
 * cap, or when the DB fails, the answer is true (not checked): the normal invite is harmless.
 */
async function codeMayBeValid(c: Context<AppEnv>, code: string): Promise<boolean> {
  try {
    const sql = c.get("sql");
    await hitLight(sql, limits.joinPageAll, "all");
    const ipHash = await keyHash(`join:${clientIp((n) => c.req.header(n))}`);
    return await sql.begin(async (tx) => {
      await lockIpAttempts(tx, ipHash);
      if (await ipAttemptsExhausted(tx, ipHash)) return true;
      const found = await findCode(tx, code);
      if (found && !found.expired) return true;
      await recordAttempt(tx, null, ipHash, false);
      return false;
    });
  } catch (err) {
    // The code is never logged (T13): route and error class only.
    if (!(err instanceof ApiError)) console.error(JSON.stringify({ event: "join_page_lookup_failed", requestId: c.get("requestId"), error: errorInfo(err) }));
    return true;
  }
}

joinPage.get("/j/:code", async (c) => {
  const raw = c.req.param("code");
  const wellFormed = /^\d{6}$/.test(raw) ? raw : null;
  const navigation = c.req.header("sec-fetch-mode") === "navigate" && c.req.header("sec-fetch-dest") === "document";
  const code = wellFormed && (!navigation || (await codeMayBeValid(c, wellFormed))) ? wellFormed : null;
  const lang = /^id\b/i.test(c.req.header("accept-language") ?? "") ? "id" : "en";
  const t = TEXT[lang];
  const nonce = base64url(randomBytes(16));
  const store = escapeHtml(storeUrl(c.env.APP_STORE_URL));

  const hero = `<div class="hero"><i class="glow"></i><i class="beam"></i><i class="ring"></i><img src="${HERO_IMAGE_PATH}" width="232" height="96" alt="${escapeHtml(t.heroAlt)}"></div>`;
  const body = code
    ? `<h1>${escapeHtml(t.heading)}</h1>
<p class="label rounded">${escapeHtml(t.manual)}</p>${codeBoxes(code)}
<div class="meta rounded"><span class="ttl">${ICON_CLOCK}${escapeHtml(t.validity)}</span>
<button id="copy" class="copy" type="button" data-code="${code}" data-label="${escapeHtml(t.copy)}" data-done="${escapeHtml(t.copied)}">${ICON_COPY}<span id="copy-label">${escapeHtml(t.copy)}</span></button></div>
<div class="actions"><a class="btn" href="shoo://join?code=${code}">${ICON_OPEN}${escapeHtml(t.open)}</a>
<p class="install">${escapeHtml(t.installLead)}<a id="install" href="${store}" data-invite="${escapeHtml(`${c.env.INVITE_BASE_URL}/j/${code}`)}">${escapeHtml(t.install)}</a></p>
<p class="hint">${escapeHtml(t.installHint)}</p></div><script nonce="${nonce}">${ACTIVE_SCRIPT}${INSTALL_SCRIPT}</script>`
    : `<div class="badge" aria-hidden="true"><span>!</span></div><h1>${escapeHtml(t.title)}</h1><p class="nocode rounded">${escapeHtml(t.noCode)}</p>
<div class="actions"><button id="request" class="btn" type="button" data-msg="${escapeHtml(t.requestMsg)}" data-label="${escapeHtml(t.requestNew)}" data-done="${escapeHtml(t.requested)}">${escapeHtml(t.requestNew)}</button>
<p class="install">${escapeHtml(t.installLead)}<a href="${store}">${escapeHtml(t.install)}</a></p></div><script nonce="${nonce}">${ACTIVE_SCRIPT}${REQUEST_SCRIPT}</script>`;
  const html = `<!doctype html><html lang="${lang}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${escapeHtml(t.title)}</title>
${ogTags(c.env.INVITE_BASE_URL.replace(/\/+$/, ""), lang)}
<style>${STYLE}</style></head><body><main class="enter${code ? "" : " invalid"}">${code ? hero : ""}${body}</main></body></html>`;

  c.header("Content-Security-Policy", csp(nonce));
  c.header("X-Content-Type-Options", "nosniff");
  c.header("Referrer-Policy", "no-referrer");
  c.header("Cache-Control", "no-store");
  return c.html(html);
});
