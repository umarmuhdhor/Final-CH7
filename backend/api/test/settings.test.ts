import { env } from "cloudflare:workers";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { quietSql, runNotifications } from "../src/cron/notifications";
import type { OpsWriter } from "../src/db/repo/ops";
import { CRONS } from "../src/index";
import { summaryText } from "../src/services/push/messages";
import { guardianPush, ownPush } from "../src/services/push/notify";
import { isQuiet, localTime } from "../src/services/push/quiet";
import type { PushMessage, PushSender } from "../src/services/push/sender";
import postgres from "postgres";
import { deleteDevice } from "../src/db/repo/devices";
import { joinFamily } from "../src/services/family";
import { becomeProtected, type BecomeProtectedHooks } from "../src/services/becomeProtected";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
import { sha256 } from "../src/http/crypto";
import { adminSql, resetDb, testSql, withoutTriggers } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";

// PF-01 settings pages (Figma "Pengaturan/*"): notification switches, quiet hours, time zone,
// avatar, the hourly cron, terms and the share link. Proposed contract additions (backend/API.md).

const sql = testSql();
beforeEach(() => resetDb(sql));
afterEach(() => vi.restoreAllMocks());

const TOKEN = "a".repeat(64);
const TOKEN_G = "b".repeat(64);
const patch = (d: Created, json: unknown) => call("/devices/me", { method: "PATCH", token: d.token, json });
const me = async (d: Created) => (await call("/devices/me", { token: d.token })).json() as Promise<Record<string, unknown>>;
const link = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};
const principal = (d: Created, name: string, mode: "guardian" | "protected") =>
  ({ deviceId: d.deviceId, name, mode, language: "en" }) as Parameters<typeof guardianPush>[1];
const scan = (status: "blocked" | "warning") => ({ id: "00000000-0000-4000-8000-000000000001", status, score: status === "blocked" ? 92 : 54 });

/** 2026-10-26 is a Monday. Jakarta is UTC+7. */
const at = (iso: string) => new Date(iso);
const NIGHT_JAKARTA = at("2026-10-27T16:00:00Z"); // 23:00 WIB Tuesday
const DAY_JAKARTA = at("2026-10-27T05:00:00Z"); // 12:00 WIB Tuesday

class Recorder implements PushSender {
  sent: PushMessage[] = [];
  async send(m: PushMessage) {
    this.sent.push(m);
    return { result: "logged" };
  }
}

describe("PATCH /devices/me settings", () => {
  it("saves only the keys sent; GET returns them as HH:MM", async () => {
    const d = await createDevice("Adhella", "guardian");
    expect((await patch(d, { timeZone: "Asia/Makassar", avatarId: "avatar_07", notifications: { weeklySummary: true, quietStart: "21:30" } })).status).toBe(200);
    expect((await patch(d, { notifications: { blocked: false } })).status).toBe(200);
    expect(await me(d)).toMatchObject({
      avatarId: "avatar_07",
      timeZone: "Asia/Makassar",
      notifications: {
        warning: true, blocked: false, family: true, protectionOff: true, weeklySummary: true,
        quietHours: true, quietStart: "21:30", quietEnd: "06:00",
      },
    });
  });

  it("422 for an unknown zone, a bad clock, an unknown key or an avatar outside 01–12", async () => {
    const d = await createDevice();
    for (const json of [
      { timeZone: "Mars/Olympus" },
      { timeZone: "Asia/Jakarta; drop" },
      { notifications: { quietStart: "24:00" } },
      { notifications: { quietEnd: "6:00" } },
      { notifications: { loud: true } },
      { notifications: { warning: "yes" } },
      { avatarId: "avatar_13" },
    ]) {
      expect((await patch(d, json)).status, JSON.stringify(json)).toBe(422);
    }
  });
});

describe("quiet hours", () => {
  const q = { quietHours: true, quietStart: 22 * 60, quietEnd: 6 * 60, timeZone: "Asia/Jakarta" };
  it("window across midnight, in the device's zone", () => {
    expect(isQuiet(q, NIGHT_JAKARTA)).toBe(true);
    expect(isQuiet(q, DAY_JAKARTA)).toBe(false);
    expect(isQuiet({ ...q, timeZone: "Asia/Jayapura" }, at("2026-10-27T13:30:00Z"))).toBe(true); // 22:30 WIT
    expect(isQuiet({ ...q, quietHours: false }, NIGHT_JAKARTA)).toBe(false);
    expect(isQuiet({ ...q, quietStart: 600, quietEnd: 600 }, DAY_JAKARTA)).toBe(true);
  });

  it("local time and weekday; an unknown stored zone falls back to WIB", () => {
    expect(localTime("Asia/Jakarta", at("2026-10-26T01:00:00Z"))).toEqual({ minutes: 8 * 60, weekday: 1, date: "2026-10-26" });
    expect(localTime("Nowhere/Land", at("2026-10-26T01:00:00Z")).minutes).toBe(8 * 60);
  });
});

describe("push switches (Situs berbahaya / diblokir / Aktivitas orang dilindungi)", () => {
  it("own scan: pushed to the device itself by status switch, no domain in the text", async () => {
    const d = await createDevice("Adhella", "guardian");
    await patch(d, { apnsToken: TOKEN, language: "id" });
    const self = principal(d, "Adhella", "guardian");
    expect(await ownPush(sql, self, scan("blocked"), DAY_JAKARTA)).toEqual({
      toDeviceId: d.deviceId, apnsToken: TOKEN, body: "Shoo memblokir situs berbahaya · 92%", scanId: scan("blocked").id,
    });
    await patch(d, { notifications: { blocked: false } });
    expect(await ownPush(sql, self, scan("blocked"), DAY_JAKARTA)).toBeUndefined();
    expect((await ownPush(sql, self, scan("warning"), DAY_JAKARTA))?.body).toBe("Shoo memperingatkanmu soal situs berisiko · 54%");
    await patch(d, { notifications: { warning: false } });
    expect(await ownPush(sql, self, scan("warning"), DAY_JAKARTA)).toBeUndefined();
  });

  it("quiet hours hold warnings but not blocked sites", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await link(g, p);
    await patch(g, { apnsToken: TOKEN_G });
    await patch(p, { apnsToken: TOKEN });
    const mom = principal(p, "Mom", "protected");
    expect(await guardianPush(sql, mom, scan("warning"), NIGHT_JAKARTA)).toBeUndefined();
    expect(await guardianPush(sql, mom, scan("blocked"), NIGHT_JAKARTA)).toBeDefined();
    expect(await ownPush(sql, mom, scan("warning"), NIGHT_JAKARTA)).toBeUndefined();
    expect(await ownPush(sql, mom, scan("blocked"), NIGHT_JAKARTA)).toBeDefined();
    await patch(g, { notifications: { quietHours: false } });
    expect(await guardianPush(sql, mom, scan("warning"), NIGHT_JAKARTA)).toBeDefined();
  });

  it("the guardian's family switch turns off every member's push; Kabari saya stays per member", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await link(g, p);
    await patch(g, { apnsToken: TOKEN_G, notifications: { family: false } });
    const mom = principal(p, "Mom", "protected");
    expect(await guardianPush(sql, mom, scan("blocked"), DAY_JAKARTA)).toBeUndefined();
    await patch(g, { notifications: { family: true } });
    expect(await guardianPush(sql, mom, scan("blocked"), DAY_JAKARTA)).toBeDefined();
    await call(`/family/members/${p.deviceId}`, { method: "PATCH", token: g.token, json: { notify: false } });
    expect(await guardianPush(sql, mom, scan("blocked"), DAY_JAKARTA)).toBeUndefined();
  });
});

describe("hourly cron: ops_jobs (fase 21a)", () => {
  it("a run moves notifications ok_at", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    await runNotifications(sql, env, { sender: new Recorder() });
    expect((await sql`select failed, ok_at > now() - interval '1 minute' as fresh from ops_jobs where job = 'notifications'`)[0])
      .toEqual({ failed: 0, fresh: true });
  });

  it("a failing status write still sends the pushes and logs ops_job_write_failed without details", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const lines: string[] = [];
    vi.spyOn(console, "error").mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Renatta");
    await link(g, p);
    await patch(g, { apnsToken: TOKEN_G, notifications: { quietHours: false } });
    await sql`update devices set ext_last_seen_at = now() - interval '30 hours' where id = ${p.deviceId}`;
    const sender = new Recorder();
    const broken: OpsWriter = {
      start: async () => { throw new Error(`ops down ${g.deviceId}`); },
      finish: async () => { throw new Error(`ops down ${g.deviceId}`); },
    };

    expect((await runNotifications(sql, env, { sender, ops: broken })).protectionOff).toBe(1);
    expect(sender.sent).toHaveLength(1);
    expect(lines).toEqual(Array(2).fill('{"event":"ops_job_write_failed","job":"notifications","error":{"name":"Error"}}'));
  });

  it("a broken APNs config fails the run (ok_at stays); a rejected device token does not", async () => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Renatta");
    await link(g, p);
    await patch(g, { apnsToken: TOKEN_G, notifications: { quietHours: false } });
    const job = async () => (await sql`select failed, ok_at is not null as ok from ops_jobs where job = 'notifications'`)[0];

    await sql`update devices set ext_last_seen_at = now() - interval '30 hours' where id = ${p.deviceId}`;
    await runNotifications(sql, env, { sender: { send: async () => ({ result: "failed:config" }) } });
    expect(await job()).toEqual({ failed: 1, ok: false });

    await sql`update family_links set off_notified_at = null`;
    await runNotifications(sql, env, { sender: { send: async () => ({ result: "failed:400 BadDeviceToken" }) } });
    expect(await job()).toEqual({ failed: 0, ok: true });
  });
});

describe("hourly cron: Perlindungan mati", () => {
  const setup = async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Renatta");
    await link(g, p);
    await patch(g, { apnsToken: TOKEN_G, notifications: { quietHours: false } });
    return { g, p };
  };
  const seen = (p: Created, hoursAgo: number) =>
    sql`update devices set ext_last_seen_at = now() - make_interval(hours => ${hoursAgo}) where id = ${p.deviceId}`;

  it("once per off period; again after the member reported back", async () => {
    const { g, p } = await setup();
    const sender = new Recorder();
    await seen(p, 2);
    expect((await runNotifications(sql, env, { sender })).protectionOff).toBe(0);

    await seen(p, 30);
    await runNotifications(sql, env, { sender });
    await runNotifications(sql, env, { sender });
    expect(sender.sent).toEqual([{ toDeviceId: g.deviceId, apnsToken: TOKEN_G, body: "Renatta's protection is off: Shoo has not run in Safari for a day" }]);

    await sql`update devices set ext_last_seen_at = now() where id = ${p.deviceId}`;
    await runNotifications(sql, env, { sender });
    await sql`update devices set ext_last_seen_at = now() - interval '30 hours' where id = ${p.deviceId}`;
    await runNotifications(sql, env, { sender });
    expect(sender.sent).toHaveLength(2);
  });

  it("not for a member that never reported, a switch that is off, or during quiet hours (sent later)", async () => {
    const { g, p } = await setup();
    const sender = new Recorder();
    await runNotifications(sql, env, { sender });
    expect(sender.sent).toHaveLength(0);

    await seen(p, 30);
    await patch(g, { notifications: { protectionOff: false } });
    await runNotifications(sql, env, { sender });
    expect(sender.sent).toHaveLength(0);

    await patch(g, { notifications: { protectionOff: true, quietHours: true } });
    await runNotifications(sql, env, { sender, now: NIGHT_JAKARTA });
    expect(sender.sent).toHaveLength(0);
    await runNotifications(sql, env, { sender, now: DAY_JAKARTA });
    expect(sender.sent).toHaveLength(1);
  });

  // Fase 27k F-N10: quiet hours are filtered in SQL before the limit. Before, the 200 members off
  // the longest all belonged to guardians in quiet hours, so a guardian outside them never got a push.
  it("a guardian outside quiet hours is not starved by 201 guardians inside them", async () => {
    await withoutTriggers(async (tx) => {
      await tx`insert into devices (id, name, mode, avatar_id, token_hash, apns_token, notify_protection_off,
                                    quiet_hours, quiet_start, quiet_end, time_zone)
        select 'g_quiet_' || i, 'G', 'guardian'::device_mode, 'avatar_01', ('\\x01' || lpad(to_hex(i), 6, '0'))::bytea, ${TOKEN_G},
               true, true, 1320, 360, 'Asia/Jakarta'
        from generate_series(1, 201) i
        union all
        select 'g_awake', 'Awake', 'guardian', 'avatar_01', '\\x02000000'::bytea, ${TOKEN}, true, false, 1320, 360, 'Asia/Jakarta'`;
      await tx`insert into devices (id, name, mode, avatar_id, token_hash, ext_last_seen_at)
        select 'p_quiet_' || i, 'Mom', 'protected'::device_mode, 'avatar_02', ('\\x03' || lpad(to_hex(i), 6, '0'))::bytea,
               now() - interval '40 hours' - make_interval(mins => i)
        from generate_series(1, 201) i
        union all
        select 'p_awake', 'Renatta', 'protected', 'avatar_02', '\\x04000000'::bytea, now() - interval '25 hours'`;
      await tx`insert into family_links (protected_id, guardian_id)
        select 'p_quiet_' || i, 'g_quiet_' || i from generate_series(1, 201) i
        union all select 'p_awake', 'g_awake'`;
    });
    const sender = new Recorder();
    expect((await runNotifications(sql, env, { sender, now: NIGHT_JAKARTA })).protectionOff).toBe(1);
    expect(sender.sent.map((m) => m.toDeviceId)).toEqual(["g_awake"]);
    // The quiet ones were not claimed: they go out on the first run after their window.
    const [left] = await sql<{ n: number }[]>`select count(*)::int as n from family_links where off_notified_at is null`;
    expect(left!.n).toBe(201);
  });
});

describe("quiet hours in SQL (cron, fase 27k F-N10) = isQuiet", () => {
  // DST zones, a name in another case (Intl accepts it, so PATCH stores it), and an unknown one → WIB.
  const zones = ["Asia/Jakarta", "Asia/Makassar", "UTC", "America/New_York", "Europe/Berlin", "Australia/Lord_Howe",
    "asia/makassar", "Mars/Olympus"];
  const windows: [boolean, number, number][] = [
    [true, 22 * 60, 6 * 60], [true, 9 * 60, 17 * 60], [true, 600, 600], [false, 22 * 60, 6 * 60], [true, 0, 1],
    [true, 90, 180], // 01:30–03:00, the hour a spring-forward skips
  ];
  const instants = [
    NIGHT_JAKARTA, DAY_JAKARTA,
    at("2026-10-27T15:00:00Z"), // 22:00 WIB: start counts as quiet
    at("2026-10-27T22:59:00Z"), // 05:59 WIB
    at("2026-10-27T23:00:00Z"), // 06:00 WIB: end does not
    at("2026-10-27T01:00:30Z"), // 09:00:30 WITA
    at("2026-10-26T16:59:59Z"), // 23:59:59 WIB
    at("2026-10-26T17:00:00Z"), // 00:00 WIB
    at("2026-03-08T06:59:00Z"), at("2026-03-08T07:00:00Z"), // New York springs forward
    at("2026-11-01T05:59:00Z"), at("2026-11-01T06:00:00Z"), // New York falls back
    at("2026-03-29T00:59:00Z"), at("2026-03-29T01:00:00Z"), // Berlin springs forward
    at("2026-04-04T14:59:00Z"), at("2026-04-04T15:00:00Z"), // Lord Howe: 30 minutes back
  ];
  const cases = zones.flatMap((timeZone) =>
    windows.map(([quietHours, quietStart, quietEnd]) => ({ quietHours, quietStart, quietEnd, timeZone })));
  const rowsJson = cases.map((c) =>
    ({ quiet_hours: c.quietHours, quiet_start: c.quietStart, quiet_end: c.quietEnd, time_zone: c.timeZone }));

  it.each(instants.map((now) => [now.toISOString(), now] as const))("at %s", async (_, now) => {
    const rows = await sql<{ quiet: boolean }[]>`
      select ${quietSql(sql, now)} as quiet
      from rows from (jsonb_to_recordset(${JSON.stringify(rowsJson)}::text::jsonb)
                        as (quiet_hours boolean, quiet_start int, quiet_end int, time_zone text))
             with ordinality as g(quiet_hours, quiet_start, quiet_end, time_zone, n)
      order by n`;
    const got = rows.map((r) => r.quiet);
    const want = cases.map((c) => isQuiet(c, now));
    expect(new Set(want)).toEqual(new Set([true, false])); // never a comparison of all-false
    expect(cases.map((c, i) => ({ ...c, quiet: got[i] }))).toEqual(cases.map((c, i) => ({ ...c, quiet: want[i] })));
  });
});

describe("hourly cron: Ringkasan mingguan", () => {
  const MONDAY_0810_WIB = at("2026-10-26T01:10:00Z");

  it("Monday from 08:00 local, once, with the family's last 7 days", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await link(g, p);
    await patch(g, { apnsToken: TOKEN_G, notifications: { weeklySummary: true } });
    await sql`insert into scans (owner_id, url, domain, score, status, detected_at) values
      (${g.deviceId}, 'https://a.example/', 'a.example', 92, 'blocked', now() - interval '1 day'),
      (${p.deviceId}, 'https://b.example/', 'b.example', 54, 'warning', now() - interval '2 days'),
      (${p.deviceId}, 'https://c.example/', 'c.example', 95, 'blocked', now() - interval '3 days'),
      (${p.deviceId}, 'https://old.example/', 'old.example', 95, 'blocked', now() - interval '9 days')`;
    const sender = new Recorder();

    await runNotifications(sql, env, { sender, now: at("2026-10-26T00:30:00Z") }); // 07:30 WIB
    await runNotifications(sql, env, { sender, now: at("2026-10-27T01:10:00Z") }); // Tuesday
    expect(sender.sent).toHaveLength(0);

    await runNotifications(sql, env, { sender, now: MONDAY_0810_WIB });
    await runNotifications(sql, env, { sender, now: at("2026-10-26T02:10:00Z") });
    expect(sender.sent).toEqual([{ toDeviceId: g.deviceId, apnsToken: TOKEN_G, body: "Your week for you and your family: 2 sites blocked, 1 warning." }]);
  });

  it("off by default; uses the device's zone", async () => {
    const d = await createDevice("Adhella", "guardian");
    await patch(d, { apnsToken: TOKEN });
    const sender = new Recorder();
    await runNotifications(sql, env, { sender, now: MONDAY_0810_WIB });
    expect(sender.sent).toHaveLength(0);

    await patch(d, { timeZone: "Asia/Jayapura", notifications: { weeklySummary: true } }); // UTC+9: 10:10 WIT
    await runNotifications(sql, env, { sender, now: MONDAY_0810_WIB });
    expect(sender.sent.map((m) => m.body)).toEqual(["Your week: no dangerous sites for you."]);
  });

  it("text in Indonesian", () => {
    expect(summaryText("id", { blocked: 3, warnings: 5, family: true })).toBe("Ringkasan minggu ini untuk kamu dan keluargamu: 3 situs diblokir, 5 peringatan.");
  });
});

describe("Tentang Shoo pages", () => {
  it("GET /terms in English and Indonesian, no script", async () => {
    const en = await call("/terms");
    expect(en.status).toBe(200);
    expect(en.headers.get("content-security-policy")).toContain("default-src 'none'");
    const html = await en.text();
    expect(html).toContain("Shoo terms of use");
    expect(html).not.toContain("<script");
    expect(await (await call("/terms?lang=id")).text()).toContain("Syarat &amp; ketentuan Shoo".replace("&amp;", "&"));
  });

  it("GET /get redirects to the store page", async () => {
    const res = await call("/get", { redirect: "manual" });
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toMatch(/^https:\/\/(apps|testflight)\.apple\.com\//);
  });

  it("the hourly trigger is the one in wrangler.jsonc", () => {
    expect(CRONS.notifications).toBe("5 * * * *");
  });
});

describe("POST /devices/me/protected (Punya kode undangan?)", () => {
  const code = async (g: Created) =>
    ((await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string }).code;

  it("a guardian without members becomes a protected member: new token, same name and settings, old device gone", async () => {
    const me1 = await createDevice("Adhella", "guardian");
    await patch(me1, { language: "id", avatarId: "avatar_05", timeZone: "Asia/Makassar", notifications: { weeklySummary: true } });
    const other = await createDevice("Budi", "guardian");
    const res = await call("/devices/me/protected", { method: "POST", token: me1.token, json: { code: await code(other) } });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { deviceId: string; token: string; avatarId: string; guardian: { name: string } };
    expect(body).toMatchObject({ avatarId: "avatar_05", guardian: { name: "Budi" } });
    expect(body.deviceId).not.toBe(me1.deviceId);

    expect((await call("/devices/me", { token: me1.token })).status).toBe(401);
    const now = await (await call("/devices/me", { token: body.token })).json();
    expect(now).toMatchObject({
      name: "Adhella", mode: "protected", language: "id", timeZone: "Asia/Makassar",
      notifications: { weeklySummary: true }, guardian: { name: "Budi" },
    });
  });

  it("409 has_members while someone is protected; a bad code keeps the guardian as it was", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("Mom");
    await link(g, p);
    const other = await createDevice("Budi", "guardian");
    const blocked = await call("/devices/me/protected", { method: "POST", token: g.token, json: { code: await code(other) } });
    expect(blocked.status).toBe(409);
    expect(((await blocked.json()) as { error: { code: string } }).error.code).toBe("has_members");

    const lone = await createDevice("Solo", "guardian");
    const before = (await sql<{ n: number }[]>`select count(*)::int as n from devices`)[0]!.n;
    const bad = await call("/devices/me/protected", { method: "POST", token: lone.token, json: { code: "000000" } });
    expect(bad.status).toBe(404);
    expect((await sql<{ n: number }[]>`select count(*)::int as n from devices`)[0]!.n).toBe(before);
    expect(await me(lone)).toMatchObject({ mode: "guardian" });
  });

  it("protected devices cannot call it", async () => {
    const p = await createDevice("Mom");
    expect((await call("/devices/me/protected", { method: "POST", token: p.token, json: { code: "123456" } })).status).toBe(403);
  });
});

// Fase 27a (F-B1, F-B2, F-B3, F-B6, K3): become-protected is one transaction. Races are tested at
// function level with two plain postgres() connections and injected hooks: a route call through
// call() while another connection holds a lock hangs in the workerd pool (fase 27 log).
// 15 s: each test makes several devices and calls; the local stack sometimes needs a few seconds.
describe("POST /devices/me/protected is atomic (fase 27a)", { timeout: 15_000 }, () => {
  useRateKeySecret(env.RATE_KEY_SECRET);
  const admin = adminSql();
  // Two extra sessions for the races. lock_timeout 2 s: a deadlock or a missed wake-up fails fast.
  const raceSql = () => postgres(env.DB.connectionString, { max: 1, fetch_types: false, connection: { lock_timeout: 2000 } });
  const a = raceSql();
  const b = raceSql();
  let racePids: [number, number] = [0, 0];
  beforeAll(async () => {
    const pid = async (s: typeof a) => (await s<{ pid: number }[]>`select pg_backend_pid() as pid`)[0]!.pid;
    racePids = [await pid(a), await pid(b)];
  });
  // Gates a failed assertion left closed: open them, so no session stays parked holding locks.
  const openGates: (() => void)[] = [];
  afterEach(() => openGates.splice(0).forEach((release) => release()));
  // Not ended, like testSql(): end() in the workerd pool raises "This socket has been closed".

  const code = async (g: Created) =>
    ((await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string }).code;
  const switchTo = (g: Created, c: string, ip?: string) =>
    call("/devices/me/protected", { method: "POST", token: g.token, json: { code: c }, ip });
  const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;
  const guardianOf = async (id: string) =>
    (await sql<{ g: string }[]>`select guardian_id as g from family_links where protected_id = ${id}`)[0]?.g ?? null;
  const members = async (g: Created) =>
    (await sql<{ n: number }[]>`select count(*)::int as n from family_links where guardian_id = ${g.deviceId}`)[0]!.n;
  const deviceCount = async () => (await sql<{ n: number }[]>`select count(*)::int as n from devices`)[0]!.n;
  const input = async (g: Created, c: string, ip = "203.0.113.50") => ({
    oldId: g.deviceId,
    ipHash: await keyHash(`join:${ip}`),
    code: c,
    tokenHash: await sha256(`shoo_test_${g.deviceId}`),
  });
  /** Resolves once session `a` or `b` waits for a lock that another one holds. */
  const someoneWaits = async () => {
    for (let i = 0; i < 100; i++) {
      const [row] = await admin<{ n: number }[]>`
        select count(*)::int as n from pg_locks where not granted and pid in (${racePids[0]}, ${racePids[1]})`;
      if (row!.n > 0) return;
      await new Promise((r) => setTimeout(r, 20));
    }
    throw new Error("nobody waited for a lock");
  };
  const settle = <T>(p: Promise<T>) =>
    p.then(
      (value) => ({ ok: true as const, value }),
      (error: unknown) => ({ ok: false as const, code: (error as { code?: string }).code ?? String(error) }),
    );
  /**
   * Starts a switch with a hook that parks it until `release()`. Returns once it is parked; throws
   * at once (instead of waiting for the test timeout) when the switch ends before the hook.
   */
  const parked = async <T>(start: (hook: () => Promise<void>) => Promise<T>) => {
    let release!: () => void;
    let arrived!: () => void;
    const open = new Promise<void>((r) => (release = r));
    const reached = new Promise<"parked">((r) => (arrived = () => r("parked")));
    openGates.push(release);
    const done = settle(
      start(async () => {
        arrived();
        await open;
      }),
    );
    const first = await Promise.race([reached, done]);
    if (first !== "parked") throw new Error(`switch ended before the gate: ${JSON.stringify(first)}`);
    return { done, release };
  };

  it("F-B1: your own code is code_invalid; the guardian stays as it was and no copy is made", async () => {
    const g = await createDevice("Solo", "guardian");
    const own = await code(g);
    const before = await deviceCount();
    const res = await switchTo(g, own);
    expect(res.status).toBe(404);
    expect(await errorCode(res)).toBe("code_invalid");
    expect(await me(g)).toMatchObject({ mode: "guardian" });
    expect(await deviceCount()).toBe(before);
    // Counts as a failed attempt, like any wrong code (F-B6).
    const [row] = await sql<{ n: number }[]>`
      select count(*)::int as n from join_attempts where device_id = ${g.deviceId} and not success`;
    expect(row!.n).toBe(1);
  });

  it("F-B6: the 6th try from one guardian is too_many_attempts, even with a good code", async () => {
    const g = await createDevice("G", "guardian");
    const other = await createDevice("Budi", "guardian");
    for (let i = 1; i <= 5; i++) {
      expect((await switchTo(g, `00000${i}`)).status).toBe(404);
    }
    const sixth = await switchTo(g, await code(other));
    expect(sixth.status).toBe(429);
    expect(await errorCode(sixth)).toBe("too_many_attempts");
    expect(await me(g)).toMatchObject({ mode: "guardian" });
    expect(await members(other)).toBe(0);
  });

  it("F-B6: 20 failures from one IP across guardians hit the IP limit; another IP still gets through", async () => {
    const ip = "203.0.113.77";
    for (let d = 0; d < 4; d++) {
      const g = await createDevice(`G${d}`, "guardian");
      for (let i = 1; i <= 5; i++) expect((await switchTo(g, `10000${i}`, ip)).status).toBe(404);
    }
    const next = await createDevice("G4", "guardian");
    const limited = await switchTo(next, "100009", ip);
    expect(limited.status).toBe(429);
    expect(await errorCode(limited)).toBe("too_many_attempts");
    expect((await switchTo(next, "100009", "203.0.113.78")).status).toBe(404);
  }, 30_000);

  it("F-B2: a member joining the old guardian mid-switch gets code_invalid, never a silent loss", async () => {
    const g = await createDevice("G", "guardian");
    const budi = await createDevice("Budi", "guardian");
    const mom = await createDevice("Mom");
    const gCode = await code(g);
    const switchInput = await input(g, await code(budi));
    const switch1 = await parked((hook) => becomeProtected(a, switchInput, { afterValidate: hook }));
    const joining = settle(joinFamily(b, mom.deviceId, await keyHash("join:203.0.113.51"), gCode));
    await someoneWaits(); // Mom's join waits for the old guardian's lock
    switch1.release();
    const [sw, jn] = await Promise.all([switch1.done, joining]);
    expect(sw.ok).toBe(true);
    expect(jn).toEqual({ ok: false, code: "code_invalid" });
    expect(await guardianOf(mom.deviceId)).toBeNull();
    expect(await members(budi)).toBe(1);
  });

  it("F-B2: a member who joined first makes the switch has_members inside the transaction", async () => {
    const g = await createDevice("G", "guardian");
    const budi = await createDevice("Budi", "guardian");
    const mom = await createDevice("Mom");
    const gCode = await code(g);
    const before = await deviceCount();
    const hooks: BecomeProtectedHooks = {
      // After the route's cheap pre-check, before any lock: Mom's join commits on another session.
      beforeValidate: async () => {
        await joinFamily(b, mom.deviceId, await keyHash("join:203.0.113.52"), gCode);
      },
    };
    const sw = await settle(becomeProtected(a, await input(g, await code(budi)), hooks));
    expect(sw).toEqual({ ok: false, code: "has_members" });
    expect(await guardianOf(mom.deviceId)).toBe(g.deviceId);
    expect(await members(budi)).toBe(0);
    expect(await deviceCount()).toBe(before);
  });

  it("F-B3: a failure after the copy is made rolls everything back; the retry makes exactly one link", async () => {
    const g = await createDevice("G", "guardian");
    const budi = await createDevice("Budi", "guardian");
    const bCode = await code(budi);
    const before = await deviceCount();
    const sw = await settle(
      becomeProtected(a, await input(g, bCode), {
        beforeLink: async () => {
          throw Object.assign(new Error("injected"), { code: "XX000" });
        },
      }),
    );
    expect(sw).toEqual({ ok: false, code: "XX000" });
    expect(await deviceCount()).toBe(before);
    expect(await me(g)).toMatchObject({ mode: "guardian" });
    expect(await members(budi)).toBe(0);

    const retry = await switchTo(g, bCode);
    expect(retry.status).toBe(200);
    expect(await members(budi)).toBe(1);
    expect(await deviceCount()).toBe(before);
  });

  it("an account deleted mid-switch stays deleted: 401, no copy, no link", async () => {
    const g = await createDevice("G", "guardian");
    const budi = await createDevice("Budi", "guardian");
    const switchInput = await input(g, await code(budi));
    const sw = await settle(
      becomeProtected(a, switchInput, {
        // DELETE /devices/me on another session commits while the switch holds its locks.
        afterValidate: async () => void (await deleteDevice(b, g.deviceId)),
      }),
    );
    expect(sw).toEqual({ ok: false, code: "unauthorized" });
    expect(await members(budi)).toBe(0);
    expect((await sql<{ n: number }[]>`select count(*)::int as n from devices where name = 'G'`)[0]!.n).toBe(0);
  });

  it("a wrong code from an account deleted mid-switch is 401, not code_invalid", async () => {
    const g = await createDevice("G", "guardian");
    const sw = await settle(
      becomeProtected(a, await input(g, "000009"), {
        beforeValidate: async () => void (await deleteDevice(b, g.deviceId)),
      }),
    );
    expect(sw).toEqual({ ok: false, code: "unauthorized" });
  });

  it("K3: two guardians using each other's codes at once finish without a deadlock: one 200, one refused", async () => {
    const g1 = await createDevice("G1", "guardian");
    const g2 = await createDevice("G2", "guardian");
    const [c1, c2] = [await code(g1), await code(g2)];
    const started = Date.now();
    const firstInput = await input(g1, c2, "203.0.113.61");
    const first = await parked((hook) => becomeProtected(a, firstInput, { afterValidate: hook }));
    const second = settle(becomeProtected(b, await input(g2, c1, "203.0.113.62")));
    await someoneWaits();
    first.release();
    const results = await Promise.all([first.done, second]);
    expect(Date.now() - started).toBeLessThan(10_000);
    expect(results[0].ok).toBe(true);
    expect(results[1].ok).toBe(false);
    expect(["has_members", "code_invalid"]).toContain(results[1].ok ? "" : results[1].code);
    expect(await members(g2)).toBe(1);
    expect((await call("/devices/me", { token: g1.token })).status).toBe(401);
  });

  it("K3: a member on the same IP as a switching guardian waits, then joins (no 500)", async () => {
    const g = await createDevice("G", "guardian");
    const budi = await createDevice("Budi", "guardian");
    const mom = await createDevice("Mom");
    const bCode = await code(budi);
    const ip = "203.0.113.70";
    const switchInput = await input(g, bCode, ip);
    const switch1 = await parked((hook) => becomeProtected(a, switchInput, { afterValidate: hook }));
    const joining = settle(joinFamily(b, mom.deviceId, await keyHash(`join:${ip}`), bCode));
    await someoneWaits(); // Mom waits for the shared IP's attempt lock
    switch1.release();
    const [sw, jn] = await Promise.all([switch1.done, joining]);
    expect(sw.ok).toBe(true);
    expect(jn.ok).toBe(true);
    expect(await members(budi)).toBe(2);
  });
});
