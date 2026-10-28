import { Hono } from "hono";
import postgres from "postgres";
import { z } from "zod";
import type { AppEnv } from "../env";
import { deleteDevice, findProfile, insertDevice, insertProtectedCopy, updateDevice } from "../db/repo/devices";
import { guardianOf } from "../db/repo/families";
import { keyHash } from "../http/keyHash";
import { joinFamily } from "../services/family";
import { deleteScreenshots } from "../services/screenshots";
import { requireDevice, requireMode } from "../http/auth";
import { base64url, randomBytes, sha256 } from "../http/crypto";
import { errors } from "../http/errors";
import { clientIp, hit, limits } from "../http/rateLimit";
import { displayName, isoTime, readJson } from "../http/validate";
import { fromClock, isTimeZone, toClock } from "../services/push/quiet";

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

// "22:00": 24-hour local time, whole minutes.
const clock = z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/, "must be HH:MM");

// PF-01 "Pengaturan/Notifikasi" (proposed): every key optional, only sent keys change.
const notificationsBody = z
  .object({
    warning: z.boolean(),
    blocked: z.boolean(),
    family: z.boolean(),
    protectionOff: z.boolean(),
    weeklySummary: z.boolean(),
    quietHours: z.boolean(),
    quietStart: clock,
    quietEnd: clock,
  })
  .partial()
  .strict();

const patchBody = z.object({
  name: name.optional(),
  apnsToken: apnsToken.nullable().optional(),
  language: z.enum(["en", "id"]).optional(),
  extensionLastSeenAt: isoTime.optional(),
  // PF-01 member detail ("iPhone 15 · iOS 26"): marketing name and major iOS version only.
  deviceModel: z.string().regex(/^[A-Za-z0-9 ()]{1,40}$/, "must be a device name").optional(),
  osVersion: z.string().regex(/^[0-9]{1,3}$/, "must be a major version").optional(),
  // PF-01 "Ubah foto": one of the onboarding avatars (ON-02).
  avatarId: z.string().regex(AVATAR_ID, "must be avatar_01…avatar_12").optional(),
  // PF-01 quiet hours and weekly summary: the phone's IANA zone, e.g. "Asia/Makassar".
  timeZone: z
    .string()
    .max(40)
    .refine((z) => /^[A-Za-z_]+(\/[A-Za-z0-9_+-]+){0,2}$/.test(z) && isTimeZone(z), "must be an IANA time zone")
    .optional(),
  notifications: notificationsBody.optional(),
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
    avatarId: body.avatarId,
    timeZone: body.timeZone,
    notifications: body.notifications && {
      ...body.notifications,
      quietStart: body.notifications.quietStart === undefined ? undefined : fromClock(body.notifications.quietStart),
      quietEnd: body.notifications.quietEnd === undefined ? undefined : fromClock(body.notifications.quietEnd),
    },
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
  const { notifications: n, ...rest } = profile;
  return c.json({
    ...rest,
    guardian,
    notifications: { ...n, quietStart: toClock(n.quietStart), quietEnd: toClock(n.quietEnd) },
  });
});

const becomeProtectedBody = z.object({ code: z.string().regex(/^\d{6}$/, "must be 6 digits") }).strict();

/**
 * PF-01 "Punya kode undangan?" (proposed): a guardian without members joins a family as protected.
 * Device mode never changes (I1), so a protected copy is made, joined with the code (same checks
 * and attempt limits as POST /family/join), and only then the old device is deleted. A failed join
 * removes the copy and leaves the guardian as it was. The new token exists only in this response.
 */
devices.post("/devices/me/protected", requireDevice, requireMode("guardian"), async (c) => {
  const sql = c.get("sql");
  const ip = clientIp((n) => c.req.header(n));
  await hit(sql, limits.createDevice, ip);
  const { code } = await readJson(c, becomeProtectedBody);
  const oldId = c.get("principal").deviceId;
  const [{ n } = { n: 0 }] = await sql<{ n: number }[]>`select count(*)::int as n from family_links where guardian_id = ${oldId}`;
  if (n > 0) throw errors.hasMembers();

  const token = `shoo_${base64url(randomBytes(32))}`;
  const copy = await insertProtectedCopy(sql, oldId, await sha256(token));
  if (!copy) throw errors.unauthorized();
  let guardian;
  try {
    guardian = await joinFamily(sql, copy.id, await keyHash(`join:${ip}`), code);
  } catch (err) {
    await deleteDevice(sql, copy.id);
    throw err;
  }
  const paths = await deleteDevice(sql, oldId);
  c.executionCtx.waitUntil(deleteScreenshots(sql, c.env, paths));
  return c.json({ deviceId: copy.id, token, avatarId: copy.avatarId, guardian });
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
