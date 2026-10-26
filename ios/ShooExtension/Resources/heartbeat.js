// Owner: lead. Heartbeat to the app (EX-01, ON-04, PR-04, GD-01). ES module, used by background.js.
// A heartbeat alone only proves the content script ran on *some* site. If the user narrows Safari's
// access from "All websites" to a few sites, it keeps arriving from those sites, so it also carries
// `allSites`: whether the extension still has access to every website (contracts/app-group-keys.md).
// Asked as every http(s) host, not `<all_urls>`: Safari's "Allow" on every website grants `*://*/*`,
// and WebKit never lets that grant cover a `<all_urls>` query (WebExtensionMatchPattern::matchesPattern),
// so `<all_urls>` read false with full access. A `<all_urls>` grant still covers `*://*/*`.

const ALL_HOSTS = { origins: ["*://*/*"] };

/**
 * @param {object} deps
 * @param {object|undefined} deps.permissions  `browser.permissions` (may be missing)
 * @param {(message: object) => Promise<object>} deps.sendNative  sendNativeMessage to the app
 */
export function createHeartbeat({ permissions, sendNative, intervalMs, now = () => Date.now() }) {
    let lastAt = -Infinity;

    /** true / false, or undefined when the API isn't there or fails (the app then keeps its old rule). */
    async function allSites() {
        if (typeof permissions?.contains !== "function") return undefined;
        try {
            return Boolean(await permissions.contains(ALL_HOSTS));
        } catch (error) {
            console.warn("[Shoo] permissions.contains failed", error);
            return undefined;
        }
    }

    /** Throttled to one per `intervalMs`; `force` (a permission just changed) skips the throttle. */
    async function beat({ force = false } = {}) {
        if (!force && now() - lastAt < intervalMs) return { ok: true, throttled: true };
        lastAt = now();
        const granted = await allSites();
        return sendNative(granted === undefined ? { type: "heartbeat" } : { type: "heartbeat", allSites: granted });
    }

    return { beat };
}
