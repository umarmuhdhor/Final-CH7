#!/usr/bin/env node
// Android (Team App). Builds the Shoo add-on for Firefox for Android into build/shoo-firefox/.
//
// Source: the Safari extension (ios/ShooExtension/Resources, lead-owned), which already uses `browser.*` and
// `background.scripts` like Firefox. Those files are copied, never edited. The build only:
//   1. writes a Firefox manifest (gecko id, no nativeMessaging, settings page);
//   2. rewrites background.js's `browser.runtime.sendNativeMessage(NATIVE_APP_ID, …)` to `nativeBridge(…)`
//      (overlay/native-bridge.js), and fails if the Safari file no longer has exactly those calls;
//   3. adds overlay/ (native-bridge.js + the settings page that links to the Shoo Android app).
//
// Usage: node android/firefox-addon/build.mjs

import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = (path) => fileURLToPath(new URL(path, import.meta.url));
export const SOURCE = here("../../ios/ShooExtension/Resources/");
export const OVERLAY = here("./overlay/");
export const OUT = here("./build/shoo-firefox/");

export const GECKO_ID = "shoo@shoo.ai.id";
export const MIN_FIREFOX = "128.0";
const NATIVE_CALL = /browser\.runtime\.sendNativeMessage\(NATIVE_APP_ID,\s*/g;
export const NATIVE_CALLS = 3; // getSession, heartbeat (sendNative), pageChecked

/** Safari manifest → Firefox for Android manifest. */
export function firefoxManifest(safari) {
    const manifest = structuredClone(safari);
    manifest.permissions = (manifest.permissions ?? []).filter((permission) => permission !== "nativeMessaging");
    manifest.background = { scripts: manifest.background?.scripts ?? ["background.js"], type: "module" };
    manifest.options_ui = { page: "options.html" };
    manifest.browser_specific_settings = {
        gecko: { id: GECKO_ID, strict_min_version: MIN_FIREFOX },
        gecko_android: { strict_min_version: MIN_FIREFOX },
    };
    return manifest;
}

/** Points the native-messaging calls at the bridge. Throws when the Safari code changed shape. */
export function patchBackground(source) {
    const found = source.match(NATIVE_CALL)?.length ?? 0;
    if (found !== NATIVE_CALLS) {
        throw new Error(`background.js has ${found} sendNativeMessage(NATIVE_APP_ID, …) calls, expected ${NATIVE_CALLS}: update native-bridge.js`);
    }
    return `import { nativeBridge } from "./native-bridge.js";\n` + source.replace(NATIVE_CALL, "nativeBridge(");
}

export function build({ source = SOURCE, out = OUT } = {}) {
    if (!existsSync(source)) throw new Error(`Safari extension not found at ${source}`);
    rmSync(out, { recursive: true, force: true });
    mkdirSync(out, { recursive: true });
    cpSync(source, out, { recursive: true });
    cpSync(OVERLAY, out, { recursive: true });
    const manifest = firefoxManifest(JSON.parse(readFileSync(new URL("manifest.json", pathToFileURL(source)), "utf8")));
    writeFileSync(new URL("manifest.json", pathToFileURL(out)), JSON.stringify(manifest, null, 4) + "\n");
    const background = new URL("background.js", pathToFileURL(out));
    writeFileSync(background, patchBackground(readFileSync(background, "utf8")));
    return out;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    console.log(`Built ${build()}`);
}
