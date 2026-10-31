#!/usr/bin/env node
// Serves SAVED scam HTML to Safari for timing only. Listens on 127.0.0.1, nothing else.
// Every served page gets: the CSP header from PLAN-ULANG.md, <meta http-equiv> and preload-type <link>
// tags stripped, and one nonce'd measuring script. Page scripts, subresources, forms and <base> are blocked.
// Usage: node server.mjs [--port 8765] [--fresh]
// Scam pages are refused until .uji-pagar-lulus exists (written by hand after the C3a fence test passed).
import { createServer as createHttp } from "node:http";
import { createServer as createTcp } from "node:net";
import { randomBytes } from "node:crypto";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const htmlDir = join(here, "..", ".html");
const hasilFile = join(here, "hasil.json");
const gateFile = join(here, ".uji-pagar-lulus");
const arg = (n, d) => (process.argv.includes(n) ? process.argv[process.argv.indexOf(n) + 1] : d);
const PORT = Number(arg("--port", 8765));
const CANARY_PORT = PORT + 1;
const LOADS = 5; // page loads per site; the first is dropped when summarising
const HOST = `127.0.0.1:${PORT}`;

const polaJs = readFileSync(join(here, "pola.js"), "utf8");
const ukurJs = readFileSync(join(here, "ukur.js"), "utf8");
const ujiJs = readFileSync(join(here, "uji.js"), "utf8");
const ujiHtml = readFileSync(join(here, "uji-pagar.html"), "utf8");

// Tag matcher that respects quotes, so a ">" inside an attribute value cannot hide an attribute.
const tag = (name) => new RegExp(`<${name}\\b(?:[^>"']|"[^"]*"|'[^']*')*>`, "gi");
const SCRIPT_RE = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;

function sanitize(html) {
    let out = html.replace(tag("meta"), (m) => (/\bhttp-equiv\b/i.test(m) ? "" : m));
    out = out.replace(tag("link"), (m) =>
        /\brel\s*=\s*["']?[^"'>]*\b(dns-prefetch|preconnect|prefetch|prerender|preload|modulepreload)\b/i.test(m) ? "" : m,
    );
    if (/http-equiv/i.test(out)) throw new Error("http-equiv left after strip, page refused");
    return out;
}

function inject(html, tagHtml) {
    const m = /<head\b[^>]*>/i.exec(html) ?? /<html\b[^>]*>/i.exec(html);
    if (!m) return tagHtml + html;
    const at = m.index + m[0].length;
    return html.slice(0, at) + tagHtml + html.slice(at);
}

// Writes the headers (CSP with a fresh nonce) and returns send(scriptBuilder) that injects the nonce'd script.
function page(res, body) {
    const nonce = randomBytes(16).toString("base64");
    const csp = `default-src 'none'; script-src 'nonce-${nonce}'; connect-src 'self'; form-action 'none'; base-uri 'none'`;
    res.writeHead(200, {
        "content-type": "text/html; charset=utf-8",
        "content-security-policy": csp,
        "cache-control": "no-store",
        "referrer-policy": "no-referrer",
        "x-content-type-options": "nosniff",
    });
    return (scriptHtml) => res.end(inject(body, scriptHtml(nonce)));
}

// Order: biggest inline-script payload first.
const inlineBytes = (html) => [...html.matchAll(SCRIPT_RE)].reduce((s, m) => s + (/\bsrc\s*=/i.test(m[1]) ? 0 : m[2].length), 0);
const sites = [];
const skipped = [];
for (const f of readdirSync(htmlDir)) {
    const id = /^(L?\d+)-desktop\.html$/.exec(f)?.[1];
    if (!id) continue;
    const html = readFileSync(join(htmlDir, f), "utf8");
    if (!html.length) skipped.push(id);
    else sites.push({ nama: `${id}-desktop`, bytes: inlineBytes(html) });
}
sites.sort((a, b) => b.bytes - a.bytes);
const order = sites.map((s) => s.nama);

let hasil = !process.argv.includes("--fresh") && existsSync(hasilFile) ? JSON.parse(readFileSync(hasilFile, "utf8")) : [];
const save = () => writeFileSync(hasilFile, JSON.stringify(hasil, null, 2));
if (process.argv.includes("--fresh")) save();

function nextAfter(nama) {
    const done = hasil.filter((r) => r.nama === nama).length;
    if (done < LOADS) return `/halaman/${nama}`;
    const i = order.indexOf(nama);
    return i + 1 < order.length ? `/halaman/${order[i + 1]}` : "/selesai";
}

// Canary: records any TCP connection to a port nothing should ever contact. Used by the C3a fence test.
const canary = [];
createTcp((sock) => {
    let got = false;
    sock.once("data", (d) => {
        got = true;
        canary.push(String(d).split("\r\n")[0].slice(0, 80));
    });
    sock.on("error", () => {});
    sock.on("close", () => {
        if (!got) canary.push("(connection, no data)");
    });
    sock.end("HTTP/1.1 204 No Content\r\nconnection: close\r\n\r\n");
}).listen(CANARY_PORT, "127.0.0.1");

const readBody = (req) =>
    new Promise((resolve, reject) => {
        let n = 0;
        const chunks = [];
        req.on("data", (c) => {
            n += c.length;
            if (n > 65536) reject(new Error("body too large"));
            else chunks.push(c);
        });
        req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    });

const json = (res, code, obj) => {
    res.writeHead(code, { "content-type": "application/json", "cache-control": "no-store" });
    res.end(JSON.stringify(obj));
};
const text = (res, code, s) => {
    res.writeHead(code, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
    res.end(s);
};

createHttp(async (req, res) => {
    try {
        if (req.headers.host !== HOST) return text(res, 421, "wrong host");
        const p = new URL(req.url, `http://${HOST}`).pathname;

        if (p === "/uji-pagar") {
            const send = page(res, sanitize(ujiHtml.replaceAll("__CANARY__", String(CANARY_PORT))));
            return void send((nonce) => `<script id="shoo-ukur" nonce="${nonce}">${ujiJs}</script>`);
        }
        if (p === "/hasil-uji" && req.method === "POST") {
            const b = JSON.parse(await readBody(req));
            writeFileSync(join(here, "hasil-uji.json"), JSON.stringify({ ...b, canary }, null, 2));
            return json(res, 200, { ok: true });
        }
        if (p === "/canary") return json(res, 200, { canary });
        if (p === "/") return text(res, 200, `ukur-safari: ${order.length} situs. Mulai: /sapu`);
        if (p === "/selesai") return text(res, 200, "selesai");
        if (p === "/status") return json(res, 200, { situs: order.length, hasil: hasil.length, perlu: order.length * LOADS, skipped, gate: existsSync(gateFile) });

        // Everything below serves scam HTML: only after the fence test passed.
        if (!existsSync(gateFile)) return text(res, 403, "pagar belum lulus (C3a): halaman scam tidak disajikan");

        if (p === "/sapu") {
            res.writeHead(302, { location: `/halaman/${order[0]}` });
            return void res.end();
        }
        const m = /^\/halaman\/(L?\d+-desktop)$/.exec(p);
        if (m) {
            const nama = m[1];
            if (!order.includes(nama)) return text(res, 404, "tidak ada");
            const send = page(res, sanitize(readFileSync(join(htmlDir, `${nama}.html`), "utf8")));
            return void send((nonce) => `<script id="shoo-ukur" nonce="${nonce}" data-nama="${nama}">${polaJs}\n${ukurJs}</script>`);
        }
        if (p === "/hasil" && req.method === "POST") {
            const b = JSON.parse(await readBody(req));
            if (!order.includes(b.nama)) return text(res, 400, "bad nama");
            const { nama, meanMs, reps, coldMs, bytes, n, hit, ua, error } = b;
            hasil.push({ nama, muatan: hasil.filter((r) => r.nama === nama).length + 1, meanMs, reps, coldMs, bytes, n, hit, ua, error, at: new Date().toISOString() });
            save();
            return json(res, 200, { next: nextAfter(nama) });
        }
        return text(res, 404, "tidak ada");
    } catch (e) {
        if (!res.headersSent) text(res, 500, String(e.message ?? e));
    }
}).listen(PORT, "127.0.0.1", () => {
    console.log(`http://${HOST}  canary tcp ${CANARY_PORT}  situs ${order.length}  dilewati(kosong) [${skipped}]  gate ${existsSync(gateFile)}`);
});
