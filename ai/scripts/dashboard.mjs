// Client for the admin dashboard (`shoo-admin`) API, shared by the 05b learning scripts (calibration-report, build-cases,
// lessons, eval/tools/import-dashboard). Auth is a Cloudflare Access service token: export:read for the exports,
// ai:write for POST /api/ai/*. The token is never printed; a failed call reports its HTTP status, not its body.
//
//   SHOO_ADMIN_URL=https://shoo-admin.<account>.workers.dev  CF_ACCESS_CLIENT_ID=…  CF_ACCESS_CLIENT_SECRET=…

const TIMEOUT_MS = 30_000;
const MAX_BYTES = 32 * 1024 * 1024;
/** intel.jsonl pages hold 1000 rows; a loop past this many pages is a broken cursor, not a big dataset. */
const MAX_PAGES = 100;

/** JSON.parse with an error that never quotes the input (node puts a slice of it in the message; logs are public). */
export function parseJson(text, what) {
    try {
        return JSON.parse(text);
    } catch {
        throw new Error(`${what}: invalid JSON`);
    }
}

/** Only an https workers.dev URL with no path, user, port or query: the token goes to this host. */
export function adminUrl(raw) {
    let u;
    try {
        u = new URL(String(raw ?? ""));
    } catch {
        return null;
    }
    if (u.protocol !== "https:" || u.username || u.password || u.port || u.search || u.hash) return null;
    if (u.pathname !== "/" || !/^[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev$/.test(u.hostname)) return null;
    return u.origin;
}

/** Reads the three variables; throws with the names (never the values) of what is missing or wrong. */
export function dashboardFromEnv(env = process.env, { fetch: http = fetch } = {}) {
    const missing = ["SHOO_ADMIN_URL", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET"].filter((k) => !env[k]);
    if (missing.length) throw new Error(`missing ${missing.join(", ")}`);
    const baseUrl = adminUrl(env.SHOO_ADMIN_URL);
    if (!baseUrl) throw new Error("SHOO_ADMIN_URL must be https://<name>.<account>.workers.dev");
    return createDashboard({ baseUrl, clientId: env.CF_ACCESS_CLIENT_ID, clientSecret: env.CF_ACCESS_CLIENT_SECRET, fetch: http });
}

/**
 * @param {{ baseUrl: string, clientId: string, clientSecret: string, fetch?: typeof fetch }} opts
 */
export function createDashboard({ baseUrl, clientId, clientSecret, fetch: http = fetch }) {
    const auth = { "cf-access-client-id": clientId, "cf-access-client-secret": clientSecret };
    async function call(path, init = {}) {
        // Access answers a bad token with a redirect to its login page: never follow it with the token.
        const url = new URL(path, baseUrl);
        const where = url.pathname; // messages never carry the query: an intel cursor is a domain
        const res = await http(url, { ...init, headers: { ...auth, ...init.headers }, redirect: "manual", signal: AbortSignal.timeout(TIMEOUT_MS) });
        if (!res.ok) throw new Error(`${init.method ?? "GET"} ${where} failed: HTTP ${res.status}`);
        if (Number(res.headers.get("content-length")) > MAX_BYTES) throw new Error(`${where}: answer larger than ${MAX_BYTES} bytes`);
        const text = await res.text();
        if (text.length > MAX_BYTES) throw new Error(`${where}: answer larger than ${MAX_BYTES} bytes`);
        return { text, headers: res.headers };
    }
    return {
        async getJson(path) {
            return parseJson((await call(path)).text, new URL(path, baseUrl).pathname);
        },
        /** Every row of a JSONL export, following X-Next-Cursor (dashboard 02b K4). */
        async getJsonl(path, params = {}) {
            const rows = [];
            let cursor = null;
            for (let page = 0; page < MAX_PAGES; page++) {
                const q = new URLSearchParams({ ...params, ...(cursor ? { cursor } : {}) });
                const { text, headers } = await call(`${path}${q.size ? `?${q}` : ""}`);
                for (const line of text.split("\n")) if (line.trim()) rows.push(parseJson(line, path));
                cursor = headers.get("x-next-cursor");
                if (!cursor) return rows;
            }
            throw new Error(`${path}: more than ${MAX_PAGES} pages`);
        },
        async postJson(path, body) {
            return parseJson((await call(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) })).text || "null", new URL(path, baseUrl).pathname);
        },
    };
}
