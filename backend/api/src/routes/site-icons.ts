import { Hono } from "hono";
import type { AppEnv } from "../env";
import favicon from "../assets/favicon.ico";
import icon192 from "../assets/icon-192.png";
import appleTouchIcon from "../assets/apple-touch-icon.png";

/**
 * Shoo's own icons (Figma "LOGO FIX" 227:3954) for the browser tab and the iPhone home screen.
 * Static, no user data, so browsers and CDNs may cache them for a week.
 */
const ICONS: Record<string, { body: ArrayBuffer; type: string }> = {
  "/favicon.ico": { body: favicon, type: "image/x-icon" },
  "/icon-192.png": { body: icon192, type: "image/png" },
  "/apple-touch-icon.png": { body: appleTouchIcon, type: "image/png" },
};

/** `<link>` tags for every Shoo page head. Pages that set a CSP need `img-src 'self'` for them. */
export const ICON_LINKS =
  '<link rel="icon" href="/favicon.ico" sizes="48x48">' +
  '<link rel="icon" href="/icon-192.png" type="image/png" sizes="192x192">' +
  '<link rel="apple-touch-icon" href="/apple-touch-icon.png">';

export const siteIcons = new Hono<AppEnv>();

for (const [path, icon] of Object.entries(ICONS)) {
  siteIcons.get(path, (c) => {
    c.header("Content-Type", icon.type);
    c.header("Cache-Control", "public, max-age=604800");
    return c.body(icon.body);
  });
}
