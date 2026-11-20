// Family-wide "Mark as safe" (plan/alief/family-safe.md): a verdict on a link counts on every phone of
// the family, never in another family, and goes the moment a member leaves.
import { beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { expectScanResult } from "./helpers/schema";
import { call, createDevice, type Created } from "./helpers/seed";

const sql = testSql();
const admin = adminSql();
beforeEach(() => resetDb(sql));

type V = { value: string; byDeviceId: string; byName: string; url?: string; lockedUntil?: string } | null;
const LINK = "https://bca-verify.top/login";
const DOMAIN = "bca-verify.top";

const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};
const scan = async (d: Created, url = LINK, domain = DOMAIN) => {
  const res = await call("/scans", {
    method: "POST", token: d.token,
    json: {
      url, domain, pageTitle: blocked92.pageTitle, faviconUrl: null, score: blocked92.score,
      status: blocked92.status, signals: blocked92.signals, detectedAt: new Date().toISOString(),
    },
  });
  expect(res.status, await res.clone().text()).toBe(201);
  return ((await res.json()) as { id: string }).id;
};
const decide = async (g: Created, scanId: string, value: "safe" | "not_safe") => {
  const res = await call("/verdicts", { method: "POST", token: g.token, json: { scanId, value } });
  return res;
};
const lookup = async (d: Created, url = LINK, domain = DOMAIN): Promise<V> => {
  const res = await call(`/verdicts?url=${encodeURIComponent(url)}&domain=${encodeURIComponent(domain)}`, { token: d.token });
  expect(res.status, await res.clone().text()).toBe(200);
  return ((await res.json()) as { verdict: V }).verdict;
};
const activityVerdict = async (viewer: Created, scanId: string): Promise<V> => {
  const res = await call(`/scans/${scanId}`, { token: viewer.token });
  expect(res.status).toBe(200);
  const item = (await res.json()) as Record<string, unknown>;
  expectScanResult(item);
  return item.verdict as V;
};
const pastWeeklyReview = () => admin`update verdicts set decided_at = decided_at - interval '8 days'`;

/** Guardian "Ayah" with two protected members. */
async function family() {
  const g = await createDevice("Ayah", "guardian");
  const a = await createDevice("Nenek");
  const b = await createDevice("Kakek");
  await connect(g, a);
  await connect(g, b);
  return { g, a, b };
}

describe("family-wide verdicts", () => {
  it("guardian marks a member's scan safe → safe on the guardian and every other member too", async () => {
    const { g, a, b } = await family();
    const id = await scan(a);
    expect((await decide(g, id, "safe")).status).toBe(200);

    for (const d of [a, b, g]) {
      expect(await lookup(d)).toMatchObject({ value: "safe", byDeviceId: g.deviceId, byName: "Ayah", url: LINK });
    }
  });

  it("guardian marks its own scan safe → members get it too", async () => {
    const { g, a } = await family();
    const id = await scan(g);
    expect((await decide(g, id, "safe")).status).toBe(200);
    expect(await lookup(a)).toMatchObject({ value: "safe", byName: "Ayah" });
  });

  it("only that link: another page of the site still has no verdict", async () => {
    const { g, a, b } = await family();
    expect((await decide(g, await scan(a), "safe")).status).toBe(200);
    expect(await lookup(b, "https://bca-verify.top/transfer")).toBeNull();
  });

  it("another family never sees it", async () => {
    const { g, a } = await family();
    const other = await createDevice("Bunda", "guardian");
    const otherMember = await createDevice("Opa");
    await connect(other, otherMember);
    const loner = await createDevice("Solo");
    expect((await decide(g, await scan(a), "safe")).status).toBe(200);

    expect(await lookup(other)).toBeNull();
    expect(await lookup(otherMember)).toBeNull();
    expect(await lookup(loner)).toBeNull();
  });

  it("each member's own Activity row of that link shows it, marked by the guardian", async () => {
    const { g, a, b } = await family();
    const idA = await scan(a);
    const idB = await scan(b);
    const idG = await scan(g);
    expect((await decide(g, idA, "safe")).status).toBe(200);

    expect(await activityVerdict(b, idB)).toMatchObject({ value: "safe", byDeviceId: g.deviceId, byName: "Ayah" });
    expect(await activityVerdict(g, idB)).toMatchObject({ value: "safe", byName: "Ayah" });
    expect(await activityVerdict(g, idG)).toMatchObject({ value: "safe", byDeviceId: g.deviceId });
    // The list endpoint follows the same rule.
    const list = (await (await call("/scans", { token: b.token })).json()) as { items: { id: string; verdict: V }[] };
    expect(list.items.find((i) => i.id === idB)?.verdict?.value).toBe("safe");
  });

  it("a later visit by another member keeps the safe row (has a verdict: only a higher score takes over)", async () => {
    const { g, a, b } = await family();
    const idB = await scan(b);
    expect((await decide(g, await scan(a), "safe")).status).toBe(200);
    expect(await scan(b)).toBe(idB);
    expect((await activityVerdict(b, idB))?.value).toBe("safe");
  });

  it("undo is family-wide: after the weekly review, Bahaya on another member's scan wins everywhere", async () => {
    const { g, a, b } = await family();
    const idA = await scan(a);
    const idB = await scan(b);
    expect((await decide(g, idA, "safe")).status).toBe(200);
    await pastWeeklyReview();
    expect((await decide(g, idB, "not_safe")).status).toBe(200);
    for (const d of [a, b, g]) expect((await lookup(d))?.value).toBe("not_safe");
  });

  it("the weekly-review lock holds across the family", async () => {
    const { g, a, b } = await family();
    const idB = await scan(b);
    expect((await decide(g, await scan(a), "safe")).status).toBe(200);
    expect((await lookup(b))?.lockedUntil).toBeTruthy();
    const res = await decide(g, idB, "not_safe");
    expect(res.status).toBe(409);
    expect((await lookup(b))?.value).toBe("safe");
  });

  it("a domain-wide not_safe stays per member: another member never sees the page it was made on", async () => {
    const { g, a, b } = await family();
    expect((await decide(g, await scan(a, "https://bca-verify.top/a"), "not_safe")).status).toBe(200);
    expect((await lookup(a, "https://bca-verify.top/b"))?.value).toBe("not_safe");
    expect(await lookup(b, "https://bca-verify.top/b")).toBeNull();
  });

  it("a member who leaves loses the family's verdicts at once, and the family loses theirs", async () => {
    const { g, a, b } = await family();
    expect((await decide(g, await scan(g), "safe")).status).toBe(200);
    expect((await lookup(b))?.value).toBe("safe");

    expect((await call("/family/guardian", { method: "DELETE", token: b.token })).status).toBe(200);
    expect(await lookup(b)).toBeNull();
    expect((await lookup(a))?.value).toBe("safe");
  });

  it("guardian removes a member: verdicts made on that member's scans are gone for the whole family", async () => {
    const { g, a, b } = await family();
    expect((await decide(g, await scan(a), "safe")).status).toBe(200);
    expect((await lookup(b))?.value).toBe("safe");

    expect((await call(`/family/members/${a.deviceId}`, { method: "DELETE", token: g.token })).status).toBe(200);
    expect(await lookup(a)).toBeNull();
    expect(await lookup(b)).toBeNull();
    expect(await lookup(g)).toBeNull();
  });

  it("a new member gets the family's current list at once", async () => {
    const { g, a } = await family();
    expect((await decide(g, await scan(a), "safe")).status).toBe(200);
    const c = await createDevice("Tante");
    expect(await lookup(c)).toBeNull();
    await connect(g, c);
    expect((await lookup(c))?.value).toBe("safe");
  });

  it("no rows are copied: one decision stays one verdict row", async () => {
    const { g, a } = await family();
    expect((await decide(g, await scan(a), "safe")).status).toBe(200);
    const [row] = await sql<{ n: number }[]>`select count(*)::int as n from verdicts`;
    expect(row?.n).toBe(1);
  });

  it("a protected member still cannot mark a site safe", async () => {
    const { a } = await family();
    expect((await decide(a, await scan(a), "safe")).status).toBe(403);
  });
});
