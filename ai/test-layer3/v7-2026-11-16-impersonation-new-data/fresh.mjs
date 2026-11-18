#!/usr/bin/env node
// Step 1b (v7): the 1.239 rows of database-link-label.csv that are NOT Kaggle (Alief's Shoo phishing feed of 2026-11-09 and the
// two manual lists) have no saved page. Fetch each one once, the same way as
// ../../test-layer-update-full/v4-2026-11-11-maliciousphishdata/pages.mjs: one static GET, no JavaScript, no cookies,
// every redirect hop checked by assertPublicUrl, at most 500 kB read. Pages are attacker data: never run, never followed further.
// Prints only counts, never URLs or hosts.
//   node fresh.mjs            writes fresh/.hasil/pages.jsonl (new file; refuses to overwrite)
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";
import { parseHtml } from "../../eval/tools/snapshot.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CSV = join(HERE, "../../test-layer-update-full/v4-2026-11-11-maliciousphishdata/.hasil/database-link-label.csv");
const OUT_DIR = join(HERE, "fresh/.hasil");
const OUT = join(OUT_DIR, "pages.jsonl");
const MAX_BYTES = 500_000, MAX_REDIRECTS = 3, TIMEOUT_MS = 15000, WORKERS = 8, EMPTY_CHARS = 200;
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

if (existsSync(OUT)) throw new Error("fresh/.hasil/pages.jsonl already exists: not overwriting");

function parseCsv(text) {
    const rows = [];
    let row = [], cell = "", q = false;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (q) {
            if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }
            else if (ch === '"') q = false;
            else cell += ch;
        } else if (ch === '"') q = true;
        else if (ch === ",") { row.push(cell); cell = ""; }
        else if (ch === "\n") { row.push(cell.replace(/\r$/, "")); rows.push(row); row = []; cell = ""; }
        else cell += ch;
    }
    if (cell || row.length) { row.push(cell); rows.push(row); }
    const [head, ...body] = rows;
    return body.filter((r) => r.length === head.length).map((r) => Object.fromEntries(head.map((h, i) => [h, r[i]])));
}

const fail = (code) => Object.assign(new Error(code), { v7: code });
function reasonOf(e) {
    if (e?.v7) return e.v7;
    if (e?.name === "TimeoutError" || e?.name === "AbortError") return "timeout";
    const m = String(e?.message ?? "");
    if (/^cannot resolve|did not resolve/.test(m)) return "dns";
    if (/private|not a public|credentials|is refused|only http|not a valid URL/.test(m)) return "ditolak";
    const c = String(e?.cause?.code ?? "");
    if (c === "ENOTFOUND" || c === "EAI_AGAIN") return "dns";
    if (/CERT|TLS|SSL/i.test(c)) return "tls";
    return "jaringan";
}

async function fetchHtml(startUrl) {
    const signal = AbortSignal.timeout(TIMEOUT_MS);
    let url = startUrl, res;
    for (let hop = 0; ; hop++) {
        await assertPublicUrl(url);
        res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html" }, redirect: "manual", credentials: "omit", signal });
        const location = res.headers.get("location");
        if (res.status >= 300 && res.status < 400 && location) {
            await res.body?.cancel();
            if (hop >= MAX_REDIRECTS) throw fail("redirect");
            url = new URL(location, url).href;
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

const toUrl = (raw) => {
    const t = String(raw).trim().replace(/^'/, "");
    try {
        const u = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(t) ? t : `https://${t}`);
        return u.protocol === "http:" || u.protocol === "https:" ? u : null;
    } catch {
        return null;
    }
};
const siteKey = (h) => h.toLowerCase().replace(/^www\./, "");

const links = parseCsv(readFileSync(CSV, "utf8")).filter((r) => r.sumber !== "kaggle_malicious_phish");
mkdirSync(OUT_DIR, { recursive: true });
const results = [];
let next = 0;
async function worker() {
    while (next < links.length) {
        const l = links[next++];
        const base = { id: l.id, label: l.label, sumber: l.sumber, kategori: l.kategori };
        const u = toUrl(l.link);
        if (!u) { results.push({ ...base, keadaan: "gagal", alasan: "bukan_url" }); continue; }
        base.url = u.href;
        try {
            const got = await Promise.race([fetchHtml(u.href), new Promise((_, rej) => setTimeout(() => rej(fail("timeout")), TIMEOUT_MS + 5000))]);
            const { snapshot } = parseHtml(got.html, { url: got.finalUrl });
            snapshot.url = got.finalUrl;
            const fields = snapshot.forms.reduce((s, f) => s + f.fields.length, 0);
            results.push({ ...base, keadaan: snapshot.text.length < EMPTY_CHARS && fields === 0 ? "kosong" : "ok", final_url: got.finalUrl,
                pindah_host: siteKey(new URL(got.finalUrl).hostname) !== siteKey(u.hostname), title: snapshot.title, text: snapshot.text,
                forms: snapshot.forms, imageAlts: snapshot.imageAlts, lang: snapshot.lang });
        } catch (e) {
            results.push({ ...base, keadaan: "gagal", alasan: reasonOf(e) });
        }
        if (results.length % 100 === 0) console.log(`${results.length}/${links.length}`);
    }
}
await Promise.all(Array.from({ length: WORKERS }, worker));
writeFileSync(OUT, results.map((r) => JSON.stringify(r)).join("\n") + "\n");
const count = {};
for (const r of results) count[`${r.sumber}|${r.keadaan}`] = (count[`${r.sumber}|${r.keadaan}`] ?? 0) + 1;
console.log(JSON.stringify(count, null, 1));
