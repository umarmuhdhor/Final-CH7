// Owner: lead. Chrome only. ES module, used by background.js. The seam to the Shoo servers.
// On iPhone the session (device token, base URLs, mode) comes from the Shoo app over native messaging
// (contracts/app-group-keys.md "getSession"). Chrome has no Shoo app to pair with, so by default there is
// no session: layer 1–2 run on the device and nothing is sent anywhere (no /analyze, /verdicts, lists).
// For development only, a session can be put in chrome.storage.local under DEV_SESSION_KEY (README):
// the same shape as the getSession reply, so lists.js / verdicts.js / analyze work unchanged.

export const DEV_SESSION_KEY = "shoo.devSession";
const MODES = ["guardian", "protected"];

const isUrl = (value) => {
    try {
        return /^https?:$/.test(new URL(value).protocol);
    } catch {
        return false;
    }
};

/** The stored dev session if it has a token and at least one base URL, else null. */
export function validSession(value) {
    if (!value || typeof value !== "object") return null;
    if (typeof value.token !== "string" || !value.token) return null;
    const apiBaseURL = isUrl(value.apiBaseURL) ? value.apiBaseURL : null;
    const aiBaseURL = isUrl(value.aiBaseURL) ? value.aiBaseURL : null;
    if (!apiBaseURL && !aiBaseURL) return null;
    return {
        ok: true,
        token: value.token,
        deviceId: typeof value.deviceId === "string" ? value.deviceId : null,
        name: typeof value.name === "string" ? value.name : "",
        mode: MODES.includes(value.mode) ? value.mode : "guardian",
        guardianName: typeof value.guardianName === "string" ? value.guardianName : null,
        apiBaseURL,
        aiBaseURL,
    };
}

/**
 * @param {{ get(keys): Promise<object> }} storage  chrome.storage.local
 * @returns {() => Promise<object|null>} getSession, never rejects
 */
export function createSession({ storage }) {
    return async function getSession() {
        try {
            const stored = await storage.get(DEV_SESSION_KEY);
            return validSession(stored?.[DEV_SESSION_KEY]);
        } catch {
            return null;
        }
    };
}
