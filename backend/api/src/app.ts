import { Hono } from "hono";
import type { AppEnv } from "./env";
import { createSql } from "./db/client";
import { ApiError, errorResponse, errors } from "./http/errors";
import { maxRequestBytes } from "./http/bodyLimit";
import { useRateKeySecret } from "./http/keyHash";
import { appSiteAssociation } from "./routes/app-site-association";
import { blocklist } from "./routes/blocklist";
import { devices } from "./routes/devices";
import { family } from "./routes/family";
import { favicons } from "./routes/favicons";
import { health } from "./routes/health";
import { joinPage } from "./routes/join-page";
import { privacy } from "./routes/privacy";
import { replicas } from "./routes/replicas";
import { scans } from "./routes/scans";
import { screenshots } from "./routes/screenshots";
import { terms } from "./routes/terms";
import { verdicts } from "./routes/verdicts";
import { errorInfo } from "./http/logError";

export const app = new Hono<AppEnv>();

app.use("*", async (c, next) => {
  const requestId = crypto.randomUUID();
  c.set("requestId", requestId);
  c.header("x-request-id", requestId);
  // SECURITY §3 P13 (D-alief-40): responses carry user data, so no client, proxy or CDN keeps a copy.
  // A route that serves no user data may override it (GET /blocklist).
  c.header("Cache-Control", "private, no-store");

  // postgres.js connects on the first query, so /healthz never opens a connection.
  // No sql.end(): Hyperdrive closes the client connection when the request ends
  // (Hyperdrive docs, connection lifecycle); ending it ourselves raises "socket has been closed".
  // Early 413 from the declared length, before auth or rate limits touch the DB. readJson still
  // caps the streamed body per route (16 KB default, 512 KB for POST /scans with a page replica).
  if (Number(c.req.header("content-length") ?? 0) > maxRequestBytes(c.req.method, c.req.path)) {
    c.res = errorResponse(c, errors.tooLarge());
    setSecurityHeaders(c.res.headers);
    return;
  }

  useRateKeySecret(c.env.RATE_KEY_SECRET);
  c.set("sql", createSql(c.env));
  await next();
  setSecurityHeaders(c.res.headers);
});

/**
 * Fase 12 hardening, on every response after the route ran (also errors and raw Responses).
 * Only fills what a route did not set: /j/<code>, /screenshots, /favicons and /replicas keep their own CSP.
 * No CORS headers anywhere: the clients are native (app, Safari extension), and OPTIONS → 404.
 */
function setSecurityHeaders(h: Headers): void {
  const defaults: Record<string, string> = {
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "x-frame-options": "DENY",
    "strict-transport-security": "max-age=31536000; includeSubDomains",
    "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  };
  for (const [k, v] of Object.entries(defaults)) if (!h.has(k)) h.set(k, v);
}

app.route("/", health);
app.route("/", appSiteAssociation);
app.route("/", devices);
app.route("/", blocklist);
app.route("/", family);
app.route("/", favicons);
app.route("/", joinPage);
app.route("/", privacy);
app.route("/", replicas);
app.route("/", scans);
app.route("/", screenshots);
app.route("/", terms);
app.route("/", verdicts);

app.notFound((c) => errorResponse(c, errors.notFound()));

app.onError((err, c) => {
  if (err instanceof ApiError) return errorResponse(c, err);
  // Never log request bodies or headers: they carry tokens and names (SECURITY §3 P6, T3).
  // The route pattern, not the path: paths carry scan and device ids (D-alief-40).
  console.error(JSON.stringify({ requestId: c.get("requestId"), route: c.req.routePath, error: errorInfo(err) }));
  return errorResponse(c, errors.internal());
});
