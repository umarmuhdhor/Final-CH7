import type { MiddlewareHandler } from "hono";
import type { AppEnv, DeviceMode } from "../env";
import { findByTokenHash, touchLastSeen } from "../db/repo/devices";
import { sha256 } from "./crypto";
import { errors } from "./errors";
import { clientIp, hit, limits } from "./rateLimit";

const BEARER = /^Bearer (shoo_[A-Za-z0-9_-]{8,128})$/;

/** Bearer token → principal (R3 §2). The token is hashed and never logged. */
export const requireDevice: MiddlewareHandler<AppEnv> = async (c, next) => {
  const match = BEARER.exec(c.req.header("authorization") ?? "");
  if (!match?.[1]) throw errors.unauthorized();

  const sql = c.get("sql");
  const device = await findByTokenHash(sql, await sha256(match[1]));
  if (!device) {
    // Only well-formed unknown tokens are counted (a malformed header costs no DB work), and valid
    // tokens never are, so neighbours behind the same CGNAT IP keep working. Over the limit → 429.
    await hit(sql, limits.authFail, clientIp((n) => c.req.header(n)));
    throw errors.unauthorized();
  }

  c.set("principal", {
    deviceId: device.id,
    mode: device.mode,
    name: device.name,
    language: device.language,
  });
  if (device.stale) await touchLastSeen(sql, device.id);
  await next();
};

/** After requireDevice: 403 forbidden unless the device has this mode (R3 §3). */
export const requireMode =
  (mode: DeviceMode): MiddlewareHandler<AppEnv> =>
  async (c, next) => {
    if (c.get("principal").mode !== mode) throw errors.forbidden();
    await next();
  };
