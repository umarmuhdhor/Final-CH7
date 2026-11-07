import { describe, expect, it } from "vitest";
import brands from "../../../detector/data/brands.json";
import expected from "./fixtures/domain-lists-expected-diff.json";
import golden from "./fixtures/domain-lists-golden.json";
import { adminSql } from "./helpers/resetDb";

// ADM-09 (dashboard plan phase 10a K4, I14, I15): admin.domain_match answers what the old hand-written
// lists answered (golden file, generated from the old code by backend/db/scripts/domain-lists-golden.mjs),
// except the cases listed with a K12 category in the expected-diff file. The seed is in the migration.

type Reader = "backend" | "build" | "official";
type Case = { host: string; backend: boolean | null; build: boolean | null; buildDomain: string | null; official: boolean };
type Diff = { host: string; reader: string; old: boolean | string; new: boolean | string; category: string };
type Match = { host: string; protected: boolean; trusted: boolean };

const sql = adminSql();
const cases = golden.cases as Case[];
const diffs = expected.diffs as Diff[];

async function domainMatch(hosts: string[]): Promise<Map<string, Match>> {
  const rows = await sql<Match[]>`
    select h as host, m.protected, m.trusted
    from jsonb_array_elements_text(${sql.json([...new Set(hosts)])}) h
    cross join lateral admin.domain_match(h) m`;
  return new Map(rows.map((r) => [r.host, r]));
}

describe("domain lists golden (I14)", () => {
  it("covers about 1100 hosts and every difference is categorized", () => {
    expect(cases.length).toBeGreaterThan(1000);
    const categories = new Set(diffs.map((d) => d.category));
    expect([...categories].every((c) => /^[a-g]$/.test(c) || c === "blockMemory-10c")).toBe(true);
  });

  it("domain_match = old answer per reader, or the categorized new answer", async () => {
    const want = new Map(diffs.filter((d) => d.reader !== "blockMemory").map((d) => [`${d.reader} ${d.host}`, d.new]));
    const got = await domainMatch(cases.flatMap((c) => (c.buildDomain ? [c.host, c.buildDomain] : [c.host])));
    const wrong: string[] = [];
    for (const c of cases) {
      const checks: [Reader, string | null, boolean | null, keyof Match][] = [
        ["backend", c.host, c.backend, "protected"],
        ["build", c.buildDomain, c.build, "protected"],
        ["official", c.host, c.official, "trusted"],
      ];
      for (const [reader, host, old, field] of checks) {
        if (old === null || host === null) continue;
        const expectedValue = want.get(`${reader} ${c.host}`) ?? old;
        const actual = got.get(host)?.[field];
        if (actual !== expectedValue) wrong.push(`${reader} ${c.host} (${host}): want ${expectedValue}, got ${actual}`);
      }
    }
    expect(wrong).toEqual([]);
  });
});

// Official brand domains the detector trusts must never reach the review queue (issue #99, Q4). Was
// test/allowlist.test.ts before the list moved to the database.
describe("brands.json is in the seed (I15)", () => {
  it("every brand domain is a subtree, trusted, hard_locked row with its brand", async () => {
    const domains = brands.brands.flatMap((b) => b.domains.map((d) => d.toLowerCase()));
    const want = brands.brands.flatMap((b) => b.domains.map((d) => `${d.toLowerCase()} ${b.id}`)).sort();
    expect(want.length).toBeGreaterThan(0);
    const rows = await sql<{ r: string }[]>`
      select domain || ' ' || brand_id as r from admin.domain_lists
      where protect = 'subtree' and trusted and hard_locked and brand_id is not null
        and domain in (select jsonb_array_elements_text(${sql.json(domains)}))
      order by 1`;
    expect(rows.map((x) => x.r)).toEqual(want);
  });
});
