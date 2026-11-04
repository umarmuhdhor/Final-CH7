// Server tes untuk ekstensi di simulator: createApp dari ai/src tanpa perubahan, blocklist kosong (L1 mati), port 8790.
// Mencatat bobot sinyal dan waktu per panggilan /analyze ke <versi>/.raw/calls.jsonl.
// Tidak mencatat teks halaman, evidence, header Authorization, atau isi ai/.env.
//   SHOO_RDAP=1 node ai/test-layer-live/scripts/server.mjs [v1]
import { AsyncLocalStorage } from "node:async_hooks";
import { appendFileSync, mkdirSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { Readable } from "node:stream";
import { fileURLToPath } from "node:url";
import { createApp } from "../../src/app.js";
import { parseVerdict } from "../../src/layer4/schema.js";

const here = dirname(fileURLToPath(import.meta.url));
const version = process.argv[2] || "v1";
const rawDir = join(here, "..", version, ".raw");
mkdirSync(rawDir, { recursive: true });
const logFile = join(rawDir, "calls.jsonl");

process.loadEnvFile(join(here, "..", "..", ".env"));
const llmEnv = Object.fromEntries(Object.entries(process.env).filter(([k]) => k.startsWith("LLM_")));
if (process.env.SHOO_RDAP !== "1") throw new Error("SHOO_RDAP=1 wajib: RDAP harus live");

const scope = new AsyncLocalStorage();
let currentId = null;

async function timedLlm(...args) {
    const call = scope.getStore();
    const started = performance.now();
    const entry = { ms: null, status: null, usage: null, verdict: null };
    call?.llm.push(entry);
    try {
        const res = await fetch(...args);
        const body = await res.clone().json().catch(() => null);
        entry.ms = Math.round(performance.now() - started);
        entry.status = res.status;
        entry.usage = body?.usage ?? null;
        const verdict = parseVerdict(body?.choices?.[0]?.message?.content ?? "");
        // Tanpa evidence: itu teks yang disalin dari halaman.
        if (verdict) entry.verdict = { page_type: verdict.pageType, asks: verdict.asks, reasonable: verdict.reasonable, confidence: verdict.confidence };
        return res;
    } catch (error) {
        entry.ms = Math.round(performance.now() - started);
        entry.status = error?.name || "error";
        throw error;
    }
}

async function timedRdap(...args) {
    const call = scope.getStore();
    const started = performance.now();
    try {
        return await fetch(...args);
    } finally {
        if (call) call.rdapMs += Math.round(performance.now() - started);
    }
}

const NO_LIMIT = { limit: Number.MAX_SAFE_INTEGER, windowMs: 60_000 };
const app = createApp({
    rateLimit: NO_LIMIT,
    analyzeRateLimit: NO_LIMIT,
    llmFetch: timedLlm,
    llmClientCallsPerHour: Infinity,
    fetch: timedRdap,
});

const brief = (signals) => (Array.isArray(signals) ? signals.map((s) => ({ id: s?.id, layer: s?.layer, weight: s?.weight })) : []);

async function analyzeLogged(request) {
    const sent = await request.clone().json().catch(() => null);
    const call = { llm: [], rdapMs: 0 };
    const started = performance.now();
    const response = await scope.run(call, () => app.fetch(request, llmEnv));
    const reply = await response.clone().json().catch(() => null);
    let host = null;
    try {
        host = new URL(sent?.snapshot?.url).hostname;
    } catch {}
    appendFileSync(logFile, JSON.stringify({
        id: currentId,
        at: new Date().toISOString(),
        host,
        status: response.status,
        localSignals: brief(sent?.localSignals),
        signals: brief(reply?.signals),
        analyzeMs: Math.round(performance.now() - started),
        rdapMs: call.rdapMs,
        llm: call.llm,
    }) + "\n");
    return response;
}

const port = 8790; // 8788 dan 8789 dipakai proxy lama dari sesi lain
createServer(async (req, res) => {
    try {
        const url = new URL(req.url, "http://localhost");
        if (url.pathname === "/_test/mark") {
            currentId = url.searchParams.get("id");
            res.writeHead(204);
            res.end();
            return;
        }
        const hasBody = req.method !== "GET" && req.method !== "HEAD";
        const request = new Request(`http://localhost${req.url}`, {
            method: req.method,
            headers: req.headers,
            body: hasBody ? Readable.toWeb(req) : undefined,
            duplex: "half",
        });
        const response = url.pathname === "/analyze" && req.method === "POST" ? await analyzeLogged(request) : await app.fetch(request, llmEnv);
        res.writeHead(response.status, Object.fromEntries(response.headers));
        res.end(Buffer.from(await response.arrayBuffer()));
    } catch {
        res.writeHead(500, { "content-type": "application/json" });
        res.end('{"error":{"code":"internal","message":"Something went wrong."}}');
    }
}).listen(port, "127.0.0.1", () => process.stdout.write(`server tes ${version} di http://127.0.0.1:${port}\n`));
