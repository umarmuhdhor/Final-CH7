import { beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import markedSafe from "../../../contracts/fixtures/blocked-marked-safe.json";
import verifiedScam from "../../../contracts/fixtures/blocked-verified-scam.json";
import warning41 from "../../../contracts/fixtures/warning-41.json";
import { sha256 } from "../src/http/crypto";
import { resetDb, testSql } from "./helpers/resetDb";
import { expectScanResult } from "./helpers/schema";
import { call, createDevice, type Created } from "./helpers/seed";

const sql = testSql();
beforeEach(() => resetDb(sql));

type Fixture = {
  url: string; domain: string; pageTitle: string; faviconUrl: string | null; score: number; status: string;
  signals: unknown[]; detectedAt: string;
};
type VerdictBody = { verdict: { value: string; byDeviceId: string; byName: string; decidedAt: string } | null };
const errorCode = async (res: Response) => ((await res.json()) as { error: { code: string } }).error.code;

const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};
/** POST /scans like the extension; domain/url overridable. */
const scan = async (d: Created, f: Fixture = blocked92 as Fixture, domain?: string) => {
  const dom = domain ?? f.domain;
  const res = await call("/scans", {
    method: "POST", token: d.token,
    json: {
      url: domain ? `https://${dom}/login` : f.url, domain: dom, pageTitle: f.pageTitle, faviconUrl: f.faviconUrl,
      score: f.score, status: f.status, signals: f.signals, detectedAt: f.detectedAt,
    },
  });
  expect(res.status, await res.clone().text()).toBe(201);
  return ((await res.json()) as { id: string }).id;
};
const verdict = (g: Created, scanId: string, value: "safe" | "not_safe") =>
  call("/verdicts", { method: "POST", token: g.token, json: { scanId, value } });
const lookup = async (d: Created, domain: string) => {
  const res = await call(`/verdicts?domain=${encodeURIComponent(domain)}`, { token: d.token });
  expect(res.status).toBe(200);
  return ((await res.json()) as VerdictBody).verdict;
};
const entry = async (domain: string) =>
  (await sql`select families, approved_at from blocklist_entries where domain = ${domain}`)[0] as
    | { families: number; approved_at: Date | null }
    | undefined;
const blocklist = async (d: Created, q = "") =>
  (await (await call(`/blocklist${q}`, { token: d.token })).json()) as {
    domains: { domain: string; addedAt: string }[];
    removed?: { domain: string; removedAt: string }[];
    nextSince: string | null;
  };
const approve = (domain: string) =>
  sql`update blocklist_entries set approved_at = now(), approved_by = 'test' where domain = ${domain}`;

/** Guardian G with a connected protected member P. */
async function family() {
  const g = await createDevice("Adhella", "guardian");
  const p = await createDevice("Mom");
  await connect(g, p);
  return { g, p };
}

describe("POST /verdicts", () => {
  it("guardian marks a member's blocked scan → { verdict } with the guardian's current name", async () => {
    const { g, p } = await family();
    const id = await scan(p);
    const res = await verdict(g, id, "safe");
    expect(res.status).toBe(200);
    const body = (await res.json()) as VerdictBody;
    expect(body.verdict).toMatchObject({ value: "safe", byDeviceId: g.deviceId, byName: "Adhella" });
    expect(Date.now() - Date.parse(body.verdict!.decidedAt)).toBeLessThan(10_000);
  });

  it("guardian may mark its own blocked scan", async () => {
    const g = await createDevice("G", "guardian");
    const id = await scan(g);
    expect((await verdict(g, id, "safe")).status).toBe(200);
    expect((await lookup(g, blocked92.domain))?.value).toBe("safe");
  });

  it("protected → 403 forbidden; other guardian → 403 verdict_not_allowed; unknown scan → 404", async () => {
    const { g, p } = await family();
    const other = await createDevice("Other", "guardian");
    const id = await scan(p);

    const asProtected = await verdict(p, id, "safe");
    expect(asProtected.status).toBe(403);
    const asOther = await verdict(other, id, "not_safe");
    expect(asOther.status).toBe(403);
    expect(await errorCode(asOther)).toBe("verdict_not_allowed");
    expect((await verdict(g, "00000000-0000-4000-8000-000000000000", "safe")).status).toBe(404);
    expect((await verdict(g, "not-a-uuid", "safe")).status).toBe(404);
  });

  it("warning scan → 409 verdict_not_allowed", async () => {
    const { g, p } = await family();
    const id = await scan(p, warning41 as Fixture);
    const res = await verdict(g, id, "safe");
    expect(res.status).toBe(409);
    expect(await errorCode(res)).toBe("verdict_not_allowed");
  });

  it("after disconnect the old guardian → 403", async () => {
    const { g, p } = await family();
    const id = await scan(p);
    expect((await call("/family/guardian", { method: "DELETE", token: p.token })).status).toBe(200);
    expect((await verdict(g, id, "safe")).status).toBe(403);
  });

  it.each([
    [{ value: "safe" }],
    [{ scanId: "x", value: "maybe" }],
    [{ scanId: "00000000-0000-4000-8000-000000000000", value: "safe", extra: 1 }],
  ])("422 for %j", async (json) => {
    const g = await createDevice("G", "guardian");
    expect((await call("/verdicts", { method: "POST", token: g.token, json })).status).toBe(422);
  });

  it("safe then not_safe → last decision wins, for every blocked scan of that owner + domain", async () => {
    const { g, p } = await family();
    const a = await scan(p);
    const b = await scan(p);
    await verdict(g, a, "safe");
    await verdict(g, b, "not_safe");
    expect((await lookup(p, blocked92.domain))?.value).toBe("not_safe");
    for (const id of [a, b]) {
      const item = (await (await call(`/scans/${id}`, { token: g.token })).json()) as { verdict: { value: string } };
      expect(item.verdict.value).toBe("not_safe");
    }
    const [n] = await sql<{ n: number }[]>`select count(*)::int as n from verdicts where owner_id = ${p.deviceId}`;
    expect(n!.n).toBe(1);
  });

  it("applies to that owner only, not to other owners on the same domain", async () => {
    const { g, p } = await family();
    const other = await createDevice("Dad");
    await connect(g, other);
    const id = await scan(p);
    await scan(other);
    await verdict(g, id, "safe");
    expect((await lookup(p, blocked92.domain))?.value).toBe("safe");
    expect(await lookup(other, blocked92.domain)).toBeNull();
  });

  it("a warning scan on a domain with a verdict keeps verdict null", async () => {
    const { g, p } = await family();
    const blocked = await scan(p, blocked92 as Fixture, "same-domain.example");
    const warning = await scan(p, warning41 as Fixture, "same-domain.example");
    await verdict(g, blocked, "not_safe");
    const w = (await (await call(`/scans/${warning}`, { token: g.token })).json()) as { verdict: unknown };
    expect(w.verdict).toBeNull();
  });

  it("ScanResult verdicts match the two contract fixtures in shape and values", async () => {
    for (const f of [verifiedScam, markedSafe] as const) {
      await resetDb(sql);
      const g = await createDevice(f.verdict.byName, "guardian");
      const p = await createDevice(f.ownerName);
      await connect(g, p);
      const id = await scan(p, f as Fixture);
      await verdict(g, id, f.verdict.value as "safe" | "not_safe");
      const item = (await (await call(`/scans/${id}`, { token: g.token })).json()) as Record<string, unknown>;
      expectScanResult(item);
      expect(item.verdict).toEqual({ ...f.verdict, byDeviceId: g.deviceId, decidedAt: expect.any(String) });
    }
  });

  it("rate limits 60 per minute per guardian", async () => {
    const { g, p } = await family();
    const id = await scan(p);
    const hash = await sha256(`verdicts_create:${g.deviceId}`);
    await sql`insert into rate_limit_hits (bucket, key_hash) select 'verdicts_create', ${hash} from generate_series(1, 60)`;
    expect((await verdict(g, id, "safe")).status).toBe(429);
  });
});

describe("GET /verdicts?domain=", () => {
  it("null without a verdict; domain normalized (www., case, spaces)", async () => {
    const { g, p } = await family();
    expect(await lookup(p, blocked92.domain)).toBeNull();
    const id = await scan(p, blocked92 as Fixture, "example-scam.id");
    await verdict(g, id, "safe");
    for (const q of ["example-scam.id", "www.Example-Scam.ID", " EXAMPLE-SCAM.id "]) {
      expect((await lookup(p, q))?.value, q).toBe("safe");
    }
  });

  it("works for both modes (guardian's own blocked page)", async () => {
    const g = await createDevice("G", "guardian");
    const id = await scan(g);
    await verdict(g, id, "safe");
    expect((await lookup(g, blocked92.domain))?.value).toBe("safe");
  });

  it.each(["", "not a domain", "localhost", "a".repeat(254) + ".com", "https://x.com/"])("422 for %j", async (q) => {
    const p = await createDevice("Mom");
    expect((await call(`/verdicts?domain=${encodeURIComponent(q)}`, { token: p.token })).status).toBe(422);
  });

  it("401 without token", async () => {
    expect((await call("/verdicts?domain=example.com")).status).toBe(401);
  });

  it("rate limits 10 per 10 s per device with Retry-After", async () => {
    const p = await createDevice("Mom");
    for (let i = 0; i < 10; i++) expect((await call("/verdicts?domain=a.example", { token: p.token })).status).toBe(200);
    const res = await call("/verdicts?domain=a.example", { token: p.token });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);
  });
});

describe("blocklist queue from verdicts (R2 §5, D-alief-25, SECURITY T5)", () => {
  it("not_safe on a connected protected member's scan → queued, not served until approved", async () => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, "evil-bank.example");
    await verdict(g, id, "not_safe");
    expect(await entry("evil-bank.example")).toEqual({ families: 1, approved_at: null });
    expect((await blocklist(p)).domains).toEqual([]);

    await approve("evil-bank.example");
    const full = await blocklist(p);
    expect(full.domains.map((d) => d.domain)).toEqual(["evil-bank.example"]);
    expect(full.nextSince).toBe(full.domains[0]!.addedAt);
  });

  it("an old verdict approved later still reaches an incremental refresh", async () => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, "late-approve.example");
    await verdict(g, id, "not_safe");
    const before = await blocklist(p);
    await approve("late-approve.example");
    const inc = await blocklist(p, `?since=${encodeURIComponent(before.nextSince ?? "2000-01-01T00:00:00.000000Z")}`);
    expect(inc.domains.map((d) => d.domain)).toEqual(["late-approve.example"]);
  });

  it("guardian's own (fake) scan + not_safe → no entry", async () => {
    const g = await createDevice("G", "guardian");
    const id = await scan(g, blocked92 as Fixture, "real-bank.example");
    await verdict(g, id, "not_safe");
    expect(await entry("real-bank.example")).toBeUndefined();
  });

  it("attacker-owned guardian + protected → entry stays waiting for review, never served", async () => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, "victim-shop.example");
    await verdict(g, id, "not_safe");
    expect((await entry("victim-shop.example"))?.approved_at).toBeNull();
    expect((await blocklist(g)).domains).toEqual([]);
  });

  it("safe verdict → no entry; not_safe → safe recounts families to 0 but keeps the row", async () => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, "flip.example");
    await verdict(g, id, "safe");
    expect(await entry("flip.example")).toBeUndefined();
    await verdict(g, id, "not_safe");
    expect((await entry("flip.example"))?.families).toBe(1);
    await verdict(g, id, "safe");
    expect((await entry("flip.example"))?.families).toBe(0);
  });

  it("families counts distinct guardians", async () => {
    const a = await family();
    const b = await family();
    await verdict(a.g, await scan(a.p, blocked92 as Fixture, "many.example"), "not_safe");
    await verdict(b.g, await scan(b.p, blocked92 as Fixture, "many.example"), "not_safe");
    expect((await entry("many.example"))?.families).toBe(2);
  });

  it("disconnect after the verdict keeps it eligible (snapshot)", async () => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, "snap.example");
    await verdict(g, id, "not_safe");
    await call("/family/guardian", { method: "DELETE", token: p.token });
    const [v] = await sql<{ e: boolean }[]>`select global_eligible as e from verdicts where domain = 'snap.example'`;
    expect(v!.e).toBe(true);
    expect((await entry("snap.example"))?.families).toBe(1);
  });

  it.each(["klikbca.com", "bca.co.id", "pajak.go.id", "google.com"])("allowlisted %s never enters the queue", async (dom) => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, dom);
    expect((await verdict(g, id, "not_safe")).status).toBe(200);
    expect(await entry(dom)).toBeUndefined();
    // The family verdict itself still applies at once.
    expect((await lookup(p, dom))?.value).toBe("not_safe");
  });

  it("a removed entry is not revived by a new verdict and shows in removed[]", async () => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, "gone.example");
    await verdict(g, id, "not_safe");
    await approve("gone.example");
    const before = await blocklist(p);
    await sql`update blocklist_entries set removed_at = now() where domain = 'gone.example'`;
    await verdict(g, id, "safe");
    await verdict(g, id, "not_safe");
    expect((await blocklist(p)).domains).toEqual([]);
    const inc = await blocklist(p, `?since=${encodeURIComponent(before.nextSince!)}`);
    expect(inc.removed?.map((r) => r.domain)).toEqual(["gone.example"]);
  });
});
