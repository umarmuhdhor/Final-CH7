#!/usr/bin/env node
// L3 penuh: skor dan waktu 35 snapshot lewat POST /analyze (dev-server.mjs, 127.0.0.1), RDAP live, plus prototipe Telegram.
// Plan: PLAN-L3-PENUH.md. Hasil: HASIL-L3-PENUH.md. Mentah: .hasil/l3-penuh.json (di-gitignore).
//
// Pengecualian khusus uji ini (izin Imelda): RDAP live ke 35 domain termasuk scam. Yang dihubungi server registry dan
// bootstrap IANA, bukan situs scam. Tidak ada permintaan ke situs scam, tidak ada HTML baru.
// LLM harus mati: skrip menolak jalan kalau ada baris LLM_* aktif di ai/.env atau di environment, dan menyaring LLM_*
// dari environment server yang dijalankannya. Isi .env tidak pernah masuk ke keluaran.
//
// Pakai:  node l3-penuh.mjs [--modes inproc,tele,off,on,cold] [--reps 5]   jalankan pengukuran (hasil digabung ke JSON)
//         node l3-penuh.mjs --report                                       cetak tabel markdown dari JSON
import { spawn, execFileSync } from "node:child_process";
import { once } from "node:events";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { cpus } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeSnapshot } from "../src/analyze.js";
import { buildNewDomainSignal } from "../src/layer3/signals.js";
import { hostOf, isOfficialHost } from "../src/layer3/official.js";
import { registrableDomain } from "../src/rdap/domain.js";
import "./ukur-safari/pola.js";

const { scanTeks } = globalThis.ShooPola;
const here = dirname(fileURLToPath(import.meta.url));
const aiDir = join(here, "..");
const snapDir = join(here, "snapshots");
const htmlDir = join(here, ".html");
const outDir = join(here, ".hasil");
const outFile = join(outDir, "l3-penuh.json");
const DEV_SERVER = join(aiDir, "src", "dev-server.mjs");

const arg = (name, fallback) => {
    const i = process.argv.indexOf(name);
    return i > -1 ? process.argv[i + 1] : fallback;
};
const REPS = Number(arg("--reps", 5)); // run pertama tiap situs dibuang
const MODES = new Set(String(arg("--modes", "inproc,tele,off,on,cold")).split(","));
const HTTP_TIMEOUT_MS = 8000; // ekstensi menyerah di 8 dtk

// ---- statistik ---------------------------------------------------------------
const sorted = (xs) => [...xs].sort((a, b) => a - b);
const median = (xs) => {
    const s = sorted(xs);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
/** nearest-rank */
const pctl = (xs, p) => sorted(xs)[Math.max(0, Math.ceil((p / 100) * xs.length) - 1)];
const summarize = (xs) => (xs.length ? { n: xs.length, median: median(xs), p95: pctl(xs, 95), max: Math.max(...xs) } : null);

// ---- data --------------------------------------------------------------------
async function loadRecords() {
    const files = (await readdir(snapDir)).filter((f) => f.endsWith(".json")).sort();
    const recs = [];
    for (const f of files) recs.push(JSON.parse(await readFile(join(snapDir, f), "utf8")));
    // scam 01..25 dulu, lalu L01..L10
    return recs.sort((a, b) => (a.id.startsWith("L") - b.id.startsWith("L")) || (a.id < b.id ? -1 : 1));
}

const slim = (s) => {
    const age = /^Domain age (\d+) /.exec(s.label?.en ?? "")?.[1];
    return age === undefined ? { id: s.id, weight: s.weight } : { id: s.id, weight: s.weight, age: Number(age) };
};

// ---- server ------------------------------------------------------------------
function assertLlmOff(envText) {
    if (/^LLM_/m.test(envText)) throw new Error("ada baris LLM_* aktif di ai/.env: comment dulu (isi tidak dicetak)");
    if (Object.keys(process.env).some((k) => k.startsWith("LLM_"))) throw new Error("ada LLM_* di environment shell");
}

async function startServer({ rdap, port }) {
    const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith("LLM_") && !k.startsWith("SHOO_")));
    env.PORT = String(port);
    if (rdap) env.SHOO_RDAP = "1";
    const child = spawn(process.execPath, [DEV_SERVER], { env, stdio: ["ignore", "pipe", "pipe"] });
    child.stderr.resume();
    await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("server tidak mulai")), 10_000);
        child.stdout.on("data", (d) => {
            if (String(d).includes("listening")) {
                clearTimeout(timer);
                resolve();
            }
        });
        child.once("exit", (code) => reject(new Error(`server berhenti (${code})`)));
    });
    return { child, base: `http://127.0.0.1:${port}` };
}

async function stopServer(server) {
    if (server.child.exitCode !== null) return;
    server.child.kill("SIGTERM");
    await once(server.child, "exit");
}

/** Wajib 0 panggilan LLM. Tanpa konfigurasi LLM server menjawab {"off":true}. Selain itu: berhenti. */
async function layer4Check(base) {
    const j = await (await fetch(`${base}/_dev/layer4`)).json();
    if (j.off === true) return "off";
    const total = j.outcomes ? Object.values(j.outcomes).reduce((a, b) => a + Number(b), 0) : NaN;
    if (total === 0) return "0";
    throw new Error(`/_dev/layer4 bukan 0 panggilan: ${JSON.stringify(j)}`);
}

async function analyzeOnce(base, body) {
    const t0 = performance.now();
    let status = 0;
    let signals = null;
    let err = null;
    try {
        const res = await fetch(`${base}/analyze`, { method: "POST", headers: { "content-type": "application/json" }, body, signal: AbortSignal.timeout(HTTP_TIMEOUT_MS) });
        status = res.status;
        const j = await res.json();
        if (Array.isArray(j.signals)) signals = j.signals.map(slim);
        else err = `status ${status}`;
    } catch (e) {
        err = e?.name ?? "error";
    }
    return { ms: performance.now() - t0, status, signals, err };
}

// ---- Telegram (prototipe, bukan kode src/) -----------------------------------
const SCRIPT_RE = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
const FORM_ACTION_RE = /<form\b[^>]*?\baction\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi;
const SRC_RE = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i;

// Sama dengan extract() di ukur-telegram.mjs: isi <script> inline dan atribut action form; <script src> tidak dibaca.
function scanHtml(html) {
    const parts = [];
    for (const m of html.matchAll(SCRIPT_RE)) if (!SRC_RE.test(m[1])) parts.push(m[2]);
    for (const m of html.matchAll(FORM_ACTION_RE)) parts.push(m[1] ?? m[2] ?? m[3]);
    return scanTeks(parts.join("\n"));
}

/** Bobot kandidat: token +35, host+method +30, host +10. Ambil yang tertinggi, tidak dijumlah. */
const telegramWeight = (h) => Math.max(h.token ? 35 : 0, h.host && h.method ? 30 : 0, h.host ? 10 : 0);

// ---- fase --------------------------------------------------------------------
async function phaseInproc(recs) {
    const rows = {};
    for (const rec of recs) {
        const ts = [];
        let signals;
        for (let r = 0; r < REPS; r++) {
            const t0 = performance.now();
            signals = analyzeSnapshot(rec.snapshot);
            ts.push(performance.now() - t0);
        }
        rows[rec.id] = { ms: ts.slice(1), signals: signals.map(slim) };
    }
    const all = Object.values(rows).flatMap((r) => r.ms);
    return { rows, pooled: summarize(all) };
}

async function phaseTele(recs) {
    const rows = {};
    for (const rec of recs) {
        const html = await readFile(join(htmlDir, `${rec.id}-desktop.html`), "utf8").catch(() => "");
        if (!html) {
            rows[rec.id] = { readable: false, weight: 0 };
            continue;
        }
        const ts = [];
        let hit;
        for (let r = 0; r < REPS; r++) {
            const t0 = performance.now();
            hit = scanHtml(html);
            ts.push(performance.now() - t0);
        }
        rows[rec.id] = { readable: true, hit, weight: telegramWeight(hit), ms: ts.slice(1), htmlKB: html.length / 1024 };
    }
    const all = Object.values(rows).flatMap((r) => r.ms ?? []);
    return { rows, pooled: summarize(all) };
}

/** Satu server, REPS putaran x semua situs. rdap=false: C1. rdap=true: putaran 0 = Lapis A (dan pemanasan), putaran 1.. = hangat. */
async function phaseServer(recs, bodies, { rdap, port }) {
    const server = await startServer({ rdap, port });
    try {
        const l4before = await layer4Check(server.base);
        const rounds = [];
        for (let r = 0; r < REPS; r++) {
            const round = {};
            for (const rec of recs) round[rec.id] = await analyzeOnce(server.base, bodies[rec.id]);
            rounds.push(round);
            process.stderr.write(`  ${rdap ? "rdap-on" : "rdap-off"} putaran ${r + 1}/${REPS}\n`);
        }
        const l4after = await layer4Check(server.base);
        return { rounds, layer4: { before: l4before, after: l4after } };
    } finally {
        await stopServer(server);
    }
}

/** RDAP dingin: server baru untuk SETIAP permintaan (cache dan bootstrap IANA kosong). Putaran luar = ulangan, supaya satu registry tidak diketik 5 kali berturutan. */
async function phaseCold(recs, bodies, warmBody) {
    const rounds = [];
    const warmups = [];
    const l4 = [];
    let port = 8790;
    for (let r = 0; r < REPS; r++) {
        const round = {};
        for (const rec of recs) {
            const server = await startServer({ rdap: true, port });
            port = port >= 8889 ? 8790 : port + 1; // port beda: koneksi keep-alive ke server lama tidak terpakai lagi
            try {
                // Satu permintaan ke host resmi (RDAP dilewati) memanaskan JIT server tanpa menyentuh cache RDAP atau bootstrap.
                warmups.push((await analyzeOnce(server.base, warmBody)).ms);
                round[rec.id] = await analyzeOnce(server.base, bodies[rec.id]);
                l4.push(await layer4Check(server.base));
            } finally {
                await stopServer(server);
            }
        }
        rounds.push(round);
        process.stderr.write(`  rdap-dingin ulangan ${r + 1}/${REPS}\n`);
    }
    return { rounds, warmups, layer4: { checks: l4.length, all: [...new Set(l4)] } };
}

// ---- main --------------------------------------------------------------------
async function measure() {
    assertLlmOff(await readFile(join(aiDir, ".env"), "utf8").catch(() => ""));
    await mkdir(outDir, { recursive: true });
    const prev = await readFile(outFile, "utf8").then(JSON.parse).catch(() => ({}));
    const recs = await loadRecords();
    const bodies = Object.fromEntries(recs.map((rec) => [rec.id, JSON.stringify({ snapshot: rec.snapshot, localSignals: [] })]));
    const warmSnap = { ...recs[0].snapshot, url: "https://www.bca.co.id/", domain: "bca.co.id" };
    if (!isOfficialHost("www.bca.co.id")) throw new Error("host pemanasan tidak resmi lagi");
    const warmBody = JSON.stringify({ snapshot: warmSnap, localSignals: [] });

    const git = (...a) => execFileSync("git", a, { cwd: aiDir, encoding: "utf8" }).trim();
    const out = {
        ...prev,
        meta: {
            ...prev.meta,
            node: process.version,
            commit: git("rev-parse", "--short", "HEAD"),
            uncommitted: git("status", "--short", "src", "test").split("\n").filter(Boolean),
            cpu: cpus()[0]?.model,
            reps: REPS,
            ids: recs.map((r) => r.id),
            startedAt: prev.meta?.startedAt ?? new Date().toISOString(),
        },
    };
    const save = () => writeFile(outFile, JSON.stringify(out));

    if (MODES.has("inproc")) {
        process.stderr.write("rules in-process\n");
        out.inproc = await phaseInproc(recs);
        await save();
    }
    if (MODES.has("tele")) {
        process.stderr.write("telegram\n");
        out.tele = await phaseTele(recs);
        await save();
    }
    if (MODES.has("off")) {
        out.off = await phaseServer(recs, bodies, { rdap: false, port: 8787 });
        await save();
    }
    if (MODES.has("on")) {
        out.on = await phaseServer(recs, bodies, { rdap: true, port: 8786 });
        out.on.finishedAt = new Date().toISOString();
        await save();
    }
    if (MODES.has("cold")) {
        out.cold = await phaseCold(recs, bodies, warmBody);
        out.cold.finishedAt = new Date().toISOString();
        await save();
    }
    process.stderr.write(`selesai, ${outFile}\n`);
}

// ---- laporan -----------------------------------------------------------------
const ms = (x) => (x === undefined || x === null ? "-" : x >= 100 ? x.toFixed(0) : x >= 1 ? x.toFixed(1) : x.toFixed(3));
const cap = (n) => Math.min(100, n);
const sum = (signals, pick = () => true) => signals.filter(pick).reduce((s, x) => s + x.weight, 0);
const isDomain = (s) => s.id === "new_domain";

async function report() {
    const d = JSON.parse(await readFile(outFile, "utf8"));
    const recs = await loadRecords();
    const byId = Object.fromEntries(recs.map((r) => [r.id, r]));
    const ids = d.meta.ids;
    const scamIds = ids.filter((i) => !i.startsWith("L"));
    const legitIds = ids.filter((i) => i.startsWith("L"));
    const lines = [];
    const p = (s = "") => lines.push(s);

    // ---- skor per situs
    const A = d.on.rounds[0]; // Lapis A: putaran pertama, server baru
    const rows = ids.map((id) => {
        const rec = byId[id];
        const a = A[id];
        const sig = a.signals ?? [];
        const rulesW = sum(sig, (s) => !isDomain(s));
        const todaySig = sig.find(isDomain);
        const frozenSig = rec.rdapAgeDays == null ? null : buildNewDomainSignal(rec.rdapAgeDays);
        const frozenW = frozenSig?.weight ?? 0;
        const todayW = todaySig?.weight ?? 0;
        const tele = d.tele.rows[id];
        const teleW = tele.weight;
        const host = hostOf(rec.snapshot.url);
        return {
            id,
            legit: id.startsWith("L"),
            rulesW,
            frozenAge: rec.rdapAgeDays,
            frozenW,
            todayAge: todaySig?.age ?? null,
            todayW,
            teleW,
            tele,
            sFrozen: cap(rulesW + frozenW),
            sToday: cap(rulesW + todayW),
            sTele: cap(rulesW + todayW + teleW),
            host,
            official: isOfficialHost(host),
            noDomain: !registrableDomain(host),
            httpErr: a.err,
        };
    });
    const count = (grp, key, th) => grp.filter((r) => r[key] >= th).length;
    const sc = rows.filter((r) => !r.legit);
    const lg = rows.filter((r) => r.legit);

    p("## 1. Tangkapan per versi");
    p("");
    p("| versi | scam ≥ 30 | scam ≥ 50 | scam ≥ 80 | legit ≥ 30 | legit maks |");
    p("|---|---:|---:|---:|---:|---:|");
    for (const [label, key] of [["field + umur beku", "sFrozen"], ["field + umur hari ini (RDAP live)", "sToday"], ["field + umur hari ini + Telegram", "sTele"]]) {
        p(`| ${label} | ${count(sc, key, 30)} / ${sc.length} | ${count(sc, key, 50)} / ${sc.length} | ${count(sc, key, 80)} / ${sc.length} | ${count(lg, key, 30)} / ${lg.length} | ${Math.max(...lg.map((r) => r[key]))} |`);
    }
    p("");
    for (const [label, key] of [["umur beku", "sFrozen"], ["umur hari ini", "sToday"], ["+ Telegram", "sTele"]]) {
        p(`- Tidak tertangkap (< 30), ${label}: ${sc.filter((r) => r[key] < 30).map((r) => `${r.id} (${r[key]})`).join(", ") || "-"}`);
    }
    const flipTele = sc.filter((r) => r.sToday < 30 && r.sTele >= 30).map((r) => r.id);
    p(`- Situs yang berubah status karena Telegram: ${flipTele.join(", ") || "tidak ada"}`);
    const flipAge = sc.filter((r) => (r.sFrozen >= 30) !== (r.sToday >= 30)).map((r) => `${r.id} (${r.sFrozen} → ${r.sToday})`);
    p(`- Situs yang berubah status karena umur hari ini vs beku: ${flipAge.join(", ") || "tidak ada"}`);
    p("");

    // Sinyal umur hidup dan mati karena timeout: ulangi hitungan untuk tiap pass dingin (server baru, tanpa cache).
    p("### Keajegan tangkapan antar pass RDAP (tiap pass = 35 situs, server baru per permintaan)");
    p("");
    p("| pass | scam ≥ 30 | ≥ 50 | ≥ 80 | scam ≥ 30 + Telegram | ≥ 50 + Tg | ≥ 80 + Tg | legit ≥ 30 (+ Tg) |");
    p("|---|---:|---:|---:|---:|---:|---:|---:|");
    const passes = [["A (server baru, pass 1)", A], ...d.cold.rounds.map((r, i) => [`dingin ${i + 1}`, r])];
    const tally = [];
    for (const [name, pass] of passes) {
        const sco = (id, tg) => cap(sum(pass[id].signals ?? []) + (tg ? d.tele.rows[id].weight : 0));
        const c = (grp, th, tg) => grp.filter((id) => sco(id, tg) >= th).length;
        const t = [c(scamIds, 30, 0), c(scamIds, 50, 0), c(scamIds, 80, 0), c(scamIds, 30, 1), c(scamIds, 50, 1), c(scamIds, 80, 1)];
        tally.push(t);
        p(`| ${name} | ${t[0]} | ${t[1]} | ${t[2]} | ${t[3]} | ${t[4]} | ${t[5]} | ${c(legitIds, 30, 0)} (${c(legitIds, 30, 1)}) |`);
    }
    const range = (i) => `${Math.min(...tally.map((t) => t[i]))}–${Math.max(...tally.map((t) => t[i]))}`;
    p("");
    p(`Rentang antar pass: scam ≥ 30 ${range(0)}, ≥ 50 ${range(1)}, ≥ 80 ${range(2)}; dengan Telegram ≥ 30 ${range(3)}, ≥ 50 ${range(4)}, ≥ 80 ${range(5)}.`);
    p("");

    // ---- umur
    p("## 2. Umur domain: beku vs hari ini");
    p("");
    const cls = { sama: [], geser: [], tuaSama: [], hilangCepat: [], timeout: [], tidakDicek: [], baru: [] };
    const offMed = (id) => median(d.off.rounds.slice(1).map((r) => r[id].ms));
    const aDelta = (id) => A[id].ms - offMed(id);
    for (const r of rows) {
        if (r.official || r.noDomain) {
            cls.tidakDicek.push(r.id);
            continue;
        }
        if (r.todayW === 0) {
            if (r.frozenAge === null) cls.tuaSama.push(`${r.id} (beku null, hari ini tanpa sinyal)`);
            else if (r.frozenAge > 90) cls.tuaSama.push(r.id);
            else if (aDelta(r.id) >= 1400) cls.timeout.push(`${r.id} (beku ${r.frozenAge} hari)`);
            else cls.hilangCepat.push(`${r.id} (beku ${r.frozenAge} hari)`);
            continue;
        }
        if (r.frozenAge === null) cls.baru.push(`${r.id} (beku null → ${r.todayAge} hari)`);
        else if (r.frozenW === r.todayW) cls.sama.push(r.id);
        else cls.geser.push(`${r.id} (${r.frozenAge} → ${r.todayAge} hari)`);
    }
    p("| hasil RDAP hari ini | jumlah | situs |");
    p("|---|---:|---|");
    const row = (label, arr) => p(`| ${label} | ${arr.length} | ${arr.join(", ") || "-"} |`);
    row("sinyal ada, kelompok bobot sama dengan beku", cls.sama);
    row("sinyal ada, kelompok bobot bergeser", cls.geser);
    row("sinyal ada, beku `null`", cls.baru);
    row("tanpa sinyal, beku > 90 hari (masih tua)", cls.tuaSama);
    row("tanpa sinyal, beku ≤ 90 hari, jawaban cepat (bukan timeout)", cls.hilangCepat);
    row("tanpa sinyal, beku ≤ 90 hari, kena batas 1,5 dtk (selisih waktu ≥ 1,4 dtk)", cls.timeout);
    row("tidak dicek (host resmi / populer atau bukan domain terdaftar)", cls.tidakDicek);
    p("");

    // ---- per situs
    p("## 3. Per situs");
    p("");
    p("| id | field + teks | umur beku → hari ini | Telegram | skor beku | skor hari ini | skor + Telegram | ≥ 30 |");
    p("|---|---:|---|---:|---:|---:|---:|:-:|");
    for (const r of rows) {
        const age = `${r.frozenAge ?? "null"} → ${r.todayAge ?? (r.official || r.noDomain ? "tidak dicek" : "tanpa sinyal")}`;
        const tl = r.tele.readable ? `+${r.teleW}${r.teleW ? ` (${["host", "token", "method"].filter((k) => r.tele.hit[k]).join("+").replace("token", "token [disamarkan]")})` : ""}` : "tidak terbaca";
        p(`| ${r.id} | ${r.rulesW} | ${age} | ${tl} | ${r.sFrozen} | ${r.sToday} | ${r.sTele} | ${r.sTele >= 30 ? "ya" : "-"} |`);
    }
    p("");

    // ---- waktu
    const sitesMs = (rounds, from, ids2) => ids2.flatMap((id) => rounds.slice(from).map((r) => r[id].ms));
    const perSite = (rounds, from, id) => median(rounds.slice(from).map((r) => r[id].ms));
    const modes = {
        "rules in-process (analyzeSnapshot, CPU)": d.inproc.pooled,
        "C1 RDAP mati (rules + HTTP)": summarize(sitesMs(d.off.rounds, 1, ids)),
        "C2 RDAP dingin (HTTP)": summarize(sitesMs(d.cold.rounds, 1, ids)),
        "C3 RDAP hangat (HTTP)": summarize(sitesMs(d.on.rounds, 1, ids)),
        "C4 Telegram, pindai di Node": d.tele.pooled,
    };
    p("## 4. Waktu");
    p("");
    p(`Sampel per mode: ${ids.length} situs × ${REPS - 1} (run pertama dibuang) = ${ids.length * (REPS - 1)}. Median dan p95 (nearest-rank) dihitung dari semua sampel; p95 per situs dari 4 sampel tidak bermakna, jadi per situs hanya median.`);
    p("");
    p("| mode | n | median (ms) | p95 (ms) | maks (ms) |");
    p("|---|---:|---:|---:|---:|");
    for (const [k, v] of Object.entries(modes)) p(`| ${k} | ${v.n} | ${ms(v.median)} | ${ms(v.p95)} | ${ms(v.max)} |`);
    p("");
    const coldRdap = ids.map((id) => perSite(d.cold.rounds, 1, id) - perSite(d.off.rounds, 1, id));
    const warmRdap = ids.map((id) => perSite(d.on.rounds, 1, id) - perSite(d.off.rounds, 1, id));
    p(`- Waktu RDAP ≈ C2 − C1 (selisih median per situs): median ${ms(median(coldRdap))} ms, maks ${ms(Math.max(...coldRdap))} ms. Hangat (C3 − C1): median ${ms(median(warmRdap))} ms, maks ${ms(Math.max(...warmRdap))} ms.`);
    const wu = summarize(d.cold.warmups);
    p(`- Permintaan pertama setelah server start (host resmi, tanpa RDAP): median ${ms(wu.median)} ms, maks ${ms(wu.max)} ms (n=${wu.n}). Tidak dihitung di C2.`);
    p(`- Cek /_dev/layer4: RDAP mati ${d.off.layer4.before}/${d.off.layer4.after}, RDAP hidup ${d.on.layer4.before}/${d.on.layer4.after}, dingin ${d.cold.layer4.checks} cek (${d.cold.layer4.all.join(",")}).`);
    p("");
    p("### Per situs (median 4 sampel, ms)");
    p("");
    p("| id | C1 mati | C2 dingin | C3 hangat | C2 − C1 | kena batas | Telegram | rules in-process |");
    p("|---|---:|---:|---:|---:|:-:|---:|---:|");
    const limited = [];
    for (const id of ids) {
        const c1 = perSite(d.off.rounds, 1, id);
        const c2 = perSite(d.cold.rounds, 1, id);
        const c3 = perSite(d.on.rounds, 1, id);
        const hit = c2 - c1 >= 1400;
        if (hit) limited.push(id);
        p(`| ${id} | ${ms(c1)} | ${ms(c2)} | ${ms(c3)} | ${ms(c2 - c1)} | ${hit ? "ya" : "-"} | ${d.tele.rows[id].ms ? ms(median(d.tele.rows[id].ms)) : "-"} | ${ms(median(d.inproc.rows[id].ms))} |`);
    }
    p("");
    p(`- Kena batas 1,5 dtk (diduga dari waktu, C2 − C1 ≥ 1,4 dtk): ${limited.length} situs: ${limited.join(", ") || "-"}`);
    const coldAll = d.cold.rounds.flatMap((r, i) => ids.map((id) => ({ id, ms: r[id].ms - perSite(d.off.rounds, 1, id), i })));
    const hitS = coldAll.filter((x) => x.ms >= 1400);
    const perId = Object.entries(hitS.reduce((m, x) => ((m[x.id] = (m[x.id] ?? 0) + 1), m), {})).map(([id, n]) => `${id} ${n}/5`);
    p(`- Dari ${coldAll.length} permintaan dingin (5 ulangan), ${hitS.length} kena batas (${((100 * hitS.length) / coldAll.length).toFixed(0)}%). Situs dan jumlahnya: ${perId.join(", ") || "-"}`);

    // ---- batas lulus
    const dingin = modes["C2 RDAP dingin (HTTP)"];
    const hangat = modes["C3 RDAP hangat (HTTP)"];
    const totalCold = sitesMs(d.cold.rounds, 1, ids);
    const all8 = [...totalCold, ...sitesMs(d.on.rounds, 1, ids), ...sitesMs(d.off.rounds, 1, ids)];
    const errs = [d.off, d.on, d.cold].flatMap((m) => m.rounds.flatMap((r) => Object.entries(r).filter(([, v]) => v.err || v.status !== 200).map(([id, v]) => `${id}:${v.err ?? v.status}`)));
    p("");
    p("### Batas lulus");
    p("");
    p("| ukuran | batas | hasil | lulus |");
    p("|---|---|---|:-:|");
    p(`| rules (sync) | < 100 ms | maks ${ms(modes["rules in-process (analyzeSnapshot, CPU)"].max)} ms | ${modes["rules in-process (analyzeSnapshot, CPU)"].max < 100 ? "ya" : "tidak"} |`);
    p(`| RDAP | ≤ 1,5 dtk | maks selisih dingin ${ms(Math.max(...coldRdap))} ms; ${limited.length} situs kena batas (batas = tanpa sinyal, bukan error) | ${Math.max(...coldRdap) <= 1600 ? "ya (dipotong di batas)" : "tidak"} |`);
    p(`| total /analyze | ≤ 6,5 dtk | maks dingin ${ms(dingin.max)} ms, maks hangat ${ms(hangat.max)} ms | ${Math.max(dingin.max, hangat.max) <= 6500 ? "ya" : "tidak"} |`);
    p(`| p95 HTTP dari klien | < 8 dtk | dingin ${ms(dingin.p95)} ms, hangat ${ms(hangat.p95)} ms | ${Math.max(dingin.p95, hangat.p95) < 8000 ? "ya" : "tidak"} |`);
    p(`| legit ≥ 30 | 0 dari ${lg.length} | umur beku ${count(lg, "sFrozen", 30)}, hari ini ${count(lg, "sToday", 30)}, + Telegram ${count(lg, "sTele", 30)} | ${count(lg, "sTele", 30) + count(lg, "sToday", 30) + count(lg, "sFrozen", 30) === 0 ? "ya" : "tidak"} |`);
    p("");
    p(`Permintaan non-200 atau error klien (semua mode): ${errs.length ? errs.join(", ") : "tidak ada"}. Sampel di atas 8 dtk: ${all8.filter((x) => x >= HTTP_TIMEOUT_MS).length}.`);

    // ---- konsistensi sinyal umur antar putaran
    p("");
    p("### Keajegan sinyal umur (RDAP hidup)");
    p("");
    const flaky = [];
    for (const id of ids) {
        const has = (r) => Boolean(r[id].signals?.some(isDomain));
        const cold = d.cold.rounds.map(has);
        const warm = d.on.rounds.map(has);
        const all = [...cold, ...warm];
        if (new Set(all).size > 1) flaky.push(`${id} (dingin ${cold.filter(Boolean).length}/${cold.length}, server hidup ${warm.filter(Boolean).length}/${warm.length})`);
    }
    p(`Situs yang sinyal \`new_domain\`-nya tidak sama di semua putaran (5 dingin + 5 di server hidup): ${flaky.join(", ") || "tidak ada"}`);
    // rules sama dengan in-process?
    const diff = ids.filter((id) => JSON.stringify(sorted((A[id].signals ?? []).filter((s) => !isDomain(s)).map((s) => `${s.id}:${s.weight}`))) !== JSON.stringify(sorted(d.inproc.rows[id].signals.map((s) => `${s.id}:${s.weight}`))));
    p(`Sinyal rules lewat HTTP berbeda dari in-process: ${diff.join(", ") || "tidak ada"}`);

    // ---- Telegram
    p("");
    p("### Telegram (HTML desktop tersimpan)");
    p("");
    const tHit = scamIds.filter((i) => d.tele.rows[i].weight > 0);
    p(`- Scam dengan bobot > 0: ${tHit.length} dari ${scamIds.length}: ${tHit.map((i) => `${i} +${d.tele.rows[i].weight}`).join(", ")}`);
    p(`- Legit dengan bobot > 0: ${legitIds.filter((i) => d.tele.rows[i].weight > 0).join(", ") || "tidak ada"}. Tidak terbaca: ${legitIds.concat(scamIds).filter((i) => !d.tele.rows[i].readable).join(", ") || "-"}`);

    // ---- meta
    p("");
    p("### Meta");
    p("");
    p(`- Node ${d.meta.node}, commit ${d.meta.commit}, belum di-commit: ${d.meta.uncommitted.map((l) => l.trim()).join("; ")}`);
    p(`- CPU: ${d.meta.cpu}. Mulai ${d.meta.startedAt}. RDAP hidup selesai ${d.on.finishedAt}; dingin selesai ${d.cold.finishedAt}.`);
    console.log(lines.join("\n"));
}

if (process.argv.includes("--report")) await report();
else await measure();
