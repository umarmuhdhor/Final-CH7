import { env } from "cloudflare:workers";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import blocked92 from "../../../contracts/fixtures/blocked-92.json";
import { useRateKeySecret } from "../src/http/keyHash";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice, type Created } from "./helpers/seed";
useRateKeySecret(env.RATE_KEY_SECRET);

// ADM-09 W16 (dashboard plan phase 10a K9): POST /verdicts reads admin.v_domain_lists_public in its own
// transaction, so a domain the dashboard protects stops entering the global review queue at once, and
// a removed one enters it again. The family's own verdict always applies.

const sql = testSql();
const admin = adminSql();
const DOMAIN = "dl-w16.test";
beforeEach(async () => {
  await resetDb(sql);
  await admin`delete from admin.domain_lists where domain = ${DOMAIN}`;
});
afterAll(async () => {
  await admin`delete from admin.domain_lists where domain = ${DOMAIN}`;
});

const connect = async (g: Created, p: Created) => {
  const { code } = (await (await call("/family/code", { method: "POST", token: g.token })).json()) as { code: string };
  expect((await call("/family/join", { method: "POST", token: p.token, json: { code } })).status).toBe(200);
};
async function family() {
  const g = await createDevice("Guardian", "guardian");
  const p = await createDevice("Mom");
  await connect(g, p);
  return { g, p };
}
const scan = async (d: Created, domain: string) => {
  const res = await call("/scans", {
    method: "POST", token: d.token,
    json: {
      url: `https://${domain}/login`, domain, pageTitle: blocked92.pageTitle, faviconUrl: blocked92.faviconUrl,
      score: blocked92.score, status: blocked92.status, signals: blocked92.signals, detectedAt: blocked92.detectedAt,
    },
  });
  expect(res.status, await res.clone().text()).toBe(201);
  return ((await res.json()) as { id: string }).id;
};
const notSafe = async (g: Created, scanId: string) => {
  const res = await call("/verdicts", { method: "POST", token: g.token, json: { scanId, value: "not_safe" } });
  expect(res.status, await res.clone().text()).toBe(200);
};
const eligible = async (domain: string) =>
  (await sql<{ e: boolean }[]>`select global_eligible as e from verdicts where domain = ${domain}`)[0]?.e;
const queued = async (domain: string) =>
  (await sql`select 1 from blocklist_entries where domain = ${domain}`).length === 1;

describe("verdicts read the domain lists (W16)", () => {
  it("a not_safe verdict on a subdomain of a subtree seed row is not queued", async () => {
    const { g, p } = await family();
    await notSafe(g, await scan(p, "x.bca.co.id"));
    expect(await eligible("x.bca.co.id")).toBe(false);
    expect(await queued("x.bca.co.id")).toBe(false);
  });

  it("a tenant of a shared host is queued, the host itself is not", async () => {
    const { g, p } = await family();
    await notSafe(g, await scan(p, "evil-dl.github.io"));
    await notSafe(g, await scan(p, "github.io"));
    expect(await eligible("evil-dl.github.io")).toBe(true);
    expect(await eligible("github.io")).toBe(false);
  });

  it("a domain protected through domain_set stops being queued; removed, it is queued again", async () => {
    const { g, p } = await family();
    const id = await scan(p, DOMAIN);
    await admin`select admin.domain_set(${DOMAIN}, 'apex', false, 'none', false, 'situs resmi uji W16', 'test@dl')`;
    await notSafe(g, id);
    expect(await eligible(DOMAIN)).toBe(false);
    expect(await queued(DOMAIN)).toBe(false);

    await admin`select admin.domain_remove(${DOMAIN}, 'hapus lagi untuk uji W16', 'test@dl')`;
    await notSafe(g, await scan(p, DOMAIN));
    expect(await eligible(DOMAIN)).toBe(true);
    expect(await queued(DOMAIN)).toBe(true);
  });
});
