// Loads chrome/extension unpacked into Chromium and screenshots every warning level, EN and ID.
// Not part of `node --test chrome/test/*.test.mjs` (needs a browser). Needs playwright-core:
//   cd chrome && npm install --no-save playwright-core && npx playwright-core install chromium
//   node chrome/test/e2e/screens.mjs [outDir]
// The demo hosts (test/fixtures/demo-urls.json) are fake: Chromium sends every http request to a local
// proxy that answers with a plain page, so nothing reaches the internet.
import { chromium } from "playwright-core";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const EXT = fileURLToPath(new URL("../../extension", import.meta.url));
const urls = JSON.parse(readFileSync(new URL("../fixtures/demo-urls.json", import.meta.url), "utf8"));
const out = process.argv[2] || join(tmpdir(), "shoo-chrome-screens");
mkdirSync(out, { recursive: true });

const page = (host) => `<!doctype html><html lang="id"><head><meta charset="utf-8"><title>${host}</title>
<style>body{font:16px/1.5 system-ui,sans-serif;margin:0;padding:40px;background:#fff;color:#222}
main{max-width:520px;margin:0 auto}input{display:block;width:100%;padding:10px;margin:8px 0 16px;font:inherit}</style></head>
<body><main><h1>Masuk ke akun Anda</h1><p>Verifikasi data Anda untuk melanjutkan.</p>
<form><label>Nama pengguna<input name="user"></label><button type="button">Lanjut</button></form></main></body></html>`;

// Proxy: the request line carries the absolute URL of the fake host.
const proxy = createServer((req, res) => {
    const host = new URL(req.url, "http://x").hostname;
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(page(host));
});
await new Promise((resolve) => proxy.listen(0, "127.0.0.1", resolve));
const proxyUrl = `http://127.0.0.1:${proxy.address().port}`;

const problems = [];
async function run(lang) {
    // Started by hand, not launchPersistentContext: macOS takes the UI language (which _locales chrome.i18n
    // picks) only from `-AppleLanguages (id)`, an argument Playwright refuses. Elsewhere --lang does it.
    const profile = mkdtempSync(join(tmpdir(), "shoo-profile-"));
    const browser = spawn(chromium.executablePath(), [
        "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`, "--no-first-run",
        "--no-default-browser-check", "--window-size=1280,800", `--disable-extensions-except=${EXT}`,
        `--load-extension=${EXT}`, `--proxy-server=${proxyUrl}`, `--lang=${lang}`,
        "--disable-features=HttpsUpgrades,HttpsFirstBalancedModeAutoEnable", // the demo hosts are http only
        // Chromium also reads "(id)" as the start page; headless allows only one, so no about:blank here.
        ...(process.platform === "darwin" ? ["-AppleLanguages", `(${lang})`] : []),
    ], { stdio: "ignore" });
    let cdp = null;
    try {
        cdp = await chromium.connectOverCDP(`http://127.0.0.1:${await devToolsPort(profile)}`);
        await scenes(lang, cdp.contexts()[0]);
    } finally {
        await cdp?.newBrowserCDPSession().then((s) => s.send("Browser.close")).catch(() => {});
        await cdp?.close().catch(() => {});
        browser.kill();
    }
}

async function scenes(lang, context) {
    const worker = context.serviceWorkers()[0] ?? (await context.waitForEvent("serviceworker"));
    worker.on("console", (m) => m.type() === "error" && problems.push(`[${lang} worker] ${m.text()}`));

    const tab = await context.newPage();
    await tab.setViewportSize({ width: 1280, height: 800 });
    tab.on("pageerror", (e) => problems.push(`[${lang} page] ${e.message}`));
    tab.on("console", (m) => m.type() === "error" && problems.push(`[${lang} console] ${m.text()}`));
    const shot = (name) => tab.screenshot({ path: join(out, `${lang}-${name}.png`) });
    const host = (name) => tab.locator(name).count();

    // < 30: nothing but the live score bubble.
    await tab.goto(urls.safe);
    await tab.waitForSelector("shoo-live-score", { state: "attached" });
    await tab.waitForTimeout(800);
    if (await host("shoo-warning")) problems.push(`[${lang}] safe page shows a warning`);
    await shot("0-safe");

    // 30–49: mini card.
    await tab.goto(urls.mini);
    await tab.waitForSelector("shoo-warning", { state: "attached" });
    await tab.waitForTimeout(600); // rise animation
    await shot("1-mini");

    // 50–79: sheet, then "Continue anyway" (a click on the dimmed page does the same) → mini card.
    await tab.goto(urls.sheet);
    await tab.waitForSelector("shoo-warning", { state: "attached" });
    await tab.waitForTimeout(600);
    await shot("2-sheet");
    await tab.mouse.click(20, 20);
    await tab.waitForTimeout(600);
    if (!(await host("shoo-warning"))) problems.push(`[${lang}] Continue removed the warning instead of shrinking it`);
    await shot("3-sheet-minimized");

    // ≥ 80: the tab moves to the extension's blocked.html.
    await tab.goto(urls.block);
    await tab.waitForURL(/^chrome-extension:\/\/[a-p]{32}\/blocked\.html#/, { timeout: 10000 });
    await tab.waitForLoadState("load");
    await tab.waitForTimeout(400);
    await shot("4-blocked");
    // Back skips the scam page (location.replace) and lands on the page before it.
    await tab.click("button.back");
    await tab.waitForURL((u) => u.href === urls.sheet, { timeout: 5000, waitUntil: "commit" }).catch(() => problems.push(`[${lang}] Back did not return to the previous page (at ${tab.url()})`));
}

/** Port Chromium wrote to <profile>/DevToolsActivePort once it listens. */
async function devToolsPort(profile) {
    for (let i = 0; i < 100; i++) {
        try {
            return Number(readFileSync(join(profile, "DevToolsActivePort"), "utf8").split("\n")[0]);
        } catch {
            await new Promise((r) => setTimeout(r, 100));
        }
    }
    throw new Error("Chromium did not start");
}

try {
    for (const lang of ["en", "id"]) await run(lang);
} finally {
    proxy.close();
}
console.log(`Screenshots → ${out}`);
if (problems.length) {
    console.error(problems.join("\n"));
    process.exitCode = 1;
} else {
    console.log("No errors.");
}
