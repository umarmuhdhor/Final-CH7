// Local development only: serves the same app over plain HTTP so `ai/eval/run.mjs --analyze-url` can reach it.
// No rate limit and no TLS here; the deployed Worker gets those in M7. Prints nothing about requests.
import { createServer } from "node:http";
import { Readable } from "node:stream";
import { createApp } from "./app.js";
import { fixtureSource } from "./blocklist/fixture.js";

// RDAP (new_domain) calls real registries, so it is off unless asked: SHOO_RDAP=1. Never point it at scam domains.
// /public-blocklist serves invented fixture domains here (ai/data/public-blocklist.seed.json), never a real feed.
// Layer 4 (LLM) stays off unless ai/.env holds LLM_API_KEY, LLM_MODEL and LLM_BASE_URL (see .env.example).
try {
    process.loadEnvFile(new URL("../.env", import.meta.url));
} catch (error) {
    if (error?.code !== "ENOENT") throw error; // a broken .env must be loud, a missing one means layer 4 off
}
const llmEnv = Object.fromEntries(Object.entries(process.env).filter(([k]) => k.startsWith("LLM_")));
const app = createApp({ blocklistSource: fixtureSource, llmFetch: (...args) => fetch(...args), ...(process.env.SHOO_RDAP === "1" ? { fetch: (...args) => fetch(...args) } : {}) });
const port = Number(process.env.PORT) || 8787;

createServer(async (req, res) => {
    try {
        const hasBody = req.method !== "GET" && req.method !== "HEAD";
        const request = new Request(`http://localhost${req.url}`, {
            method: req.method,
            headers: req.headers,
            body: hasBody ? Readable.toWeb(req) : undefined,
            duplex: "half",
        });
        const response = await app.fetch(request, llmEnv);
        res.writeHead(response.status, Object.fromEntries(response.headers));
        res.end(Buffer.from(await response.arrayBuffer()));
    } catch {
        res.writeHead(500, { "content-type": "application/json" });
        res.end('{"error":{"code":"internal","message":"Something went wrong."}}');
    }
}).listen(port, "127.0.0.1", () => process.stdout.write(`shoo-ai listening on http://127.0.0.1:${port}\n`));
