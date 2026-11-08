import { env } from "cloudflare:workers";
import type { Sql } from "postgres";
import { attachScreenshot } from "../../src/services/scans";

/**
 * Fase 20a: POST /scans ignores `screenshotBase64`, so tests that serve, delete or guard an old
 * screenshot store it through the service the route used to call. Removed with the service in 20b.
 */
export const seedScreenshot = (sql: Sql, scan: { id: string; ownerId: string; domain: string }, base64: string) =>
  attachScreenshot(sql, env, scan, base64);
