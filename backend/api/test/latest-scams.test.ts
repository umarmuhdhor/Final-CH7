import { beforeEach, describe, expect, it } from "vitest";
import { adminSql, resetDb, testSql } from "./helpers/resetDb";
import { call, createDevice } from "./helpers/seed";

const sql = testSql();
const admin = adminSql();
let token: string;

beforeEach(async () => {
  await resetDb(sql);
  await admin`delete from admin.review_decisions where actor = 'latest-scams-test'`;
  token = (await createDevice()).token;
});

type Body = { items: { category: string; title: { en: string; id: string }; lastSeenAt: string }[] };
const get = async () => {
  const res = await call("/scams/latest", { token });
  return { res, body: (await res.json()) as Body };
};

/** A blocklist domain approved by an admin with this category (what admin.vote leaves behind). */
async function approve(domain: string, category: string, { removed = false } = {}) {
  await admin`insert into blocklist_entries (domain, approved_at, approved_by, removed_at)
    values (${domain}, now(), 't', ${removed ? admin`now()` : null})`;
  await admin`insert into admin.review_decisions (domain, action, category, note, actor)
    values (${domain}, 'approve', ${category}, 'approved in a test', 'latest-scams-test')`;
}

/** Devices older than a day (the age gate), each with one scan on `domain`. */
async function hits(domain: string, n: number, opts: { status?: "blocked" | "warning"; ageHours?: number; createdAgo?: string } = {}) {
  const ids: string[] = [];
  for (let i = 0; i < n; i++) {
    const { deviceId } = await createDevice(`D${i}`);
    await admin`update devices set created_at = now() - make_interval(hours => ${opts.ageHours ?? 48}) where id = ${deviceId}`;
    await scan(deviceId, domain, opts);
    ids.push(deviceId);
  }
  return ids;
}

async function scan(ownerId: string, domain: string, opts: { status?: "blocked" | "warning"; createdAgo?: string } = {}) {
  const status = opts.status ?? "blocked";
  const created = opts.createdAgo ? admin`now() - ${opts.createdAgo}::interval` : admin`now()`;
  await admin`insert into scans (owner_id, url, domain, score, status, detected_at, created_at)
    values (${ownerId}, ${`https://${domain}/login`}, ${domain}, ${status === "blocked" ? 95 : 50}, ${status}, now(), ${created})`;
}

describe("GET /scams/latest", () => {
  it("401 without token", async () => {
    expect((await call("/scams/latest")).status).toBe(401);
  });

  it("empty: no items, cacheable for 10 minutes", async () => {
    const { res, body } = await get();
    expect(res.status).toBe(200);
    expect(body).toEqual({ items: [] });
    expect(res.headers.get("cache-control")).toBe("private, max-age=600");
  });

  it("a category 3 devices were blocked on this week, with the admin's words only", async () => {
    await approve("hadiah-shopee.example", "undian_palsu");
    await hits("hadiah-shopee.example", 2);
    await hits("klaim.hadiah-shopee.example", 1); // a subdomain counts for the approved domain

    const { body } = await get();
    expect(body.items).toHaveLength(1);
    const item = body.items[0]!;
    expect(item.category).toBe("undian_palsu");
    expect(item.title).toEqual({ en: "Fake prize", id: "Undian/hadiah palsu" });
    expect(item.lastSeenAt).toMatch(/^\d{4}-\d\d-\d\dT\d\d:00:00Z$/);
    // Nothing that points at a site or a person.
    expect(JSON.stringify(body)).not.toMatch(/example|login|D0/);
  });

  it("fewer than 3 devices: hidden, however many scans one device sends", async () => {
    await approve("bank-palsu.example", "phishing_bank");
    const [a] = await hits("bank-palsu.example", 2);
    for (let i = 0; i < 10; i++) await scan(a!, "bank-palsu.example");
    expect((await get()).body.items).toEqual([]);
  });

  it("spam gates: unapproved, removed, warning-only, fresh devices, old scans and 'lainnya' count for nothing", async () => {
    await admin`insert into blocklist_entries (domain) values ('pending.example')`; // waiting for review
    await hits("pending.example", 3);
    await approve("removed.example", "phishing_bank", { removed: true });
    await hits("removed.example", 3);
    await approve("warn.example", "investasi_bodong");
    await hits("warn.example", 3, { status: "warning" });
    await approve("fresh.example", "phishing_ewallet");
    await hits("fresh.example", 3, { ageHours: 1 });
    await approve("old.example", "pinjol_ilegal");
    await hits("old.example", 3, { createdAgo: "8 days" });
    await approve("other.example", "lainnya");
    await hits("other.example", 3);

    expect((await get()).body.items).toEqual([]);
  });

  it("an official site on the trusted/protected lists never shows, even if approved", async () => {
    const [row] = await admin<{ domain: string }[]>`
      select domain from admin.domain_lists where trusted and not public_suffix order by domain limit 1`;
    expect(row).toBeDefined();
    await approve(row!.domain, "phishing_bank");
    await hits(row!.domain, 3);
    expect((await get()).body.items).toEqual([]);
  });

  it("a deleted device stops counting at once", async () => {
    await approve("bank-palsu.example", "phishing_bank");
    const ids = await hits("bank-palsu.example", 3);
    expect((await get()).body.items).toHaveLength(1);
    await admin`delete from devices where id = ${ids[0]!}`;
    expect((await get()).body.items).toEqual([]);
  });

  it("one row per category, newest first, at most 4", async () => {
    const cats = ["phishing_bank", "phishing_ewallet", "marketplace_palsu", "undian_palsu", "investasi_bodong"];
    for (const [i, cat] of cats.entries()) {
      await approve(`${cat.replace("_", "-")}.example`, cat);
      await approve(`${cat.replace("_", "-")}-2.example`, cat);
      await hits(`${cat.replace("_", "-")}.example`, 3, { createdAgo: `${10 - i} hours` });
      await hits(`${cat.replace("_", "-")}-2.example`, 1, { createdAgo: `${10 - i} hours` });
    }
    const { body } = await get();
    expect(body.items.map((x) => x.category)).toEqual(["investasi_bodong", "undian_palsu", "marketplace_palsu", "phishing_ewallet"]);
  });
});
