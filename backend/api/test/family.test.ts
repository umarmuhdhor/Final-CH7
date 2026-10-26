import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import fixture from "../../../contracts/fixtures/family-members.json";
import { claimCode } from "../src/db/repo/codes";
import { ApiError } from "../src/http/errors";
import { issueCode, randomCode } from "../src/services/family";
import { resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
beforeEach(() => resetDb(sql));

const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

const newCode = async (g: Created, json?: unknown) => {
  const res = await call("/family/code", { method: "POST", token: g.token, json });
  expect(res.status).toBe(200);
  return (await res.json()) as { code: string; expiresAt: string; inviteUrl: string };
};
const join = (p: Created, code: string, ip?: string) =>
  call("/family/join", { method: "POST", token: p.token, json: { code }, ip });

/** Any 6-digit code that is not the active one. */
const otherCode = (code: string, step = 1) => String((Number(code) + step) % 1_000_000).padStart(6, "0");

describe("POST /family/code", () => {
  it("returns a 6-digit code valid 30 min with an invite link /j/<code>", async () => {
    const g = await createDevice("Adhella", "guardian");
    const before = Date.now();
    const body = await newCode(g);
    expect(Object.keys(body).sort()).toEqual(["code", "expiresAt", "inviteUrl"]);
    expect(body.code).toMatch(/^\d{6}$/);
    const ttl = new Date(body.expiresAt).getTime() - before;
    expect(ttl).toBeGreaterThan(30 * 60_000 - 5_000);
    expect(ttl).toBeLessThanOrEqual(30 * 60_000 + 1_000);
    expect(body.inviteUrl).toBe(`http://localhost:8787/j/${body.code}`);
  });

  it("returns the same active code again (no body or {}), so the screen and a shared link match", async () => {
    const g = await createDevice("G", "guardian");
    const first = await newCode(g);
    expect(await newCode(g)).toEqual(first);
    expect(await newCode(g, {})).toEqual(first);
    expect(await newCode(g, { refresh: false })).toEqual(first);
  });

  it("refresh: true makes a new code; the old one stops working at once", async () => {
    const g = await createDevice("G", "guardian");
    const first = await newCode(g);
    const second = await newCode(g, { refresh: true });
    expect(second.code).not.toBe(first.code);
    const rows = await sql`select code from family_codes where guardian_id = ${g.deviceId}`;
    expect(rows.map((r) => r.code)).toEqual([second.code]);
    const res = await join(await createDevice("Mom"), first.code);
    expect(res.status).toBe(404);
    expect(await errorCode(res)).toBe("code_invalid");
  });

  it("a code with 5 min or less left is replaced, so a shared link is not dead on arrival", async () => {
    const g = await createDevice("G", "guardian");
    const first = await newCode(g);
    await sql`update family_codes set expires_at = now() + interval '6 minutes' where code = ${first.code}`;
    expect((await newCode(g)).code).toBe(first.code);
    await sql`update family_codes set expires_at = now() + interval '4 minutes' where code = ${first.code}`;
    const second = await newCode(g);
    expect(second.code).not.toBe(first.code);
    expect(new Date(second.expiresAt).getTime() - Date.now()).toBeGreaterThan(29 * 60_000);
  });

  it("parallel requests for the active code agree on one code", async () => {
    const g = await createDevice("G", "guardian");
    const codes = await Promise.all(Array.from({ length: 4 }, () => newCode(g).then((b) => b.code)));
    expect(new Set(codes).size).toBe(1);
  });

  it.each([[{ refresh: "yes" }], [{ refresh: 1 }], [{ other: true }], [[]]])("422 invalid_body for %j", async (json) => {
    const g = await createDevice("G", "guardian");
    const res = await call("/family/code", { method: "POST", token: g.token, json });
    expect(res.status).toBe(422);
    expect(await errorCode(res)).toBe("invalid_body");
  });

  it("403 forbidden for a protected device", async () => {
    const p = await createDevice("Mom", "protected");
    const res = await call("/family/code", { method: "POST", token: p.token });
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("forbidden");
  });

  it("401 without token", async () => {
    expect((await call("/family/code", { method: "POST" })).status).toBe(401);
  });

  it("rate limits 6 per minute per guardian", async () => {
    const g = await createDevice("G", "guardian");
    for (let i = 0; i < 6; i++) await newCode(g);
    const res = await call("/family/code", { method: "POST", token: g.token });
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("rate_limited");
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);
  });

  it("503 code_unavailable when every drawn code is active; never steals one", async () => {
    const g1 = await createDevice("G1", "guardian");
    const g2 = await createDevice("G2", "guardian");
    await sql`insert into family_codes (code, guardian_id, expires_at)
      values ('123456', ${g1.deviceId}, now() + interval '30 minutes')`;
    let draws = 0;
    const err = await issueCode(sql, g2.deviceId, false, () => (draws++, "123456")).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect([(err as ApiError).status, (err as ApiError).code]).toEqual([503, "code_unavailable"]);
    expect(draws).toBe(20); // CODE_TRIES
    const rows = await sql`select code, guardian_id from family_codes`;
    expect(rows.map((r) => [r.code, r.guardian_id])).toEqual([["123456", g1.deviceId]]);
  });

  // Whole code space taken, end to end. Inserting 10^6 rows is too slow for CI: opt in with SHOO_SLOW_TESTS=1.
  it.runIf(env.SHOO_SLOW_TESTS === "1")("503 over HTTP when all 10^6 codes are active", async () => {
    const g1 = await createDevice("G1", "guardian");
    const g2 = await createDevice("G2", "guardian");
    await sql`insert into family_codes (code, guardian_id, expires_at)
      select lpad(n::text, 6, '0'), ${g1.deviceId}, now() + interval '30 minutes' from generate_series(0, 999999) n`;
    const res = await call("/family/code", { method: "POST", token: g2.token });
    expect(res.status).toBe(503);
    expect(await errorCode(res)).toBe("code_unavailable");
    const [row] = await sql<{ n: number }[]>`select count(*)::int as n from family_codes where guardian_id = ${g1.deviceId}`;
    expect(row!.n).toBe(1_000_000);
  }, 60_000); // a million rows take longer than the default 5 s
});

describe("claimCode", () => {
  it("takes over an expired code, refuses an active one", async () => {
    const g1 = await createDevice("G1", "guardian");
    const g2 = await createDevice("G2", "guardian");
    await sql`insert into family_codes (code, guardian_id, expires_at) values
      ('111111', ${g1.deviceId}, now() - interval '1 second'),
      ('222222', ${g1.deviceId}, now() + interval '30 minutes')`;
    const taken = await sql.begin((tx) => claimCode(tx, g2.deviceId, "111111"));
    expect(taken?.code).toBe("111111");
    expect(new Date(taken!.expiresAt).getTime()).toBeGreaterThan(Date.now());
    expect(await sql.begin((tx) => claimCode(tx, g2.deviceId, "222222"))).toBeUndefined();
    const rows = await sql`select code, guardian_id from family_codes order by code`;
    expect(rows.map((r) => [r.code, r.guardian_id])).toEqual([["111111", g2.deviceId], ["222222", g1.deviceId]]);
  });

  it("randomCode is always 6 digits", () => {
    for (let i = 0; i < 2000; i++) expect(randomCode()).toMatch(/^\d{6}$/);
  });
});

describe("POST /family/join", () => {
  it("joins with a valid code and returns the guardian", async () => {
    const g = await createDevice("Adhella", "guardian");
    const p = await createDevice("Mom", "protected");
    const { code } = await newCode(g);
    const res = await join(p, code);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ guardian: { deviceId: g.deviceId, name: "Adhella", avatarId: g.avatarId } });
    const [link] = await sql`select guardian_id from family_links where protected_id = ${p.deviceId}`;
    expect(link!.guardian_id).toBe(g.deviceId);
  });

  it("a code is multi-use while valid, until the family is full", async () => {
    const g = await createDevice("G", "guardian");
    const { code } = await newCode(g);
    for (const name of ["P1", "P2", "P3"]) {
      expect((await join(await createDevice(name), code)).status).toBe(200);
    }
    const res = await join(await createDevice("P4"), code);
    expect(res.status).toBe(409);
    expect(await errorCode(res)).toBe("family_full");
  });

  it("410 code_expired after 30 min", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const { code } = await newCode(g);
    await sql`update family_codes set expires_at = now() - interval '1 second' where code = ${code}`;
    const res = await join(p, code);
    expect(res.status).toBe(410);
    expect(await errorCode(res)).toBe("code_expired");
  });

  it("404 code_invalid for an unknown code", async () => {
    const res = await join(await createDevice("Mom"), "000000");
    expect(res.status).toBe(404);
    expect(await errorCode(res)).toBe("code_invalid");
  });

  it.each([[{}], [{ code: "1234" }], [{ code: "1234567" }], [{ code: "12a456" }], [{ code: 123456 }]])("422 invalid_body for %j", async (json) => {
    const p = await createDevice("Mom");
    const res = await call("/family/join", { method: "POST", token: p.token, json });
    expect(res.status).toBe(422);
  });

  it("403 for a guardian, 409 already_connected for a linked protected", async () => {
    const g = await createDevice("G", "guardian");
    const { code } = await newCode(g);
    const asGuardian = await call("/family/join", { method: "POST", token: g.token, json: { code } });
    expect(asGuardian.status).toBe(403);

    const p = await createDevice("Mom");
    expect((await join(p, code)).status).toBe(200);
    const again = await join(p, code);
    expect(again.status).toBe(409);
    expect(await errorCode(again)).toBe("already_connected");
  });

  it("5 failures per device in 10 minutes → 429 too_many_attempts, even with a valid code", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const { code } = await newCode(g);
    for (let i = 0; i < 5; i++) expect((await join(p, otherCode(code))).status).toBe(404);
    const res = await join(p, code);
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("too_many_attempts");
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);

    // Other devices on other IPs are not affected.
    expect((await join(await createDevice("Dad"), code)).status).toBe(200);
  });

  it("20 failures per IP in 10 minutes → 429 for every device on that IP (CGNAT-tolerant)", async () => {
    const g = await createDevice("G", "guardian");
    const { code } = await newCode(g);
    const ip = "198.51.100.200";
    for (let i = 0; i < 20; i++) {
      expect((await join(await createDevice(`P${i}`), otherCode(code), ip)).status).toBe(404);
    }
    const res = await join(await createDevice("Fresh"), code, ip);
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("too_many_attempts");

    // Only hashes are stored, never the raw IP.
    const hash = await keyHash(`join:${ip}`);
    const [row] = await sql<{ n: number }[]>`select count(*)::int as n from join_attempts where ip_hash = ${hash}`;
    expect(row!.n).toBe(20);
  });

  it("code_expired counts as a failure; family_full and already_connected do not", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const { code } = await newCode(g);
    await sql`update family_codes set expires_at = now() - interval '1 second' where code = ${code}`;
    expect((await join(p, code)).status).toBe(410);

    const fresh = (await newCode(g)).code;
    for (const name of ["P1", "P2", "P3"]) expect((await join(await createDevice(name), fresh)).status).toBe(200);
    expect((await join(p, fresh)).status).toBe(409); // family_full

    const rows = await sql<{ success: boolean }[]>`select success from join_attempts where device_id = ${p.deviceId}`;
    expect(rows.map((r) => r.success)).toEqual([false]);
  });

  it("already_connected does not record an attempt", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const { code } = await newCode(g);
    expect((await join(p, code)).status).toBe(200);
    expect((await join(p, code)).status).toBe(409);
    const rows = await sql<{ success: boolean }[]>`select success from join_attempts where device_id = ${p.deviceId}`;
    expect(rows.map((r) => r.success)).toEqual([true]);
  });

  it("failures older than 10 minutes no longer count", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const { code } = await newCode(g);
    for (let i = 0; i < 5; i++) await join(p, otherCode(code));
    await sql`update join_attempts set attempted_at = now() - interval '11 minutes'`;
    expect((await join(p, code)).status).toBe(200);
  });

  it("parallel guesses cannot exceed the 5-failure budget", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    const { code } = await newCode(g);
    const statuses = await Promise.all(
      Array.from({ length: 12 }, (_, i) => join(p, otherCode(code, 1 + i)).then((r) => r.status)),
    );
    expect(statuses.filter((s) => s === 404 || s === 410)).toHaveLength(5);
    expect(statuses.filter((s) => s === 429)).toHaveLength(7);
  });

  it("two parallel joins for the last slot: exactly one succeeds", async () => {
    const g = await createDevice("G", "guardian");
    const { code } = await newCode(g);
    for (const name of ["P1", "P2"]) expect((await join(await createDevice(name), code)).status).toBe(200);
    const [a, b] = [await createDevice("A"), await createDevice("B")];
    const statuses = (await Promise.all([join(a, code), join(b, code)])).map((r) => r.status).sort();
    expect(statuses).toEqual([200, 409]);
    const [row] = await sql<{ n: number }[]>`select count(*)::int as n from family_links where guardian_id = ${g.deviceId}`;
    expect(row!.n).toBe(3);
  });
});

describe("GET /family/members", () => {
  const members = async (g: Created) => {
    const res = await call("/family/members", { token: g.token });
    expect(res.status).toBe(200);
    return (await res.json()) as typeof fixture;
  };

  it("matches the fixture shape: extensionActive and lastScan", async () => {
    const g = await createDevice("G", "guardian");
    const { code } = await newCode(g);
    const mom = await createDevice("Mom");
    const dad = await createDevice("Dad");
    const aunt = await createDevice("Aunt");
    for (const p of [mom, dad, aunt]) expect((await join(p, code)).status).toBe(200);

    await sql`update devices set ext_last_seen_at = now() - interval '1 hour' where id = ${mom.deviceId}`;
    await sql`update devices set ext_last_seen_at = now() - interval '25 hours' where id = ${dad.deviceId}`;
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at) values
      (${mom.deviceId}, 'https://old.example/', 'old.example', 41, 'warning', '2026-10-21T03:00:00Z'),
      (${mom.deviceId}, 'https://bca-verifikasi.site/login?ref=wa', 'bca-verifikasi.site', 92, 'blocked', '2026-10-21T04:05:00Z')`;

    const body = await members(g);
    expect(Object.keys(body)).toEqual(Object.keys(fixture));
    expect(body.members).toEqual([
      {
        deviceId: mom.deviceId, name: "Mom", avatarId: mom.avatarId, extensionActive: true,
        lastScan: { status: "blocked", score: 92, url: "https://bca-verifikasi.site/login?ref=wa", detectedAt: "2026-10-21T04:05:00.000Z" },
      },
      { deviceId: dad.deviceId, name: "Dad", avatarId: dad.avatarId, extensionActive: false, lastScan: null },
      // No heartbeat yet → active (never "Not connected" without evidence).
      { deviceId: aunt.deviceId, name: "Aunt", avatarId: aunt.avatarId, extensionActive: true, lastScan: null },
    ]);
    for (const [i, m] of body.members.entries()) {
      const ref = fixture.members[Math.min(i, 1)]!;
      expect(Object.keys(m).sort()).toEqual(Object.keys(ref).sort());
    }
    expect(Object.keys(body.members[0]!.lastScan!).sort()).toEqual(Object.keys(fixture.members[0]!.lastScan!).sort());
  });

  it("only the guardian's own members; 403 for protected", async () => {
    const g1 = await createDevice("G1", "guardian");
    const g2 = await createDevice("G2", "guardian");
    const p = await createDevice("Mom");
    expect((await join(p, (await newCode(g1)).code)).status).toBe(200);
    expect((await members(g2)).members).toEqual([]);
    expect((await call("/family/members", { token: p.token })).status).toBe(403);
  });
});

describe("disconnect", () => {
  const linked = async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    expect((await join(p, (await newCode(g)).code)).status).toBe(200);
    return { g, p };
  };

  it("DELETE /family/members/{id}: guardian removes a member, then no longer sees it", async () => {
    const { g, p } = await linked();
    const res = await call(`/family/members/${p.deviceId}`, { method: "DELETE", token: g.token });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    const list = (await (await call("/family/members", { token: g.token })).json()) as typeof fixture;
    expect(list.members).toEqual([]);
    // The protected device can join again.
    expect((await join(p, (await newCode(g)).code)).status).toBe(200);
  });

  it("DELETE /family/members/{id}: 404 for a device that is not my member", async () => {
    const { p } = await linked();
    const other = await createDevice("Other", "guardian");
    const res = await call(`/family/members/${p.deviceId}`, { method: "DELETE", token: other.token });
    expect(res.status).toBe(404);
    expect(await errorCode(res)).toBe("not_found");
    expect((await call("/family/members/nope", { method: "DELETE", token: other.token })).status).toBe(404);
    expect((await call(`/family/members/${p.deviceId}`, { method: "DELETE", token: p.token })).status).toBe(403);
  });

  it("DELETE /family/guardian: protected leaves; 404 when not connected; 403 for guardian", async () => {
    const { g, p } = await linked();
    expect((await call("/family/guardian", { method: "DELETE", token: g.token })).status).toBe(403);
    const res = await call("/family/guardian", { method: "DELETE", token: p.token });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    const again = await call("/family/guardian", { method: "DELETE", token: p.token });
    expect(again.status).toBe(404);
    const list = (await (await call("/family/members", { token: g.token })).json()) as typeof fixture;
    expect(list.members).toEqual([]);
  });
});
