import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { deleteDevice, findProfile, insertDevice, updateDevice } from "../db/repo/devices";
import { guardianOf } from "../db/repo/families";
import { deleteScreenshots } from "../services/screenshots";
import { requireDevice } from "../http/auth";
import { base64url, randomBytes, sha256 } from "../http/crypto";
import { errors } from "../http/errors";
import { clientIp, hit, limits } from "../http/rateLimit";
import { displayName, isoTime, readJson } from "../http/validate";

const name = displayName;
// APNs device tokens are hex; Apple says not to assume a fixed length.
const apnsToken = z.string().regex(/^[0-9a-fA-F]{32,200}$/, "must be a hex APNs token");

const createBody = z.object({
  name,
  mode: z.enum(["guardian", "protected"]),
  apnsToken: apnsToken.optional(),
});

const patchBody = z.object({
  name: name.optional(),
  apnsToken: apnsToken.nullable().optional(),
  language: z.enum(["en", "id"]).optional(),
  extensionLastSeenAt: isoTime.optional(),
});

/** 1–12 without modulo bias (256 % 12 != 0): reject bytes ≥ 252. */
function randomAvatar(): number {
  for (;;) {
    const b = randomBytes(1)[0]!;
    if (b < 252) return (b % 12) + 1;
  }
}

const FUTURE_SKEW_MS = 5 * 60 * 1000;

export const devices = new Hono<AppEnv>();

devices.post("/devices", async (c) => {
  const sql = c.get("sql");
  await hit(sql, limits.createDevice, clientIp((n) => c.req.header(n)));
  const body = await readJson(c, createBody);

  const token = `shoo_${base64url(randomBytes(32))}`;
  const avatarId = `avatar_${String(randomAvatar()).padStart(2, "0")}`;
  const deviceId = await insertDevice(sql, {
    name: body.name,
    mode: body.mode,
    avatarId,
    apnsToken: body.apnsToken ?? null,
    tokenHash: await sha256(token),
  });
  // The plain token exists only in this response (D-alief-10).
  return c.json({ deviceId, token, avatarId }, 201);
});

devices.patch("/devices/me", requireDevice, async (c) => {
  const body = await readJson(c, patchBody);
  let seen: Date | undefined;
  if (body.extensionLastSeenAt !== undefined) {
    seen = new Date(body.extensionLastSeenAt);
    if (seen.getTime() > Date.now() + FUTURE_SKEW_MS) {
      throw errors.invalidBody("extensionLastSeenAt: must not be in the future");
    }
  }
  await updateDevice(c.get("sql"), c.get("principal").deviceId, {
    name: body.name,
    apnsToken: body.apnsToken,
    language: body.language,
    extensionLastSeenAt: seen,
  });
  return c.json({ ok: true });
});

/** Contract: profile + guardian (Protected learns it was disconnected), always null for a Guardian. */
devices.get("/devices/me", requireDevice, async (c) => {
  const sql = c.get("sql");
  const { deviceId, mode } = c.get("principal");
  const profile = await findProfile(sql, deviceId);
  if (!profile) throw errors.unauthorized();
  const guardian = mode === "protected" ? await guardianOf(sql, deviceId) : null;
  return c.json({ ...profile, guardian });
});

/**
 * Proposal C19 (SECURITY §3 P3, App Store 5.1.1(v)): delete everything about this device.
 * Storage objects go after the DB commit; a Storage failure never brings the data back.
 */
devices.delete("/devices/me", requireDevice, async (c) => {
  const paths = await deleteDevice(c.get("sql"), c.get("principal").deviceId);
  c.executionCtx.waitUntil(deleteScreenshots(c.env, paths));
  return c.json({ ok: true });
});
