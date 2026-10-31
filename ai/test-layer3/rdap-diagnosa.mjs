#!/usr/bin/env node
// Kenapa RDAP dingin kena batas 1,5 dtk? Pisahkan dua bagian yang dijalankan klien di src/rdap/rdap.js:
//   (1) unduh bootstrap IANA (data.iana.org/rdap/dns.json), (2) query registry untuk satu domain.
// Tiap percobaan jalan di PROSES BARU (DNS, TLS, dan koneksi dingin, seperti server dingin). Tidak mengubah src/.
// Izin Imelda (29 Okt 2026): query tambahan ke registry untuk domain 35 situs, 3 ulangan. Tidak ada permintaan ke situs scam.
// Domain tidak ditulis ke laporan; hanya id situs, TLD, dan host registry.
//
// Pakai:  node rdap-diagnosa.mjs [--reps 3]     ukur (simpan ke .hasil/rdap-diagnosa.json)
//         node rdap-diagnosa.mjs --report       tabel markdown
import { execFileSync } from "node:child_process";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const outFile = join(here, ".hasil", "rdap-diagnosa.json");
const BOOTSTRAP_URL = "https://data.iana.org/rdap/dns.json";
const LIMIT_MS = 1500;
const arg = (n, f) => {
    const i = process.argv.indexOf(n);
    return i > -1 ? process.argv[i + 1] : f;
};

const sorted = (xs) => [...xs].sort((a, b) => a - b);
const median = (xs) => {
    const s = sorted(xs);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const pctl = (xs, p) => sorted(xs)[Math.max(0, Math.ceil((p / 100) * xs.length) - 1)];
const f0 = (x) => (x === null || x === undefined || Number.isNaN(x) ? "-" : Math.round(x));

// ---- anak: satu percobaan di proses baru ----------------------------------------
async function child(domain) {
    const out = { tld: domain.slice(domain.lastIndexOf(".") + 1) };
    const headers = { accept: "application/json" };
    const t0 = performance.now();
    let servers = null;
    try {
        const res = await fetch(BOOTSTRAP_URL, { method: "GET", headers, redirect: "manual", signal: AbortSignal.timeout(8000) });
        out.bootStatus = res.status;
        out.bootTtfbMs = performance.now() - t0;
        const text = await res.text();
        out.bootMs = performance.now() - t0;
        out.bootBytes = text.length;
        const tp = performance.now();
        const data = JSON.parse(text);
        for (const entry of data.services ?? []) if (entry[0]?.includes(out.tld)) servers = entry[1];
        out.bootParseMs = performance.now() - tp;
    } catch (e) {
        out.bootErr = e?.name ?? "error";
        out.bootMs = performance.now() - t0;
    }
    const server = servers?.find((s) => /^https:\/\//.test(s));
    if (!server) {
        out.regSkipped = true;
        return out;
    }
    out.server = new URL(server).hostname;
    const t1 = performance.now();
    try {
        const url = `${server.endsWith("/") ? server : `${server}/`}domain/${domain}`;
        const res = await fetch(url, { method: "GET", headers: { accept: "application/rdap+json, application/json" }, redirect: "manual", signal: AbortSignal.timeout(8000) });
        out.regStatus = res.status;
        out.regTtfbMs = performance.now() - t1;
        const text = await res.text();
        out.regMs = performance.now() - t1;
        out.regBytes = text.length;
        if (res.status === 200) {
            const reg = (JSON.parse(text).events ?? []).find((e) => String(e.eventAction).toLowerCase() === "registration");
            if (reg) out.ageDays = Math.floor((Date.now() - Date.parse(reg.eventDate)) / 86_400_000);
        }
    } catch (e) {
        out.regErr = e?.name ?? "error";
        out.regMs = performance.now() - t1;
    }
    return out;
}

// ---- induk -------------------------------------------------------------------------
async function measure() {
    const { hostOf, isOfficialHost } = await import("../src/layer3/official.js");
    const { registrableDomain } = await import("../src/rdap/domain.js");
    const reps = Number(arg("--reps", 3));
    const files = (await readdir(join(here, "snapshots"))).filter((f) => f.endsWith(".json")).sort();
    const sites = [];
    for (const f of files) {
        const rec = JSON.parse(await readFile(join(here, "snapshots", f), "utf8"));
        const host = hostOf(rec.snapshot.url);
        const domain = registrableDomain(host);
        if (!domain || isOfficialHost(host)) continue;
        sites.push({ id: rec.id, domain, frozen: rec.rdapAgeDays });
    }
    sites.sort((a, b) => (a.id.startsWith("L") - b.id.startsWith("L")) || (a.id < b.id ? -1 : 1));
    const rows = [];
    for (let r = 0; r < reps; r++) {
        for (const s of sites) {
            const raw = execFileSync(process.execPath, [fileURLToPath(import.meta.url), "--child", s.domain], { encoding: "utf8", timeout: 30_000 });
            rows.push({ rep: r, id: s.id, frozen: s.frozen, ...JSON.parse(raw) });
        }
        process.stderr.write(`  ulangan ${r + 1}/${reps}\n`);
    }
    await mkdir(dirname(outFile), { recursive: true });
    await writeFile(outFile, JSON.stringify({ at: new Date().toISOString(), node: process.version, reps, sites: sites.length, rows }));
    process.stderr.write(`selesai, ${outFile}\n`);
}

async function report() {
    const d = JSON.parse(await readFile(outFile, "utf8"));
    const rows = d.rows;
    const L = [];
    const p = (s = "") => L.push(s);
    const stat = (xs) => (xs.length ? `${f0(median(xs))} / ${f0(pctl(xs, 95))} / ${f0(Math.max(...xs))}` : "-");
    const boot = rows.map((r) => r.bootMs);
    const reg = rows.filter((r) => r.regMs !== undefined && !r.regSkipped).map((r) => r.regMs);
    const total = rows.filter((r) => !r.regSkipped).map((r) => r.bootMs + (r.bootParseMs ?? 0) + (r.regMs ?? 0));
    const over = (xs) => `${xs.filter((x) => x > LIMIT_MS).length}/${xs.length}`;

    p(`Percobaan: ${rows.length} (${d.reps} ulangan × ${d.sites} situs), tiap percobaan di proses baru. Node ${d.node}, ${d.at}. Format sel: median / p95 / maks (ms).`);
    p("");
    p("| bagian | n | median / p95 / maks | lewat 1,5 dtk |");
    p("|---|---:|---|---:|");
    p(`| (1) unduh bootstrap IANA, sampai tubuh habis | ${boot.length} | ${stat(boot)} | ${over(boot)} |`);
    p(`| (1a) bootstrap sampai header pertama | ${rows.length} | ${stat(rows.map((r) => r.bootTtfbMs).filter((x) => x !== undefined))} | - |`);
    p(`| (1b) parse JSON bootstrap | ${rows.length} | ${stat(rows.map((r) => r.bootParseMs).filter((x) => x !== undefined))} | - |`);
    p(`| (2) query registry, sampai tubuh habis | ${reg.length} | ${stat(reg)} | ${over(reg)} |`);
    p(`| (2a) registry sampai header pertama | ${reg.length} | ${stat(rows.map((r) => r.regTtfbMs).filter((x) => x !== undefined))} | - |`);
    p(`| **(1) + (2) berurutan** (yang dibatasi 1,5 dtk) | ${total.length} | ${stat(total)} | ${over(total)} |`);
    p("");
    p(`Ukuran bootstrap: ${f0(median(rows.map((r) => r.bootBytes ?? 0)) / 1024)} KB (median). Status bootstrap: ${JSON.stringify(rows.reduce((m, r) => ((m[r.bootStatus ?? r.bootErr] = (m[r.bootStatus ?? r.bootErr] ?? 0) + 1), m), {}))}.`);
    p("");

    const slow = rows.filter((r) => !r.regSkipped && r.bootMs + (r.bootParseMs ?? 0) + (r.regMs ?? 0) > LIMIT_MS);
    const bootBig = slow.filter((r) => r.bootMs >= (r.regMs ?? 0)).length;
    p(`Dari ${slow.length} percobaan yang totalnya lewat 1,5 dtk: bagian terbesar adalah bootstrap di ${bootBig}, registry di ${slow.length - bootBig}.`);
    p(`Bootstrap saja sudah lewat 1,5 dtk di ${boot.filter((x) => x > LIMIT_MS).length} dari ${boot.length}. Registry saja lewat 1,5 dtk di ${reg.filter((x) => x > LIMIT_MS).length} dari ${reg.length}.`);
    p("");

    p("### Per host registry (query registry saja, ms)");
    p("");
    p("| host registry | situs | n | median / p95 / maks | status |");
    p("|---|---|---:|---|---|");
    const byServer = {};
    for (const r of rows) if (r.server) (byServer[r.server] ??= []).push(r);
    for (const [server, rs] of Object.entries(byServer).sort((a, b) => median(b[1].map((r) => r.regMs)) - median(a[1].map((r) => r.regMs)))) {
        const st = rs.reduce((m, r) => ((m[r.regStatus ?? r.regErr] = (m[r.regStatus ?? r.regErr] ?? 0) + 1), m), {});
        p(`| ${server} | ${[...new Set(rs.map((r) => r.id))].join(", ")} | ${rs.length} | ${stat(rs.map((r) => r.regMs))} | ${Object.entries(st).map(([k, v]) => `${k}×${v}`).join(" ")} |`);
    }
    p("");
    const noServer = [...new Set(rows.filter((r) => r.regSkipped).map((r) => `${r.id} (.${r.tld})`))];
    p(`Tanpa server RDAP di bootstrap (TLD tidak terdaftar): ${noServer.join(", ") || "tidak ada"}.`);
    p("");

    p("### Per situs (median 3 ulangan, ms)");
    p("");
    p("| id | bootstrap | registry | total | lewat 1,5 dtk (dari 3) | status registry | umur hari ini |");
    p("|---|---:|---:|---:|---:|---|---:|");
    const ids = [...new Set(rows.map((r) => r.id))];
    for (const id of ids) {
        const rs = rows.filter((r) => r.id === id);
        const tot = rs.map((r) => r.bootMs + (r.bootParseMs ?? 0) + (r.regMs ?? 0));
        const st = [...new Set(rs.map((r) => r.regStatus ?? r.regErr ?? "tanpa server"))].join(",");
        const ages = [...new Set(rs.map((r) => r.ageDays).filter((x) => x !== undefined))].join(",");
        p(`| ${id} | ${f0(median(rs.map((r) => r.bootMs)))} | ${f0(median(rs.map((r) => r.regMs ?? NaN).filter((x) => !Number.isNaN(x))))} | ${f0(median(tot))} | ${tot.filter((x) => x > LIMIT_MS).length} | ${st} | ${ages || "-"} |`);
    }
    console.log(L.join("\n"));
}

if (process.argv.includes("--child")) process.stdout.write(JSON.stringify(await child(arg("--child"))));
else if (process.argv.includes("--report")) await report();
else await measure();
