// Owner: lead. Bridges content scripts ↔ native app (contracts/app-group-keys.md) and does every
// network call: content scripts run under the page's origin, so cross-origin fetches belong here.

import { PSL_RULES } from "./psl.js";
import { parseRules, registrableDomain, naiveDomain, shareableUrl } from "./domain.js";
import { captureEvidence } from "./capture.js";
import { createLists } from "./lists.js";
import { createVerdicts } from "./verdicts.js";
import { createHeartbeat } from "./heartbeat.js";
import { createLastSeen } from "./last-seen.js";

const NATIVE_APP_ID = "com.shoo.app"; // ignored by Safari, required by the API
const HEARTBEAT_INTERVAL_MS = 60 * 1000;
const SESSION_TTL_MS = 30 * 1000; // onboarding can finish while Safari is open
const ANALYZE_TIMEOUT_MS = 8 * 1000; // contracts/api.md
const SCAN_TIMEOUT_MS = 15 * 1000; // includes the screenshot upload

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
        if (!response.ok) {
            // status + Retry-After let callers tell "rate limited, retry later" (429) from a real failure.
            throw Object.assign(new Error(`HTTP ${response.status}`), {
                status: response.status,
                retryAfter: response.headers.get("Retry-After"),
            });
        }
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
            body: JSON.stringify({ snapshot: { ...snapshot, url: shareableUrl(snapshot.url) }, localSignals }),
        });
        return { ok: true, signals: Array.isArray(body?.signals) ? body.signals : [] };
    } catch (error) {
        console.warn("[Shoo] /analyze failed", error);
        return { ok: true, signals: [], skipped: "error" };
    }
}

// EX-06: GET /verdicts with a short cache; a 429 is answered from the last known verdict (verdicts.js).
const verdicts = createVerdicts({ getSession, fetchJSON: (url, init) => fetchJSON(url, init) });

// Layer 1 (docs/design/blocklist.md): download + keep the lists here, content scripts only ask match().
const lists = createLists({
    storage: browser.storage.local,
    getSession,
    fetchJSON: (url, init) => fetchJSON(url, init),
    registrableDomain: domainFor,
});
lists.refresh();
// EX-01: tells the app the extension is alive and whether it still has access to every website.
const heartbeat = createHeartbeat({
    permissions: browser.permissions,
    sendNative: (message) => browser.runtime.sendNativeMessage(NATIVE_APP_ID, message),
    intervalMs: HEARTBEAT_INTERVAL_MS,
});
// C11: the same heartbeat also tells the backend, at most once per hour (GD-03 "Not connected").
const lastSeen = createLastSeen({
    storage: browser.storage.local,
    getSession,
    fetchJSON: (url, init) => fetchJSON(url, init),
});
const beatNow = () => heartbeat.beat({ force: true }).catch(() => {});
browser.permissions?.onAdded?.addListener(beatNow);
browser.permissions?.onRemoved?.addListener(beatNow);

if (browser.alarms) {
    browser.alarms.create("shoo-lists", { periodInMinutes: 60 });
    browser.alarms.onAlarm.addListener((alarm) => {
        if (alarm.name !== "shoo-lists") return;
        lists.refresh();
        heartbeat.beat().catch(() => {}); // access can be narrowed while no page is open
        lastSeen.report();
    });
}

const reports = new Map(); // report key → Promise<backend scan id | null>

/**
 * EX-07. Replies as soon as the screenshot is taken (report.js then unblurs the page / block.js navigates);
 * the POST continues here, so it survives the page going away.
 */
async function startReport(message, sender) {
    const session = await getSession();
    if (!session?.apiBaseURL) return { ok: false, skipped: "no_api_url" }; // not onboarded → nothing leaves the phone

    let screenshotBase64 = null;
    try {
        if (sender?.tab) screenshotBase64 = await captureEvidence(sender.tab.windowId, message.evidence);
    } catch (error) {
        console.warn("[Shoo] screenshot failed, sending without it", error);
    }

    const body = {
        ...message.scan,
        ownerDeviceId: session.deviceId,
        ownerName: (session.name || "").slice(0, 20),
        ...(screenshotBase64 ? { screenshotBase64 } : {}),
    };
    const post = fetchJSON(endpoint(session.apiBaseURL, "/scans"), {
        method: "POST",
        token: session.token,
        timeoutMs: SCAN_TIMEOUT_MS,
        body: JSON.stringify(body),
    })
        .then((reply) => (typeof reply?.id === "string" ? reply.id : null))
        .catch((error) => {
            console.warn("[Shoo] POST /scans failed", error);
            return null;
        });
    reports.set(message.key, post);
    return { ok: true, screenshot: Boolean(screenshotBase64) };
}

// Content scripts run in the page's process: no message ever answers with the token or the base URLs.
browser.runtime.onMessage.addListener((message, sender) => {
    switch (message?.type) {
        case "heartbeat":
            lastSeen.report();
            return heartbeat.beat();
        case "profile":
            // What blocked.html needs to pick its wording. Never the token.
            return getSession().then((s) => ({
                ok: true,
                onboarded: Boolean(s),
                mode: s?.mode ?? null,
                guardianName: s?.guardianName ?? null,
            }));
        case "listMatch":
            return lists.match(message.hostname).then((match) => ({ ok: true, match }));
        case "domain":
            return Promise.resolve({ ok: true, domain: domainFor(message.hostname) });
        case "analyze":
            return analyze(message.snapshot, message.localSignals ?? []);
        case "report":
            return startReport(message, sender);
        case "recordId":
            return Promise.resolve(reports.get(message.key) ?? null).then((recordId) => ({ ok: true, recordId }));
        case "verdict":
            return verdicts.lookup(message.domain, { fresh: Boolean(message.fresh) });
        default:
            return Promise.resolve({ ok: false, error: "unknown_type" });
    }
});
