import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import markedSafe from "../../../contracts/fixtures/blocked-marked-safe.json";
import verifiedScam from "../../../contracts/fixtures/blocked-verified-scam.json";
import warning41 from "../../../contracts/fixtures/warning-41.json";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { expectScanResult } from "./helpers/schema";
import { atWindowStart } from "./helpers/rateWindow";
import { call, createDevice, type Created } from "./helpers/seed";
import { keyHash, useRateKeySecret } from "../src/http/keyHash";
useRateKeySecret(env.RATE_KEY_SECRET);

const sql = testSql();
const admin = adminSql();
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
  admin`update blocklist_entries set approved_at = now(), approved_by = 'test' where domain = ${domain}`;

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

  it("warning scan takes a verdict too (GD-07, Figma Waspada)", async () => {
    const { g, p } = await family();
    const id = await scan(p, warning41 as Fixture);
    const res = await verdict(g, id, "safe");
    expect(res.status, await res.clone().text()).toBe(200);
    expect(((await res.json()) as VerdictBody).verdict?.value).toBe("safe");
    const item = (await (await call(`/scans/${id}`, { token: g.token })).json()) as Record<string, unknown>;
    expectScanResult(item);
    expect((item.verdict as { value: string }).value).toBe("safe");
    expect((await lookup(p, warning41.domain))?.value).toBe("safe");
  });

  it.each([
    ["guardian removes the member", "member"],
    ["protected leaves", "guardian"],
  ])("disconnect (%s): the ex-guardian's verdicts are gone at once (P13)", async (_, how) => {
    const { g, p } = await family();
    const id = await scan(p);
    await verdict(g, id, "safe");
    const res = how === "member"
      ? await call(`/family/members/${p.deviceId}`, { method: "DELETE", token: g.token })
      : await call("/family/guardian", { method: "DELETE", token: p.token });
    expect(res.status).toBe(200);
    expect(await lookup(p, blocked92.domain)).toBeNull();
    const item = (await (await call(`/scans/${id}`, { token: p.token })).json()) as { verdict: unknown };
    expect(item.verdict).toBeNull();
    const [n] = await sql<{ n: number }[]>`select count(*)::int as n from verdicts where by_device_id = ${g.deviceId}`;
    expect(n!.n).toBe(0);
  });

  it("the guardian's verdicts on its own scans survive a member's disconnect", async () => {
    const { g, p } = await family();
    const own = await scan(g);
    await verdict(g, own, "safe");
    await call("/family/guardian", { method: "DELETE", token: p.token });
    expect((await lookup(g, blocked92.domain))?.value).toBe("safe");
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

  it("a warning scan on a domain with a verdict carries it too", async () => {
    const { g, p } = await family();
    const blocked = await scan(p, blocked92 as Fixture, "same-domain.example");
    const warning = await scan(p, warning41 as Fixture, "same-domain.example");
    await verdict(g, blocked, "not_safe");
    const w = (await (await call(`/scans/${warning}`, { token: g.token })).json()) as { verdict: { value: string } | null };
    expect(w.verdict?.value).toBe("not_safe");
  });

  it("a new verdict replaces the old one (Ubah)", async () => {
    const { g, p } = await family();
    const id = await scan(p, warning41 as Fixture);
    await verdict(g, id, "safe");
    const res = await verdict(g, id, "not_safe");
    expect(res.status).toBe(200);
    expect((await lookup(p, warning41.domain))?.value).toBe("not_safe");
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
    const hash = await keyHash(`verdicts_create:${g.deviceId}`);
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

  it("a trailing dot is tolerated; a missing domain → 422", async () => {
    const p = await createDevice("Mom");
    expect(await lookup(p, "example.com.")).toBeNull();
    expect((await call("/verdicts", { token: p.token })).status).toBe(422);
  });

  it.each(["", "not a domain", "localhost", "a".repeat(254) + ".com", "https://x.com/"])("422 for %j", async (q) => {
    const p = await createDevice("Mom");
    expect((await call(`/verdicts?domain=${encodeURIComponent(q)}`, { token: p.token })).status).toBe(422);
  });

  it("401 without token", async () => {
    expect((await call("/verdicts?domain=example.com")).status).toBe(401);
  });

  it("rate limits 30 per 10 s per device with Retry-After, through the binding: no rate_limit_hits row", async () => {
    const p = await createDevice("Mom");
    await atWindowStart(10); // all 31 requests in one 10 s window of the binding
    for (let i = 0; i < 30; i++) expect((await call("/verdicts?domain=a.example", { token: p.token })).status).toBe(200);
    const res = await call("/verdicts?domain=a.example", { token: p.token });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get("retry-after"))).toBeGreaterThan(0);
    expect(await sql`select 1 from rate_limit_hits where bucket = 'verdicts_get'`).toHaveLength(0);
  }, 15_000);
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

  it("safe verdict → no entry; not_safe → safe removes the unapproved row (no browsing domain kept)", async () => {
    const { g, p } = await family();
    const id = await scan(p, blocked92 as Fixture, "flip.example");
    await verdict(g, id, "safe");
    expect(await entry("flip.example")).toBeUndefined();
    await verdict(g, id, "not_safe");
    expect((await entry("flip.example"))?.families).toBe(1);
    await verdict(g, id, "safe");
    expect(await entry("flip.example")).toBeUndefined();
  });

  it("a rejected entry stays rejected and unserved as support grows, and goes when support ends", async () => {
    const a = await family();
    const b = await family();
    const id = await scan(a.p, blocked92 as Fixture, "rejected.example");
    await verdict(a.g, id, "not_safe");
    await admin`update blocklist_entries set rejected_at = now(), rejected_by = 'test' where domain = 'rejected.example'`;
    await verdict(b.g, await scan(b.p, blocked92 as Fixture, "rejected.example"), "not_safe");
    const [row] = await sql`select families, rejected_at from blocklist_entries where domain = 'rejected.example'`;
    expect(row!.families).toBe(2);
    expect(row!.rejected_at).not.toBeNull();
    expect((await blocklist(a.p)).domains).toEqual([]);

    await verdict(a.g, id, "safe");
    await call("/family/guardian", { method: "DELETE", token: b.p.token });
    expect(await entry("rejected.example")).toBeUndefined();
  });

  it("families counts distinct guardians", async () => {
    const a = await family();
    const b = await family();
    await verdict(a.g, await scan(a.p, blocked92 as Fixture, "many.example"), "not_safe");
    await verdict(b.g, await scan(b.p, blocked92 as Fixture, "many.example"), "not_safe");
    expect((await entry("many.example"))?.families).toBe(2);
  });

  it("disconnect removes the ex-guardian's support; an approved entry stays served", async () => {
    const { g, p } = await family();
    await verdict(g, await scan(p, blocked92 as Fixture, "queued.example"), "not_safe");
    await verdict(g, await scan(p, blocked92 as Fixture, "approved.example"), "not_safe");
    await approve("approved.example");
    await call("/family/guardian", { method: "DELETE", token: p.token });
    expect(await entry("queued.example")).toBeUndefined();
    expect((await entry("approved.example"))?.families).toBe(0);
    expect((await blocklist(p)).domains.map((d) => d.domain)).toEqual(["approved.example"]);
  });

  it("DELETE /devices/me of the protected owner recounts families", async () => {
    const { g, p } = await family();
    await verdict(g, await scan(p, blocked92 as Fixture, "owner-gone.example"), "not_safe");
    expect((await call("/devices/me", { method: "DELETE", token: p.token })).status).toBe(200);
    expect(await entry("owner-gone.example")).toBeUndefined();
  });

  it("DELETE /devices/me of the guardian recounts families", async () => {
    const { g, p } = await family();
    await verdict(g, await scan(p, blocked92 as Fixture, "guardian-gone.example"), "not_safe");
    await verdict(g, await scan(p, blocked92 as Fixture, "guardian-approved.example"), "not_safe");
    await approve("guardian-approved.example");
    expect((await call("/devices/me", { method: "DELETE", token: g.token })).status).toBe(200);
    expect(await entry("guardian-gone.example")).toBeUndefined();
    expect((await blocklist(p)).domains.map((d) => d.domain)).toEqual(["guardian-approved.example"]);
  });

  it("at most 10 newly queued domains per guardian per 24 h; the verdict itself still applies", async () => {
    const { g, p } = await family();
    for (let i = 0; i < 10; i++) await verdict(g, await scan(p, blocked92 as Fixture, `cap${i}.example`), "not_safe");
    const id = await scan(p, blocked92 as Fixture, "cap10.example");
    expect((await verdict(g, id, "not_safe")).status).toBe(200);
    expect(await entry("cap10.example")).toBeUndefined();
    expect((await lookup(p, "cap10.example"))?.value).toBe("not_safe");
    // Re-deciding an already queued domain is not a new one.
    await verdict(g, await scan(p, blocked92 as Fixture, "cap0.example"), "not_safe");
    expect((await entry("cap0.example"))?.families).toBe(1);
  });

  it("re-confirming an already queued domain keeps it queued even when the cap is full", async () => {
    const { g, p } = await family();
    const old = await scan(p, blocked92 as Fixture, "old-queued.example");
    await verdict(g, old, "not_safe");
    await sql`update verdicts set decided_at = now() - interval '2 days' where domain = 'old-queued.example'`;
    for (let i = 0; i < 10; i++) await verdict(g, await scan(p, blocked92 as Fixture, `new${i}.example`), "not_safe");
    await verdict(g, old, "not_safe");
    expect((await entry("old-queued.example"))?.families).toBe(1);
  });

  it("the queue cap holds under parallel verdicts", async () => {
    const g = await createDevice("G", "guardian");
    const members = [await createDevice("A"), await createDevice("B"), await createDevice("C")];
    for (const m of members) await connect(g, m);
    const ids: string[] = [];
    for (let i = 0; i < 15; i++) ids.push(await scan(members[i % 3]!, blocked92 as Fixture, `par${i}.example`));
    const res = await Promise.all(ids.map((id) => verdict(g, id, "not_safe")));
    expect(res.map((r) => r.status)).toEqual(Array(15).fill(200));
    const [n] = await sql<{ n: number }[]>`select count(*)::int as n from blocklist_entries where domain like 'par%'`;
    expect(n!.n).toBe(10);
  });

  it.each(["co.id", "github.io", "vercel.app", "blogspot.com"])("public suffix / shared host %s never enters the queue", async (dom) => {
    const { g, p } = await family();
    expect((await verdict(g, await scan(p, blocked92 as Fixture, dom), "not_safe")).status).toBe(200);
    expect(await entry(dom)).toBeUndefined();
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
    await admin`update blocklist_entries set removed_at = now() where domain = 'gone.example'`;
    await verdict(g, id, "safe");
    await verdict(g, id, "not_safe");
    expect((await blocklist(p)).domains).toEqual([]);
    const inc = await blocklist(p, `?since=${encodeURIComponent(before.nextSince!)}`);
    expect(inc.removed?.map((r) => r.domain)).toEqual(["gone.example"]);
  });
});

describe("GET /verdicts logs verdict_seen for fresh verdicts (EX-06, fase 25 K7)", () => {
  afterEach(() => vi.restoreAllMocks());
  const seen = () => {
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));
    return () => lines.filter((l) => l.includes('"verdict_seen"')).map((l) => JSON.parse(l) as Record<string, unknown>);
  };

  it("a verdict decided within 120 s: one line with exactly event, ageMs ≥ 0 and value; no domain or ids", async () => {
    const g = await createDevice("Guardian Name", "guardian");
    const p = await createDevice("Protected Name");
    await connect(g, p);
    const id = await scan(p, blocked92 as Fixture, "fresh-private.example");
    expect((await verdict(g, id, "safe")).status).toBe(200);
    const lines = seen();
    expect(await lookup(p, "fresh-private.example")).toMatchObject({ value: "safe" });
    const got = lines();
    expect(got).toHaveLength(1);
    expect(Object.keys(got[0]!)).toEqual(["event", "ageMs", "value"]);
    expect(got[0]).toMatchObject({ event: "verdict_seen", value: "safe" });
    expect(got[0]!.ageMs).toEqual(expect.any(Number));
    expect(got[0]!.ageMs as number).toBeGreaterThanOrEqual(0);
    expect(got[0]!.ageMs as number).toBeLessThanOrEqual(120_000);
    const text = JSON.stringify(got);
    for (const leak of ["fresh-private", g.deviceId, p.deviceId, id, "Guardian Name", g.token, p.token]) expect(text).not.toContain(leak);
  });

  it("a verdict older than 120 s, or no verdict at all: no line", async () => {
    const g = await createDevice("G", "guardian");
    const p = await createDevice("P");
    await connect(g, p);
    const id = await scan(p, blocked92 as Fixture, "old.example");
    expect((await verdict(g, id, "not_safe")).status).toBe(200);
    await admin`update verdicts set decided_at = now() - interval '121 seconds' where scan_id = ${id}`;
    const lines = seen();
    expect(await lookup(p, "old.example")).toMatchObject({ value: "not_safe" });
    expect(await lookup(p, "never-decided.example")).toBeNull();
    expect(lines()).toEqual([]);
  });
});

describe("verdicts per link (#241, contracts/api.md Verdicts)", () => {
  /**
   * One scan row per page. POST /scans keeps one row per owner + domain (recordScan), so a second
   * page of a domain is written directly, as the rows a Guardian would decide on.
   */
  let seq = 0;
  const scanAt = async (d: Created, url: string, domain: string) => {
    const [r] = await sql<{ id: string }[]>`
      insert into scans (owner_id, url, domain, score, status, detected_at)
      values (${d.deviceId}, ${url}, ${domain}, 92, 'blocked', now() - make_interval(secs => ${++seq}))
      returning id`;
    return r!.id;
  };
  const lookupLink = async (d: Created, url: string, domain: string) => {
    const res = await call(`/verdicts?url=${encodeURIComponent(url)}&domain=${encodeURIComponent(domain)}`, { token: d.token });
    expect(res.status, await res.clone().text()).toBe(200);
    return ((await res.json()) as VerdictBody).verdict;
  };
  const decide = (g: Created, scanId: string, value: "safe" | "not_safe", notes?: unknown) =>
    call("/verdicts", { method: "POST", token: g.token, json: notes === undefined ? { scanId, value } : { scanId, value, notes } });
  const row = async (owner: string) =>
    (await sql<{ url: string; notes: string | null; value: string }[]>`
      select url, notes, value from verdicts where owner_id = ${owner} order by url`);

  it("stores the scan's link (origin + path, no query or fragment) and keeps one row per link", async () => {
    const { g, p } = await family();
    const a = await scanAt(p, "https://Login.Penipu.test/akun/masuk?ref=wa#top", "penipu.test");
    const b = await scanAt(p, "https://penipu.test/hadiah", "penipu.test");
    expect((await decide(g, a, "not_safe")).status).toBe(200);
    expect((await decide(g, b, "safe")).status).toBe(200);
    expect((await decide(g, a, "not_safe")).status).toBe(200); // the same link again: still one row
    expect((await row(p.deviceId)).map((r) => [r.url, r.value])).toEqual([
      ["https://login.penipu.test/akun/masuk", "not_safe"],
      ["https://penipu.test/hadiah", "safe"],
    ]);
  });

  it("safe opens only its own link", async () => {
    const { g, p } = await family();
    const a = await scanAt(p, "https://sites.example/a", "sites.example");
    expect((await decide(g, a, "safe")).status).toBe(200);
    expect(await lookupLink(p, "https://sites.example/a?utm=1#x", "sites.example")).toMatchObject({ value: "safe", byName: "Adhella" });
    expect(await lookupLink(p, "https://sites.example/b", "sites.example")).toBeNull();
    expect(await lookupLink(g, "https://sites.example/a", "sites.example")).toBeNull(); // another owner
  });

  it("not_safe on one link covers the other links of the domain; an exact verdict wins", async () => {
    const { g, p } = await family();
    const a = await scanAt(p, "https://evil.test/a", "evil.test");
    const b = await scanAt(p, "https://evil.test/b", "evil.test");
    expect((await decide(g, a, "not_safe")).status).toBe(200);
    expect(await lookupLink(p, "https://evil.test/c", "evil.test")).toMatchObject({ value: "not_safe" });
    expect(await lookupLink(p, "https://www.evil.test/c", "evil.test")).toMatchObject({ value: "not_safe" });
    expect((await decide(g, b, "safe")).status).toBe(200);
    expect(await lookupLink(p, "https://evil.test/b", "evil.test")).toMatchObject({ value: "safe" });
    expect(await lookupLink(p, "https://evil.test/c", "evil.test")).toMatchObject({ value: "not_safe" });
  });

  it("on a shared host one page says nothing about the others (admin.domain_lists hosting)", async () => {
    const { g, p } = await family();
    // host_path: anyone publishes under a path of sites.google.com (registrable domain google.com).
    const page = await scanAt(p, "https://sites.google.com/view/hadiah", "google.com");
    expect((await decide(g, page, "not_safe")).status).toBe(200);
    expect(await lookupLink(p, "https://sites.google.com/view/hadiah", "google.com")).toMatchObject({ value: "not_safe" });
    expect(await lookupLink(p, "https://sites.google.com/view/sekolah", "google.com")).toBeNull();
    // subdomains: a tenant (evil.github.io) is one owner, so its pages share the fallback.
    const tenant = await scanAt(p, "https://evil.github.io/a", "evil.github.io");
    expect((await decide(g, tenant, "not_safe")).status).toBe(200);
    expect(await lookupLink(p, "https://evil.github.io/b", "evil.github.io")).toMatchObject({ value: "not_safe" });
    expect(await lookupLink(p, "https://other.github.io/b", "other.github.io")).toBeNull();
  });

  it("?url= needs a domain it belongs to, and an http(s) URL", async () => {
    const { p } = await family();
    const status = async (q: string) => (await call(`/verdicts?${q}`, { token: p.token })).status;
    expect(await status(`url=${encodeURIComponent("https://a.test/x")}`)).toBe(422);
    expect(await status(`url=${encodeURIComponent("https://a.test/x")}&domain=b.test`)).toBe(422);
    expect(await status(`url=${encodeURIComponent("https://nota.test/x")}&domain=a.test`)).toBe(422);
    expect(await status(`url=${encodeURIComponent("ftp://a.test/x")}&domain=a.test`)).toBe(422);
    expect(await status(`url=not-a-url&domain=a.test`)).toBe(422);
    expect(await status(`url=${encodeURIComponent("https://a.test/x")}&domain=A.test`)).toBe(200);
  });

  it("deprecated ?domain= alone: any not_safe on the domain, else the newest safe", async () => {
    const { g, p } = await family();
    const a = await scanAt(p, "https://old.test/a", "old.test");
    const b = await scanAt(p, "https://old.test/b", "old.test");
    expect((await decide(g, a, "safe")).status).toBe(200);
    expect(await lookup(p, "old.test")).toMatchObject({ value: "safe" });
    expect((await decide(g, b, "not_safe")).status).toBe(200);
    expect((await decide(g, a, "safe")).status).toBe(200); // newer, but a not_safe wins
    expect(await lookup(p, "old.test")).toMatchObject({ value: "not_safe" });
  });

  it("Activity shows each scan the verdict of the same rule", async () => {
    const { g, p } = await family();
    const a = await scanAt(p, "https://act.test/a", "act.test");
    const b = await scanAt(p, "https://act.test/b", "act.test");
    const c = await scanAt(p, "https://act.test/c", "act.test");
    expect((await decide(g, a, "safe")).status).toBe(200);
    const items = async () => {
      const body = (await (await call(`/scans?owner=${p.deviceId}`, { token: g.token })).json()) as {
        items: { id: string; verdict: { value: string } | null }[];
      };
      return Object.fromEntries(body.items.map((i) => [i.id, i.verdict?.value ?? null]));
    };
    expect(await items()).toEqual({ [a]: "safe", [b]: null, [c]: null });
    expect((await decide(g, b, "not_safe")).status).toBe(200);
    expect(await items()).toEqual({ [a]: "safe", [b]: "not_safe", [c]: "not_safe" });
  });

  describe("notes", () => {
    it("are stored, never returned, and replaced by the next decision", async () => {
      const { g, p } = await family();
      const a = await scanAt(p, "https://note.test/a", "note.test");
      const res = await decide(g, a, "not_safe", "  Minta kode OTP\nlewat WA ‮ ");
      expect(res.status).toBe(200);
      const body = (await res.json()) as { verdict: Record<string, unknown> };
      expect(Object.keys(body.verdict).sort()).toEqual(["byDeviceId", "byName", "decidedAt", "value"]);
      expect((await row(p.deviceId))[0]!.notes).toBe("Minta kode OTP lewat WA");
      expect(await lookupLink(p, "https://note.test/a", "note.test")).not.toHaveProperty("notes");
      expect((await decide(g, a, "safe")).status).toBe(200); // older builds send none
      expect((await row(p.deviceId))[0]!.notes).toBeNull();
      expect((await decide(g, a, "safe", "   ")).status).toBe(200);
      expect((await row(p.deviceId))[0]!.notes).toBeNull();
    });

    it("at most 280 characters (code points); not a string → 422", async () => {
      const { g, p } = await family();
      const a = await scanAt(p, "https://note.test/a", "note.test");
      expect((await decide(g, a, "not_safe", "😀".repeat(280))).status).toBe(200);
      expect(await errorCode(await decide(g, a, "not_safe", "x".repeat(281)))).toBe("invalid_body");
      expect(await errorCode(await decide(g, a, "not_safe", 42))).toBe("invalid_body");
      expect((await decide(g, a, "not_safe", null)).status).toBe(200);
    });

    it("reach the admin label and archive masked (admin.mask_note), never raw", async () => {
      const { g, p } = await family();
      const a = await scanAt(p, "https://note.test/a", "note.test");
      expect((await decide(g, a, "not_safe", "Telepon 081234567890 atau a@b.co")).status).toBe(200);
      const [label] = await admin<{ note: string }[]>`
        select note from admin.domain_labels where domain = 'note.test' order by id desc limit 1`;
      expect(label!.note).toBe("Telepon [nomor] atau [email]");
      const [archived] = await admin<{ note: string | null }[]>`select note from admin.scan_archive where scan_id = ${a}`;
      expect(archived?.note).toBe("Telepon [nomor] atau [email]");
    });
  });
});
