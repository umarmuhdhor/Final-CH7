// Owner: lead. Bridges content scripts ↔ native app (contracts/app-group-keys.md).

const NATIVE_APP_ID = "com.shoo.app"; // ignored by Safari, required by the API
const HEARTBEAT_INTERVAL_MS = 60 * 1000;
let lastHeartbeatAt = 0;

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
        default:
            return Promise.resolve({ ok: false, error: "unknown_type" });
    }
});
