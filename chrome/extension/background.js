// Owner: lead. Chrome MV3 service worker. Same job as the Safari background.js minus the native app:
// answers the content scripts and does every network call (content scripts run under the page's origin).
// Server calls only happen with a session, and Chrome has none unless a developer sets one (session.js).
// A service worker stops when idle: nothing here may rely on memory surviving; listeners register at top level.

import { PSL_RULES } from "./psl.js";
import { parseRules, registrableDomain, naiveDomain, shareableUrl } from "./domain.js";
import { createLists } from "./lists.js";
import { createVerdicts } from "./verdicts.js";
import { createSession } from "./session.js";
import { createRouter } from "./router.js";
import { listen } from "./messaging.js";

const ANALYZE_TIMEOUT_MS = 8 * 1000; // contracts/api.md
const LISTS_ALARM = "shoo-lists";

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

const getSession = createSession({ storage: chrome.storage.local });

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

/** Layer 3–4. Never rejects: no session, server down or slow → no signals (PRD §5). */
async function analyze(snapshot, localSignals) {
    const session = await getSession();
    if (!session?.aiBaseURL) return { ok: true, signals: [], skipped: "no_ai_url" };
    try {
        const body = await fetchJSON(session.aiBaseURL.replace(/\/+$/, "") + "/analyze", {
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

const verdicts = createVerdicts({ getSession, fetchJSON });
const lists = createLists({ storage: chrome.storage.local, getSession, fetchJSON, registrableDomain: domainFor });

listen(chrome.runtime.onMessage, createRouter({ getSession, lists, verdicts, domainFor, analyze }));

// create() replaces an alarm of the same name and restarts its period, and this file runs on every wake-up.
chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === LISTS_ALARM) lists.refresh();
});
chrome.alarms.get(LISTS_ALARM).then((alarm) => {
    if (!alarm) chrome.alarms.create(LISTS_ALARM, { periodInMinutes: 60 });
});
lists.refresh();
