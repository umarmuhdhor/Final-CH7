#!/usr/bin/env node
// Layer 3 v2: run layer 3 only (form rules + content rules + domain age) on a new list of links, and keep, per link,
// the PageSnapshot that was scored and every signal that fired with its evidence, so the patterns can be checked by hand.
//
// Network: DNS + one static GET per link to the tested site (iPhone Safari user agent), and RDAP (domain names only).
// No JavaScript is run, no cookies, no form is filled or sent, nothing is clicked. Raw HTML is never written to disk: only
// the parsed snapshot is. Pages are attacker data: never executed, never followed beyond automatic redirects (max 3 hops:
// HTTP 3xx and <meta http-equiv="refresh">). Every hop is checked so a page cannot send us to localhost or the LAN.
// Layer 1, 2 and 4 are off: localSignals is empty (word weights are the "quiet" version) and there is no LLM.
// The console prints numbers only, never a URL or a domain.
//
// Use:  node run.mjs --links <file>     fetch + snapshot + score; links already in snapshots/ are skipped
//       node run.mjs --rescore          score the saved snapshots again, no network (saved domain age is reused)
//       node run.mjs --report           write HASIL.md and .hasil/detail.csv from snapshots/
// Opts: --links <file>      .csv (needs a `url` column; `id`, `label`/`jenis` optional), .json (array) or one link per line
//       --label scam|legit  label for rows without one (default scam)
//       --limit N           only the first N links
//       --concurrency N     parallel links (default 6)
//       --no-rdap           skip RDAP (new_domain never fires)
//       --retry-failed      fetch again the links whose last attempt failed
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeWithDomain } from "../../src/analyze.js";
import { hostOf, isOfficialHost } from "../../src/layer3/official.js";
import { registrableDomain } from "../../src/rdap/domain.js";
import { createRdapClient } from "../../src/rdap/rdap.js";
import { createMemoryCache } from "../../src/rdap/cache.js";
import { assertPublicUrl } from "../../eval/tools/safe-url.mjs";
import { parseHtml } from "../../eval/tools/snapshot.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const base = process.env.L3V2_OUT ?? here; // L3V2_OUT: another folder for trial runs, the real results stay untouched
const snapDir = join(base, "snapshots");
const outDir = join(base, ".hasil");
const hasilFile = join(base, "HASIL.md");
const detailFile = join(outDir, "detail.csv");

const arg = (name) => {
    const i = process.argv.indexOf(name);
    return i > -1 ? process.argv[i + 1] : undefined;
};
const flag = (name) => process.argv.includes(name);
const log = (s) => process.stderr.write(`${s}\n`);
const pct = (n, d) => (d ? `${((100 * n) / d).toFixed(1)}%` : "-");

const CAUGHT = 30; // layer 3 alone reaches "warning" from here
const MAX_BYTES = 2_000_000;
const MAX_HOPS = 3;
const TIMEOUT_MS = 15000;
const HTTPS_FIRST_TIMEOUT_MS = 8000; // link without a scheme: https first with a shorter limit, then http
const RDAP_TIMEOUT_MS = 5000; // production uses 1 s; longer here so the age is stable enough to study patterns
const EMPTY_CHARS = 200; // shorter text than this and no field = "kosong" (the page probably needs JavaScript)
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
const RETRY_WITH_HTTP = new Set(["tls", "koneksi", "jaringan", "timeout"]);
// parseHtml masks e-mail addresses with /[A-Z0-9._%+-]+@.../gi (eval/tools/patterns.mjs): quadratic on one long run of those
// characters, so a page with a 1 MB run (found at id 120774) freezes the whole run at 100% CPU. Such a page is not parsed.
const MAX_RUN = 20000;
function longestRun(s) {
    let best = 0;
    let cur = 0;
    for (let i = 0; i < s.length; i++) {
        const c = s.charCodeAt(i);
        if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 46 || c === 95 || c === 37 || c === 43 || c === 45) {
            if (++cur > best) best = cur;
        } else cur = 0;
    }
    return best;
}

// ---- links file --------------------------------------------------------------
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
/** Undo the usual "defanged" spelling (hxxp, [.]) so a pasted list still works. */
const refang = (raw) => String(raw).trim().replace(/^hxxp/i, "http").replace(/\[\.\]|\(\.\)/g, ".").replace(/\[:\]/g, ":");
/** The link as given; only `https://` is added when there is no scheme. null when it is not http(s). */
function toUrl(raw) {
    try {
        const u = new URL(hasScheme(raw) ? raw : `https://${raw}`);
        if (u.protocol !== "http:" && u.protocol !== "https:") return null;
        return u.hostname.includes(".") ? u : null;
    } catch {
        return null;
    }
}
const normLabel = (v, fallback) => {
    const t = String(v ?? "").trim().toLowerCase();
    if (/^(scam|phish|phishing|malicious|malware|defacement)/.test(t)) return "scam";
    if (/^(legit|normal|benign|safe|aman)/.test(t)) return "legit";
    return fallback;
};

function loadLinks(file, fallbackLabel) {
    const text = readFileSync(file, "utf8").replace(/^﻿/, "");
    const ext = extname(file).toLowerCase();
    let items;
    if (ext === ".json") {
        items = JSON.parse(text).map((x) => (typeof x === "string" ? { url: x } : x));
    } else if (ext === ".csv" || ext === ".tsv") {
        const rows = parseCsv(ext === ".tsv" ? text.replaceAll("\t", ",") : text);
        const head = rows[0].map((h) => h.trim().toLowerCase());
        const col = (...names) => head.findIndex((h) => names.includes(h));
        const iUrl = col("url", "link", "links", "tautan");
        if (iUrl < 0) throw new Error("the CSV has no `url` (or `link`) column in its first row");
        const iId = col("id");
        const iLabel = col("label", "jenis", "type");
        items = rows.slice(1).map((r) => ({ url: r[iUrl], id: iId < 0 ? undefined : r[iId], label: iLabel < 0 ? undefined : r[iLabel] }));
    } else {
        items = text.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#")).map((url) => ({ url }));
    }
    const seen = new Set();
    const out = [];
    let dropped = 0;
    for (const it of items) {
        const raw = refang(it.url ?? "");
        if (!raw || !toUrl(raw) || seen.has(raw)) {
            dropped++;
            continue;
        }
        seen.add(raw);
        out.push({ url: raw, id: it.id, label: normLabel(it.label, fallbackLabel) });
    }
    const width = Math.max(3, String(out.length).length);
    const ids = new Set();
    out.forEach((l, i) => {
        let id = String(l.id ?? "").trim().replace(/[^A-Za-z0-9_-]/g, "") || String(i + 1).padStart(width, "0");
        while (ids.has(id)) id += "x";
        ids.add(id);
        l.id = id;
    });
    return { links: out, dropped };
}

// ---- fetch -------------------------------------------------------------------
const fail = (code) => Object.assign(new Error(code), { code3: code });
const withCap = (p, ms) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(fail("timeout")), ms))]);

/** Failure reason as a short code. The original message is not kept: it can carry the host name. */
function reasonOf(e) {
    if (e?.code3) return e.code3;
    if (e?.name === "TimeoutError" || e?.name === "AbortError") return "timeout";
    const m = String(e?.message ?? "");
    if (/^cannot resolve|did not resolve/.test(m)) return "dns";
    if (/private|not a public|credentials|is refused|only http|not a valid URL/.test(m)) return "ditolak";
    const c = String(e?.cause?.code ?? "");
    if (c === "ENOTFOUND" || c === "EAI_AGAIN") return "dns";
    if (/CERT|TLS|SSL|SELF_SIGNED|ALTNAME/i.test(c) || /certificate|ssl|tls/i.test(String(e?.cause?.message ?? ""))) return "tls";
    if (/TIMEOUT|ETIMEDOUT/.test(c)) return "timeout";
    if (/ECONN|EPIPE|SOCKET|EHOSTUNREACH|ENETUNREACH/.test(c)) return "koneksi";
    return "jaringan";
}

/** Target of `<meta http-equiv="refresh" content="0; url=...">`: Safari follows it without a click. null when there is none. */
function metaRefreshTarget(html, baseUrl) {
    const tag = /<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*>/i.exec(html.replace(/<!--[\s\S]*?-->/g, ""))?.[0];
    const content = tag && /content\s*=\s*(?:"([^"]*)"|'([^']*)')/i.exec(tag);
    const target = content && /url\s*=\s*['"]?([^'"]+)/i.exec(content[1] ?? content[2] ?? "")?.[1];
    if (!target) return null;
    try {
        const u = new URL(target.trim().replace(/&amp;/g, "&"), baseUrl);
        return u.protocol === "http:" || u.protocol === "https:" ? u.href : null;
    } catch {
        return null;
    }
}

async function readCapped(res) {
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
    return Buffer.concat(chunks).toString("utf8");
}

async function fetchPage(startUrl, timeoutMs) {
    const signal = AbortSignal.timeout(timeoutMs);
    let url = startUrl;
    let hops = 0;
    let viaMeta = false;
    for (;;) {
        await assertPublicUrl(url);
        const res = await fetch(url, { headers: { "User-Agent": UA, Accept: "text/html" }, redirect: "manual", credentials: "omit", signal });
        const location = res.headers.get("location");
        if (res.status >= 300 && res.status < 400 && location) {
            await res.body?.cancel();
            if (++hops > MAX_HOPS) throw fail("redirect");
            try {
                url = new URL(location, url).href;
            } catch {
                throw fail("redirect");
            }
            continue;
        }
        if (!res.ok) {
            await res.body?.cancel();
            throw fail(`http_${res.status}`);
        }
        if (!/html/i.test(res.headers.get("content-type") || "")) {
            await res.body?.cancel();
            throw fail("bukan_html");
        }
        const html = await readCapped(res);
        const target = metaRefreshTarget(html, url);
        if (target && target !== url && hops < MAX_HOPS) {
            hops++;
            viaMeta = true;
            url = target;
            continue;
        }
        return { html, finalUrl: url, hops, viaMeta };
    }
}

// ---- layer 3 -----------------------------------------------------------------
const slim = (s) => (s.evidence ? { id: s.id, weight: s.weight, evidence: s.evidence } : { id: s.id, weight: s.weight });
const sum = (xs) => xs.reduce((a, b) => a + b, 0);

/** Layer 3 on one snapshot. `lookup(host)` gives the domain age; it is not called for official hosts. */
async function scoreSnapshot(snapshot, lookup) {
    const official = isOfficialHost(hostOf(snapshot.url));
    let asked = false;
    let domain = { registeredAt: null, ageDays: null };
    const rdap = lookup && {
        lookup: async (host) => {
            asked = true;
            domain = (await lookup(host)) ?? domain;
            return domain;
        },
    };
    const { signals } = await analyzeWithDomain(snapshot, { rdap: rdap || null });
    const kept = signals.filter((s) => s.layer === 3).map(slim);
    const score = Math.min(100, sum(kept.map((s) => s.weight)));
    return {
        rdap: { status: !lookup ? "mati" : !asked ? "dilewati" : domain.ageDays == null ? "gagal" : "ok", ageDays: domain.ageDays ?? null, registeredAt: domain.registeredAt ?? null },
        l3: {
            official,
            score,
            scoreNoAge: Math.min(100, sum(kept.filter((s) => s.id !== "new_domain").map((s) => s.weight))),
            caught: score >= CAUGHT,
            signals: kept,
        },
    };
}

const readRecords = () =>
    existsSync(snapDir)
        ? readdirSync(snapDir).filter((f) => f.endsWith(".json")).sort().map((f) => JSON.parse(readFileSync(join(snapDir, f), "utf8")))
        : [];
const writeRecord = (rec) => writeFileSync(join(snapDir, `${rec.id}.json`), `${JSON.stringify(rec, null, 2)}\n`);
/** v1 records say "terbuka" and keep the age in `rdapAgeDays`; both shapes are read. */
const isOpen = (r) => Boolean(r.snapshot) && r.status !== "gagal";
const ageOf = (r) => r.rdap?.ageDays ?? r.rdapAgeDays ?? null;

// ---- modes -------------------------------------------------------------------
async function runFetch() {
    const file = arg("--links");
    if (!file) throw new Error("give the list: node run.mjs --links <file>");
    const { links, dropped } = loadLinks(file, normLabel(arg("--label"), "scam"));
    const todoAll = links.slice(0, Number(arg("--limit") ?? Infinity));
    mkdirSync(snapDir, { recursive: true });
    const prior = new Map(readRecords().map((r) => [r.id, r]));
    const todo = todoAll.filter((l) => !prior.has(l.id) || (flag("--retry-failed") && prior.get(l.id).status === "gagal"));
    log(`links: ${links.length} valid, ${dropped} dropped (empty, not http(s), or repeated). To fetch now: ${todo.length}, already saved: ${todoAll.length - todo.length}`);

    let lookup = null;
    if (!flag("--no-rdap")) {
        const client = createRdapClient({ fetch, cache: createMemoryCache(), timeoutMs: RDAP_TIMEOUT_MS });
        const canary = await client.lookup("example.com").catch(() => null);
        if (canary?.ageDays == null) throw new Error("RDAP does not answer for example.com: check the network, or pass --no-rdap");
        lookup = (host) => client.lookup(host).catch(() => null);
    }

    async function visit(l) {
        const t0 = Date.now();
        const rec = { id: l.id, label: l.label, fetchedAt: new Date().toISOString(), originalUrl: l.url };
        const first = toUrl(l.url).href;
        const tries = hasScheme(l.url)
            ? [[first, TIMEOUT_MS]]
            : [
                  [first, HTTPS_FIRST_TIMEOUT_MS],
                  [first.replace(/^https:/, "http:"), TIMEOUT_MS],
              ];
        let got = null;
        let reason = null;
        for (const [url, ms] of tries) {
            try {
                got = await withCap(fetchPage(url, ms), ms + 5000);
                break;
            } catch (e) {
                reason = reasonOf(e);
                if (!RETRY_WITH_HTTP.has(reason)) break;
            }
        }
        if (!got) return { ...rec, status: "gagal", reason, ms: Date.now() - t0 };
        if (longestRun(got.html) >= MAX_RUN) return { ...rec, status: "gagal", reason: "teks_ekstrem", ms: Date.now() - t0 };
        try {
            const host = new URL(got.finalUrl).hostname.toLowerCase();
            const { snapshot, meta } = parseHtml(got.html, { url: got.finalUrl, domain: registrableDomain(host) ?? host, capturedAt: rec.fetchedAt });
            const fields = sum(snapshot.forms.map((f) => f.fields.length));
            const scored = await scoreSnapshot(snapshot, lookup);
            return {
                ...rec,
                finalUrl: got.finalUrl,
                status: snapshot.text.length < EMPTY_CHARS && fields === 0 ? "kosong" : "ok",
                movedHost: host.replace(/^www\./, "") !== toUrl(l.url).hostname.toLowerCase().replace(/^www\./, ""),
                hops: got.hops,
                viaMetaRefresh: got.viaMeta,
                bytes: meta.bytes,
                iframes: meta.iframes,
                scriptTags: (got.html.match(/<script\b/gi) || []).length,
                ...scored,
                snapshot,
                ms: Date.now() - t0,
            };
        } catch {
            return { ...rec, status: "gagal", reason: "galat_urai", ms: Date.now() - t0 };
        }
    }

    const t0 = Date.now();
    let next = 0;
    let finished = 0;
    const counts = { ok: 0, kosong: 0, gagal: 0 };
    async function worker() {
        for (;;) {
            const l = todo[next++];
            if (!l) return;
            const rec = await visit(l);
            writeRecord(rec);
            counts[rec.status]++;
            if (++finished % 25 === 0) log(`  ${finished}/${todo.length}: ok ${counts.ok}, kosong ${counts.kosong}, gagal ${counts.gagal}, ${Math.round((Date.now() - t0) / 1000)} s`);
        }
    }
    await Promise.all(Array.from({ length: Math.max(1, Number(arg("--concurrency") ?? 6)) }, worker));
    log(`done: ${finished} fetched in ${Math.round((Date.now() - t0) / 1000)} s. ok ${counts.ok}, kosong ${counts.kosong}, gagal ${counts.gagal}`);
    printSummary(readRecords());
}

async function runRescore() {
    const recs = readRecords();
    let changed = 0;
    for (const rec of recs) {
        if (!isOpen(rec)) continue;
        const age = ageOf(rec);
        const before = JSON.stringify(rec.l3?.signals ?? null);
        const scored = await scoreSnapshot(rec.snapshot, age == null ? null : async () => ({ ageDays: age, registeredAt: rec.rdap?.registeredAt ?? null }));
        rec.l3 = scored.l3;
        if (!rec.rdap) rec.rdap = { status: age == null ? "gagal" : "ok", ageDays: age, registeredAt: null };
        if (JSON.stringify(rec.l3.signals) !== before) changed++;
        writeRecord(rec);
    }
    log(`rescored ${recs.filter(isOpen).length} snapshots, signals changed on ${changed}`);
    printSummary(recs);
}

function printSummary(recs) {
    for (const label of [...new Set(recs.map((r) => r.label))].sort()) {
        const rs = recs.filter((r) => r.label === label);
        const open = rs.filter(isOpen);
        log(`${label}: ${rs.length} links, opened ${open.length} (kosong ${open.filter((r) => r.status === "kosong").length}), failed ${rs.length - open.length}, caught (>= ${CAUGHT}) ${open.filter((r) => r.l3?.caught).length} of ${open.length} opened`);
    }
}

// ---- report ------------------------------------------------------------------
const cell = (v, max = 80) => {
    const t = String(v ?? "").replace(/\s+/g, " ").replace(/\|/g, "\\|").trim();
    return t.length > max ? `${t.slice(0, max - 1)}…` : t || "-";
};
const defang = (host) => String(host ?? "").replaceAll(".", "[.]");
const hostOfRec = (r) => {
    try {
        return new URL(r.finalUrl ?? r.snapshot?.url ?? toUrl(r.originalUrl).href).hostname.toLowerCase();
    } catch {
        return "";
    }
};
const fieldsOf = (r) => (r.snapshot?.forms ?? []).flatMap((f) => f.fields);
const fieldText = (f) => `${f.type}:${[f.name, f.id, f.placeholder, f.label].filter(Boolean).join("/") || "-"}`;
const sigText = (r) => (r.l3?.signals ?? []).map((s) => `${s.id}:${s.weight}${s.evidence ? ` (${s.evidence})` : ""}`).join(", ") || "-";
function tally(values) {
    const m = new Map();
    for (const v of values) m.set(v, (m.get(v) ?? 0) + 1);
    return [...m.entries()].sort((a, b) => b[1] - a[1] || (String(a[0]) < String(b[0]) ? -1 : 1));
}
const table = (head, rows) => [`| ${head.join(" | ")} |`, `|${head.map(() => "---").join("|")}|`, ...rows.map((r) => `| ${r.join(" | ")} |`)].join("\n");
const csvCell = (v) => {
    const t = String(v ?? "");
    return /[",\n\r]/.test(t) ? `"${t.replaceAll('"', '""')}"` : t;
};

function runReport() {
    const recs = readRecords();
    if (!recs.length) throw new Error("snapshots/ is empty: run `node run.mjs --links <file>` first");
    mkdirSync(outDir, { recursive: true });
    const open = recs.filter(isOpen);
    const failed = recs.filter((r) => !isOpen(r));
    const labels = [...new Set(recs.map((r) => r.label))].sort();
    const L = [];
    const p = (s = "") => L.push(s);

    p("# Hasil layer 3 v2: snapshot dan sinyal per link");
    p();
    p(`_Dibuat oleh \`node run.mjs --report\` dari \`snapshots/\` pada ${new Date().toISOString()}. Jangan edit di atas bagian "Analisis"._`);
    p();
    p("## 0. Cara baca");
    p();
    p("- **Lingkup: hanya layer 3** (rule form + rule konten + umur domain). Layer 1, 2, 4 mati: `localSignals` kosong (bobot kata versi quiet), tanpa LLM.");
    p(`- Skor = jumlah bobot sinyal, maks 100. **Tertangkap = skor ≥ ${CAUGHT}.** "Tanpa umur" = skor tanpa \`new_domain\`.`);
    p("- Snapshot dibuat dari **HTML statis** halaman pertama (UA Safari iPhone, tanpa JavaScript). Form atau teks yang dibangun JavaScript **tidak terlihat** di sini, padahal terlihat oleh ekstensi. Status `kosong` = teks < 200 karakter dan tanpa kolom isian (kemungkinan halaman butuh JavaScript).");
    p(`- Redirect otomatis diikuti maks ${MAX_HOPS} lompatan (HTTP 3xx dan \`<meta refresh>\`). Redirect lewat JavaScript tidak diikuti.`);
    p(`- Umur domain: RDAP live, batas ${RDAP_TIMEOUT_MS / 1000} dtk (produksi 1 dtk), supaya umur lebih stabil untuk dibaca polanya.`);
    p("- Snapshot lengkap per link (teks, form, alt gambar) dan sinyal + bukti: `snapshots/<id>.json`. Tabel datar untuk spreadsheet: `.hasil/detail.csv`.");
    p("- Host ditulis dengan `[.]` supaya tidak bisa diklik. Jangan buka link di browser.");
    p();

    p("## 1. Ringkasan");
    p();
    p(
        table(
            ["label", "link", "terbuka", "ok", "kosong", "gagal", `tertangkap (≥ ${CAUGHT})`, "tanpa umur", "skor median", "skor maks"],
            labels.map((label) => {
                const rs = recs.filter((r) => r.label === label);
                const op = rs.filter(isOpen);
                const scores = op.map((r) => r.l3.score).sort((a, b) => a - b);
                return [
                    label,
                    rs.length,
                    `${op.length} (${pct(op.length, rs.length)})`,
                    op.filter((r) => r.status !== "kosong").length,
                    op.filter((r) => r.status === "kosong").length,
                    rs.length - op.length,
                    `${op.filter((r) => r.l3.caught).length} (${pct(op.filter((r) => r.l3.caught).length, op.length)})`,
                    `${op.filter((r) => r.l3.scoreNoAge >= CAUGHT).length} (${pct(op.filter((r) => r.l3.scoreNoAge >= CAUGHT).length, op.length)})`,
                    scores.length ? scores[scores.length >> 1] : "-",
                    scores.length ? scores[scores.length - 1] : "-",
                ];
            }),
        ),
    );
    p();
    p("Persen tertangkap dihitung dari halaman yang **terbuka**, bukan dari semua link.");
    p();
    const buckets = [
        ["0", (s) => s === 0],
        ["1–29", (s) => s > 0 && s < 30],
        ["30–49", (s) => s >= 30 && s < 50],
        ["50–79", (s) => s >= 50 && s < 80],
        ["≥ 80", (s) => s >= 80],
    ];
    p("### Sebaran skor (halaman terbuka)");
    p();
    p(table(["label", ...buckets.map((b) => b[0])], labels.map((label) => [label, ...buckets.map(([, test]) => open.filter((r) => r.label === label && test(r.l3.score)).length)])));
    p();
    if (failed.length) {
        p("### Alasan gagal dibuka");
        p();
        p(table(["alasan", "jumlah"], tally(failed.map((r) => r.reason ?? "tidak diketahui")).map(([k, n]) => [k, n])));
        p();
    }

    p("## 2. Sinyal yang menyala");
    p();
    const sigRows = open.flatMap((r) => r.l3.signals.map((s) => ({ ...s, label: r.label })));
    p(
        table(
            ["sinyal", "bobot", ...labels.map((l) => `halaman ${l}`), "bukti paling sering (jumlah)"],
            tally(sigRows.map((s) => s.id)).map(([id]) => {
                const mine = sigRows.filter((s) => s.id === id);
                const weights = [...new Set(mine.map((s) => s.weight))].sort((a, b) => a - b).join(" / ");
                const ev = tally(mine.filter((s) => s.evidence).map((s) => s.evidence.toLowerCase())).slice(0, 8);
                return [
                    `\`${id}\``,
                    weights,
                    ...labels.map((l) => `${mine.filter((s) => s.label === l).length} (${pct(mine.filter((s) => s.label === l).length, open.filter((r) => r.label === l).length)})`),
                    cell(ev.map(([k, n]) => `${k} (${n})`).join(" · "), 300),
                ];
            }),
        ),
    );
    p();
    p(`Tanpa sinyal sama sekali: ${labels.map((l) => `${l} ${open.filter((r) => r.label === l && !r.l3.signals.length).length}`).join(", ")}.`);
    p();
    p("### Kombinasi sinyal");
    p();
    const comboOf = (r) => r.l3.signals.map((s) => s.id).sort().join(" + ") || "(tanpa sinyal)";
    p(
        table(
            ["kombinasi", ...labels.map((l) => l), "skor (min–maks)", "tertangkap"],
            tally(open.map(comboOf)).map(([combo, n]) => {
                const rs = open.filter((r) => comboOf(r) === combo);
                const sc = rs.map((r) => r.l3.score);
                return [cell(combo, 120), ...labels.map((l) => rs.filter((r) => r.label === l).length), `${Math.min(...sc)}–${Math.max(...sc)}`, `${rs.filter((r) => r.l3.caught).length} / ${n}`];
            }),
        ),
    );
    p();

    p("## 3. Pola snapshot");
    p();
    const split = (name, test) => [
        name,
        ...labels.flatMap((l) => {
            const rs = open.filter((r) => r.label === l && test(r));
            return [rs.length, `${rs.filter((r) => r.l3.caught).length} (${pct(rs.filter((r) => r.l3.caught).length, rs.length)})`];
        }),
    ];
    const splitHead = ["kelompok", ...labels.flatMap((l) => [`${l}`, `${l} tertangkap`])];
    p("### Form");
    p();
    p(
        table(splitHead, [
            split("tanpa kolom isian", (r) => fieldsOf(r).length === 0),
            split("1 kolom", (r) => fieldsOf(r).length === 1),
            split("2–3 kolom", (r) => fieldsOf(r).length >= 2 && fieldsOf(r).length <= 3),
            split("≥ 4 kolom", (r) => fieldsOf(r).length >= 4),
            split("ada kolom `type=password`", (r) => fieldsOf(r).some((f) => f.type === "password")),
            split("ada iframe", (r) => (r.iframes?.length ?? 0) > 0),
            split("status kosong", (r) => r.status === "kosong"),
            split("pindah host (redirect)", (r) => r.movedHost === true),
        ]),
    );
    p();
    p("### Kolom isian paling sering (`type:name/id/placeholder/label`, halaman scam terbuka)");
    p();
    const scamOpen = open.filter((r) => r.label === "scam");
    const perPage = (fn) => scamOpen.flatMap((r) => [...new Set(fieldsOf(r).map(fn).filter(Boolean))]);
    p(table(["kolom", "halaman"], tally(perPage((f) => fieldText(f).toLowerCase())).slice(0, 30).map(([k, n]) => [cell(k, 100), n])));
    p();
    p("### Judul halaman yang berulang (≥ 2 halaman)");
    p();
    const titleOf = (r) => (r.snapshot.title || "(tanpa judul)").trim();
    const titles = tally(open.map(titleOf)).filter(([, n]) => n >= 2).slice(0, 30);
    p(titles.length ? table(["judul", "halaman", "tertangkap"], titles.map(([t, n]) => [cell(t, 90), n, open.filter((r) => titleOf(r) === t && r.l3.caught).length])) : "Tidak ada judul yang berulang.");
    p();
    p("### Domain induk paling sering (halaman terbuka)");
    p();
    const domOf = (r) => registrableDomain(hostOfRec(r)) ?? hostOfRec(r);
    p(table(["domain induk", "halaman", "tertangkap"], tally(open.map(domOf)).slice(0, 25).map(([d, n]) => [defang(d), n, open.filter((r) => domOf(r) === d && r.l3.caught).length])));
    p();
    p("### Umur domain (RDAP)");
    p();
    const ageBuckets = [
        ["< 30 hari", (a) => a !== null && a < 30],
        ["30–179 hari", (a) => a !== null && a >= 30 && a < 180],
        ["180–364 hari", (a) => a !== null && a >= 180 && a < 365],
        ["≥ 1 tahun", (a) => a !== null && a >= 365],
        ["tidak diketahui", (a) => a === null],
    ];
    p(table(splitHead, ageBuckets.map(([name, test]) => split(name, (r) => test(ageOf(r))))));
    p();
    p("### Bahasa (`lang`)");
    p();
    p(table(["lang", "halaman"], tally(open.map((r) => r.snapshot.lang ?? "(kosong)")).slice(0, 12).map(([k, n]) => [k, n])));
    p();

    const perSite = (rs) =>
        table(
            ["id", "label", "host", "status", "skor", "tanpa umur", "umur (hari)", "sinyal (bukti)", "judul", "kolom isian", "teks awal"],
            rs.map((r) => [
                r.id,
                r.label,
                defang(hostOfRec(r)),
                r.status,
                r.l3.score,
                r.l3.scoreNoAge,
                ageOf(r) ?? "-",
                cell(sigText(r), 200),
                cell(r.snapshot.title, 60),
                cell(fieldsOf(r).map(fieldText).join("; "), 140),
                cell(r.snapshot.text, 100),
            ]),
        );
    const byScore = (a, b) => a.l3.score - b.l3.score || (a.id < b.id ? -1 : 1);
    p(`## 4. Scam yang lolos (skor < ${CAUGHT})`);
    p();
    const missed = scamOpen.filter((r) => !r.l3.caught).sort(byScore);
    p(missed.length ? perSite(missed) : "Tidak ada.");
    p();
    if (labels.includes("legit")) {
        const legitHit = open.filter((r) => r.label === "legit" && r.l3.caught);
        p(`## 5. Legit yang kena (skor ≥ ${CAUGHT})`);
        p();
        p(legitHit.length ? perSite(legitHit.sort(byScore)) : "Tidak ada.");
        p();
    }
    p("## 6. Semua halaman terbuka");
    p();
    p(perSite([...open].sort((a, b) => (a.id < b.id ? -1 : 1))));
    p();
    if (failed.length) {
        p("## 7. Gagal dibuka");
        p();
        p(table(["id", "label", "host", "alasan"], failed.map((r) => [r.id, r.label, defang(toUrl(r.originalUrl)?.hostname ?? ""), r.reason ?? "-"])));
        p();
    }
    p("## Analisis");
    p();
    p("_Belum ditulis._");
    p();
    writeFileSync(hasilFile, L.join("\n"));

    const head = ["id", "label", "status", "alasan", "url", "final_url", "host", "domain_induk", "pindah_host", "rdap_status", "rdap_umur_hari", "skor_l3", "skor_tanpa_umur", "tertangkap", "sinyal", "bukti", "judul", "lang", "panjang_teks", "jumlah_form", "jumlah_kolom", "kolom", "alt_gambar", "iframe", "teks_awal"];
    const rows = recs.map((r) => {
        const o = isOpen(r);
        return [
            r.id,
            r.label,
            r.status,
            r.reason ?? "",
            r.originalUrl,
            r.finalUrl ?? "",
            o ? hostOfRec(r) : (toUrl(r.originalUrl)?.hostname ?? ""),
            o ? domOf(r) : "",
            o ? (r.movedHost ? "ya" : "tidak") : "",
            r.rdap?.status ?? "",
            o ? (ageOf(r) ?? "") : "",
            o ? r.l3.score : "",
            o ? r.l3.scoreNoAge : "",
            o ? (r.l3.caught ? "ya" : "tidak") : "",
            o ? r.l3.signals.map((s) => `${s.id}:${s.weight}`).join(" | ") : "",
            o ? r.l3.signals.filter((s) => s.evidence).map((s) => `${s.id}=${s.evidence}`).join(" | ") : "",
            o ? r.snapshot.title : "",
            o ? (r.snapshot.lang ?? "") : "",
            o ? r.snapshot.text.length : "",
            o ? r.snapshot.forms.length : "",
            o ? fieldsOf(r).length : "",
            o ? fieldsOf(r).map(fieldText).join(" ; ") : "",
            o ? (r.snapshot.imageAlts ?? []).join(" ; ") : "",
            o ? (r.iframes?.length ?? 0) : "",
            o ? r.snapshot.text.slice(0, 300).replace(/\s+/g, " ") : "",
        ];
    });
    writeFileSync(detailFile, `${[head, ...rows].map((r) => r.map(csvCell).join(",")).join("\n")}\n`);
    log(`wrote HASIL.md (${L.length} lines) and .hasil/detail.csv (${rows.length} rows)`);
    printSummary(recs);
}

if (flag("--report")) runReport();
else if (flag("--rescore")) await runRescore();
else await runFetch();
