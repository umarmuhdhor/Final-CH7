import { Hono } from "hono";
import type { AppEnv } from "./env";
import { createSql } from "./db/client";
import { ApiError, errorResponse, errors } from "./http/errors";
import { blocklist } from "./routes/blocklist";
import { devices } from "./routes/devices";
import { family } from "./routes/family";
import { health } from "./routes/health";
import { joinPage } from "./routes/join-page";
import { scans } from "./routes/scans";
import { screenshots } from "./routes/screenshots";
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
  c.set("sql", createSql(c.env));
  await next();
});

app.route("/", health);
app.route("/", devices);
app.route("/", blocklist);
app.route("/", family);
app.route("/", joinPage);
app.route("/", scans);
app.route("/", screenshots);
app.route("/", verdicts);

app.notFound((c) => errorResponse(c, errors.notFound()));

app.onError((err, c) => {
  if (err instanceof ApiError) return errorResponse(c, err);
  // Never log request bodies or headers: they carry tokens and names (SECURITY §3 P6, T3).
  // The route pattern, not the path: paths carry scan and device ids (D-alief-40).
  console.error(JSON.stringify({ requestId: c.get("requestId"), route: c.req.routePath, error: errorInfo(err) }));
  return errorResponse(c, errors.internal());
});
