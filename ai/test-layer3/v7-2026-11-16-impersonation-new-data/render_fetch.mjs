#!/usr/bin/env node
// v7 extra (render_check.py): load each page of .hasil/render/todo.jsonl once in headless Google Chrome (JavaScript runs, 8 s
// virtual time, throwaway profile, no clicks, no typing), take the rendered DOM and keep only parseHtml's title and text.
// Each URL is checked with assertPublicUrl first; Chrome is killed after 30 s. HTML is not stored. Prints only counts.
//   node render_fetch.mjs        writes .hasil/render/rendered.jsonl (refuses to overwrite)
import { readFileSync, writeFileSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";
import { parseHtml } from "../../eval/tools/snapshot.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIR = join(HERE, ".hasil/render");
const OUT = join(DIR, "rendered.jsonl");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const TIMEOUT_MS = 30000, WORKERS = 6, MAX_DOM = 3_000_000;

if (existsSync(OUT)) throw new Error("rendered.jsonl already exists: not overwriting");
const rows = readFileSync(join(DIR, "todo.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

function dumpDom(url) {
    const profile = mkdtempSync(join(tmpdir(), "render-"));
    const args = ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--disable-extensions",
        "--disable-sync", "--disable-background-networking", "--mute-audio", "--deny-permission-prompts",
        `--user-data-dir=${profile}`, `--user-agent=${UA}`, "--window-size=390,844", "--virtual-time-budget=8000", "--dump-dom", url];
    return new Promise((res) => {
        const p = spawn(CHROME, args, { stdio: ["ignore", "pipe", "ignore"] });
        let out = "";
        p.stdout.on("data", (b) => { if (out.length < MAX_DOM) out += b; });
        const t = setTimeout(() => p.kill("SIGKILL"), TIMEOUT_MS);
        p.on("exit", () => { clearTimeout(t); rmSync(profile, { recursive: true, force: true }); res(out); });
    });
}

const results = [];
let next = 0;
async function worker() {
    while (next < rows.length) {
        const r = rows[next++];
        const rec = { id: r.id, ok: false, title: "", text: "" };
        try {
            await assertPublicUrl(r.url);
            const html = await dumpDom(r.url);
            if (html.length > 200) {
                const { snapshot } = parseHtml(html, { url: r.url, domain: new URL(r.url).hostname });
                Object.assign(rec, { ok: true, title: snapshot.title || "", text: (snapshot.text || "").slice(0, 6000) });
            }
        } catch { /* not public / DNS failed: stays ok=false */ }
        results.push(rec);
    }
}
await Promise.all(Array.from({ length: WORKERS }, worker));
writeFileSync(OUT, results.map((x) => JSON.stringify(x)).join("\n") + "\n");
console.log("pages", results.length, "ok", results.filter((x) => x.ok).length);
