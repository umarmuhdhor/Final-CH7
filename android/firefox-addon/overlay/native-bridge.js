// Android (Team App). Firefox for Android has no native messaging, so the Safari background.js's three
// `browser.runtime.sendNativeMessage` calls are rewritten by build.mjs to call `nativeBridge` instead.
// It answers the same messages (contracts/app-group-keys.md "Native messages") from the session the Shoo
// Android app handed over once, through options.html and a one-time code (android/.../AddonBridge.kt).

export const SESSION_KEY = "shoo.appSession";
export const STATS_KEY = "shoo.stats";
const REFRESH_MS = 60 * 60 * 1000;
const MODES = ["guardian", "protected"];

const isHttpUrl = (value) => {
    try {
        return /^https?:$/.test(new URL(value).protocol);
    } catch {
        return false;
    }
};

/** The `session` object from the app's `POST /pair` reply, cleaned; null if it isn't one. */
export function validateAppSession(value) {
    if (!value || typeof value !== "object") return null;
    if (typeof value.token !== "string" || !value.token) return null;
    if (typeof value.deviceId !== "string" || !value.deviceId) return null;
    if (!MODES.includes(value.mode)) return null;
    return {
        deviceId: value.deviceId,
        token: value.token,
        mode: value.mode,
        name: typeof value.name === "string" ? value.name.slice(0, 20) : "",
        guardianName: typeof value.guardianName === "string" ? value.guardianName : null,
        apiBaseURL: isHttpUrl(value.apiBaseURL) ? value.apiBaseURL : null,
        aiBaseURL: isHttpUrl(value.aiBaseURL) ? value.aiBaseURL : null,
        autoSend: value.autoSend !== false,
        shareWarnings: value.shareWarnings !== false,
        linkedAt: typeof value.linkedAt === "number" ? value.linkedAt : null,
        refreshedAt: typeof value.refreshedAt === "number" ? value.refreshedAt : 0,
    };
}

/**
 * @param {{ get(key): Promise<object>, set(items): Promise<void>, remove(key): Promise<void> }} storage
 * @returns {(message: object) => Promise<object>} answers getSession, heartbeat, pageChecked
 */
export function createNativeBridge({ storage, fetchImpl = (...args) => fetch(...args), now = () => Date.now() }) {
    async function stored() {
        try {
            return validateAppSession((await storage.get(SESSION_KEY))?.[SESSION_KEY]);
        } catch {
            return null;
        }
    }

    // Name, mode and Guardian change on the server (a Protected person disconnected, a rename): GET /devices/me
    // at most hourly keeps "Link sent to …" right. 401 = the device was deleted → the add-on forgets the session.
    async function refreshed(session) {
        if (!session.apiBaseURL || now() - session.refreshedAt < REFRESH_MS) return session;
        try {
            const response = await fetchImpl(session.apiBaseURL.replace(/\/+$/, "") + "/devices/me", {
                headers: { Authorization: `Bearer ${session.token}` },
            });
            if (response.status === 401) {
                await storage.remove(SESSION_KEY);
                return null;
            }
            if (!response.ok) return session;
            const me = await response.json();
            const next = {
                ...session,
                name: typeof me?.name === "string" ? me.name : session.name,
                mode: MODES.includes(me?.mode) ? me.mode : session.mode,
                guardianName: typeof me?.guardian?.name === "string" ? me.guardian.name : null,
                refreshedAt: now(),
            };
            await storage.set({ [SESSION_KEY]: next });
            return next;
        } catch {
            return session; // offline: keep what we have
        }
    }

    return async function nativeBridge(message) {
        switch (message?.type) {
            case "getSession": {
                const current = await stored();
                const session = current && (await refreshed(current));
                if (!session) return { ok: false, error: "not_onboarded" };
                const { deviceId, token, mode, name, guardianName, apiBaseURL, aiBaseURL, autoSend, shareWarnings } = session;
                return { ok: true, deviceId, token, mode, name, guardianName, apiBaseURL, aiBaseURL, autoSend, shareWarnings };
            }
            case "heartbeat":
                // The app can't read add-on storage; the backend learns we're alive through last-seen.js instead.
                return { ok: true };
            case "pageChecked": {
                // A count only, never an address (PF-01).
                const stats = (await storage.get(STATS_KEY))?.[STATS_KEY] ?? {};
                const checked = Number.isInteger(stats.checked) ? stats.checked + 1 : 1;
                await storage.set({ [STATS_KEY]: { checked, lastCheckedAt: new Date(now()).toISOString() } });
                return { ok: true };
            }
            default:
                return { ok: false, error: "unknown_type" };
        }
    };
}

export const nativeBridge = globalThis.browser?.storage ? createNativeBridge({ storage: globalThis.browser.storage.local }) : null;
