// node --test android/firefox-addon/test
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { build, firefoxManifest, patchBackground, GECKO_ID, SOURCE } from "../build.mjs";
import { createNativeBridge, validateAppSession, SESSION_KEY, STATS_KEY } from "../overlay/native-bridge.js";

function memoryStorage(initial = {}) {
    const data = { ...initial };
    return {
        data,
        get: async (key) => (key in data ? { [key]: data[key] } : {}),
        set: async (items) => Object.assign(data, items),
        remove: async (key) => void delete data[key],
    };
}

const session = {
    deviceId: "dev_1", token: "shoo_x", mode: "protected", name: "Ibu", guardianName: "Rina",
    apiBaseURL: "https://api.example", aiBaseURL: null, autoSend: true, shareWarnings: false,
};

test("manifest: gecko id, no native messaging, settings page, module background", () => {
    const safari = JSON.parse(readFileSync(join(SOURCE, "manifest.json"), "utf8"));
    const manifest = firefoxManifest(safari);
    assert.equal(manifest.browser_specific_settings.gecko.id, GECKO_ID);
    assert.ok(manifest.browser_specific_settings.gecko_android);
    assert.ok(!manifest.permissions.includes("nativeMessaging"));
    assert.deepEqual(manifest.background, { scripts: ["background.js"], type: "module" });
    assert.equal(manifest.options_ui.page, "options.html");
    assert.ok(safari.permissions.includes("nativeMessaging"), "the Safari manifest itself is untouched");
});

test("the Safari background.js still has exactly the native calls the bridge answers", () => {
    const patched = patchBackground(readFileSync(join(SOURCE, "background.js"), "utf8"));
    assert.ok(patched.startsWith('import { nativeBridge } from "./native-bridge.js";'));
    assert.ok(!patched.includes("sendNativeMessage("));
    assert.equal(patched.match(/nativeBridge\(/g).length, 3);
    assert.throws(() => patchBackground("browser.runtime.sendNativeMessage(NATIVE_APP_ID, {})"), /expected 3/);
});

test("build writes a loadable add-on with the overlay", () => {
    const out = build();
    for (const file of ["manifest.json", "background.js", "native-bridge.js", "options.html", "options.js", "detector.js", "_locales/id/messages.json"]) {
        assert.ok(existsSync(join(out, file)), file);
    }
});

test("validateAppSession keeps only a usable session", () => {
    assert.equal(validateAppSession(null), null);
    assert.equal(validateAppSession({ ...session, token: "" }), null);
    assert.equal(validateAppSession({ ...session, mode: "admin" }), null);
    const cleaned = validateAppSession({ ...session, apiBaseURL: "javascript:alert(1)" });
    assert.equal(cleaned.apiBaseURL, null);
    assert.equal(cleaned.shareWarnings, false);
});

test("getSession: not onboarded without a stored session", async () => {
    const bridge = createNativeBridge({ storage: memoryStorage(), fetchImpl: () => assert.fail("no fetch") });
    assert.deepEqual(await bridge({ type: "getSession" }), { ok: false, error: "not_onboarded" });
});

test("getSession: answers the contract shape, never extra fields", async () => {
    const storage = memoryStorage({ [SESSION_KEY]: { ...session, refreshedAt: 1000 } });
    const bridge = createNativeBridge({ storage, now: () => 1000 + 60_000, fetchImpl: () => assert.fail("fresh, no fetch") });
    const reply = await bridge({ type: "getSession" });
    assert.deepEqual(Object.keys(reply).sort(), ["aiBaseURL", "apiBaseURL", "autoSend", "deviceId", "guardianName", "mode", "name", "ok", "shareWarnings", "token"]);
    assert.equal(reply.guardianName, "Rina");
});

test("getSession: refreshes the Guardian hourly from GET /devices/me", async () => {
    const storage = memoryStorage({ [SESSION_KEY]: { ...session, refreshedAt: 0 } });
    let asked = null;
    const fetchImpl = async (url, init) => {
        asked = { url, auth: init.headers.Authorization };
        return { ok: true, status: 200, json: async () => ({ name: "Ibu", mode: "protected", guardian: null }) };
    };
    const reply = await createNativeBridge({ storage, fetchImpl, now: () => 2 * 60 * 60 * 1000 })({ type: "getSession" });
    assert.deepEqual(asked, { url: "https://api.example/devices/me", auth: "Bearer shoo_x" });
    assert.equal(reply.guardianName, null, "disconnected Guardian is gone");
});

test("getSession: a 401 forgets the session (device deleted)", async () => {
    const storage = memoryStorage({ [SESSION_KEY]: { ...session, refreshedAt: 0 } });
    const fetchImpl = async () => ({ ok: false, status: 401 });
    const reply = await createNativeBridge({ storage, fetchImpl, now: () => 9e12 })({ type: "getSession" });
    assert.equal(reply.ok, false);
    assert.ok(!(SESSION_KEY in storage.data));
});

test("pageChecked counts without an address; heartbeat answers ok", async () => {
    const storage = memoryStorage();
    const bridge = createNativeBridge({ storage, now: () => 0 });
    await bridge({ type: "pageChecked", url: "https://secret.example" });
    await bridge({ type: "pageChecked" });
    assert.deepEqual(storage.data[STATS_KEY], { checked: 2, lastCheckedAt: "1970-01-01T00:00:00.000Z" });
    assert.deepEqual(await bridge({ type: "heartbeat", allSites: true }), { ok: true });
    assert.deepEqual(await bridge({ type: "nope" }), { ok: false, error: "unknown_type" });
});
