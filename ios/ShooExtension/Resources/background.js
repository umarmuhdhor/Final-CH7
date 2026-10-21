// Owner: lead. Bridges content scripts ↔ native app (contracts/app-group-keys.md) and does every
// network call: content scripts run under the page's origin, so cross-origin fetches belong here.

import { PSL_RULES } from "./psl.js";
import { parseRules, registrableDomain, naiveDomain } from "./domain.js";

const NATIVE_APP_ID = "com.shoo.app"; // ignored by Safari, required by the API
const HEARTBEAT_INTERVAL_MS = 60 * 1000;
const SESSION_TTL_MS = 30 * 1000; // onboarding can finish while Safari is open
const VERDICT_TTL_MS = 60 * 1000;
const ANALYZE_TIMEOUT_MS = 8 * 1000; // contracts/api.md
const VERDICT_TIMEOUT_MS = 3 * 1000;

let lastHeartbeatAt = 0;

let rules = null;
function domainFor(hostname) {
    try {
        rules ??= parseRules(PSL_RULES);
        return registrableDomain(hostname, rules);
    } catch (error) {
        console.warn("[Shoo] PSL failed, using naive domain", error);
        return naiveDomain(hostname);
    }
}

let sessionCache = { value: null, at: 0 };
/** @returns {Promise<object|null>} getSession reply, or null if the app isn't onboarded / unreachable */
async function getSession() {
    if (Date.now() - sessionCache.at < SESSION_TTL_MS) return sessionCache.value;
    let value = null;
    try {
        const reply = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, { type: "getSession" });
        value = reply?.ok ? reply : null;
    } catch (error) {
        console.warn("[Shoo] getSession failed", error);
    }
    sessionCache = { value, at: Date.now() };
    return value;
}

async function fetchJSON(url, { timeoutMs, token, ...init }) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const response = await fetch(url, {
            ...init,
            signal: controller.signal,
            headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return await response.json();
    } finally {
        clearTimeout(timer);
    }
}

function endpoint(base, path) {
    return base.replace(/\/+$/, "") + path;
}

/** Layer 3–4. Never rejects: server down or slow → no signals (PRD §5). */
async function analyze(snapshot, localSignals) {
    const session = await getSession();
    if (!session?.aiBaseURL) return { ok: true, signals: [], skipped: "no_ai_url" };
    try {
        const body = await fetchJSON(endpoint(session.aiBaseURL, "/analyze"), {
            method: "POST",
            token: session.token,
            timeoutMs: ANALYZE_TIMEOUT_MS,
            body: JSON.stringify({ snapshot, localSignals }),
        });
        return { ok: true, signals: Array.isArray(body?.signals) ? body.signals : [] };
    } catch (error) {
        console.warn("[Shoo] /analyze failed", error);
        return { ok: true, signals: [], skipped: "error" };
    }
}

const verdictCache = new Map(); // domain → { verdict, at }
async function verdict(domain, { fresh = false } = {}) {
    const cached = verdictCache.get(domain);
    if (!fresh && cached && Date.now() - cached.at < VERDICT_TTL_MS) return { ok: true, verdict: cached.verdict };

    const session = await getSession();
    if (!session?.apiBaseURL) return { ok: true, verdict: null, skipped: "no_api_url" };
    try {
        const body = await fetchJSON(endpoint(session.apiBaseURL, `/verdicts?domain=${encodeURIComponent(domain)}`), {
            method: "GET",
            token: session.token,
            timeoutMs: VERDICT_TIMEOUT_MS,
        });
        const value = body?.verdict ?? null;
        verdictCache.set(domain, { verdict: value, at: Date.now() });
        return { ok: true, verdict: value };
    } catch (error) {
        console.warn("[Shoo] /verdicts failed", error);
        return { ok: true, verdict: null, skipped: "error" };
    }
}

browser.runtime.onMessage.addListener((message) => {
    switch (message?.type) {
        case "heartbeat": {
            if (Date.now() - lastHeartbeatAt < HEARTBEAT_INTERVAL_MS) {
                return Promise.resolve({ ok: true, throttled: true });
            }
            lastHeartbeatAt = Date.now();
            return browser.runtime.sendNativeMessage(NATIVE_APP_ID, { type: "heartbeat" });
        }
        case "getSession":
            return browser.runtime.sendNativeMessage(NATIVE_APP_ID, { type: "getSession" });
        case "domain":
            return Promise.resolve({ ok: true, domain: domainFor(message.hostname) });
        case "analyze":
            return analyze(message.snapshot, message.localSignals ?? []);
        case "verdict":
            return verdict(message.domain, { fresh: Boolean(message.fresh) });
        default:
            return Promise.resolve({ ok: false, error: "unknown_type" });
    }
});
