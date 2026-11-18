#!/usr/bin/env node
// v7 extra: one screenshot per page in .hasil/eyecheck50/pick.jsonl, for the eye-check report (eyecheck50.py).
// System Google Chrome, headless, throwaway profile, iPhone-sized window, no clicks, no typing. Each URL is checked with
// assertPublicUrl first; Chrome is killed after 30 s. Pages are attacker data: the screenshot is the only thing kept.
// Prints only counts, never URLs or hosts.
//   node eyecheck50_shot.mjs        writes .hasil/eyecheck50/ss/<id>.png and shots.jsonl (refuses to overwrite shots.jsonl)
import { readFileSync, writeFileSync, existsSync, mkdirSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIR = join(HERE, ".hasil/eyecheck50");
const SS = join(DIR, "ss");
const OUT = join(DIR, "shots.jsonl");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const TIMEOUT_MS = 30000, WORKERS = 4;

if (existsSync(OUT)) throw new Error("shots.jsonl already exists: not overwriting");
mkdirSync(SS, { recursive: true });
const rows = readFileSync(join(DIR, "pick.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const at = new Date().toISOString().slice(0, 16).replace("T", " ") + " UTC";

function shoot(url, file) {
    const profile = mkdtempSync(join(tmpdir(), "eyecheck50-"));
    const args = ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", "--no-default-browser-check",
        "--disable-extensions", "--disable-sync", "--disable-background-networking", "--mute-audio", "--deny-permission-prompts",
        `--user-data-dir=${profile}`, `--user-agent=${UA}`, "--window-size=390,844", "--force-device-scale-factor=1",
        "--virtual-time-budget=8000", `--screenshot=${file}`, url];
    return new Promise((res) => {
        const p = spawn(CHROME, args, { stdio: "ignore" });
        const t = setTimeout(() => p.kill("SIGKILL"), TIMEOUT_MS);
        p.on("exit", () => { clearTimeout(t); rmSync(profile, { recursive: true, force: true }); res(); });
    });
}

const results = [];
let next = 0;
async function worker() {
    while (next < rows.length) {
        const r = rows[next++];
        const url = r.url.includes("//") ? r.url : "http://" + r.url;
        const file = join(SS, `${r.id}.png`);
        const rec = { id: r.id, ok: false, why: "", at };
        try {
            await assertPublicUrl(url);
            await shoot(url, file);
            rec.ok = existsSync(file) && statSync(file).size > 0;
            if (!rec.ok) rec.why = "Chrome tidak menghasilkan gambar (timeout/gagal)";
        } catch (e) {
            rec.why = "URL ditolak pengecek alamat publik / DNS gagal";
        }
        results.push(rec);
    }
}
await Promise.all(Array.from({ length: WORKERS }, worker));
writeFileSync(OUT, results.map((x) => JSON.stringify(x)).join("\n") + "\n");
console.log("pages", results.length, "ok", results.filter((x) => x.ok).length);
