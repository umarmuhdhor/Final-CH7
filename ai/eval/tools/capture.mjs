#!/usr/bin/env node
// Turns one page into an eval sample: node ai/eval/tools/capture.mjs <url> --label scam|legit --id <slug> --source "<where it came from>"
//   --file <saved.html>   read a HTML file you already saved instead of fetching (use this for scam pages: fetch once, keep the file)
//   --tags a,b            e.g. lookalike-trap,clean-domain-scam
//   --out <dir>           default: ai/eval/data/<label>
//
// Safety: a static GET only (no JavaScript, no cookies, 500 KB cap). Scam pages are hostile: never open them in a normal
// browser to "check". The result is written with redacted:false; READ the file, remove anything personal that the
// automatic masking missed, then set redacted:true. run.mjs refuses real scam samples until you do.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseHtml } from "./snapshot.mjs";
import { domainOf, validateSample } from "../lib.mjs";
import { assertPublicUrl } from "./safe-url.mjs";

const MAX_BYTES = 500_000;
const MAX_REDIRECTS = 3;
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

function parseArgs(argv) {
    const args = { _: [] };
    for (let i = 0; i < argv.length; i++) {
        if (argv[i].startsWith("--")) args[argv[i].slice(2)] = argv[++i];
        else args._.push(argv[i]);
    }
    return args;
}

async function fetchHtml(startUrl) {
    // Redirects are followed by hand so every hop is checked: a public page must not bounce us to localhost or the LAN.
    let url = startUrl;
    let res;
    for (let hop = 0; ; hop++) {
        await assertPublicUrl(url);
        res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html" }, redirect: "manual", credentials: "omit", signal: AbortSignal.timeout(15000) });
        if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
            if (hop >= MAX_REDIRECTS) throw new Error("too many redirects");
            url = new URL(res.headers.get("location"), url).href;
            await res.body?.cancel();
            continue;
        }
        break;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const type = res.headers.get("content-type") || "";
    if (!/html/i.test(type)) throw new Error(`not HTML (${type})`);
    const reader = res.body.getReader();
    const chunks = [];
    let size = 0;
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > MAX_BYTES) {
            await reader.cancel();
            break;
        }
        chunks.push(value);
    }
    return { html: Buffer.concat(chunks).toString("utf8"), finalUrl: url };
}

async function main() {
    const a = parseArgs(process.argv.slice(2));
    const url = a._[0];
    if (!url || !a.label || !a.id || !a.source) {
        console.error('usage: capture.mjs <url> --label scam|legit --id <slug> --source "<where it came from>" [--file saved.html] [--tags a,b] [--out dir]');
        process.exit(2);
    }
    if (!/^https?:\/\//i.test(url)) {
        console.error("only http(s) URLs");
        process.exit(2);
    }

    let html, finalUrl;
    if (a.file) {
        html = readFileSync(a.file, "utf8");
        finalUrl = url;
    } else ({ html, finalUrl } = await fetchHtml(url));

    const { snapshot, meta } = parseHtml(html, { url: finalUrl, domain: domainOf(finalUrl) });
    const sample = {
        id: a.id,
        label: a.label,
        tags: a.tags ? a.tags.split(",").map((t) => t.trim()).filter(Boolean) : [],
        synthetic: false,
        redacted: false, // set to true only after you read this file
        source: a.source,
        collectedAt: new Date().toISOString(),
        notes: "",
        snapshot,
        meta, // not part of PageSnapshot: iframes found in the static HTML (a login form inside an iframe is invisible to snapshot.forms)
    };

    const problems = validateSample({ ...sample, redacted: true });
    if (problems.length) {
        console.error("sample would be invalid:\n  - " + problems.join("\n  - "));
        process.exit(2);
    }
    const dir = a.out || join(dirname(fileURLToPath(import.meta.url)), "..", "data", a.label);
    mkdirSync(dir, { recursive: true });
    const file = join(dir, `${a.id}.json`);
    if (existsSync(file)) {
        console.error(`${file} already exists, not overwriting`);
        process.exit(2);
    }
    writeFileSync(file, JSON.stringify(sample, null, 2) + "\n");
    console.log(`wrote ${file}`);
    console.log(`  ${snapshot.text.length} chars of text, ${snapshot.forms.length} form(s), ${meta.iframes.length} iframe(s)`);
    console.log("  NEXT: read the file, remove any personal data that is left, then set \"redacted\": true.");
}

main().catch((e) => {
    console.error(e.message);
    process.exit(1);
});
