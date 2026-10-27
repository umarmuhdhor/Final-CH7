#!/usr/bin/env node
// Runner for ai/testing/PLAN-model-compare.md. Compares several LLM models x thinking on/off on the SAME stored snapshots,
// through the real layer-4 code path (createRealityCheck, 6 s limit). Writes ONE folder:
//   ai/testing/<DD-mon-YYYY>/<NN>-testing-<HH.MM>/{report.md, llm-response.md, conclusions.html, results.json}
//
//   node ai/testing/tools/run-model-compare.mjs [--runs 8] [--diag 2] [--models a,b,c] [--samples p1.json,p2.json]
//                                               [--max-samples N] [--out-root dir] [--note "text"]
//
// Safety: NO network fetch of any scam page (snapshots already on disk are reused). Links are defanged. The API key is read
// from ai/.env, never printed, and every output file is scanned for it. The name must NOT end in "-test.mjs".
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import vm from "node:vm";

const R = fileURLToPath(new URL("../../../", import.meta.url));
const imp = (p) => import(pathToFileURL(join(R, p)).href);

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) args[argv[i].replace(/^--/, "")] = argv[i + 1];
const RUNS = Number(args.runs ?? 8);
const DIAG = Number(args.diag ?? 2);
const MODELS = (args.models ?? "deepseek-v4-flash,deepseek-v4.1-flash,deepseek-v4-flash-0731").split(",").map((s) => s.trim()).filter(Boolean);
const T = join(R, "ai/testing/26-oct-2026");
const DEFAULT_SAMPLES = ["07-testing-15.58", "08-testing-16.06", "09-testing-16.24"].map((d) => join(T, d, "captured-sample.json"));
let SAMPLE_FILES = (args.samples ?? DEFAULT_SAMPLES.join(",")).split(",").map((s) => s.trim()).filter(Boolean);
if (args["max-samples"]) SAMPLE_FILES = SAMPLE_FILES.slice(0, Number(args["max-samples"]));
const NOTE = args.note ?? "";
const INTO = args.into ?? null; // regenerate report/html from INTO/results.json, no LLM calls

// ---- helpers ---------------------------------------------------------------------------------------------------------
const pad = (n) => String(n).padStart(2, "0");
const MON = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const defang = (u) => String(u).replace(/^https?/i, (m) => (m.toLowerCase() === "https" ? "hxxps" : "hxxp")).replace(/\./g, "[.]");
const num = (x, d = 1) => (x == null || Number.isNaN(x) ? "-" : Number(x).toFixed(d).replace(".", ","));
const sec = (ms) => (ms == null ? "-" : num(ms / 1000, 2) + " s");
const sorted = (a) => [...a].sort((x, y) => x - y);
const median = (a) => {
    if (!a.length) return null;
    const s = sorted(a);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const pct = (a, p) => (a.length ? sorted(a)[Math.min(a.length - 1, Math.floor((p / 100) * a.length))] : null);
const esc = (s) => String(s ?? "").replace(/\|/g, "\\|").replace(/\n/g, " ");
const hesc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const git = (...a) => {
    try {
        return execFileSync("git", ["-C", R, ...a], { encoding: "utf8" }).trim();
    } catch {
        return "?";
    }
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- output folder -----------------------------------------------------------------------------------------------------
const now = args.into ? new Date(JSON.parse(readFileSync(join(args.into, "results.json"), "utf8")).meta.started) : new Date();
const outRoot = args["out-root"] ?? join(R, "ai/testing");
const dateName = `${pad(now.getDate())}-${MON[now.getMonth()]}-${now.getFullYear()}`;
const dateDir = join(outRoot, dateName);
const taken = existsSync(dateDir) ? readdirSync(dateDir).map((n) => /^(\d+)-testing-/.exec(n)).filter(Boolean).map((m) => Number(m[1])) : [];
const NN = pad(Math.max(0, ...taken) + 1);
const TIME = `${pad(now.getHours())}.${pad(now.getMinutes())}`;
const folderName = INTO ? INTO.split("/").slice(-1)[0] : `${NN}-testing-${TIME}`;
const OUT = INTO ?? join(dateDir, folderName);
mkdirSync(OUT, { recursive: true });
const PREV = INTO ? JSON.parse(readFileSync(join(INTO, "results.json"), "utf8")) : null;
const written = [];
const put = (rel, text) => {
    writeFileSync(join(OUT, rel), text);
    if (!written.includes(join(OUT, rel))) written.push(join(OUT, rel));
};
console.log(`folder: ${OUT}`);

// ---- imports + config ----------------------------------------------------------------------------------------------------
const ctx = { URL, console };
vm.createContext(ctx);
vm.runInContext(readFileSync(join(R, "ios/ShooExtension/Resources/detector.js"), "utf8"), ctx);
const { analyze, analyzeSnapshot } = await imp("ai/src/analyze.js");
const { buildInput, passesGate, createRealityCheck } = await imp("ai/src/layer4/reality.js");
const { sanitizeSnapshot } = await imp("ai/src/validate.js");
const { readConfig } = await imp("ai/src/layer4/config.js");
const { parseVerdict } = await imp("ai/src/layer4/schema.js");
const { SYSTEM_PROMPT, PROMPT_VERSION } = await imp("ai/prompts/reality-check.js");
try {
    process.loadEnvFile(join(R, "ai/.env"));
} catch (e) {
    if (e?.code !== "ENOENT") throw e;
}
const config = readConfig(process.env);
if (!config) throw new Error("layer 4 mati: LLM_API_KEY / LLM_MODEL / LLM_BASE_URL belum lengkap di ai/.env");
const endpoint = `${config.baseUrl}/chat/completions`;
const headers = { "content-type": "application/json", authorization: `Bearer ${config.apiKey}` };
const providerHost = new URL(config.baseUrl).host;

// ---- samples (stored snapshots, no network) -----------------------------------------------------------------------------------
const samples = [];
for (const f of SAMPLE_FILES) {
    const snap = JSON.parse(readFileSync(f, "utf8")).snapshot;
    const l3 = analyzeSnapshot(snap);
    const clean = sanitizeSnapshot(snap);
    const l3score = l3.reduce((a, x) => a + x.weight, 0);
    samples.push({
        file: f,
        snap,
        l3score,
        gate: passesGate(clean, { official: false, score: l3score }),
        input: buildInput(clean, l3.map((x) => x.id)),
        label: defang(snap.url ?? snap.domain),
        domain: snap.domain,
        local: await ctx.ShooDetector.analyzeLocal(snap),
    });
}
console.log(`samples: ${samples.map((s) => `${s.domain} (skor l3 ${s.l3score}, gate ${s.gate})`).join("; ")}`);

// ---- LLM helpers ---------------------------------------------------------------------------------------------------------------
const reasoningTokens = (u) => u?.completion_tokens_details?.reasoning_tokens ?? u?.reasoning_tokens ?? null;
const body = (model, sample, extra = {}) => ({ model, messages: [{ role: "system", content: SYSTEM_PROMPT }, { role: "user", content: `DATA_START\n${JSON.stringify(sample.input)}\nDATA_END` }], temperature: 0, max_tokens: 200, response_format: { type: "json_object" }, ...extra });
const plain = async (model, sample, extra) => {
    const t0 = performance.now();
    try {
        const res = await fetch(endpoint, { method: "POST", headers, body: JSON.stringify(body(model, sample, extra)), signal: AbortSignal.timeout(90000) });
        const text = await res.text();
        const totalMs = performance.now() - t0;
        let b = null;
        try {
            b = JSON.parse(text);
        } catch {}
        const m = b?.choices?.[0];
        const v = parseVerdict(m?.message?.content);
        const rc = m?.message?.reasoning_content ?? m?.message?.reasoning ?? "";
        return { http: res.status, totalMs, finish: m?.finish_reason ?? null, usage: b?.usage ?? null, reasoningTokens: reasoningTokens(b?.usage), reasoningChars: String(rc).length, content: m?.message?.content ?? null, verdict: v ? { reasonable: v.reasonable, confidence: v.confidence } : null, error: b?.error?.message ?? (res.ok ? null : text.slice(0, 200)) };
    } catch (e) {
        return { totalMs: performance.now() - t0, reasoningChars: 0, error: `${e.name}: ${e.message}` };
    }
};
const hasReasoning = (r) => (r.reasoningTokens ?? 0) > 0 || r.reasoningChars > 0;

// ---- stage A: probe how to turn thinking off, per model --------------------------------------------------------------------
const OFF_CANDIDATES = [
    ["thinking:{type:disabled}", { thinking: { type: "disabled" } }],
    ["reasoning:{enabled:false}", { reasoning: { enabled: false } }],
    ["reasoning_effort:none", { reasoning_effort: "none" }],
    ["chat_template_kwargs:{thinking:false}", { chat_template_kwargs: { thinking: false } }],
    ["enable_thinking:false", { enable_thinking: false }],
];
const probeSample = samples.find((s) => s.gate) ?? samples[0];
const probe = PREV ? PREV.probe : {};
for (const model of PREV ? [] : MODELS) {
    const p = { on: await plain(model, probeSample, {}), tried: [], off: null, offEffective: false };
    console.log(`probe ${model} default: ${Math.round(p.on.totalMs)} ms, reasoning tokens ${p.on.reasoningTokens ?? "-"}, http ${p.on.http ?? p.on.error}`);
    for (const [name, extra] of OFF_CANDIDATES) {
        const r = await plain(model, probeSample, extra);
        const ok = r.http === 200 && !hasReasoning(r); // "effective" = thinking is gone; answer validity is measured separately (bad_schema)
        p.tried.push({ name, http: r.http ?? null, totalMs: r.totalMs, reasoningTokens: r.reasoningTokens, reasoningChars: r.reasoningChars, valid: Boolean(r.verdict), error: r.error, effective: ok });
        console.log(`  off? ${name}: http ${r.http ?? "-"}, reasoning ${r.reasoningTokens ?? "-"}/${r.reasoningChars} chars, ${Math.round(r.totalMs)} ms -> ${ok ? "EFEKTIF" : "tidak"}`);
        if (ok) {
            p.off = { name, extra };
            p.offEffective = true;
            break;
        }
        await sleep(250);
    }
    if (!p.off) p.off = { name: OFF_CANDIDATES[0][0], extra: OFF_CANDIDATES[0][1] }; // documented, but has no effect
    probe[model] = p;
}

// ---- stage B: main matrix (round-robin so provider load drifts evenly across configs) -------------------------------------------
const configs = MODELS.flatMap((model) => [
    { id: `${model} | default`, model, mode: "default", extra: {} },
    { id: `${model} | thinking off`, model, mode: "off", extra: probe[model].off.extra, offName: probe[model].off.name, offEffective: probe[model].offEffective },
]);
const results = PREV ? PREV.results : [];
const diagRows = PREV ? PREV.diagRows : [];
let consecutiveErrors = 0;
let aborted = null;
const save = () => put("results.json", JSON.stringify({ meta: { promptVersion: PROMPT_VERSION, models: MODELS, runs: RUNS, diag: DIAG, started: now.toISOString() }, probe, results, diagRows }, null, 2));

outer: for (let i = 1; i <= (PREV ? 0 : RUNS); i++) {
    for (const sample of samples) {
        if (!sample.gate) continue;
        for (const c of configs) {
            let raw = null;
            const spy = async (u, init) => {
                const b = { ...JSON.parse(init.body), model: c.model, ...c.extra };
                const res = await fetch(u, { ...init, body: JSON.stringify(b) });
                raw = await res.clone().text();
                return res;
            };
            const check = createRealityCheck({ config: { ...config, model: c.model }, fetch: spy });
            const t0 = performance.now();
            const signals = await analyze(sample.snap, { rdap: null, llm: check, localSignals: sample.local, client: `cmp-${i}`, deadline: Date.now() + 6500 });
            const totalMs = performance.now() - t0;
            let parsed = null;
            try {
                parsed = JSON.parse(raw);
            } catch {}
            const outcome = Object.entries(check.stats().outcomes).find(([, v]) => v > 0)?.[0] ?? "?";
            const content = parsed?.choices?.[0]?.message?.content ?? null;
            const v = parseVerdict(content);
            results.push({ run: i, sample: sample.domain, config: c.id, model: c.model, mode: c.mode, outcome, totalMs, finish: parsed?.choices?.[0]?.finish_reason ?? null, usage: parsed?.usage ?? null, reasoningTokens: reasoningTokens(parsed?.usage), verdict: v ? { reasonable: v.reasonable, confidence: v.confidence } : null, content, score: signals.reduce((a, s) => a + s.weight, 0) });
            consecutiveErrors = outcome === "http_error" ? consecutiveErrors + 1 : 0;
            console.log(`  #${i} ${sample.domain} ${c.id}: ${Math.round(totalMs)} ms ${outcome}`);
            if (consecutiveErrors >= 20) {
                aborted = "20 http_error berturut-turut (key/saldo/proxy bermasalah): run dihentikan";
                break outer;
            }
            await sleep(250);
        }
        if (i <= DIAG) {
            for (const c of configs) {
                const r = await plain(c.model, sample, c.extra);
                diagRows.push({ run: i, sample: sample.domain, config: c.id, model: c.model, mode: c.mode, ...r });
                console.log(`  diag #${i} ${sample.domain} ${c.id}: ${Math.round(r.totalMs)} ms reasoning ${r.reasoningTokens ?? "-"}`);
                await sleep(250);
            }
        }
    }
    save();
}
if (!PREV) save();

// ---- aggregate --------------------------------------------------------------------------------------------------------------------
const agg = configs.map((c) => {
    const rs = results.filter((r) => r.config === c.id);
    const ds = diagRows.filter((r) => r.config === c.id && !r.error);
    const done = rs.filter((r) => !["timeout", "http_error", "capped"].includes(r.outcome));
    const outcomes = {};
    for (const r of rs) outcomes[r.outcome] = (outcomes[r.outcome] ?? 0) + 1;
    const rt = ds.map((r) => r.reasoningTokens).filter((x) => x != null);
    return {
        ...c,
        n: rs.length,
        outcomes,
        timeouts: outcomes.timeout ?? 0,
        flagged: outcomes.flagged ?? 0,
        medDone: median(done.map((r) => r.totalMs)),
        p90Done: pct(done.map((r) => r.totalMs), 90),
        medDiag: median(ds.map((r) => r.totalMs)),
        maxDiag: ds.length ? Math.max(...ds.map((r) => r.totalMs)) : null,
        medReasoning: rt.length ? median(rt) : null,
        badSchema: outcomes.bad_schema ?? 0,
        httpErr: outcomes.http_error ?? 0,
        score30: rs.filter((r) => r.score >= 30).length,
    };
});
const gatedOut = samples.filter((s) => !s.gate).map((s) => s.domain);

const label = (a) => `${a.model} · ${a.mode === "off" ? "thinking off" : "default"}`;

// ---- conclusions (rule-based; manual analysis may follow) -------------------------------------------------------------------------
const concl = [];
const best = [...agg].filter((a) => a.n).sort((a, b) => b.flagged / b.n - a.flagged / a.n || a.timeouts - b.timeouts || (a.medDone ?? 1e9) - (b.medDone ?? 1e9))[0];
if (best) concl.push(`Paling sering menandai scam (flagged = LLM selesai < 6 s dan benar): **${label(best)}**, ${best.flagged}/${best.n} run, timeout ${best.timeouts}/${best.n}, median selesai ${sec(best.medDone)}. Skor akhir ≥ 30 sengaja tidak dipakai: sampel blogspot sudah 40 dari layer 3 tanpa LLM.`);
for (const model of MODELS) {
    const d = agg.find((a) => a.model === model && a.mode === "default");
    const o = agg.find((a) => a.model === model && a.mode === "off");
    if (!d || !o) continue;
    const pr = probe[model];
    if (!pr.offEffective) concl.push(`${model}: **tidak ada cara mematikan thinking yang berhasil** (dicoba ${pr.tried.length} field; token reasoning tetap > 0 atau ditolak). Baris "thinking off" model ini sama dengan default, jangan dibaca sebagai efek mematikan thinking.`);
    else concl.push(`${model}: thinking bisa dimatikan lewat \`${pr.off.name}\`. Timeout ${d.timeouts}/${d.n} → ${o.timeouts}/${o.n}; median non-stream ${sec(d.medDiag)} → ${sec(o.medDiag)}; flagged ${d.flagged}/${d.n} → ${o.flagged}/${o.n}.`);
}
concl.push("Satu sesi, 3 sampel scam (semua seharusnya terdeteksi), n kecil per konfigurasi: selisih satu dua run bukan bukti. Waktu penyedia berubah menurut beban (urutan run di-interleave supaya adil).");

// ---- report.md ----------------------------------------------------------------------------------------------------------------------
const probeRows = MODELS.map((m) => `| \`${m}\` | ${probe[m].on.reasoningTokens ?? "-"} (${probe[m].on.reasoningChars} char) | ${probe[m].tried.map((t) => `\`${t.name}\``).join(", ")} | ${probe[m].tried.map((t) => (t.effective ? `**efektif** (jawaban ${t.valid ? "valid" : "TIDAK valid"})` : t.http && t.http !== 200 ? `http ${t.http}` : `reasoning ${t.reasoningTokens ?? "-"}`)).join(", ")} | ${probe[m].offEffective ? `\`${probe[m].off.name}\`` : "(tidak ada yang efektif)"} |`).join("\n");
const aggRows = agg.map((a) => `| ${label(a)}${a.mode === "off" && !a.offEffective ? " *(off tidak efektif)*" : ""} | ${a.n} | ${a.flagged} | ${a.timeouts} | ${a.badSchema} | ${a.httpErr} | ${a.score30} | ${sec(a.medDone)} / ${sec(a.p90Done)} | ${sec(a.medDiag)} / ${sec(a.maxDiag)} | ${a.medReasoning ?? "-"} |`).join("\n");
const perSample = agg.map((a) => `| ${label(a)} | ${samples.map((s) => { const rs = results.filter((r) => r.config === a.id && r.sample === s.domain); return rs.length ? `${rs.filter((r) => r.outcome === "flagged").length} / ${rs.filter((r) => r.outcome === "timeout").length} dari ${rs.length}` : "-"; }).join(" | ")} |`).join("\n");
const rep = `# Testing ${NN}: bandingkan model x thinking on/off

> Tanggal: ${now.getDate()} ${MON[now.getMonth()]} ${now.getFullYear()}, ${TIME} · folder \`${dateName}/${folderName}\` · branch \`${git("branch", "--show-current")}\` @ \`${git("rev-parse", "--short", "HEAD")}\` · plan \`PLAN-model-compare.md\`, runner \`tools/run-model-compare.mjs\`
> Visualisasi: \`conclusions.html\` · data mentah: \`results.json\` · request/jawaban: \`llm-response.md\`
${aborted ? `\n> **DIHENTIKAN LEBIH AWAL:** ${aborted}\n` : ""}
## 1. Setelan

| Item | Nilai |
|---|---|
| Penyedia | \`${providerHost}\` |
| Model | ${MODELS.map((m) => `\`${m}\``).join(", ")} |
| Mode | default (tanpa field tambahan, = produksi) vs thinking off (field hasil probe tahap A) |
| Prompt | \`${PROMPT_VERSION}\` · \`temperature\` 0 · \`max_tokens\` 200 · \`json_object\` |
| Batas layer 4 | ${config.timeoutMs} ms (kode asli \`createRealityCheck\`) |
| Run | ${RUNS} putaran × ${samples.length} sampel × ${configs.length} konfigurasi, + ${DIAG} panggilan tanpa batas waktu per sampel per konfigurasi |
| Sampel (snapshot tersimpan, tidak diambil ulang) | ${samples.map((s) => `\`${s.label}\` (skor layer 3 ${s.l3score})`).join(", ")} |
${gatedOut.length ? `| Tidak lolos gerbang LLM (dilewati) | ${gatedOut.join(", ")} |\n` : ""}| Catatan | ${NOTE || "-"} |

## 2. Tahap A: bisakah thinking dimatikan?

| Model | Default: token reasoning | Field yang dicoba (urut) | Hasil | Dipakai untuk "off" |
|---|---|---|---|---|
${probeRows}

## 3. Hasil per konfigurasi

| Konfigurasi | n | flagged | timeout | bad_schema | http_error | skor ≥ 30 (inflasi layer 3) | selesai: median / p90 | non-stream: median / maks | token reasoning (median) |
|---|---|---|---|---|---|---|---|---|---|
${aggRows}

## 4. Per sampel (flagged / timeout dari n)

| Konfigurasi | ${samples.map((s) => s.domain).join(" | ")} |
|---|${samples.map(() => "---").join("|")}|
${perSample}

## 5. Kesimpulan otomatis

${concl.map((c) => `- ${c}`).join("\n")}

## 6. Analisis (diisi Claude setelah Imelda bangun)

_Belum diisi._

## 7. Batasan

- Satu penyedia, satu mesin, satu malam. n kecil. Sampel dari snapshot lama (\`redacted: false\`, jangan masuk eval set sebelum diperiksa).
- "flagged" = layer 4 menandai tidak wajar; semua sampel adalah halaman scam, jadi flagged = benar, reasonable = lolos (salah), timeout = tidak ada hasil.
- Layer 1 (blocklist) dan RDAP tidak ikut.
`;
put("report.md", rep);

// ---- llm-response.md ---------------------------------------------------------------------------------------------------------------------
const md = `# Request dan jawaban LLM (${providerHost})

> Testing ${NN} · prompt \`${PROMPT_VERSION}\` · API key tidak ikut tersimpan. Semua jawaban mentah ada di \`results.json\`.

## 1. Request contoh (model pertama, sampel pertama, default)

\`\`\`json
${JSON.stringify({ ...body(MODELS[0], samples[0]), messages: [{ role: "system", content: `(system prompt ${PROMPT_VERSION}, bagian 3)` }, { role: "user", content: `DATA_START\n${JSON.stringify(samples[0].input)}\nDATA_END` }] }, null, 2)}
\`\`\`

## 2. Jawaban tiap run yang selesai

| Run | Sampel | Konfigurasi | Hasil | Waktu | Token reasoning | Jawaban |
|---|---|---|---|---|---|---|
${results.filter((r) => r.content).map((r) => `| ${r.run} | ${r.sample} | ${r.config} | ${r.outcome} | ${sec(r.totalMs)} | ${r.reasoningTokens ?? "-"} | \`${esc(String(r.content).replace(/\s+/g, " ").slice(0, 300))}\` |`).join("\n")}

## 3. System prompt (\`${PROMPT_VERSION}\`)

\`\`\`text
${SYSTEM_PROMPT}
\`\`\`
`;
put("llm-response.md", md);

// ---- conclusions.html (self-contained, inline SVG) ------------------------------------------------------------------------------------------
const COL = { default: "var(--c-default)", off: "var(--c-off)" };
const shortModel = (m) => m.replace("deepseek-", "");
function bars(title, sub, valueOf, fmt, unit) {
    const W = 760;
    const rowH = 26;
    const vals = agg.map(valueOf).filter((v) => v != null);
    const max = Math.max(1e-9, ...vals);
    const H = MODELS.length * (rowH * 2 + 18) + 10;
    let y = 4;
    let svg = "";
    for (const m of MODELS) {
        svg += `<text x="0" y="${y + 12}" class="gl">${hesc(shortModel(m))}</text>`;
        y += 18;
        for (const mode of ["default", "off"]) {
            const a = agg.find((x) => x.model === m && x.mode === mode);
            const v = valueOf(a);
            const w = v == null ? 0 : Math.max(2, (v / max) * (W - 330));
            const note = mode === "off" && !a.offEffective ? " (off tidak efektif)" : "";
            svg += `<text x="140" y="${y + 14}" text-anchor="end" class="al">${mode === "off" ? "thinking off" : "default"}</text><rect x="150" y="${y}" width="${w}" height="${rowH - 6}" rx="3" fill="${COL[mode]}"${note ? ' opacity="0.45"' : ""}/><text x="${158 + w}" y="${y + 14}" class="vl">${v == null ? "-" : hesc(fmt(v))}${unit}${hesc(note)}</text>`;
            y += rowH;
        }
    }
    return `<section class="card"><h2>${hesc(title)}</h2><p class="sub">${hesc(sub)}</p><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${hesc(title)}">${svg}</svg></section>`;
}
const OC = { flagged: "var(--ok)", reasonable: "var(--bad)", timeout: "var(--mute)", http_error: "var(--warn)", bad_schema: "var(--warn)", capped: "var(--warn)" };
const heat = `<section class="card"><h2>Peta hasil per run</h2><p class="sub">Tiap kotak = satu run. Hijau = flagged (benar), merah = lolos (salah), abu = timeout, kuning = error atau skema salah.</p>${agg
    .map((a) => `<div class="hrow"><span class="hl">${hesc(shortModel(a.model))} · ${a.mode === "off" ? "thinking off" : "default"}${a.mode === "off" && !a.offEffective ? " *" : ""}</span><span class="cells">${results.filter((r) => r.config === a.id).map((r) => `<i title="run ${r.run} · ${hesc(r.sample)} · ${r.outcome} · ${sec(r.totalMs)}" style="background:${OC[r.outcome] ?? "var(--mute)"}"></i>`).join("")}</span></div>`)
    .join("")}<p class="sub">* thinking tidak bisa dimatikan di model ini; baris sama dengan default.</p></section>`;
const trs = agg.map((a) => `<tr><td>${hesc(shortModel(a.model))}</td><td>${a.mode === "off" ? "thinking off" : "default"}${a.mode === "off" && !a.offEffective ? " *" : ""}</td><td>${a.flagged}/${a.n}</td><td>${a.timeouts}/${a.n}</td><td>${sec(a.medDone)}</td><td>${sec(a.medDiag)}</td><td>${a.medReasoning ?? "-"}</td><td>${a.badSchema + a.httpErr}/${a.n}</td></tr>`).join("");
const html = `<!doctype html>
<html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Model Thinking Compare</title>
<style>
:root{--bg:#f6f5f2;--card:#fff;--fg:#1d1c1a;--mute:#9a968f;--line:#e3e0d9;--c-default:#3b5ccc;--c-off:#e08a1e;--ok:#2f9e5f;--bad:#d1453b;--warn:#d9b100}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#151514;--card:#1f1e1c;--fg:#ecebe7;--mute:#77736c;--line:#33312d;--c-default:#7d97f0;--c-off:#f0a94a;--ok:#4cc386;--bad:#ef6c62;--warn:#e8c43a}}
:root[data-theme="dark"]{--bg:#151514;--card:#1f1e1c;--fg:#ecebe7;--mute:#77736c;--line:#33312d;--c-default:#7d97f0;--c-off:#f0a94a;--ok:#4cc386;--bad:#ef6c62;--warn:#e8c43a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,system-ui,sans-serif}
main{max-width:860px;margin:0 auto;padding:24px 16px 64px}h1{font-size:24px;margin:0 0 4px}h2{font-size:16px;margin:0 0 2px}
.meta{color:var(--mute);font-size:13px;margin-bottom:20px}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:0 0 16px}
.sub{color:var(--mute);font-size:13px;margin:0 0 10px}svg{width:100%;height:auto;display:block}.gl{font-weight:600;font-size:13px;fill:var(--fg)}.al{font-size:12px;fill:var(--mute)}.vl{font-size:12px;fill:var(--fg)}
.legend span{display:inline-flex;align-items:center;gap:6px;margin-right:14px;font-size:13px}.legend i{width:12px;height:12px;border-radius:3px;display:inline-block}
ul{margin:0;padding-left:18px}li{margin:6px 0}table{width:100%;border-collapse:collapse;font-size:13px;display:block;overflow-x:auto}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
.hrow{display:flex;gap:10px;align-items:center;margin:4px 0}.hl{width:190px;flex:none;font-size:12px;color:var(--mute)}.cells{display:flex;flex-wrap:wrap;gap:2px}.cells i{width:11px;height:11px;border-radius:2px;display:inline-block}
@media (max-width:560px){.hrow{flex-direction:column;align-items:flex-start}.hl{width:auto}}
</style></head><body><main>
<h1>Model × thinking</h1>
<p class="meta">Testing ${NN} · ${now.getDate()} ${MON[now.getMonth()]} ${now.getFullYear()} · ${hesc(providerHost)} · prompt ${hesc(PROMPT_VERSION)} · ${RUNS} putaran × ${samples.length} sampel scam · batas ${config.timeoutMs / 1000} s${aborted ? ` · <b>DIHENTIKAN: ${hesc(aborted)}</b>` : ""}</p>
<div class="card legend"><span><i style="background:var(--c-default)"></i>default (produksi)</span><span><i style="background:var(--c-off)"></i>thinking off</span></div>
<section class="card"><h2>Kesimpulan</h2><ul>${concl.map((c) => `<li>${hesc(c).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/`(.+?)`/g, "<code>$1</code>")}</li>`).join("")}</ul></section>
${bars("Berhasil menandai scam (flagged)", "Makin tinggi makin baik: persen run di mana LLM selesai dalam 6 s dan menandai halaman scam.", (a) => (a.n ? (a.flagged / a.n) * 100 : null), (v) => v.toFixed(0), "%")}
${bars("Timeout (batas 6 s)", "Makin rendah makin baik.", (a) => (a.n ? (a.timeouts / a.n) * 100 : null), (v) => v.toFixed(0), "%")}
${bars("Waktu selesai, median (run yang tidak timeout)", "Lewat kode asli, detik.", (a) => (a.medDone == null ? null : a.medDone / 1000), (v) => v.toFixed(2), " s")}
${bars("Waktu non-stream tanpa batas, median", "Berapa lama penyedia sebenarnya butuh.", (a) => (a.medDiag == null ? null : a.medDiag / 1000), (v) => v.toFixed(2), " s")}
${bars("Token reasoning, median", "0 = thinking benar-benar mati.", (a) => a.medReasoning, (v) => v.toFixed(0), " tok")}
${heat}
<section class="card"><h2>Tabel ringkas</h2><table><thead><tr><th>Model</th><th>Mode</th><th>flagged</th><th>timeout</th><th>selesai (median)</th><th>non-stream (median)</th><th>token reasoning</th><th>error/skema</th></tr></thead><tbody>${trs}</tbody></table></section>
<p class="meta">Kesimpulan dibuat otomatis oleh runner dari data mentah (<code>results.json</code>). Satu sesi, n kecil: selisih satu dua run bukan bukti. Analisis manual ada di <code>report.md</code> bagian 6.</p>
</main></body></html>`;
put("conclusions.html", html);

// ---- key leak check -----------------------------------------------------------------------------------------------------------------------------
for (const f of written) {
    if (readFileSync(f, "utf8").includes(config.apiKey)) {
        rmSync(f);
        throw new Error(`API key ditemukan di ${f}; file dihapus.`);
    }
}
console.log(`selesai. file: ${written.map((f) => f.slice(OUT.length + 1)).join(", ")}`);
console.log(`OUT=${OUT}`);
