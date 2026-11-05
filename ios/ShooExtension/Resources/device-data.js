// Owner: lead. Keeps what the extension stored tied to the device that stored it. ES module, used by
// background.js. Deleting the account in the app clears the App Group, which the extension can't see, so
// it notices at the next getSession: block memory, cached lists and the rest go with the device.

export const OWNER_KEY = "deviceData.owner"; // device id; "" once nobody is signed in

/**
 * @param {object} deps
 * @param {{get(keys): Promise<object>, set(items): Promise<void>, clear(): Promise<void>}} deps.storage  browser.storage.local
 * @param {() => void} deps.onWipe  drops what is cached in memory
 */
export function createDeviceData({ storage, onWipe }) {
    let queue = Promise.resolve(); // two pages can ask at once

    /**
     * Call with the deviceId of a getSession reply, or null on the app's `not_onboarded`, never for
     * "unreachable": a session that can't be read says nothing about the account. Never rejects.
     */
    function sync(deviceId) {
        queue = queue.then(async () => {
            const owner = (await storage.get([OWNER_KEY]))?.[OWNER_KEY];
            const now = deviceId || "";
            if (owner === now) return;
            // No owner yet: an update of the extension, the data is this device's. Unless nobody is signed in.
            const stale = owner === undefined ? !now : Boolean(owner);
            if (stale) {
                await storage.clear();
                onWipe();
            }
            await storage.set({ [OWNER_KEY]: now });
        }).catch((error) => console.warn("[Shoo] device data", error));
        return queue;
    }

    return { sync };
}
