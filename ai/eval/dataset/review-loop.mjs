#!/usr/bin/env node
// Local stand-in for the dashboard cron (layer 5, plan fase-09 task 4):
//   admin.review_due(25) -> POST /review -> admin.review_record(...)
// against the LOCAL database and a LOCAL dev server only.
//
//   node eval/dataset/review-loop.mjs [--mock-llm]
//
// --mock-llm starts `src/dev-server.mjs` itself with REVIEW_MOCK=1 and a throw-away secret (no provider, no cost).
// Without it the loop uses a running dev server: REVIEW_URL (default http://127.0.0.1:8787/review) and AI_REVIEW_SECRET
// (env or ai/.env); that server needs the real LLM_* settings. Prints `stored N` per batch, then latency and the queue.
import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";

const AI_DIR = fileURLToPath(new URL("../../", import.meta.url));
const ACTOR = "imelda-dummy";
const BATCH = 25;
const MAX_BATCHES = 4;
const LOCAL_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"]);

/** Throws unless the URL points at this machine (the database password and the review secret must not travel further). */
export function assertLocalUrl(raw, what) {
    let host;
    try {
        host = new URL(raw).hostname;
    } catch {
        throw new Error(`refusing: ${what} is not a valid URL`);
    }
    if (!LOCAL_HOSTS.has(host) || /[?&]host(addr)?=/.test(raw)) throw new Error(`refusing: ${what} is not local (host: ${host})`);
}

/** POST /review answer + the rows it was asked about -> the objects admin.review_record() stores. */
export function toRecords(rows, response) {
    const results = response?.results;
    if (!Array.isArray(results) || results.length !== rows.length) throw new Error("/review answered a different number of results than domains");
    return rows.map((row, i) => {
        const r = results[i];
        if (r?.index !== i) throw new Error(`/review result ${i} has index ${r?.index}`);
        return { domain: row.domain, input: row.input, result: r.result, confidence: r.confidence, reason: r.reason, suggestion: r.suggestion };
    });
}

function psqlBin() {
    const found = spawnSync("which", ["psql"], { encoding: "utf8" }).stdout.trim();
    const bin = found || "/opt/homebrew/opt/libpq/bin/psql";
    if (!existsSync(bin)) throw new Error("psql not found (brew install libpq)");
    return bin;
}

function makeDb(url) {
    assertLocalUrl(url, "DB_URL");
    const bin = psqlBin();
    return function sql(text, vars = {}) {
        const args = [url, "-v", "ON_ERROR_STOP=1", "-At", "-q", ...Object.entries(vars).flatMap(([k, v]) => ["-v", `${k}=${v}`]), "-f", "-"];
        const r = spawnSync(bin, args, { input: text, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
        if (r.status !== 0) throw new Error(`psql failed: ${r.stderr.trim().split("\n")[0]}`);
        return r.stdout.trim();
    };
}

const freePort = () =>
    new Promise((resolve, reject) => {
        const srv = createServer();
        srv.once("error", reject);
        srv.listen(0, "127.0.0.1", () => {
            const { port } = srv.address(); // read before close(): the address is gone afterwards
            srv.close(() => resolve(port));
        });
    });

async function waitUntilUp(url, tries = 50) {
    for (let i = 0; i < tries; i++) {
        try {
            await fetch(url, { method: "GET" }); // any answer (404 without a secret, 405 with one) means the server is up
            return;
        } catch {
            await new Promise((r) => setTimeout(r, 100));
        }
    }
    throw new Error("dev server did not start");
}

async function main() {
    const mock = process.argv.includes("--mock-llm");
    const sql = makeDb(process.env.DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres");
    let server = null;
    let url;
    let secret;
    if (mock) {
        const port = await freePort();
        secret = `local-${randomBytes(12).toString("hex")}`;
        url = `http://127.0.0.1:${port}/review`;
        server = spawn(process.execPath, ["src/dev-server.mjs"], {
            cwd: AI_DIR,
            env: { ...process.env, PORT: String(port), REVIEW_MOCK: "1", AI_REVIEW_SECRET: secret, REVIEW_DAILY_CAP: "100" },
            stdio: "ignore",
        });
    } else {
        try {
            process.loadEnvFile(new URL("../../.env", import.meta.url));
        } catch (error) {
            if (error?.code !== "ENOENT") throw error;
        }
        url = process.env.REVIEW_URL ?? "http://127.0.0.1:8787/review";
        secret = process.env.AI_REVIEW_SECRET;
        if (!secret) throw new Error("AI_REVIEW_SECRET is not set (env or ai/.env)");
    }
    try {
        assertLocalUrl(url, "REVIEW_URL");
        await waitUntilUp(url);
        let total = 0;
        for (let batch = 0; batch < MAX_BATCHES; batch++) {
            const rows = JSON.parse(sql(`select coalesce(json_agg(json_build_object('domain', domain, 'input', input)), '[]') from admin.review_due(${BATCH});`));
            if (rows.length === 0) break;
            const t0 = performance.now();
            const res = await fetch(url, {
                method: "POST",
                headers: { "content-type": "application/json", authorization: `Bearer ${secret}` },
                body: JSON.stringify({ domains: rows.map((r) => r.input) }),
            });
            const ms = Math.round(performance.now() - t0);
            if (!res.ok) throw new Error(`/review answered ${res.status}`);
            const body = await res.json();
            const records = toRecords(rows, body);
            const stored = Number(
                sql("select admin.review_record(:'results'::jsonb, :'model', :'prompt', :'actor');", {
                    results: JSON.stringify(records),
                    model: body.model,
                    prompt: body.prompt,
                    actor: ACTOR,
                }),
            );
            total += stored;
            const nulls = records.filter((r) => r.result === null).length;
            console.log(`stored ${stored} (asked ${rows.length}, model ${body.model}, ${ms} ms, ${nulls} failed)`);
        }
        if (total === 0) console.log("stored 0");
        const reviewed = sql("select count(*) from admin.v_review_queue where review_result is not null;");
        console.log(`v_review_queue rows with review_result: ${reviewed}`);
    } finally {
        server?.kill();
    }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
    main().catch((error) => {
        console.error(error.message);
        process.exit(1);
    });
}
