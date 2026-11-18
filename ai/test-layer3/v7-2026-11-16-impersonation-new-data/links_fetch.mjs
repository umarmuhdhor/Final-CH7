#!/usr/bin/env node
// v7 extra, step 2 of the outbound-link test: PageSnapshot has no links, so fetch each page once more and keep ONLY counts of links to
// chat apps (t.me, wa.me, ...). Same fetch rules as fresh.mjs: one static GET, no JavaScript, no cookies, every redirect hop checked by
// assertPublicUrl, at most 500 kB. The HTML is not saved. Prints only counts.
//   node links_fetch.mjs      reads .hasil/links-todo.jsonl, writes .hasil/links.jsonl (new file; refuses to overwrite)
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const IN = join(HERE, ".hasil/links-todo.jsonl");
const OUT = join(HERE, ".hasil/links.jsonl");
const MAX_BYTES = 500_000, MAX_REDIRECTS = 3, TIMEOUT_MS = 15000, WORKERS = 8;
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
// Chat apps that scam pages send people to. Host match is exact or a subdomain.
const CHAT = ["t.me", "telegram.me", "telegram.dog", "wa.me", "api.whatsapp.com", "chat.whatsapp.com", "web.whatsapp.com", "whatsapp.com", "wa.link", "line.me", "lin.ee"];
if (existsSync(OUT)) throw new Error(".hasil/links.jsonl already exists: not overwriting");

const fail = (c) => Object.assign(new Error(c), { code7: c });
async function fetchHtml(startUrl) {
    const signal = AbortSignal.timeout(TIMEOUT_MS);
    let url = startUrl, res;
    for (let hop = 0; ; hop++) {
        await assertPublicUrl(url);
        res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html" }, redirect: "manual", credentials: "omit", signal });
        const loc = res.headers.get("location");
        if (res.status >= 300 && res.status < 400 && loc) {
            await res.body?.cancel();
            if (hop >= MAX_REDIRECTS) throw fail("redirect");
            url = new URL(loc, url).href;
            continue;
        }
        break;
    }
    if (!res.ok) { await res.body?.cancel(); throw fail(`http_${res.status}`); }
    if (!/html/i.test(res.headers.get("content-type") || "")) { await res.body?.cancel(); throw fail("bukan_html"); }
    const reader = res.body.getReader();
    const chunks = [];
    let size = 0;
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > MAX_BYTES) { await reader.cancel(); break; }
        chunks.push(value);
    }
    return { html: Buffer.concat(chunks).toString("utf8"), finalUrl: url };
}

const chatHost = (h) => CHAT.find((c) => h === c || h.endsWith("." + c)) || null;

function extract(html, base) {
    const src = html.replace(/<!--[\s\S]*?-->/g, "");
    const msg = {};
    let total = 0;
    for (const m of src.matchAll(/<(?:a|area|form)\b[^>]*?\s(?:href|action)\s*=\s*["']?([^"'\s>]+)/gi)) {
        total++;
        let h = "";
        try { h = new URL(m[1].replace(/&amp;/g, "&"), base).hostname.toLowerCase(); } catch { continue; }
        const c = chatHost(h);
        if (c) msg[c] = (msg[c] ?? 0) + 1;
    }
    // Links built in scripts or onclick (window.open, location.href) are counted separately.
    const scripts = [...src.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]).join(" ");
    const handlers = [...src.matchAll(/\son\w+\s*=\s*["']([^"']*)/gi)].map((m) => m[1]).join(" ");
    const inScript = /(?:https?:)?\/\/(?:t\.me|telegram\.me|wa\.me|api\.whatsapp\.com|chat\.whatsapp\.com|wa\.link)\//i.test(scripts + " " + handlers);
    return { msg, links_total: total, msg_in_script: inScript };
}

const todo = readFileSync(IN, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const results = [];
let next = 0;
async function worker() {
    while (next < todo.length) {
        const t = todo[next++];
        try {
            const got = await Promise.race([fetchHtml(t.url), new Promise((_, rej) => setTimeout(() => rej(fail("timeout")), TIMEOUT_MS + 5000))]);
            results.push({ id: t.id, keadaan: "ok", ...extract(got.html, got.finalUrl) });
        } catch (e) {
            results.push({ id: t.id, keadaan: "gagal", alasan: e?.code7 || (e?.name === "TimeoutError" ? "timeout" : "jaringan") });
        }
        if (results.length % 200 === 0) console.log(`${results.length}/${todo.length}`);
    }
}
await Promise.all(Array.from({ length: WORKERS }, worker));
writeFileSync(OUT, results.map((r) => JSON.stringify(r)).join("\n") + "\n");
const ok = results.filter((r) => r.keadaan === "ok");
console.log(`ok ${ok.length} of ${results.length}; with a chat link ${ok.filter((r) => Object.keys(r.msg).length).length}`);
