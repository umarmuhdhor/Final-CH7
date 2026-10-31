// node --test chrome/test/*.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";

const ext = (path) => new URL(`../extension/${path}`, import.meta.url);
const read = (path) => readFileSync(ext(path), "utf8");
const manifest = JSON.parse(read("manifest.json"));
const locales = Object.fromEntries(["en", "id"].map((l) => [l, JSON.parse(read(`_locales/${l}/messages.json`))]));
const scripts = manifest.content_scripts[0].js;

test("Manifest V3 with a module service worker, no Safari-only keys", () => {
    assert.equal(manifest.manifest_version, 3);
    assert.deepEqual(manifest.background, { service_worker: "background.js", type: "module" });
    assert.ok(!manifest.permissions.includes("nativeMessaging"), "no native app on Chrome");
    assert.ok(!("scripts" in manifest.background) && !("persistent" in manifest.background));
});

test("every file the manifest names exists", () => {
    const files = [
        manifest.background.service_worker,
        ...scripts,
        ...Object.values(manifest.icons),
        ...manifest.web_accessible_resources.flatMap((r) => r.resources),
    ];
    for (const file of files) assert.ok(existsSync(ext(file)), file);
});

test("content scripts: shim first, then the Safari order, content.js last", () => {
    assert.equal(scripts[0], "browser-shim.js");
    assert.equal(scripts.at(-1), "content.js");
    const order = (name) => scripts.indexOf(name);
    assert.ok(order("dom.js") < order("lists-client.js") && order("lists-client.js") < order("detector.js"));
    assert.ok(order("detector.js") < order("pipeline.js"));
    for (const ui of ["pill.js", "popup.js", "marks.js", "block.js"]) assert.ok(order("pipeline.js") < order(ui), ui);
    assert.ok(order("block.js") < order("snapshot.js"));
});

test("blocked.html's scripts and stylesheet are web-accessible and exist", () => {
    const html = read("blocked.html");
    const refs = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map((m) => m[1]);
    assert.deepEqual(refs, ["blocked.css", "images/icon-96.png", "browser-shim.js", "block.js", "blocked-page.js"]);
    const war = manifest.web_accessible_resources.flatMap((r) => r.resources);
    for (const ref of [...refs, "blocked.html"]) assert.ok(war.includes(ref), ref);
});

test("EN and ID have the same keys, and every __MSG_x__ exists", () => {
    assert.deepEqual(Object.keys(locales.id).sort(), Object.keys(locales.en).sort());
    for (const [, key] of JSON.stringify(manifest).matchAll(/__MSG_(\w+)__/g)) assert.ok(locales.en[key], key);
    for (const l of ["en", "id"]) for (const [key, value] of Object.entries(locales[l])) assert.ok(value.message, `${l}.${key}`);
});

test("every message key the scripts ask for exists (template keys checked per tier/kind)", () => {
    const code = readdirSync(ext(".")).filter((f) => f.endsWith(".js")).map(read).join("\n") + read("blocked-page.js");
    const plain = [...code.matchAll(/\bt\("([a-z]+_[a-z0-9_]+)"/g)].map((m) => m[1]);
    const expanded = [
        ...["1", "2"].flatMap((tier) => [`popup_status_${tier}`, `popup_body_${tier}`]),
        ...["safe", "warning", "danger"].map((tone) => `pill_status_${tone}`),
        ...["pin", "otp", "card", "ktp", "password"].flatMap((k) => [`mark_dont_${k}`, `mark_why_${k}`]),
        "block_auto_open",
        "block_back",
        "block_title",
    ];
    for (const key of new Set([...plain, ...expanded])) assert.ok(locales.en[key], key);
});

test("no Shoo-app deep links in the Chrome UI (no app to open)", () => {
    for (const file of ["popup.js", "pill.js", "blocked-page.js", "blocked.html"]) {
        assert.doesNotMatch(read(file), /shoo:\/\//, file);
    }
});
