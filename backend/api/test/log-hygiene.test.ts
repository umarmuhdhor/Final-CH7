import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { runRetention } from "../src/cron/retention";
import { logReplicaUsage } from "../src/services/replicas";
import { limits } from "../src/http/rateLimit";
import { PUSH_CAP } from "../src/services/push/notify";
import { b64, jpeg } from "./helpers/images";
import { gzipBase64 } from "./helpers/replica";
import { resetDb, testSql } from "./helpers/resetDb";
import { seedScreenshot } from "./helpers/screenshots";
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
      json: {
        ...body, domain: "very-private-domain.example", url: "https://very-private-domain.example/login?u=mom",
        screenshotBase64: b64(jpeg(50, 50)),
        pageReplicaBase64: await gzipBase64("<html><body>Mom Secret very-private-domain</body></html>"),
      },
    });
    const { id } = (await scanRes.json()) as { id: string };
    // Fase 20a (K3 a): the screenshot above is ignored with one bare event, no id or domain.
    expect(lines.filter((l) => l.includes("screenshot_ignored")).map((l) => JSON.parse(l))).toEqual([{ event: "screenshot_ignored" }]);
    // An older scan's screenshot, seeded through the service, so its serving and deletion stay in the flow.
    await seedScreenshot(sql, { id, ownerId: p.deviceId, domain: "very-private-domain.example" }, b64(jpeg(50, 50)));
    expect((await sql`select screenshot_path from scans where id = ${id}`)[0]?.screenshot_path).toBeTruthy();
    // EX-07: the replica is stored in waitUntil after the push.
    await vi.waitFor(async () => expect((await sql`select replica_path from scans where id = ${id}`)[0]?.replica_path).toBeTruthy());
    // A broken replica on a second scan: the drop is logged with its reason only.
    await call("/scans", {
      method: "POST", token: p.token, ip,
      json: { ...body, domain: "other-private.example", url: "https://other-private.example/x", pageReplicaBase64: "@@broken@@" },
    });
    await vi.waitFor(() => expect(lines.some((l) => l.includes('"replica_dropped"'))).toBe(true));
    // Fase 19: a family over its quota, and the hourly gauge: reason and aggregates only.
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at, replica_path, replica_bytes)
      select ${g.deviceId}, 'https://quota-private.example/', 'quota-private.example', 92, 'blocked', now(),
             ${g.deviceId} || '/f' || n || '-replica.html.gz', 1000
      from generate_series(1, 60) n`;
    await call("/scans", {
      method: "POST", token: p.token, ip,
      json: { ...body, domain: "third-private.example", url: "https://third-private.example/x", pageReplicaBase64: await gzipBase64("<html>x</html>") },
    });
    await vi.waitFor(() => expect(lines.some((l) => l.includes('"reason":"family_quota"'))).toBe(true));
    await logReplicaUsage(sql);
    expect(lines.some((l) => l.includes('"event":"replica_quota_usage"'))).toBe(true);
    const detail = (await (await call(`/scans/${id}`, { token: g.token })).json()) as { screenshotUrl: string | null; pageReplicaUrl: string | null };
    expect(detail.screenshotUrl).toBeTruthy();
    expect((await call(new URL(detail.screenshotUrl!).pathname + new URL(detail.screenshotUrl!).search, { token: g.token })).status).toBe(200);
    expect(detail.pageReplicaUrl).toBeTruthy();
    await call(new URL(detail.pageReplicaUrl!).pathname + new URL(detail.pageReplicaUrl!).search);
    await call("/verdicts", { method: "POST", token: g.token, json: { scanId: id, value: "not_safe" } });
    await call("/verdicts?domain=very-private-domain.example", { token: p.token });
    // EX-06 fase 25 K7: the fresh verdict above is logged as verdict_seen (numbers + value only).
    expect(lines.some((l) => l.includes('"verdict_seen"'))).toBe(true);
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
    // E7 (fase 24a-1): the inactive-devices step runs in dry_run (wrangler.jsonc) and logs counts only.
    expect(lines.some((l) => l.includes('"event":"inactive_devices"') && l.includes('"mode":"dry_run"'))).toBe(true);
    // Fase 21a: the ops status endpoint, with and without the token.
    await call("/ops/status", { headers: { authorization: `Bearer ${env.OPS_STATUS_TOKEN}` } });
    await call("/ops/status", { headers: { authorization: "Bearer wrong-ops-token-wrong-ops-token-x" } });

    expect(lines.length).toBeGreaterThan(0);
    const all = lines.join("\n");
    for (const leak of [
      g.token, p.token, g.deviceId, p.deviceId, id, "Adhella", "Mom Secret", "very-private-domain", "https://",
      "shoo_wrong", code, ip, "sig=", "ab".repeat(32), env.SCREENSHOT_URL_SECRET!, env.RATE_KEY_SECRET!,
      "replica.html.gz", "other-private", "quota-private", "third-private", env.OPS_STATUS_TOKEN!, "wrong-ops-token",
    ]) {
      expect(all, `log contains ${leak.slice(0, 12)}`).not.toContain(leak);
    }
  });
});

describe("inactive devices log counts only (E7, fase 24a-1)", () => {
  it("dry_run and delete log the mode and counts, never ids, names or push tokens", async () => {
    const lines: string[] = [];
    for (const m of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, m).mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));
    }
    const g = await createDevice("Adhella Secret", "guardian");
    const p = await createDevice("Mom Secret");
    await call("/devices/me", { method: "PATCH", token: g.token, json: { apnsToken: "cd".repeat(32) } });
    await sql`insert into family_links (protected_id, guardian_id) values (${p.deviceId}, ${g.deviceId})`;
    await sql`update devices set last_seen_at = now() - interval '100 days', created_at = now() - interval '200 days'`;

    await runRetention(sql, env);
    await runRetention(sql, env, { inactiveMode: "delete" });
    expect((await sql`select 1 from devices`).length).toBe(0);
    const events = lines.filter((l) => l.includes('"event":"inactive_devices"'));
    expect(events.map((l) => JSON.parse(l))).toEqual([
      { event: "inactive_devices", mode: "dry_run", candidates: 2, deleted: 0, skipped: 0, failed: 0 },
      { event: "inactive_devices", mode: "delete", candidates: 2, deleted: 2, skipped: 0, failed: 0 },
    ]);
    const all = lines.join("\n");
    for (const leak of [g.token, p.token, g.deviceId, p.deviceId, "Adhella", "Mom Secret", "cd".repeat(32)]) {
      expect(all, `log contains ${leak.slice(0, 12)}`).not.toContain(leak);
    }
  });
});

describe("every rate limit has a test (429, or 401 + Retry-After for auth_fail; fase 12 hardening)", () => {
  it("the list of limits is the reviewed one; a new limit needs a test and an entry here", () => {
    // Bucket → test file that proves its 429.
    const tested: Record<string, string> = {
      devices_create: "devices.test.ts", healthz_db: "health.test.ts", healthz_db_all: "health.test.ts", family_code: "family.test.ts",
      scans_create: "scans.test.ts", screenshots_view: "screenshots.test.ts", verdicts_create: "verdicts.test.ts",
      verdicts_get: "verdicts.test.ts", auth_fail: "security-headers.test.ts", auth_fail_all: "security-headers.test.ts",
      devices_create_all: "security-review.test.ts", scans_create_all: "security-review.test.ts",
      favicons_view: "favicons.test.ts", favicons_fetch: "favicons.test.ts", favicons_fetch_all: "favicons.test.ts",
      replicas_ip: "replicas.test.ts", replicas_view: "replicas.test.ts", replicas_view_day: "replicas.test.ts",
      ops_status: "ops-status.test.ts",
    };
    expect(Object.values(limits).map((l) => l.bucket).sort()).toEqual(Object.keys(tested).sort());
    // Not in `limits`: join attempts (family.test.ts "too_many_attempts") and the push cap (push-notify.test.ts).
    expect(PUSH_CAP).toEqual({ max: 10, minutes: 10 });
  });
});
