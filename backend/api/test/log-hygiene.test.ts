import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { runRetention } from "../src/cron/retention";
import { limits } from "../src/http/rateLimit";
import { PUSH_CAP } from "../src/services/push/notify";
import { b64, jpeg } from "./helpers/images";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

describe("logs carry no personal data (SECURITY §3 P6, D-alief-40)", () => {
  it("a full flow logs no tokens, names, ids, URLs, domains, codes, IPs or signatures", async () => {
    const lines: string[] = [];
    for (const m of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, m).mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));
    }
    const ip = "198.51.100.200";
    const g = await createDevice("Adhella Secret", "guardian");
    const p = await createDevice("Mom Secret");
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: "ab".repeat(32), language: "id" } });
    const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
    await call("/family/join", { method: "POST", token: p.token, json: { code: "0000" === code ? "1111" : "0000" }, ip });
    await call("/family/join", { method: "POST", token: p.token, json: { code }, ip });
    const { id: _i, verdict: _v, screenshotUrl: _s, ownerDeviceId: _o, ownerName: _n, ...body } = blocked92;
    const scanRes = await call("/scans", {
      method: "POST", token: p.token, ip,
      json: { ...body, domain: "very-private-domain.example", url: "https://very-private-domain.example/login?u=mom", screenshotBase64: b64(jpeg(50, 50)) },
    });
    const { id } = (await scanRes.json()) as { id: string };
    const detail = (await (await call(`/scans/${id}`, { token: g.token })).json()) as { screenshotUrl: string | null };
    if (detail.screenshotUrl) await call(new URL(detail.screenshotUrl).pathname + new URL(detail.screenshotUrl).search, { token: g.token });
    await call("/verdicts", { method: "POST", token: g.token, json: { scanId: id, value: "not_safe" } });
    await call("/verdicts?domain=very-private-domain.example", { token: p.token });
    await call("/devices/me", { token: "shoo_wrongwrongwrong", ip });
    await call(`/scans/${id}`, { token: "shoo_wrongwrongwrong2" });
    // waitUntil push work: done once its push_log row exists.
    await vi.waitFor(async () => expect((await sql`select 1 from push_log where scan_id = ${id}`).length).toBe(1));
    await call(`/family/members/${p.deviceId}`, { method: "DELETE", token: g.token });
    await call("/devices/me", { method: "DELETE", token: p.token });
    await call("/devices/me", { method: "DELETE", token: g.token });
    // waitUntil Storage work of DELETE /devices/me: done once the object is gone.
    await vi.waitFor(async () => {
      const info = await fetch(`${env.SUPABASE_URL}/storage/v1/object/info/screenshots/${p.deviceId}/${id}.jpg`, {
        headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY!, authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
      });
      await info.body?.cancel();
      expect(info.ok).toBe(false);
    });
    await runRetention(sql, env);

    expect(lines.length).toBeGreaterThan(0);
    const all = lines.join("\n");
    for (const leak of [
      g.token, p.token, g.deviceId, p.deviceId, id, "Adhella", "Mom Secret", "very-private-domain", "https://",
      "shoo_wrong", code, ip, "sig=", "ab".repeat(32), env.SCREENSHOT_URL_SECRET!, env.RATE_KEY_SECRET!,
    ]) {
      expect(all, `log contains ${leak.slice(0, 12)}`).not.toContain(leak);
    }
  });
});

describe("every rate limit has a test (429, or 401 + Retry-After for auth_fail; fase 12 hardening)", () => {
  it("the list of limits is the reviewed one; a new limit needs a test and an entry here", () => {
    // Bucket → test file that proves its 429.
    const tested: Record<string, string> = {
      devices_create: "devices.test.ts", healthz_db: "health.test.ts", family_code: "family.test.ts",
      scans_create: "scans.test.ts", screenshots_view: "screenshots.test.ts", verdicts_create: "verdicts.test.ts",
      verdicts_get: "verdicts.test.ts", auth_fail: "security-headers.test.ts",
      devices_create_all: "security-review.test.ts", scans_create_all: "security-review.test.ts",
    };
    expect(Object.values(limits).map((l) => l.bucket).sort()).toEqual(Object.keys(tested).sort());
    // Not in `limits`: join attempts (family.test.ts "too_many_attempts") and the push cap (push-notify.test.ts).
    expect(PUSH_CAP).toEqual({ max: 10, minutes: 10 });
  });
});
