import { Hono } from "hono";
import type { AppEnv } from "../env";

// Universal Link for the invite page (PR-03, issue #129): with Shoo installed, `/j/<code>` opens the
// app instead of Safari. Apple's CDN fetches this file; it carries no user data, so it may be cached.

/** `<Team ID>.<bundle ID>`, as Apple lists it in `appIDs`. */
const APP_ID = /^[A-Z0-9]{10}\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;

/** Comma-separated `APPLINKS_APP_IDS`; anything malformed is dropped. */
export function appIds(value: string | undefined): string[] {
  return (value ?? "").split(",").map((s) => s.trim()).filter((s) => APP_ID.test(s));
}

export const appSiteAssociation = new Hono<AppEnv>();

appSiteAssociation.get("/.well-known/apple-app-site-association", (c) => {
  const ids = appIds(c.env.APPLINKS_APP_IDS);
  const details = ids.length ? [{ appIDs: ids, components: [{ "/": "/j/*", comment: "Family invite (PR-03)" }] }] : [];
  c.header("Cache-Control", "public, max-age=3600");
  return c.json({ applinks: { details } });
});
