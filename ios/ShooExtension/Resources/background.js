// Owner: lead. Bridges content scripts ↔ native app (contracts/app-group-keys.md) and does every
// network call: content scripts run under the page's origin, so cross-origin fetches belong here.

import { PSL_RULES } from "./psl.js";
import { parseRules, registrableDomain, naiveDomain, shareableUrl } from "./domain.js";
import { buildFragments, buildReplica, webIO } from "./replica-build.js";
import { createLists } from "./lists.js";
import { createVerdicts } from "./verdicts.js";
import { createHeartbeat } from "./heartbeat.js";
import { createLastSeen } from "./last-seen.js";
import { createBlockMemory } from "./block-memory.js";
import { createDeviceData } from "./device-data.js";
import { createReportLog } from "./report-log.js";
import { mayReport } from "./share-settings.js";
import { createThresholds } from "./thresholds.js";
import { createLive } from "./live.js";

const NATIVE_APP_ID = "com.shoo.app"; // ignored by Safari, required by the API
const HEARTBEAT_INTERVAL_MS = 60 * 1000;
const SESSION_TTL_MS = 30 * 1000; // onboarding can finish while Safari is open
const SESSION_WAIT_MS = 1000;
const ANALYZE_TIMEOUT_MS = 8 * 1000; // contracts/api.md
const SCAN_TIMEOUT_MS = 15 * 1000; // includes the page replica upload
const LIVE_TIMEOUT_MS = 5 * 1000; // a late live score is useless (EX-03)

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

// A deleted account leaves nothing behind here either: what is stored belongs to the device that stored it.
const deviceData = createDeviceData({
    storage: browser.storage.local,
    onWipe: () => {
        lists.reset();
        thresholds.reset();
        lastSeen.reset();
        verdicts.reset();
        reports.clear();
    },
});

let sessionCache = { value: null, at: 0 };
/** @returns {Promise<object|null>} getSession reply, or null if the app isn't onboarded / unreachable */
async function getSession() {
    if (Date.now() - sessionCache.at < SESSION_TTL_MS) return sessionCache.value;
    let reply = null;
    try {
        reply = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, { type: "getSession" });
    } catch (error) {
        console.warn("[Shoo] getSession failed", error);
    }
    const value = reply?.ok ? reply : null;
    sessionCache = { value, at: Date.now() };
    if (value) await deviceData.sync(value.deviceId);
    else if (reply?.error === "not_onboarded") await deviceData.sync(null);
    return value;
}

/** Before reading stored data for a page: a deleted account's data is gone first. Never holds a page up for long. */
const sessionSettled = () => Promise.race([getSession(), new Promise((resolve) => setTimeout(resolve, SESSION_WAIT_MS))]);

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
        return { ok: true, signals: Array.isArray(body?.signals) ? body.signals : [], rdapRegisteredAt: body?.rdapRegisteredAt ?? null };
    } catch (error) {
        console.warn("[Shoo] /analyze failed", error);
        return { ok: true, signals: [], skipped: "error" };
    }
}

// EX-06: GET /verdicts with a short cache; a 429 is answered from the last known verdict (verdicts.js).
const verdicts = createVerdicts({ getSession, fetchJSON: (url, init) => fetchJSON(url, init) });
// #231: sites blocked on this phone stay blocked without /analyze until a `safe` verdict clears them.
const blockMemory = createBlockMemory({ storage: browser.storage.local, registrableDomain: domainFor });

/** GET /verdicts; a `safe` verdict also clears the block memory of that domain before anyone reopens it. */
async function lookupVerdict(domain, fresh) {
    const reply = await verdicts.lookup(domain, { fresh });
    if (reply?.verdict?.value === "safe") await blockMemory.forgetDomain(domain);
    return reply;
}

/** Remembers a blocked page now; the backend's scan id is added once POST /scans answers. */
function rememberBlock(message) {
    const saved = blockMemory.remember(message.url, { domain: message.domain, score: message.score, signals: message.signals });
    if (message.reportKey) {
        recordIdFor(message.reportKey).then((recordId) => saved.then(() => blockMemory.setRecord(message.url, recordId)));
    }
    return saved.then(() => ({ ok: true }));
}

// Layer 1 (docs/design/blocklist.md): download + keep the lists here, content scripts only ask match().
const lists = createLists({
    storage: browser.storage.local,
    getSession,
    fetchJSON: (url, init) => fetchJSON(url, init),
    registrableDomain: domainFor,
});
lists.refresh();
// Dashboard 05b X1: score thresholds from GET /config/public; content scripts get numbers only.
const thresholds = createThresholds({
    storage: browser.storage.local,
    getSession,
    fetchJSON: (url, init) => fetchJSON(url, init),
});
thresholds.refresh();
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
        thresholds.refresh();
        heartbeat.beat().catch(() => {}); // access can be narrowed while no page is open
        lastSeen.report();
    });
}

const reports = new Map(); // report key → Promise<backend scan id | null>
const reportLog = createReportLog({ storage: browser.storage.local });
/** The Map dies with this page; the log answers for a report sent before that. */
const recordIdFor = (key) => Promise.resolve(reports.has(key) ? reports.get(key) : reportLog.recordId(key));

/**
 * EX-07. Replies at once (block.js navigates as soon as we have the message); the page replica is
 * finished and the POST runs here, so both survive the page going away.
 */
async function startReport(message) {
    const session = await getSession();
    if (!session?.apiBaseURL) return { ok: false, skipped: "no_api_url" }; // not onboarded → nothing leaves the phone
    if (!mayReport(message.scan?.status, session)) return { ok: false, skipped: "sharing_off" };

    // X1: a 422 on a scan that carries thresholdsVersion means the status and that version disagree
    // (thresholds changed while the page was being scored). Sent again without it, only the fence
    // applies; the scan matters more than the check.
    const { thresholdsVersion, ...scan } = message.scan ?? {};
    const post1 = (body) =>
        fetchJSON(endpoint(session.apiBaseURL, "/scans"), { method: "POST", token: session.token, timeoutMs: SCAN_TIMEOUT_MS, body });
    const send = (pageReplicaBase64, evidenceFragmentsBase64) => {
        const body = (version) => JSON.stringify({
            ...scan,
            ...(Number.isInteger(version) ? { thresholdsVersion: version } : {}),
            ownerDeviceId: session.deviceId,
            ownerName: (session.name || "").slice(0, 20),
            ...(pageReplicaBase64 ? { pageReplicaBase64 } : {}),
            ...(evidenceFragmentsBase64 ? { evidenceFragmentsBase64 } : {}),
        });
        return post1(body(thresholdsVersion)).catch((error) =>
            Number.isInteger(thresholdsVersion) && error.status === 422 ? post1(body(undefined)) : Promise.reject(error));
    };
    const io = webIO();
    const built = (build, what) =>
        build().catch((error) => {
            console.warn(`[Shoo] ${what} failed, sending without it`, error);
            return null;
        });
    // ADM-07: the fragments go with every report; the replica as before. Both reuse the page's cached files.
    // POST /scans keeps the first visit's evidence, so a site reported lately doesn't send it again.
    const evidence = (await reportLog.sentRecently(scan.domain))
        ? [null, null]
        : [built(() => buildReplica(message.replica, io), "page replica"), built(() => buildFragments(message.fragments, io), "evidence fragments")];
    const post = Promise.all(evidence)
        // 413: the backend's body limit is lower (older backend) — drop the fragments, then the replica; the scan matters more.
        .then(([replica, parts]) =>
            send(replica, parts)
                .catch((error) => (parts && error.status === 413 ? send(replica, null) : Promise.reject(error)))
                .catch((error) => (replica && error.status === 413 ? send(null, null) : Promise.reject(error))))
        .then(async (reply) => {
            const id = typeof reply?.id === "string" ? reply.id : null;
            await reportLog.markSent(scan.domain);
            if (id) await reportLog.saveRecord(message.key, id);
            return id;
        })
        .catch((error) => {
            console.warn("[Shoo] POST /scans failed", error);
            return null;
        });
    reports.set(message.key, post);
    return { ok: true };
}

// EX-03 path C (#49): running score → POST /live → Dynamic Island. Coalescing and the online-check rule
// live in live.js; the backend forwards domain + score to APNs and stores neither.
const live = createLive({
    getSession,
    post: (session, body) =>
        fetchJSON(endpoint(session.apiBaseURL, "/live"), {
            method: "POST",
            token: session.token,
            timeoutMs: LIVE_TIMEOUT_MS,
            body: JSON.stringify(body),
        }),
});

// Content scripts run in the page's process: no message ever answers with the token or the base URLs.
browser.runtime.onMessage.addListener((message) => {
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
            return sessionSettled().then(() => lists.match(message.hostname)).then((match) => ({ ok: true, match }));
        case "thresholds":
            return thresholds.current().then((t) => ({ ok: true, thresholds: t }));
        case "domain":
            return Promise.resolve({ ok: true, domain: domainFor(message.hostname) });
        case "analyze":
            return analyze(message.snapshot, message.localSignals ?? []);
        case "report":
            return startReport(message);
        case "recordId":
            return recordIdFor(message.key).then((recordId) => ({ ok: true, recordId }));
        case "verdict":
            return lookupVerdict(message.domain, Boolean(message.fresh));
        case "pageChecked":
            // A count for the app, no address (PF-01). Nothing depends on it, so a failure stays here.
            return browser.runtime.sendNativeMessage(NATIVE_APP_ID, { type: "pageChecked" }).catch(() => ({ ok: false }));
        case "liveScore":
            return message.open === false
                ? live.hide()
                : live.show({
                      domain: domainFor(String(message.hostname ?? "")),
                      score: message.score,
                      status: message.status,
                      analyzing: message.analyzing,
                  });
        case "recallBlock":
            return sessionSettled().then(() => blockMemory.recall(message.url)).then((memory) => ({ ok: true, memory }));
        case "rememberBlock":
            return rememberBlock(message);
        default:
            return Promise.resolve({ ok: false, error: "unknown_type" });
    }
});
