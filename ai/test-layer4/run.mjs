#!/usr/bin/env node
// Tes Layer 4 (LLM): 25 scam + 10 legit + 1 trap legit, 3 putaran tiap sampel, prompt reality-check.v4.
// Plan: PLAN.md. Hasil: HASIL.md. Mentah: .hasil/l4.json (di-gitignore, isi payload dengan domain asli).
//
// Yang dilakukan tiap sampel: L2 (detector.js lewat vm) -> L3 (analyze, tanpa RDAP, tanpa LLM) -> payload L4 persis
// seperti reality.js (buildInput + SYSTEM_PROMPT) -> provider dari ai/.env. Gate produksi DILEWATI (K1): provider dipanggil
// langsung, bukan check(). Gate tetap dicatat. Hanya skrip ini yang menambah chat_template_kwargs {thinking:false} (K7).
// Tidak ada permintaan ke situs scam, tidak ada RDAP. Isi ai/.env tidak pernah dicetak atau disimpan.
//
// Pakai:  node run.mjs [--only 01] [--dry]   jalankan (--dry: tanpa LLM, cetak payload; --only: satu sampel, ke .hasil/l4-only.json)
//         node run.mjs --report              tulis HASIL.md dari .hasil/l4.json
import { execFileSync } from "node:child_process";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { analyze } from "../src/analyze.js";
import { sanitizeSnapshot } from "../src/validate.js";
import { hostOf, isOfficialHost } from "../src/layer3/official.js";
import { registrableDomain } from "../src/rdap/domain.js";
import { buildInput, passesGate, MIN_CONFIDENCE, GATE_MIN_SCORE } from "../src/layer4/reality.js";
import { createProvider } from "../src/layer4/provider.js";
import { parseVerdict } from "../src/layer4/schema.js";
import { readConfig, MAX_TIMEOUT_MS } from "../src/layer4/config.js";
import { SYSTEM_PROMPT, PROMPT_VERSION, LINK_TEXT } from "../prompts/reality-check.js";

const here = dirname(fileURLToPath(import.meta.url));
const aiDir = join(here, "..");
const repoDir = join(aiDir, "..");
const snapDir = join(aiDir, "test-layer3", "snapshots");
const trapFile = join(aiDir, "eval", "data", "legit", "traps.json");
const detectorFile = join(repoDir, "ios", "ShooExtension", "Resources", "detector.js");
const outDir = join(here, ".hasil");
const TRAP_ID = "trap-github-pages-dokumentasi";

const REPS = 3;
const CALL_TIMEOUT_MS = 8000; // ekstensi menyerah di 8 dtk (K2)
const SLOW_MS = MAX_TIMEOUT_MS; // > 6 dtk: di produksi kena timeout
const STOP_AFTER_HTTP_ERRORS = 10;

const arg = (name) => {
    const i = process.argv.indexOf(name);
    return i > -1 ? process.argv[i + 1] : undefined;
};
const flag = (name) => process.argv.includes(name);

// ---- statistik ---------------------------------------------------------------
const sorted = (xs) => [...xs].sort((a, b) => a - b);
const median = (xs) => {
    const s = sorted(xs);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const pctl = (xs, p) => sorted(xs)[Math.max(0, Math.ceil((p / 100) * xs.length) - 1)]; // nearest-rank
const sum = (xs) => xs.reduce((a, b) => a + b, 0);

// ---- data --------------------------------------------------------------------
/** Urutan: scam 01..25, legit L01..L10, trap. Tiap rekaman: { id, kind, snapshot }. */
async function loadSamples() {
    const files = (await readdir(snapDir)).filter((f) => f.endsWith(".json")).sort();
    const recs = [];
    for (const f of files) {
        const r = JSON.parse(await readFile(join(snapDir, f), "utf8"));
        recs.push({ id: r.id, kind: r.id.startsWith("L") ? "legit" : "scam", snapshot: r.snapshot, rdapAgeDays: r.rdapAgeDays ?? null });
    }
    recs.sort((a, b) => (a.kind === "legit") - (b.kind === "legit") || (a.id < b.id ? -1 : 1));
    const traps = JSON.parse(await readFile(trapFile, "utf8"));
    const trap = traps.find((t) => t.id === TRAP_ID);
    if (!trap) throw new Error(`${TRAP_ID} tidak ada di traps.json`);
    recs.push({ id: TRAP_ID, kind: "trap", snapshot: trap.snapshot, rdapAgeDays: null });
    return recs;
}

// ---- L2: detector.js lewat vm (cara test-layer2/analyze.mjs) ------------------
async function loadDetector() {
    const ctx = { URL, console };
    ctx.globalThis = ctx;
    vm.createContext(ctx);
    vm.runInContext(await readFile(detectorFile, "utf8"), ctx);
    return ctx.ShooDetector;
}

const slimSignal = (s) => ({ id: s.id, weight: s.weight, ...(s.evidence ? { evidence: s.evidence } : {}) });

/** Satu sampel: L2, L3, gate, payload. Tanpa jaringan. */
async function prepare(rec, detector) {
    const snapshot = sanitizeSnapshot(rec.snapshot);
    const l2Raw = await detector.analyzeLocal(rec.snapshot);
    const localSignals = Array.isArray(l2Raw) ? l2Raw : [];
    const l3Raw = await analyze(rec.snapshot, { rdap: null, llm: null, localSignals });
    const ruleIds = l3Raw.map((s) => s.id);
    const score = sum(l3Raw.map((s) => s.weight));
    const official = isOfficialHost(hostOf(snapshot.url));
    const total = score + sum(localSignals.map((s) => s.weight));
    const gate = passesGate({ official, score: total });
    const hasField = snapshot.forms.some((f) => f.fields.length > 0);
    const gateReason = gate ? "lolos" : official ? "situs resmi" : total < GATE_MIN_SCORE ? `total ${total} < ${GATE_MIN_SCORE}` : `total ${total}: sudah diblokir`;
    const input = buildInput(snapshot, ruleIds, localSignals);
    const messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: `DATA_START\n${JSON.stringify(input)}\nDATA_END` },
    ];
    return {
        id: rec.id,
        kind: rec.kind,
        url: snapshot.url,
        host: hostOf(snapshot.url),
        title: snapshot.title,
        rdapAgeDays: rec.rdapAgeDays,
        l2: { signals: localSignals.map(slimSignal) },
        l3: { signals: l3Raw.map(slimSignal), score, official, hasField },
        gate: { passes: gate, reason: gateReason },
        input,
        skippedNoSite: !input.site, // check() berhenti di sini (host bukan domain publik); tes ini tetap kirim
        messages,
    };
}

// ---- panggilan LLM -----------------------------------------------------------
/**
 * Membungkus fetch: menambah thinking:false (K7), membaca seluruh body sampai selesai, mencatat status dan usage, lalu
 * mengembalikan Response baru dengan body yang sama supaya provider.js jalan apa adanya. Kunci API ada di header dan
 * tidak pernah disimpan.
 */
function wrappedFetch(rec) {
    return async (url, init) => {
        const body = JSON.parse(init.body);
        body.chat_template_kwargs = { thinking: false };
        const res = await fetch(url, { ...init, body: JSON.stringify(body) });
        rec.status = res.status;
        const text = await res.text();
        try {
            const j = JSON.parse(text);
            rec.usage = j.usage ?? null;
            rec.finish = j.choices?.[0]?.finish_reason ?? null;
            rec.raw = j.choices?.[0]?.message?.content ?? null;
        } catch {
            rec.rawBody = text.slice(0, 300); // bukan JSON: simpan sedikit untuk diagnosis (isi respons provider, bukan kunci)
        }
        const empty = [204, 205, 304].includes(res.status);
        return new Response(empty ? null : text, { status: res.status, headers: { "content-type": res.headers.get("content-type") ?? "application/json" } });
    };
}

const approxTokens = (s) => Math.ceil(String(s).length / 4);

async function callOnce(cfg, messages) {
    const rec = { status: null, usage: null, finish: null, raw: null };
    const ask = createProvider({ config: cfg, fetch: wrappedFetch(rec) });
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), CALL_TIMEOUT_MS);
    const t0 = performance.now();
    let answer;
    try {
        answer = await ask(messages, controller.signal);
    } finally {
        clearTimeout(timer);
    }
    const ms = performance.now() - t0;
    const out = { ms: Math.round(ms), slow: ms > SLOW_MS, status: rec.status, finish: rec.finish, raw: rec.raw };
    // Perkiraan karakter ÷ 4 selalu disimpan di samping usage provider, untuk pembanding (usage dari proxy bisa membengkak).
    const ap = approxTokens(messages.map((m) => m.content).join(""));
    const ac = approxTokens(rec.raw ?? "");
    out.approx = { prompt: ap, completion: ac, total: ap + ac };
    if (rec.usage && Number.isFinite(rec.usage.prompt_tokens)) {
        out.usage = { prompt: rec.usage.prompt_tokens, completion: rec.usage.completion_tokens, total: rec.usage.total_tokens, estimated: false };
    } else {
        out.usage = { ...out.approx, estimated: true };
    }
    if (rec.rawBody) out.rawBody = rec.rawBody;
    if (!answer.ok) return { ...out, outcome: controller.signal.aborted ? "timeout" : answer.reason };
    const verdict = parseVerdict(answer.content);
    if (!verdict) return { ...out, outcome: "bad_schema" };
    const flagged = !(verdict.reasonable || verdict.confidence < MIN_CONFIDENCE || verdict.asks.length === 0);
    return { ...out, outcome: flagged ? "flagged" : "reasonable", verdict, flagged };
}

// ---- jalankan ----------------------------------------------------------------
const git = (...a) => execFileSync("git", a, { cwd: aiDir, encoding: "utf8" }).trim();

async function measure() {
    const only = arg("--only");
    const dry = flag("--dry");
    const detector = await loadDetector();
    let recs = await loadSamples();
    if (only) {
        recs = recs.filter((r) => r.id === only);
        if (!recs.length) throw new Error(`sampel ${only} tidak ada`);
    }
    const prepared = [];
    for (const r of recs) prepared.push(await prepare(r, detector));

    if (dry) {
        for (const p of prepared) {
            console.log(`\n=== ${p.id} (${p.kind}) ===`);
            console.log(`gate produksi : ${p.gate.passes ? "dipanggil" : "tidak dipanggil"} (${p.gate.reason})`);
            console.log(`L2            : ${p.l2.signals.map((s) => `${s.id}:${s.weight}${s.evidence ? `[${s.evidence}]` : ""}`).join("; ") || "-"}`);
            console.log(`L3            : ${p.l3.signals.map((s) => `${s.id}:${s.weight}`).join("; ") || "-"} (skor ${p.l3.score})`);
            console.log(`payload user  : ${p.messages[1].content}`);
            console.log(`pesan system  : ${p.messages[0].content.length} karakter (sama untuk semua sampel)`);
        }
        return;
    }

    // Konfigurasi dari ai/.env. Tidak ada nilai yang dicetak.
    try {
        process.loadEnvFile(join(aiDir, ".env"));
    } catch (e) {
        if (e?.code !== "ENOENT") throw e;
    }
    const cfg = readConfig(process.env);
    if (!cfg) throw new Error("ai/.env belum lengkap (LLM_API_KEY, LLM_MODEL, LLM_BASE_URL) atau tidak aman");

    await mkdir(outDir, { recursive: true });
    const outFile = join(outDir, only ? "l4-only.json" : "l4.json");
    const out = {
        meta: {
            model: cfg.model,
            host: new URL(cfg.baseUrl).hostname,
            promptVersion: PROMPT_VERSION,
            thinking: "off (chat_template_kwargs {thinking:false}, hanya di skrip ini)",
            temperature: 0,
            maxTokens: 200,
            callTimeoutMs: CALL_TIMEOUT_MS,
            slowMs: SLOW_MS,
            reps: REPS,
            minConfidence: MIN_CONFIDENCE,
            node: process.version,
            commit: git("rev-parse", "--short", "HEAD"),
            uncommitted: git("status", "--short", "src", "prompts").split("\n").filter(Boolean),
            detectorVersion: detector.version ?? null,
            linkTextCodes: Object.keys(LINK_TEXT),
            systemPrompt: SYSTEM_PROMPT,
            startedAt: new Date().toISOString(),
            finishedAt: null,
            stoppedEarly: null,
        },
        samples: [],
    };
    const save = () => writeFile(outFile, JSON.stringify(out));

    let httpErrorsInRow = 0;
    for (const p of prepared) {
        const { messages, ...keep } = p;
        const sample = { ...keep, runs: [] };
        out.samples.push(sample);
        for (let r = 1; r <= REPS; r++) {
            const run = await callOnce(cfg, messages);
            sample.runs.push(run);
            process.stderr.write(`${p.id} #${r} ${run.outcome} ${run.ms} ms${run.slow ? " (>6s)" : ""}\n`);
            httpErrorsInRow = run.outcome === "http_error" ? httpErrorsInRow + 1 : 0;
            if (httpErrorsInRow >= STOP_AFTER_HTTP_ERRORS) {
                out.meta.stoppedEarly = `${STOP_AFTER_HTTP_ERRORS} http_error berturut-turut, berhenti di ${p.id} putaran ${r}`;
                await save();
                process.stderr.write(`BERHENTI: ${out.meta.stoppedEarly}\n`);
                return;
            }
        }
        await save();
    }
    out.meta.finishedAt = new Date().toISOString();
    await save();
    process.stderr.write(`selesai, ${outFile}\n`);
}

// ---- laporan -----------------------------------------------------------------
const maskHost = (h) => h.replace(/\./g, "[.]");
function masker(sample) {
    const hosts = [...new Set([sample.host, sample.host.replace(/^www\./, ""), registrableDomain(sample.host)].filter(Boolean))].sort((a, b) => b.length - a.length);
    return (text) => hosts.reduce((t, h) => t.split(h).join(maskHost(h)), String(text));
}
const maskedUrl = (sample) => `hxxps://${maskHost(sample.host)}`;
const cell = (s) => String(s).replace(/\|/g, "\\|").replace(/\n/g, " ");
const sigText = (signals) => (signals.length ? signals.map((s) => `${s.id}:${s.weight}`).join(", ") : "-");
const l2Text = (signals) => (signals.length ? signals.map((s) => `${s.id}:${s.weight}${s.id === "suspicious_link" && s.evidence ? ` [${s.evidence}]` : ""}`).join(", ") : "-");
const fmtMs = (x) => (x == null ? "-" : Math.round(x).toString());
const avg = (xs) => (xs.length ? sum(xs) / xs.length : 0);

/** Kunci jawaban satu putaran untuk membandingkan antar putaran: tipe halaman, asks, reasonable, flagged. Confidence tidak ikut (selalu bergeser sedikit). */
const answerKey = (run) => (run.verdict ? JSON.stringify([run.verdict.pageType, [...run.verdict.asks].sort(), run.verdict.reasonable, run.flagged]) : `x:${run.outcome}`);

function describe(sample) {
    const runs = sample.runs;
    const keys = runs.map(answerKey);
    const ms = runs.map((r) => r.ms);
    const flaggedN = runs.filter((r) => r.flagged).length;
    return {
        n: runs.length,
        flaggedN,
        majorityFlag: flaggedN * 2 > runs.length,
        anyFlag: flaggedN > 0,
        consistent: new Set(keys).size <= 1,
        diffCount: new Set(keys).size,
        medianMs: ms.length ? median(ms) : null,
        maxMs: ms.length ? Math.max(...ms) : null,
        slow: runs.some((r) => r.slow),
        tokens: { prompt: avg(runs.map((r) => r.usage.prompt)), completion: avg(runs.map((r) => r.usage.completion)), total: avg(runs.map((r) => r.usage.total)), estimated: runs.some((r) => r.usage.estimated) },
        first: runs.find((r) => r.verdict) ?? runs[0],
    };
}

async function report() {
    const d = JSON.parse(await readFile(join(outDir, "l4.json"), "utf8"));
    const samples = d.samples;
    const desc = Object.fromEntries(samples.map((s) => [s.id, describe(s)]));
    const scam = samples.filter((s) => s.kind === "scam");
    const legit = samples.filter((s) => s.kind === "legit");
    const trap = samples.filter((s) => s.kind === "trap");
    const lines = [];
    const p = (s = "") => lines.push(s);

    const allRuns = samples.flatMap((s) => s.runs);
    const msAll = allRuns.map((r) => r.ms);
    const outcome = (o) => allRuns.filter((r) => r.outcome === o).length;
    const gatePass = scam.filter((s) => s.gate.passes);
    const scamFlag = scam.filter((s) => desc[s.id].majorityFlag);
    const scamFlagGate = gatePass.filter((s) => desc[s.id].majorityFlag);
    const legitFlag = legit.filter((s) => desc[s.id].majorityFlag);
    const legitFlagAny = legit.filter((s) => desc[s.id].anyFlag);
    const trapFlag = trap.filter((s) => desc[s.id].majorityFlag);
    const trapFlagAny = trap.filter((s) => desc[s.id].anyFlag);
    const changed = samples.filter((s) => !desc[s.id].consistent);
    const tokTotal = sum(allRuns.map((r) => r.usage.total));
    const tokIn = sum(allRuns.map((r) => r.usage.prompt));
    const tokOut = sum(allRuns.map((r) => r.usage.completion));
    const estimated = allRuns.some((r) => r.usage.estimated);
    const tilde = estimated ? "~" : "";
    const p95 = msAll.length ? pctl(msAll, 95) : null;

    p("<!-- AUTO:START -->");
    p(`_Dibuat oleh \`run.mjs --report\` dari \`.hasil/l4.json\` pada ${new Date().toISOString()}. Jangan edit di dalam blok ini; bagian "Analisis" di bawah blok ini aman._`);
    p("");
    p("# Hasil tes Layer 4 (LLM)");
    p("");
    p(`- Model \`${d.meta.model}\` di \`${d.meta.host}\`, prompt \`${d.meta.promptVersion}\`, thinking off, temperature ${d.meta.temperature}, max_tokens ${d.meta.maxTokens}.`);
    p(`- Kode: commit \`${d.meta.commit}\`, belum di-commit di \`src\`/\`prompts\`: ${d.meta.uncommitted.map((l) => `\`${l.trim()}\``).join(", ") || "tidak ada"}. Node ${d.meta.node}. detector.js versi ${d.meta.detectorVersion ?? "?"}.`);
    p(`- Mulai ${d.meta.startedAt}, selesai ${d.meta.finishedAt ?? "BELUM SELESAI"}.${d.meta.stoppedEarly ? ` **Berhenti dini: ${d.meta.stoppedEarly}.**` : ""}`);
    p(`- ${samples.length} sampel × ${d.meta.reps} putaran = ${allRuns.length} panggilan, satu per satu. Gate produksi dilewati (K1): semua sampel dikirim. Batas ${d.meta.callTimeoutMs / 1000} dtk per panggilan; > ${d.meta.slowMs / 1000} dtk ditandai ⚠.`);
    p('- Domain disamarkan. "+30" = jawaban `reasonable: false`, `confidence ≥ 0.6`, `asks` tidak kosong (aturan `reality.js`); di tabel ditulis `ya (n/3)` = n dari 3 putaran. "ya"/"tidak" di ringkasan = mayoritas putaran (≥ 2 dari 3).');
    const noUsage = allRuns.filter((r) => r.usage.estimated).length;
    p(`- Token: dibaca dari \`usage\` respons provider${noUsage ? `; ${noUsage} panggilan tanpa respons (timeout) diganti perkiraan karakter ÷ 4 dan ditandai ~` : ""}. Perkiraan karakter ÷ 4 untuk semua panggilan ada di baris pembanding di Ringkasan.`);
    p("");

    p("## Ringkasan");
    p("");
    p("| ukuran | hasil |");
    p("|---|---|");
    p(`| Scam dapat +30 | ${scamFlag.length} / ${scam.length} |`);
    p(`| Scam dapat +30, hanya yang lolos gate produksi | ${scamFlagGate.length} / ${gatePass.length} |`);
    p(`| Scam tidak dapat +30 | ${scam.filter((s) => !desc[s.id].majorityFlag).map((s) => s.id).join(", ") || "-"} |`);
    p(`| Scam tidak lolos gate produksi | ${scam.filter((s) => !s.gate.passes).map((s) => `${s.id} (${s.gate.reason})`).join(", ") || "-"} |`);
    p(`| Legit dapat +30 (false positive) | ${legitFlag.length} / ${legit.length}; di putaran mana pun: ${legitFlagAny.length}${legitFlagAny.length ? ` (${legitFlagAny.map((s) => s.id).join(", ")})` : ""} |`);
    p(`| Trap GitHub Pages dapat +30 | ${trapFlag.length ? "**ya**" : "tidak"} (${trap.map((s) => `${desc[s.id].flaggedN}/${desc[s.id].n} putaran`).join("")}) |`);
    p(`| Legit + trap dapat +30 | ${legitFlag.length + trapFlag.length} / ${legit.length + trap.length} |`);
    p(`| Waktu (ms) | median ${fmtMs(median(msAll))}, p95 ${fmtMs(p95)}, maks ${fmtMs(Math.max(...msAll))} |`);
    p(`| Panggilan > ${d.meta.slowMs / 1000} dtk | ${allRuns.filter((r) => r.slow).length} / ${allRuns.length} |`);
    p(`| Timeout ${d.meta.callTimeoutMs / 1000} dtk | ${outcome("timeout")} |`);
    p(`| Token total | ${tilde}${tokTotal} (rata-rata ${tilde}${Math.round(tokTotal / allRuns.length)} per panggilan; input ${tilde}${tokIn}, output ${tilde}${tokOut}) |`);
    p(`| Token, perkiraan karakter ÷ 4 (pembanding) | ${sum(allRuns.map((r) => r.approx.total))} (input ${sum(allRuns.map((r) => r.approx.prompt))}, output ${sum(allRuns.map((r) => r.approx.completion))}) |`);
    p(`| Gagal | bad_schema ${outcome("bad_schema")}, http_error ${outcome("http_error")}, timeout ${outcome("timeout")} |`);
    p(`| Jawaban berubah antar putaran | ${changed.length} link${changed.length ? `: ${changed.map((s) => s.id).join(", ")}` : ""} |`);
    const answered = (s) => s.runs.filter((r) => r.verdict);
    const flipped = samples.filter((s) => new Set(answered(s).map((r) => r.flagged)).size > 1);
    const withFailure = samples.filter((s) => s.runs.some((r) => !r.verdict));
    p(`| Status +30 berubah antar putaran (hanya putaran yang dijawab) | ${flipped.length} link${flipped.length ? `: ${flipped.map((s) => s.id).join(", ")}` : ""} |`);
    p(`| Link dengan putaran gagal (timeout / bad_schema / http_error) | ${withFailure.length} link${withFailure.length ? `: ${withFailure.map((s) => `${s.id} (${s.runs.filter((r) => !r.verdict).map((r) => r.outcome).join(", ")})`).join(", ")}` : ""} |`);
    p(`| Sampel lengkap | ${samples.filter((s) => s.runs.length === d.meta.reps).length} / ${samples.length} |`);
    p("");
    p('"Berubah" = tipe halaman, isi `asks`, `reasonable` atau status +30 beda di antara putaran. Angka confidence selalu bergeser sedikit dan tidak dihitung.');
    p("");

    p("## Batas lulus");
    p("");
    p("Ditetapkan di PLAN.md sebelum mengukur. Untuk legit dihitung ketat: +30 di putaran mana pun.");
    p("");
    p("| ukuran | batas | hasil | lulus |");
    p("|---|---|---|:-:|");
    const fpAny = legitFlagAny.length + trapFlagAny.length;
    const checks = [
        ["legit dapat +30", `0 / ${legit.length + trap.length}`, `${fpAny} / ${legit.length + trap.length}`, fpAny === 0],
        ["`bad_schema`", "0", String(outcome("bad_schema")), outcome("bad_schema") === 0],
        ["p95 waktu", `≤ ${d.meta.slowMs / 1000} dtk`, `${fmtMs(p95)} ms`, p95 != null && p95 <= d.meta.slowMs],
        ["jawaban berubah antar putaran", "0 link", `${changed.length} link`, changed.length === 0],
    ];
    for (const [k, b, h, ok] of checks) p(`| ${k} | ${b} | ${h} | ${ok ? "lulus" : "**gagal**"} |`);
    p("");
    p(`Scam yang tertangkap (${scamFlag.length} / ${scam.length}) dilaporkan saja, tanpa batas.`);
    p("");

    const tableHead = ["id", "domain", "gate produksi", "L2 ditemukan", "L2 dikirim (`link_checks`)", "L3 ditemukan", "L3 dikirim", "LLM (putaran 1)", "+30?", "konsisten", "waktu median / maks (ms)", "token rata-rata in / out / total"];
    const row = (s) => {
        const m = masker(s);
        const x = desc[s.id];
        const f = x.first;
        const llm = f?.verdict
            ? `\`${f.verdict.pageType}\`; asks ${f.verdict.asks.length ? f.verdict.asks.join("+") : "[]"}; reasonable=${f.verdict.reasonable}; conf ${f.verdict.confidence}; evidence ${f.verdict.evidence ? `"${m(f.verdict.evidence)}"` : "null"}`
            : `(${s.runs[0]?.outcome ?? "belum jalan"})`;
        const flagTxt = s.runs.length ? (x.anyFlag ? `ya (${x.flaggedN}/${x.n})` : `tidak (0/${x.n})`) : "-";
        const cons = !s.runs.length ? "-" : x.consistent ? `sama (${x.n}/${x.n})` : `**beda** (${s.runs.map((r) => (r.verdict ? `${r.verdict.pageType}/${r.verdict.reasonable}/${r.verdict.confidence}` : r.outcome)).join(" | ")})`;
        const tk = x.tokens;
        const t = tk.estimated ? "~" : "";
        const l3dikirim = `rules [${s.input.rules.join(", ")}]; brands [${s.input.brands.join(", ")}]; field ${s.input.fields.length}${s.input.fields.length ? ` (${s.input.fields.map((q) => `${q.type}:"${m(q.label)}"`).join(", ")})` : ""}`;
        return `| ${[
            s.id,
            `\`${maskHost(s.host)}\``,
            s.gate.passes ? "dipanggil" : `tidak (${s.gate.reason})`,
            l2Text(s.l2.signals),
            s.input.link_checks.length ? s.input.link_checks.join(", ") : "-",
            `${sigText(s.l3.signals)} (skor ${s.l3.score})`,
            l3dikirim,
            llm,
            flagTxt,
            cons,
            s.runs.length ? `${fmtMs(x.medianMs)} / ${fmtMs(x.maxMs)}${x.slow ? " ⚠" : ""}` : "-",
            s.runs.length ? `${t}${Math.round(tk.prompt)} / ${t}${Math.round(tk.completion)} / ${t}${Math.round(tk.total)}` : "-",
        ]
            .map(cell)
            .join(" | ")} |`;
    };
    const header = `| ${tableHead.join(" | ")} |\n|${tableHead.map(() => "---").join("|")}|`;
    p("## Tabel per link");
    p("");
    p("`rules` dan `brands` = persis isi yang dikirim ke LLM. Umur domain tidak dikirim.");
    p("");
    p("### Scam (25)");
    p("");
    p(header);
    for (const s of scam) p(row(s));
    p("");
    p("### Legit (10)");
    p("");
    p(header);
    for (const s of legit) p(row(s));
    p("");
    p("### Trap legit: GitHub Pages dokumentasi (sintetis, K8)");
    p("");
    p(header);
    for (const s of trap) p(row(s));
    p("");

    p("## Detail per link");
    p("");
    p("JSON di bawah = isi `user message` persis yang dikirim (di antara `DATA_START` dan `DATA_END`), domain disamarkan. `system message` sama untuk semua dan ada di akhir. Jawaban mentah = putaran 1.");
    p("");
    for (const s of samples) {
        const m = masker(s);
        const r1 = s.runs[0];
        p(`### ${s.id} ${maskedUrl(s)} (${s.kind})`);
        p("");
        p(`- Gate produksi: ${s.gate.passes ? "dipanggil" : `tidak dipanggil (${s.gate.reason})`}${s.skippedNoSite ? "; `site` null, `check()` berhenti di sini" : ""}`);
        p(`- L2: ${l2Text(s.l2.signals)}`);
        p(`- L3: ${sigText(s.l3.signals)}, skor ${s.l3.score}${s.rdapAgeDays != null ? `; umur domain beku ${s.rdapAgeDays} hari (tidak dikirim)` : ""}`);
        p("");
        p("```json");
        p(m(JSON.stringify(s.input, null, 2)));
        p("```");
        p("");
        p(`Jawaban mentah putaran 1 (${r1 ? `${r1.outcome}, ${r1.ms} ms, status ${r1.status}, finish ${r1.finish ?? "?"}` : "belum jalan"}):`);
        p("");
        p("```json");
        p(r1 ? m(r1.raw ?? r1.rawBody ?? "(kosong)") : "-");
        p("```");
        p("");
    }
    p("### System message (sama untuk semua)");
    p("");
    p("```");
    p(d.meta.systemPrompt);
    p("```");
    p("<!-- AUTO:END -->");

    const file = join(here, "HASIL.md");
    const old = await readFile(file, "utf8").catch(() => "");
    const i = old.indexOf("<!-- AUTO:END -->");
    const manual = i >= 0 ? old.slice(i + "<!-- AUTO:END -->".length) : "\n\n## Analisis\n\nBelum diisi.\n";
    await writeFile(file, lines.join("\n") + manual);
    console.log(`ok: ${file} (${samples.length} sampel, ${allRuns.length} panggilan)`);
}

if (flag("--report")) await report();
else await measure();
