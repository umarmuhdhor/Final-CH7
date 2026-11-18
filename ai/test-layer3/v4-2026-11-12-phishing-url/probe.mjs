#!/usr/bin/env node
// Liveness probe for links.csv, run BEFORE layer 3 (run.mjs): find out which links answer at all, so layer 3 only
// fetches those. Every link in the file is checked (no sampling).
//
//   Phase 1  DNS per unique host (A + AAAA, c-ares resolver, system DNS servers).
//   Phase 2  one GET per link whose host resolved: status line + headers only. The body is cancelled unread,
//            redirects are NOT followed, no cookies, no JavaScript, no form, nothing is downloaded.
//   Phase 3  links-alive.csv = links that layer 3 can use (3xx, or 2xx with an html content type), same columns as
//            links.csv, so `node run.mjs --links links-alive.csv` keeps the same ids (and skips finished snapshots).
//
// Use:  UV_THREADPOOL_SIZE=128 node probe.mjs            all phases, resumable (finished work is skipped)
// Opts: --limit N            only the first N links (smoke test; use PROBE_OUT=<folder> so real results stay untouched)
//       --dns-concurrency N  default 300
//       --concurrency N      HTTP probes in flight, default 150
//       --per-host N         HTTP probes in flight per host, default 4
//       --summary            only (re)build summary + links-alive.csv from the saved results, no network
// PROBE_OUT=<folder> moves .probe/ and links-alive.csv elsewhere.
//
// Safety: only reads. Console prints numbers, never a URL or a host. Raw results (.probe/*.jsonl) hold hosts: gitignored.
// A host with 50 probes and not one 2xx/3xx stops being probed (rest = "host_skipped", counted and reported).
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { isIP } from "node:net";
import { fileURLToPath } from "node:url";
import { Resolver } from "node:dns/promises";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const base = process.env.PROBE_OUT ?? here;
const probeDir = join(base, ".probe");
const dnsFile = join(probeDir, "dns.jsonl");
const httpFile = join(probeDir, "http.jsonl");
const summaryFile = join(probeDir, "summary.json");
const aliveFile = join(base, "links-alive.csv");

const arg = (name, dflt) => {
    const i = process.argv.indexOf(name);
    return i > -1 ? process.argv[i + 1] : dflt;
};
const flag = (name) => process.argv.includes(name);
const log = (s) => process.stderr.write(`${s}\n`);

const DNS_CONCURRENCY = Number(arg("--dns-concurrency", 300));
const CONCURRENCY = Number(arg("--concurrency", 150));
const PER_HOST = Number(arg("--per-host", 4));
const HTTP_TIMEOUT_MS = 10000;
const HOST_GIVE_UP = 50; // probes with zero 2xx/3xx before the rest of that host is skipped
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

// ---- links.csv (same rules as run.mjs: same refang, same dedupe, same ids) ---------------------------------
function parseCsv(text) {
    const rows = [];
    let row = [];
    let cell = "";
    let quoted = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (quoted) {
            if (c === '"' && text[i + 1] === '"') {
                cell += '"';
                i++;
            } else if (c === '"') quoted = false;
            else cell += c;
        } else if (c === '"') quoted = true;
        else if (c === ",") {
            row.push(cell);
            cell = "";
        } else if (c === "\n" || c === "\r") {
            if (c === "\r" && text[i + 1] === "\n") i++;
            row.push(cell);
            if (row.some((x) => x !== "")) rows.push(row);
            row = [];
            cell = "";
        } else cell += c;
    }
    row.push(cell);
    if (row.some((x) => x !== "")) rows.push(row);
    return rows;
}
const hasScheme = (raw) => /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
const refang = (raw) => String(raw).trim().replace(/^hxxp/i, "http").replace(/\[\.\]|\(\.\)/g, ".").replace(/\[:\]/g, ":");
function toUrl(raw) {
    try {
        const u = new URL(hasScheme(raw) ? raw : `https://${raw}`);
        if (u.protocol !== "http:" && u.protocol !== "https:") return null;
        return u.hostname.includes(".") ? u : null;
    } catch {
        return null;
    }
}
const normLabel = (v) => (/^(legit|normal|benign|safe|aman)/.test(String(v ?? "").trim().toLowerCase()) ? "legit" : "scam");
const hostOfUrl = (u) => u.hostname.replace(/^\[|\]$/g, "").toLowerCase().replace(/\.$/, "");

function loadLinks(limit) {
    const rows = parseCsv(readFileSync(join(here, "links.csv"), "utf8").replace(/^﻿/, ""));
    const head = rows[0].map((h) => h.trim().toLowerCase());
    const iUrl = head.indexOf("url");
    const iId = head.indexOf("id");
    const iLabel = head.indexOf("label");
    if (iUrl < 0 || iId < 0) throw new Error("links.csv needs id and url columns");
    const seen = new Set();
    const out = [];
    let dropped = 0;
    for (const r of rows.slice(1)) {
        const raw = refang(r[iUrl] ?? "");
        const u = raw && toUrl(raw);
        if (!u || seen.has(raw)) {
            dropped++;
            continue;
        }
        seen.add(raw);
        out.push({ id: String(r[iId]).trim(), raw, url: u.href, host: hostOfUrl(u), label: normLabel(iLabel < 0 ? "" : r[iLabel]) });
    }
    return { links: limit ? out.slice(0, limit) : out, dropped };
}

async function pool(items, n, fn) {
    let i = 0;
    await Promise.all(
        Array.from({ length: Math.min(n, items.length) }, async () => {
            for (;;) {
                const k = i++;
                if (k >= items.length) return;
                await fn(items[k], k);
            }
        }),
    );
}

function loadJsonl(file) {
    if (!existsSync(file)) return [];
    return readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
}
function appender(file) {
    let buf = [];
    const flush = () => {
        if (buf.length) appendFileSync(file, buf.join("\n") + "\n");
        buf = [];
    };
    return { push: (o) => { buf.push(JSON.stringify(o)); if (buf.length >= 500) flush(); }, flush };
}

// ---- phase 1: DNS ------------------------------------------------------------------------------------------
const resolver = new Resolver({ timeout: 4000, tries: 2 });
async function resolveHost(host) {
    if (isIP(host)) return { s: "ok", a: [host] };
    const a = [];
    let transient = false;
    for (const fn of ["resolve4", "resolve6"]) {
        try {
            a.push(...(await resolver[fn](host)));
        } catch (e) {
            if (e?.code !== "ENOTFOUND" && e?.code !== "ENODATA") transient = true;
        }
    }
    if (a.length) return { s: "ok", a: a.slice(0, 4) };
    return { s: transient ? "transient" : "nxdomain", a: [] };
}

async function phaseDns(links, dns) {
    const todo = [...new Set(links.map((l) => l.host))].filter((h) => !dns.has(h));
    log(`dns: ${todo.length} hosts to resolve (${dns.size} already done)`);
    mkdirSync(probeDir, { recursive: true });
    const out = appender(dnsFile);
    let done = 0;
    const t0 = Date.now();
    await pool(todo, DNS_CONCURRENCY, async (h) => {
        const r = await resolveHost(h);
        dns.set(h, r);
        out.push({ h, ...r });
        if (++done % 10000 === 0) log(`dns: ${done}/${todo.length} (${Math.round((Date.now() - t0) / 1000)}s)`);
    });
    out.flush();
    // one slower pass for answers that were not final (timeouts, SERVFAIL)
    const again = [...dns.entries()].filter(([, r]) => r.s === "transient").map(([h]) => h);
    if (again.length) {
        log(`dns: ${again.length} unclear, trying once more with lower concurrency`);
        const out2 = appender(dnsFile);
        await pool(again, 50, async (h) => {
            const r = await resolveHost(h);
            const fin = r.s === "transient" ? { s: "transient-final", a: [] } : r;
            dns.set(h, fin);
            out2.push({ h, ...fin });
        });
        out2.flush();
    }
}

// ---- phase 2: HTTP -----------------------------------------------------------------------------------------
function failCode(e) {
    if (e?.name === "TimeoutError" || e?.name === "AbortError") return "timeout";
    const m = String(e?.message ?? "");
    if (/private|not a public|credentials|is refused|only http|not a valid URL|did not resolve|cannot resolve/.test(m)) return "ditolak";
    const c = String(e?.cause?.code ?? "");
    if (c === "ENOTFOUND" || c === "EAI_AGAIN") return "dns";
    if (/CERT|TLS|SSL|SELF_SIGNED|ALTNAME/i.test(c) || /certificate|ssl|tls/i.test(String(e?.cause?.message ?? ""))) return "tls";
    if (/TIMEOUT|ETIMEDOUT/.test(c)) return "timeout";
    if (/ECONN|EPIPE|SOCKET|EHOSTUNREACH|ENETUNREACH/.test(c)) return "koneksi";
    return "jaringan";
}

async function probeOne(link, addrs) {
    try {
        await assertPublicUrl(link.url, { resolve: async () => addrs }); // refuses private / reserved addresses
        const res = await fetch(link.url, { headers: { "User-Agent": UA, Accept: "text/html" }, redirect: "manual", credentials: "omit", signal: AbortSignal.timeout(HTTP_TIMEOUT_MS) });
        const ct = (res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
        const loc = res.headers.get("location");
        let rd = "";
        if (res.status >= 300 && res.status < 400 && loc) {
            try {
                rd = hostOfUrl(new URL(loc, link.url)) === link.host ? "same" : "other";
            } catch {
                rd = "bad";
            }
        }
        await res.body?.cancel();
        return { id: link.id, st: res.status, ct, rd };
    } catch (e) {
        return { id: link.id, st: 0, r: failCode(e) };
    }
}

function interleave(links) {
    const byHost = new Map();
    for (const l of links) (byHost.get(l.host) ?? byHost.set(l.host, []).get(l.host)).push(l);
    const out = [];
    for (let r = 0, more = true; more; r++) {
        more = false;
        for (const q of byHost.values()) if (q.length > r) { out.push(q[r]); more = true; }
    }
    return out;
}

async function phaseHttp(links, dns, http) {
    const todo = interleave(links.filter((l) => dns.get(l.host)?.s === "ok" && !http.has(l.id)));
    log(`http: ${todo.length} links to probe (${http.size} already done)`);
    const out = appender(httpFile);
    const sem = new Map(); // host -> { active, waiters[] }
    const stats = new Map(); // host -> { tries, good }
    const acquire = async (h) => {
        const s = sem.get(h) ?? sem.set(h, { active: 0, waiters: [] }).get(h);
        if (s.active >= PER_HOST) await new Promise((res) => s.waiters.push(res));
        else s.active++;
    };
    const release = (h) => {
        const s = sem.get(h);
        const next = s.waiters.shift();
        if (next) next(); // slot passes straight to the waiter
        else s.active--;
    };
    let done = 0;
    const t0 = Date.now();
    await pool(todo, CONCURRENCY, async (link) => {
        await acquire(link.host);
        let rec;
        try {
            const st = stats.get(link.host) ?? stats.set(link.host, { tries: 0, good: 0 }).get(link.host);
            if (st.tries >= HOST_GIVE_UP && st.good === 0) {
                rec = { id: link.id, st: 0, r: "host_skipped" };
            } else {
                rec = await probeOne(link, dns.get(link.host).a);
                st.tries++;
                if (rec.st >= 200 && rec.st < 400) st.good++;
            }
        } finally {
            release(link.host);
        }
        http.set(link.id, rec);
        out.push(rec);
        if (++done % 5000 === 0) log(`http: ${done}/${todo.length} (${Math.round((Date.now() - t0) / 1000)}s)`);
    });
    out.flush();
}

// ---- phase 3: summary + alive list -------------------------------------------------------------------------
const isAlive = (r) => r && ((r.st >= 300 && r.st < 400) || (r.st >= 200 && r.st < 300 && /html/.test(r.ct ?? "")));
function bucket(link, dns, http) {
    const d = dns.get(link.host);
    if (!d) return "dns_belum";
    if (d.s === "nxdomain") return "dns_mati";
    if (d.s !== "ok") return "dns_tidak_jelas";
    const r = http.get(link.id);
    if (!r) return "http_belum";
    if (r.st === 0) return r.r === "host_skipped" ? "host_skipped" : `gagal_${r.r}`;
    if (r.st >= 200 && r.st < 300) return /html/.test(r.ct ?? "") ? "hidup_2xx_html" : "2xx_bukan_html";
    if (r.st >= 300 && r.st < 400) return `hidup_3xx_${r.rd || "tanpa_location"}`;
    if ([401, 403, 429].includes(r.st)) return `http_${r.st}`;
    if (r.st === 404 || r.st === 410) return "http_404_410";
    if (r.st === 451) return "http_451";
    return r.st >= 500 ? "http_5xx" : "http_4xx_lain";
}

function phaseSummary(links, dns, http) {
    const table = { scam: {}, legit: {} };
    const alive = [];
    for (const l of links) {
        const b = bucket(l, dns, http);
        table[l.label][b] = (table[l.label][b] ?? 0) + 1;
        if (isAlive(http.get(l.id)) && dns.get(l.host)?.s === "ok") alive.push(l);
    }
    const q = (s) => (/[",\n\r]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s);
    writeFileSync(aliveFile, "id,url,label\n" + alive.map((l) => `${l.id},${q(l.raw)},${l.label}`).join("\n") + "\n");
    const count = (label) => links.filter((l) => l.label === label).length;
    const summary = { total: links.length, scam: count("scam"), legit: count("legit"), alive: alive.length, aliveScam: alive.filter((l) => l.label === "scam").length, aliveLegit: alive.filter((l) => l.label === "legit").length, uniqueHosts: new Set(links.map((l) => l.host)).size, buckets: table };
    mkdirSync(probeDir, { recursive: true });
    writeFileSync(summaryFile, JSON.stringify(summary, null, 2));
    return summary;
}

// ---- main --------------------------------------------------------------------------------------------------
const { links, dropped } = loadLinks(Number(arg("--limit", 0)) || 0);
log(`links: ${links.length} (dropped ${dropped}), hosts: ${new Set(links.map((l) => l.host)).size}`);
mkdirSync(probeDir, { recursive: true });
const dns = new Map(loadJsonl(dnsFile).map((r) => [r.h, { s: r.s, a: r.a }]));
const http = new Map(loadJsonl(httpFile).map((r) => [r.id, r]));
if (!flag("--summary")) {
    await phaseDns(links, dns);
    await phaseHttp(links, dns, http);
}
const s = phaseSummary(links, dns, http);
log(`done: ${s.total} links (${s.scam} scam, ${s.legit} legit), alive for layer 3: ${s.alive} (scam ${s.aliveScam}, legit ${s.aliveLegit})`);
for (const label of ["scam", "legit"]) log(`${label}: ${JSON.stringify(s.buckets[label])}`);
