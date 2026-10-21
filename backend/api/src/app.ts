import { Hono } from "hono";
import type { AppEnv } from "./env";
import { createSql } from "./db/client";
import { ApiError, errorResponse, errors } from "./http/errors";
import { blocklist } from "./routes/blocklist";
import { debugApns } from "./routes/debug-apns";
import { devices } from "./routes/devices";
import { family } from "./routes/family";
import { health } from "./routes/health";
import { joinPage } from "./routes/join-page";
import { scans } from "./routes/scans";
import { screenshots } from "./routes/screenshots";

export const app = new Hono<AppEnv>();

app.use("*", async (c, next) => {
  const requestId = crypto.randomUUID();
  c.set("requestId", requestId);
  c.header("x-request-id", requestId);

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
app.route("/", debugApns);

app.notFound((c) => errorResponse(c, errors.notFound()));

app.onError((err, c) => {
  if (err instanceof ApiError) return errorResponse(c, err);
  // Never log request bodies or headers: they carry tokens and names (SECURITY §3 P6, T3).
  console.error(JSON.stringify({ requestId: c.get("requestId"), path: c.req.path, error: String(err) }));
  return errorResponse(c, errors.internal());
});
