import { Hono } from "hono";
import postgres from "postgres";
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
  // ON-02 (#120): never a 422. Anything that is not avatar_01…avatar_12 falls back to random.
  avatarId: z.unknown().optional(),
});

const AVATAR_ID = /^avatar_(0[1-9]|1[0-2])$/;

const patchBody = z.object({
  name: name.optional(),
  apnsToken: apnsToken.nullable().optional(),
  language: z.enum(["en", "id"]).optional(),
  extensionLastSeenAt: isoTime.optional(),
  // PF-01 member detail ("iPhone 15 · iOS 26"): marketing name and major iOS version only.
  deviceModel: z.string().regex(/^[A-Za-z0-9 ()]{1,40}$/, "must be a device name").optional(),
  osVersion: z.string().regex(/^[0-9]{1,3}$/, "must be a major version").optional(),
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
  // After validation, so rejected bodies spend no global budget (accepted trade-off, D-alief-B12 i).
  await hit(sql, limits.createDeviceAll, "all");

  const token = `shoo_${base64url(randomBytes(32))}`;
  const avatarId =
    typeof body.avatarId === "string" && AVATAR_ID.test(body.avatarId)
      ? body.avatarId
      : `avatar_${String(randomAvatar()).padStart(2, "0")}`;
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
    deviceModel: body.deviceModel,
    osVersion: body.osVersion,
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
  let paths: string[] | undefined;
  for (let attempt = 1; !paths; attempt++) {
    try {
      paths = await deleteDevice(c.get("sql"), c.get("principal").deviceId);
    } catch (err) {
      const code = err instanceof postgres.PostgresError ? err.code : undefined;
      // A rare deadlock or lock timeout with a concurrent writer (e.g. retention): Postgres rolled
      // back, retry once. Deleting your data must not fail on a race (SECURITY §3 P3).
      if ((code === "40P01" || code === "40001" || code === "55P03") && attempt < 2) {
        await new Promise((r) => setTimeout(r, 100));
        continue;
      }
      throw err;
    }
  }
  c.executionCtx.waitUntil(deleteScreenshots(c.get("sql"), c.env, paths));
  return c.json({ ok: true });
});
