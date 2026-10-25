import { beforeEach, describe, expect, it } from "vitest";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";

const sql = testSql();
const admin = adminSql();
let token: string;
beforeEach(async () => {
  await resetDb(sql);
  token = (await createDevice()).token;
});

type Body = {
  domains: { domain: string; addedAt: string }[];
  removed?: { domain: string; removedAt: string }[];
  nextSince: string | null;
};
const get = async (q = "") => {
  const res = await call(`/blocklist${q}`, { token });
  return { res, body: (await res.json()) as Body };
};

describe("GET /blocklist", () => {
  it("401 without token", async () => {
    expect((await call("/blocklist")).status).toBe(401);
  });

  it("empty list", async () => {
    const { res, body } = await get();
    expect(res.status).toBe(200);
    expect(body).toEqual({ domains: [], nextSince: null });
    expect(res.headers.get("cache-control")).toBe("private, max-age=300");
  });

  it("serves only approved, not removed entries, ordered by approval", async () => {
    await admin`insert into blocklist_entries (domain, approved_at, approved_by) values
      ('b-scam.example', '2026-10-21T05:00:00.000002Z', 't'),
      ('a-scam.example', '2026-10-21T05:00:00.000001Z', 't')`;
    await admin`insert into blocklist_entries (domain) values ('pending.example')`;
    await admin`insert into blocklist_entries (domain, rejected_at, rejected_by) values ('rejected.example', now(), 't')`;
    await admin`insert into blocklist_entries (domain, approved_at, approved_by, removed_at) values
      ('gone.example', '2026-10-21T04:00:00Z', 't', '2026-10-21T06:00:00Z')`;

    const { body } = await get();
    expect(body.domains).toEqual([
      { domain: "a-scam.example", addedAt: "2026-10-21T05:00:00.000001Z" },
      { domain: "b-scam.example", addedAt: "2026-10-21T05:00:00.000002Z" },
    ]);
    expect(body.removed).toBeUndefined(); // full refresh: removals are implied
    expect(body.nextSince).toBe("2026-10-21T05:00:00.000002Z");
  });

  it("since: only newer approvals plus removals, exact microsecond cursor", async () => {
    await admin`insert into blocklist_entries (domain, approved_at, approved_by) values
      ('old.example', '2026-10-21T05:00:00.000001Z', 't'),
      ('new.example', '2026-10-21T05:00:00.000002Z', 't')`;
    await admin`insert into blocklist_entries (domain, approved_at, approved_by, removed_at) values
      ('gone.example', '2026-10-21T04:00:00Z', 't', '2026-10-21T06:00:00Z')`;

    const { body } = await get(`?since=${encodeURIComponent("2026-10-21T05:00:00.000001Z")}`);
    expect(body.domains).toEqual([{ domain: "new.example", addedAt: "2026-10-21T05:00:00.000002Z" }]);
    expect(body.removed).toEqual([{ domain: "gone.example", removedAt: "2026-10-21T06:00:00.000000Z" }]);
    expect(body.nextSince).toBe("2026-10-21T06:00:00.000000Z");

    const next = await get(`?since=${encodeURIComponent(body.nextSince!)}`);
    expect(next.body).toEqual({ domains: [], removed: [], nextSince: body.nextSince });
  });

  it("pages by event time without skipping", async () => {
    await admin`insert into blocklist_entries (domain, approved_at, approved_by)
      select 'd' || g || '.example', timestamptz '2026-10-01T00:00:00Z' + g * interval '1 second', 't'
      from generate_series(1, 1001) g`;
    const first = await get();
    expect(first.body.domains).toHaveLength(1000);
    const second = await get(`?since=${encodeURIComponent(first.body.nextSince!)}`);
    expect(second.body.domains.map((d) => d.domain)).toEqual(["d1001.example"]);
  });

  it("a full page never splits entries that share one approval time", async () => {
    await admin`insert into blocklist_entries (domain, approved_at, approved_by)
      select 'd' || lpad(g::text, 4, '0') || '.example', timestamptz '2026-10-01T00:00:00Z' + g * interval '1 second', 't'
      from generate_series(1, 998) g`;
    // Bulk manual approval: three domains with the same timestamp straddle the 1000 boundary.
    await admin`insert into blocklist_entries (domain, approved_at, approved_by)
      select 'tie' || g || '.example', timestamptz '2026-10-02T00:00:00Z', 't' from generate_series(1, 3) g`;
    await admin`insert into blocklist_entries (domain, approved_at, approved_by)
      values ('last.example', '2026-10-03T00:00:00Z', 't')`;

    const first = await get();
    const second = await get(`?since=${encodeURIComponent(first.body.nextSince!)}`);
    const all = [...first.body.domains, ...second.body.domains].map((d) => d.domain);
    expect(new Set(all).size).toBe(1002);
    expect(second.body.domains.map((d) => d.domain)).toContain("last.example");
  });

  it("re-approving a removed domain gives it a new addedAt", async () => {
    await admin`insert into blocklist_entries (domain, approved_at, approved_by, removed_at)
      values ('back.example', '2026-10-01T00:00:00Z', 't', '2026-10-02T00:00:00Z')`;
    const before = await get(`?since=${encodeURIComponent("2026-10-02T00:00:00Z")}`);
    expect(before.body.domains).toEqual([]);

    await admin`update blocklist_entries set removed_at = null where domain = 'back.example'`;
    const after = await get(`?since=${encodeURIComponent("2026-10-02T00:00:00Z")}`);
    expect(after.body.domains.map((d) => d.domain)).toEqual(["back.example"]);
  });

  it("an approval by update gets a fresh, unique time", async () => {
    await admin`insert into blocklist_entries (domain) values ('q1.example'), ('q2.example')`;
    await admin`update blocklist_entries set approved_at = now(), approved_by = 'alief'`;
    const { body } = await get();
    expect(body.domains).toHaveLength(2);
    expect(body.domains[0]!.addedAt).not.toBe(body.domains[1]!.addedAt);
  });

  it.each(["yesterday", "0000-01-01T00:00:00Z", "9999-12-31T23:59:59Z"])("422 for since=%s", async (since) => {
    const { res } = await get(`?since=${encodeURIComponent(since)}`);
    expect(res.status).toBe(422);
  });
});
