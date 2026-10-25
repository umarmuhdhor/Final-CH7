import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../env";
import { deleteGuardianLink, deleteMember, listMembers } from "../db/repo/families";
import { requireDevice, requireMode } from "../http/auth";
import { errors } from "../http/errors";
import { keyHash } from "../http/keyHash";
import { clientIp, hit, limits } from "../http/rateLimit";
import { readJson, readOptionalJson } from "../http/validate";
import { issueCode, joinFamily } from "../services/family";

const joinBody = z.object({ code: z.string().regex(/^\d{6}$/, "must be 6 digits") });
const codeBody = z.object({ refresh: z.boolean().optional() }).strict();

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

/** GD-04: 404 when the device is not one of my members (anti-enumeration, R3 §1). */
family.delete("/family/members/:deviceId", requireMode("guardian"), async (c) => {
  const removed = await deleteMember(c.get("sql"), c.get("principal").deviceId, c.req.param("deviceId"));
  if (!removed) throw errors.notFound();
  return c.json({ ok: true });
});

/** PF-01. */
family.delete("/family/guardian", requireMode("protected"), async (c) => {
  if (!(await deleteGuardianLink(c.get("sql"), c.get("principal").deviceId))) throw errors.notFound();
  return c.json({ ok: true });
});
