import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { claimReminder, deleteGuardianLink, deleteMember, listMembers, setMemberNotify } from "../db/repo/families";
import { requireDevice, requireMode } from "../http/auth";
import { ApiError, errors } from "../http/errors";
import { errorInfo } from "../http/logError";
import { keyHash } from "../http/keyHash";
import { clientIp, hit, limits } from "../http/rateLimit";
import { readJson, readOptionalJson } from "../http/validate";
import { issueCode, joinFamily } from "../services/family";
import { deliverPush } from "../services/push/deliver";
import { familyPushText } from "../services/push/messages";
import { pushSender, type PushMessage } from "../services/push/sender";
import type { Context } from "hono";

const joinBody = z.object({ code: z.string().regex(/^\d{6}$/, "must be 6 digits") });
const codeBody = z.object({ refresh: z.boolean().optional() }).strict();
const memberBody = z.object({ notify: z.boolean() }).strict();

export const family = new Hono<AppEnv>();

family.use("/family/*", requireDevice);

/** GD-04, PR-03, R4 §1. No body (or `{}`) returns the active code; `{ refresh: true }` replaces it. */
family.post("/family/code", requireMode("guardian"), async (c) => {
  const sql = c.get("sql");
  const { deviceId } = c.get("principal");
  const { refresh } = await readOptionalJson(c, codeBody);
  await hit(sql, limits.familyCode, deviceId);
  const { code, expiresAt } = await issueCode(sql, deviceId, refresh === true);
  return c.json({ code, expiresAt, inviteUrl: `${c.env.INVITE_BASE_URL}/j/${code}` });
});

/** PR-01, PR-03, R4 §2. Attempts are limited per device and per IP (/64 for IPv6), hashed. */
family.post("/family/join", requireMode("protected"), async (c) => {
  const { code } = await readJson(c, joinBody);
  const ipHash = await keyHash(`join:${clientIp((n) => c.req.header(n))}`);
  const guardian = await joinFamily(c.get("sql"), c.get("principal").deviceId, ipHash, code);
  return c.json({ guardian });
});

/** GD-03. */
family.get("/family/members", requireMode("guardian"), async (c) => {
  return c.json({ members: await listMembers(c.get("sql"), c.get("principal").deviceId) });
});

/** Sends after the response, like the scan push; a push problem never fails the request. */
function sendLater(c: Context<AppEnv>, message: PushMessage): void {
  c.executionCtx.waitUntil(
    deliverPush(c.get("sql"), pushSender(c.env), message).catch((err) =>
      // Name only: a DB error can quote values (D-alief-40).
      console.error(JSON.stringify({ event: "push_failed", requestId: c.get("requestId"), error: errorInfo(err) })),
    ),
  );
}

/**
 * GD-04: 404 when the device is not one of my members (anti-enumeration, R3 §1).
 * PF-01: the member is told ("Adhella stopped protecting you") when it has an APNs token.
 */
family.delete("/family/members/:deviceId", requireMode("guardian"), async (c) => {
  const guardian = c.get("principal");
  const memberId = c.req.param("deviceId");
  const removed = await deleteMember(c.get("sql"), guardian.deviceId, memberId);
  if (!removed) throw errors.notFound();
  if (removed.apnsToken) {
    sendLater(c, {
      toDeviceId: memberId,
      apnsToken: removed.apnsToken,
      body: familyPushText(removed.language, "disconnected", guardian.name),
    });
  }
  return c.json({ ok: true });
});

/** PF-01 "Kabari saya" (proposed): `{ notify }` turns the scan push for this member on or off. */
family.patch("/family/members/:deviceId", requireMode("guardian"), async (c) => {
  const { notify } = await readJson(c, memberBody);
  if (!(await setMemberNotify(c.get("sql"), c.get("principal").deviceId, c.req.param("deviceId"), notify))) {
    throw errors.notFound();
  }
  return c.json({ ok: true });
});

/**
 * PF-01 "Ingatkan" (proposed): one push to the member to turn Shoo on in Safari, at most every 6 h.
 * 409 `push_unavailable` when the member has notifications off; 429 `remind_too_soon` with Retry-After.
 */
family.post("/family/members/:deviceId/remind", requireMode("guardian"), async (c) => {
  const guardian = c.get("principal");
  const target = await claimReminder(c.get("sql"), guardian.deviceId, c.req.param("deviceId"));
  switch (target.kind) {
    case "notMember":
      throw errors.notFound();
    case "noPush":
      throw new ApiError(409, "push_unavailable", "Member has notifications off");
    case "tooSoon":
      throw new ApiError(429, "remind_too_soon", "Already reminded recently", target.retryAfter);
    case "ok":
      sendLater(c, {
        toDeviceId: target.deviceId,
        apnsToken: target.apnsToken,
        body: familyPushText(target.language, "remind", guardian.name),
      });
      return c.json({ ok: true });
  }
});

/** PF-01. */
family.delete("/family/guardian", requireMode("protected"), async (c) => {
  if (!(await deleteGuardianLink(c.get("sql"), c.get("principal").deviceId))) throw errors.notFound();
  return c.json({ ok: true });
});
