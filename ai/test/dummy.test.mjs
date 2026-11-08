import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { buildDummySql } from "../eval/dataset/dummy.mjs";

const SCRIPT = new URL("../eval/dataset/seed-dummy.sh", import.meta.url).pathname;

test("buildDummySql is deterministic per seed", () => {
    assert.equal(buildDummySql({ seed: 1 }), buildDummySql({ seed: 1 }));
    assert.notEqual(buildDummySql({ seed: 1 }), buildDummySql({ seed: 2 }));
});

test("dummy scans only use *.shoo-dummy.test domains and the one shared host", () => {
    const sql = buildDummySql({ seed: 7 });
    const domains = [...sql.matchAll(/insert into public\.scans \(.*?\) values \('[^']+', '[^']+', '[^']+', '([^']+)'/g)].map((m) => m[1]);
    assert.ok(domains.length >= 35, `scans: ${domains.length}`);
    for (const d of domains) assert.ok(d.endsWith(".shoo-dummy.test") || d === "sites.google.com", d);
    assert.ok(domains.includes("sites.google.com"));
});

test("dummy sql is one transaction and ends by analysing", () => {
    const sql = buildDummySql({});
    assert.match(sql, /^-- Generated[^\n]*\nbegin;\n/);
    assert.match(sql, /select admin\.run_analysis\('manual', 'imelda-dummy'\);\nalter role shoo_ai password 'shoo_ai_local';\ncommit;\n$/);
});

for (const [name, env] of [
    ["cloud DB_URL", { DB_URL: "postgresql://postgres:secret@db.abcdefgh.supabase.co:5432/postgres" }],
    ["cloud AI_DB_URL", { AI_DB_URL: "postgresql://shoo_ai:secret@db.abcdefgh.supabase.co:5432/postgres" }],
    ["host override in the query string", { DB_URL: "postgresql://postgres:postgres@127.0.0.1:54322/postgres?host=db.abcdefgh.supabase.co" }],
]) {
    test(`seed-dummy.sh refuses ${name} before any query`, () => {
        // PATH has no psql and no node here: if the guard did not stop the script first, it would fail differently.
        const r = spawnSync("/bin/bash", [SCRIPT], { env: { PATH: "/usr/bin:/bin", ...env }, encoding: "utf8" });
        assert.equal(r.status, 1);
        assert.match(r.stderr, /refusing: not a local database/);
    });
}
