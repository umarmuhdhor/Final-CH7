// #270: POST /scans accepts the RDAP registration date from POST /analyze. A bad value never
// refuses the scan (the extension would drop it); it is stored as null. A repeat visit of the same
// site (PR-05) fills the date only while it is unknown, and the archive row follows.
import { beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";

const sql = testSql();
let p: Created;
beforeEach(async () => {
  await resetDb(sql);
  p = await createDevice("Mom", "protected");
});

const body = (rdapRegisteredAt?: unknown, domain = blocked92.domain) => ({
  url: `https://${domain}/login`, domain, pageTitle: blocked92.pageTitle, faviconUrl: null,
  score: blocked92.score, status: blocked92.status, signals: blocked92.signals, detectedAt: new Date().toISOString(),
  ...(rdapRegisteredAt === undefined ? {} : { rdapRegisteredAt }),
});
const post = (v?: unknown, domain?: string) => call("/scans", { method: "POST", token: p.token, json: body(v, domain) });
const stored = async (domain: string) => {
  const [r] = await sql<{ d: string | null }[]>`select rdap_registered_at::text as d from scans where domain = ${domain}`;
  return r?.d ?? null;
};
// By scan id: admin.scan_archive outlives resetDb, so older tests leave rows of the same domain.
const archived = async (domain: string) => {
  const [r] = await adminSql()<{ d: string | null }[]>`
    select a.rdap_registered_at::text as d from admin.scan_archive a
      join public.scans s on s.id = a.scan_id where s.domain = ${domain}`;
  return r?.d ?? null;
};

describe("POST /scans rdapRegisteredAt (#270)", () => {
  it("stores a valid date on the scan and on its archive row", async () => {
    expect((await post("2026-10-30")).status).toBe(201);
    expect(await stored(blocked92.domain)).toBe("2026-10-30");
    expect(await archived(blocked92.domain)).toBe("2026-10-30");
  });

  it("absent or null: null (older extension, failed RDAP lookup)", async () => {
    expect((await post(undefined, "absent.test")).status).toBe(201);
    expect((await post(null, "null-date.test")).status).toBe(201);
    expect(await stored("absent.test")).toBeNull();
    expect(await stored("null-date.test")).toBeNull();
  });

  it("a bad value is stored as null, never a 422", async () => {
    const tomorrow2 = new Date(Date.now() + 2 * 86_400_000).toISOString().slice(0, 10);
    const bad = ["2026-02-30", "1984-12-31", tomorrow2, "2026-1-5", "2026-10-30T00:00:00Z", 20261030, {}, "x".repeat(5000)];
    for (const [i, v] of bad.entries()) {
      const domain = `bad-${i}.test`;
      const res = await post(v, domain);
      expect([v, res.status]).toEqual([v, 201]);
      expect([v, await stored(domain)]).toEqual([v, null]);
    }
  });

  it("today and tomorrow (UTC) are accepted, for registries ahead of the device clock", async () => {
    const today = new Date().toISOString().slice(0, 10);
    const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
    expect((await post(today, "today.test")).status).toBe(201);
    expect((await post(tomorrow, "tomorrow.test")).status).toBe(201);
    expect(await stored("today.test")).toBe(today);
    expect(await stored("tomorrow.test")).toBe(tomorrow);
  });

  it("a repeat visit fills an unknown date and never overwrites a known one (PR-05)", async () => {
    expect((await post(undefined)).status).toBe(201);
    expect((await post("2026-10-01")).status).toBe(201);
    expect(await stored(blocked92.domain)).toBe("2026-10-01");
    expect(await archived(blocked92.domain)).toBe("2026-10-01");
    expect((await post("2020-01-01")).status).toBe(201);
    expect((await post(null)).status).toBe(201);
    expect(await stored(blocked92.domain)).toBe("2026-10-01");
    expect(await archived(blocked92.domain)).toBe("2026-10-01");
    const [n] = await sql<{ n: number }[]>`select count(*)::int as n from scans`;
    expect(n!.n).toBe(1);
  });
});
