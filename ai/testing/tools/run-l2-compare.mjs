#!/usr/bin/env node
// Runner: does adding the layer-2 v2 link score (prototype dissect2.mjs) to the layer-4 input help? 3 models x 2 arms, thinking OFF.
//   arm "tanpa L2" = production input and prompt (reality-check.v3)
//   arm "dengan L2" = same + input.link = { score, hints } and one extra paragraph in the system prompt (experiment only, nothing in ai/src changes)
// Samples: 2 real scam snapshots, synthetic scam, legit "traps" (legit pages that look suspicious) -> measures catches AND false positives.
// Calls the provider directly (no production gate: every sample is judged), 6 s limit, same flagged rule as reality.js.
//
//   node ai/testing/tools/run-l2-compare.mjs [--runs 4] [--models a,b,c] [--out-root dir] [--note "text"]
//
// Safety: no network fetch of any page (snapshots on disk). Links defanged in output. API key never printed; every output file is scanned for it.
// The name must NOT end in "-test.mjs".
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const R = fileURLToPath(new URL("../../../", import.meta.url));
const imp = (p) => import(pathToFileURL(join(R, p)).href);
const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) args[argv[i].replace(/^--/, "")] = argv[i + 1];
const RUNS = Number(args.runs ?? 4);
const MODELS = (args.models ?? "deepseek-v4-flash,deepseek-v4.1-flash,deepseek-v4-flash-0731").split(",").map((s) => s.trim());
const NOTE = args.note ?? "";
const OFF = { chat_template_kwargs: { thinking: false } };
const LIMIT_MS = 6000;

const pad = (n) => String(n).padStart(2, "0");
const MON = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const num = (x, d = 1) => (x == null || Number.isNaN(x) ? "-" : Number(x).toFixed(d).replace(".", ","));
const sec = (ms) => (ms == null ? "-" : num(ms / 1000, 2) + " s");
const median = (a) => {
    if (!a.length) return null;
    const s = [...a].sort((x, y) => x - y);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const hesc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const esc = (s) => String(s ?? "").replace(/\|/g, "\\|").replace(/\n/g, " ");
const git = (...a) => {
    try {
        return execFileSync("git", ["-C", R, ...a], { encoding: "utf8" }).trim();
    } catch {
        return "?";
    }
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- output folder ----------------------------------------------------------------------------------------------------
const now = new Date();
const dateName = `${pad(now.getDate())}-${MON[now.getMonth()]}-${now.getFullYear()}`;
const dateDir = join(args["out-root"] ?? join(R, "ai/testing"), dateName);
const taken = existsSync(dateDir) ? readdirSync(dateDir).map((n) => /^(\d+)-testing-/.exec(n)).filter(Boolean).map((m) => Number(m[1])) : [];
const NN = pad(Math.max(0, ...taken) + 1);
const TIME = `${pad(now.getHours())}.${pad(now.getMinutes())}`;
const folderName = `${NN}-testing-${TIME}`;
const OUT = join(dateDir, folderName);
mkdirSync(OUT, { recursive: true });
const written = [];
const put = (rel, text) => {
    writeFileSync(join(OUT, rel), text);
    if (!written.includes(join(OUT, rel))) written.push(join(OUT, rel));
};
console.log(`folder: ${OUT}`);

// ---- imports + config --------------------------------------------------------------------------------------------------
const { analyzeSnapshot } = await imp("ai/src/analyze.js");
const { buildInput, MIN_CONFIDENCE } = await imp("ai/src/layer4/reality.js");
const { sanitizeSnapshot } = await imp("ai/src/validate.js");
const { readConfig } = await imp("ai/src/layer4/config.js");
const { parseVerdict } = await imp("ai/src/layer4/schema.js");
const { SYSTEM_PROMPT, PROMPT_VERSION } = await imp("ai/prompts/reality-check.js");
const { dissect2 } = await imp("ai/testing/26-oct-2026/06-testing-14.57/dissect2.mjs");
try {
    process.loadEnvFile(join(R, "ai/.env"));
} catch (e) {
    if (e?.code !== "ENOENT") throw e;
}
const config = readConfig(process.env);
if (!config) throw new Error("layer 4 mati: LLM_API_KEY / LLM_MODEL / LLM_BASE_URL belum lengkap di ai/.env");
const endpoint = `${config.baseUrl}/chat/completions`;
const headers = { "content-type": "application/json", authorization: `Bearer ${config.apiKey}` };

const L2_PARAGRAPH = `

About link: when the data has "link", it is our own check of the page ADDRESS only. "score" is 0-100 (15 or more = the address looks suspicious) and "hints" are names of the address checks that fired (for example freehost = the page sits on a free hosting service). The address alone never proves a scam: honest blogs, documentation and small shops also use free hosts or words like "login". Use it only as one more reason to doubt a request for a password, PIN, OTP or card, never as the only reason. If link is missing, ignore this paragraph.`;

// ---- samples ----------------------------------------------------------------------------------------------------------------
const T = join(R, "ai/testing/26-oct-2026");
const corpus = (f) => {
    const j = JSON.parse(readFileSync(join(R, "ai/eval/data", f), "utf8"));
    return Array.isArray(j) ? j : j.samples ?? [j];
};
const SYN = ["syn-anteraja-alamat", "syn-etilang-denda", "syn-apple-pay-tagihan", "syn-tiki-nomor-resi", "syn-telkomsel-poin", "syn-linkaja-hadiah"];
const raw = [
    ...["07-testing-15.58", "08-testing-16.06"].map((d) => ({ kind: "scam-real", id: d, snapshot: JSON.parse(readFileSync(join(T, d, "captured-sample.json"), "utf8")).snapshot })),
    ...corpus("scam/synthetic.json").filter((s) => SYN.includes(s.id)).map((s) => ({ kind: "scam-syn", id: s.id, snapshot: s.snapshot })),
    ...corpus("legit/traps.json").filter((s) => s.snapshot.forms?.some((f) => f.fields.length)).map((s) => ({ kind: "legit-trap", id: s.id, snapshot: s.snapshot })),
];
const HINT_OK = new Set(["scheme", "userinfo", "host", "tld", "port", "path", "path-ext", "path-slash", "path-bait", "query", "fragment", "length", "freehost", "free-label", "free-number", "free-path"]);
const samples = raw.map((s) => {
    const clean = sanitizeSnapshot(s.snapshot);
    const l3 = analyzeSnapshot(s.snapshot);
    const input = buildInput(clean, l3.map((x) => x.id));
    const d = dissect2(s.snapshot.url ?? "");
    const hints = [...new Set(d.parts.filter((p) => p.weight > 0 && HINT_OK.has(p.part)).map((p) => p.part))];
    return { ...s, l3score: l3.reduce((a, x) => a + x.weight, 0), l2score: d.score, inputPlain: input, inputL2: { ...input, link: { score: d.score, hints } } };
});
console.log(`samples: ${samples.length} (${["scam-real", "scam-syn", "legit-trap"].map((k) => `${k} ${samples.filter((s) => s.kind === k).length}`).join(", ")})`);

// ---- call -----------------------------------------------------------------------------------------------------------------------
const ARMS = [
    { id: "tanpa", label: "tanpa L2", prompt: SYSTEM_PROMPT, pick: (s) => s.inputPlain },
    { id: "dengan", label: "dengan L2 v2", prompt: SYSTEM_PROMPT + L2_PARAGRAPH, pick: (s) => s.inputL2 },
];
async function call(model, arm, sample) {
    const body = { model, messages: [{ role: "system", content: arm.prompt }, { role: "user", content: `DATA_START\n${JSON.stringify(arm.pick(sample))}\nDATA_END` }], temperature: 0, max_tokens: 200, response_format: { type: "json_object" }, ...OFF };
    const t0 = performance.now();
    try {
        const res = await fetch(endpoint, { method: "POST", headers, body: JSON.stringify(body), signal: AbortSignal.timeout(LIMIT_MS) });
        const text = await res.text();
        const ms = performance.now() - t0;
        let b = null;
        try {
            b = JSON.parse(text);
        } catch {}
        const content = b?.choices?.[0]?.message?.content ?? null;
        if (!res.ok) return { outcome: "http_error", ms, content: null, status: res.status };
        const v = parseVerdict(content);
        if (!v) return { outcome: "bad_schema", ms, content };
        const outcome = v.reasonable || v.confidence < MIN_CONFIDENCE || v.asks.length === 0 ? "reasonable" : "flagged";
        return { outcome, ms, content, verdict: { reasonable: v.reasonable, confidence: v.confidence, asks: v.asks } };
    } catch (e) {
        const ms = performance.now() - t0;
        return { outcome: /abort|timeout/i.test(e.name + e.message) ? "timeout" : "http_error", ms, content: null, error: e.name };
    }
}

const results = [];
let errStreak = 0;
let aborted = null;
const save = () => put("results.json", JSON.stringify({ meta: { promptVersion: PROMPT_VERSION, models: MODELS, runs: RUNS, limitMs: LIMIT_MS, started: now.toISOString() }, samples: samples.map((s) => ({ id: s.id, kind: s.kind, l3score: s.l3score, l2score: s.l2score, link: s.inputL2.link })), results }, null, 2));
outer: for (let i = 1; i <= RUNS; i++) {
    for (const s of samples) {
        for (const model of MODELS) {
            for (const arm of ARMS) {
                const r = await call(model, arm, s);
                results.push({ run: i, sample: s.id, kind: s.kind, model, arm: arm.id, ...r });
                errStreak = r.outcome === "http_error" ? errStreak + 1 : 0;
                console.log(`  #${i} ${s.id} ${model} ${arm.id}: ${Math.round(r.ms)} ms ${r.outcome}`);
                if (errStreak >= 25) {
                    aborted = "25 http_error berturut-turut: run dihentikan";
                    break outer;
                }
                await sleep(200);
            }
        }
    }
    save();
}
save();

// ---- aggregate ---------------------------------------------------------------------------------------------------------------------
const cfgs = MODELS.flatMap((m) => ARMS.map((a) => ({ model: m, arm: a.id, label: `${m} · ${a.label}` })));
const agg = cfgs.map((c) => {
    const rs = results.filter((r) => r.model === c.model && r.arm === c.arm);
    const by = (k) => rs.filter((r) => r.kind === k);
    const done = rs.filter((r) => !["timeout", "http_error"].includes(r.outcome));
    return {
        ...c,
        n: rs.length,
        real: by("scam-real"),
        syn: by("scam-syn"),
        legit: by("legit-trap"),
        realFlag: by("scam-real").filter((r) => r.outcome === "flagged").length,
        synFlag: by("scam-syn").filter((r) => r.outcome === "flagged").length,
        fp: by("legit-trap").filter((r) => r.outcome === "flagged").length,
        timeouts: rs.filter((r) => r.outcome === "timeout").length,
        bad: rs.filter((r) => r.outcome === "bad_schema").length,
        err: rs.filter((r) => r.outcome === "http_error").length,
        med: median(done.map((r) => r.ms)),
    };
});
const A = (m, a) => agg.find((x) => x.model === m && x.arm === a);
const concl = [];
for (const m of MODELS) {
    const t = A(m, "tanpa");
    const d = A(m, "dengan");
    concl.push(`${m}: scam nyata flagged ${t.realFlag}/${t.real.length} → ${d.realFlag}/${d.real.length}; scam sintetis ${t.synFlag}/${t.syn.length} → ${d.synFlag}/${d.syn.length}; **false positive pada halaman sah ${t.fp}/${t.legit.length} → ${d.fp}/${d.legit.length}**; timeout ${t.timeouts}/${t.n} → ${d.timeouts}/${d.n} (tanpa L2 → dengan L2 v2).`);
}
concl.push("n kecil (4 putaran), 2 scam nyata dan 9 halaman sah; scam sintetis berurl buatan. Selisih satu dua run bukan bukti, dan timeout membuat banyak run tidak punya jawaban.");

// ---- report.md ---------------------------------------------------------------------------------------------------------------------------
const sampleRows = samples.map((s) => `| ${s.kind} | \`${esc(s.id)}\` | ${s.l3score} | ${s.l2score} | ${s.inputL2.link.hints.join(", ") || "-"} |`).join("\n");
const aggRows = agg.map((a) => `| ${a.label} | ${a.realFlag}/${a.real.length} | ${a.synFlag}/${a.syn.length} | **${a.fp}/${a.legit.length}** | ${a.timeouts} | ${a.bad} | ${a.err} | ${sec(a.med)} |`).join("\n");
const perSample = samples
    .map((s) => `| ${s.kind} | \`${esc(s.id)}\` | ${cfgs.map((c) => { const rs = results.filter((r) => r.sample === s.id && r.model === c.model && r.arm === c.arm); return `${rs.filter((r) => r.outcome === "flagged").length}/${rs.filter((r) => r.outcome === "timeout").length}`; }).join(" | ")} |`)
    .join("\n");
put(
    "report.md",
    `# Testing ${NN}: layer 2 v2 sebagai tambahan input layer 4

> Tanggal: ${now.getDate()} ${MON[now.getMonth()]} ${now.getFullYear()}, ${TIME} · folder \`${dateName}/${folderName}\` · branch \`${git("branch", "--show-current")}\` @ \`${git("rev-parse", "--short", "HEAD")}\` · runner \`tools/run-l2-compare.mjs\`
> Visualisasi: \`conclusions.html\` · data mentah: \`results.json\` · request/jawaban: \`llm-response.md\`
${aborted ? `\n> **DIHENTIKAN LEBIH AWAL:** ${aborted}\n` : ""}
## 1. Setelan

| Item | Nilai |
|---|---|
| Penyedia / model | \`${new URL(config.baseUrl).host}\` / ${MODELS.map((m) => `\`${m}\``).join(", ")} |
| Thinking | **off** (\`chat_template_kwargs: {thinking: false}\`) di semua panggilan |
| Arm "tanpa L2" | input dan prompt produksi (\`${PROMPT_VERSION}\`) |
| Arm "dengan L2 v2" | input + \`link: {score, hints}\` dari prototipe \`dissect2.mjs\` + satu paragraf tambahan di prompt (eksperimen, tidak ada perubahan di \`ai/src\`) |
| Batas / parameter | ${LIMIT_MS} ms per panggilan, \`temperature\` 0, \`max_tokens\` 200, \`json_object\`; "flagged" = aturan \`reality.js\` (tidak wajar, confidence ≥ ${MIN_CONFIDENCE}, ada \`asks\`) |
| Gerbang LLM | **dilewati**: semua sampel dinilai (produksi memanggil LLM hanya bila skor layer 3 ≥ 15) |
| Run | ${RUNS} putaran × ${samples.length} sampel × ${cfgs.length} konfigurasi |
| Catatan | ${NOTE || "-"} |

Paragraf tambahan di prompt (arm "dengan L2 v2") ada di \`llm-response.md\`. Hanya nama pemeriksaan (\`hints\`) dari daftar tetap yang dikirim, bukan teks URL.

## 2. Sampel

| Jenis | id | skor layer 3 | skor L2 v2 | hints |
|---|---|---|---|---|
${sampleRows}

## 3. Hasil per konfigurasi

| Konfigurasi | scam nyata flagged | scam sintetis flagged | **false positive (sah)** | timeout | bad_schema | http_error | selesai: median |
|---|---|---|---|---|---|---|---|
${aggRows}

## 4. Per sampel (flagged/timeout, tiap kolom satu konfigurasi)

| Jenis | id | ${cfgs.map((c) => `${c.model.replace("deepseek-", "")} ${c.arm === "tanpa" ? "–" : "+L2"}`).join(" | ")} |
|---|---|${cfgs.map(() => "---").join("|")}|
${perSample}

## 5. Kesimpulan otomatis

${concl.map((c) => `- ${c}`).join("\n")}

## 6. Analisis (diisi Claude setelah data dibaca)

_Belum diisi._

## 7. Batasan

- Prototipe L2 v2 belum dikalibrasi: kata umpan dan daftar hosting gratis ditulis setelah melihat sebagian sampel (lihat \`06-testing-14.57/PROPOSAL.md\`). Skor sampel nyata di sini bukan ukuran akurasi.
- Scam sintetis punya URL buatan; hanya 2 scam nyata. Satu malam, satu mesin, penyedia berubah menurut beban.
- Layer 1 dan RDAP tidak ikut. Tidak ada perubahan kode produksi.
`
);

// ---- llm-response.md ------------------------------------------------------------------------------------------------------------------------
put(
    "llm-response.md",
    `# Request dan jawaban LLM

> Testing ${NN} · prompt dasar \`${PROMPT_VERSION}\` · API key tidak tersimpan. Semua jawaban mentah: \`results.json\`.

## 1. Pesan user, kedua arm (sampel pertama: \`${samples[0].id}\`)

Tanpa L2:
\`\`\`json
${JSON.stringify(samples[0].inputPlain)}
\`\`\`
Dengan L2 v2:
\`\`\`json
${JSON.stringify(samples[0].inputL2)}
\`\`\`

## 2. Paragraf tambahan di prompt (arm "dengan L2 v2")

\`\`\`text${L2_PARAGRAPH}
\`\`\`

## 3. Jawaban yang ditandai flagged pada halaman sah (false positive)

| Run | Sampel | Model | Arm | Jawaban |
|---|---|---|---|---|
${results.filter((r) => r.kind === "legit-trap" && r.outcome === "flagged").map((r) => `| ${r.run} | ${esc(r.sample)} | ${r.model} | ${r.arm} | \`${esc(String(r.content).replace(/\s+/g, " ").slice(0, 260))}\` |`).join("\n") || "| - | - | - | - | (tidak ada false positive) |"}

## 4. System prompt dasar (\`${PROMPT_VERSION}\`)

\`\`\`text
${SYSTEM_PROMPT}
\`\`\`
`
);

// ---- conclusions.html ------------------------------------------------------------------------------------------------------------------------
function bars(title, sub, valOf, fmt, unit) {
    const W = 760;
    const rowH = 26;
    const vals = agg.map(valOf).filter((v) => v != null);
    const max = Math.max(1e-9, ...vals);
    let y = 4;
    let svg = "";
    for (const m of MODELS) {
        svg += `<text x="0" y="${y + 12}" class="gl">${hesc(m.replace("deepseek-", ""))}</text>`;
        y += 18;
        for (const arm of ARMS) {
            const v = valOf(A(m, arm.id));
            const w = v == null ? 0 : Math.max(2, (v / max) * (W - 330));
            svg += `<text x="140" y="${y + 14}" text-anchor="end" class="al">${hesc(arm.label)}</text><rect x="150" y="${y}" width="${w}" height="${rowH - 6}" rx="3" fill="${arm.id === "tanpa" ? "var(--c-a)" : "var(--c-b)"}"/><text x="${158 + w}" y="${y + 14}" class="vl">${v == null ? "-" : hesc(fmt(v))}${unit}</text>`;
            y += rowH;
        }
    }
    return `<section class="card"><h2>${hesc(title)}</h2><p class="sub">${hesc(sub)}</p><svg viewBox="0 0 ${W} ${y + 6}" role="img" aria-label="${hesc(title)}">${svg}</svg></section>`;
}
const pc = (n, d) => (d ? (n / d) * 100 : null);
const OC = { flagged: "var(--ok)", reasonable: "var(--bad)", timeout: "var(--mute)", http_error: "var(--warn)", bad_schema: "var(--warn)" };
const FPC = { flagged: "var(--bad)", reasonable: "var(--ok)", timeout: "var(--mute)", http_error: "var(--warn)", bad_schema: "var(--warn)" };
const heat = (kind, title, sub, colors) => `<section class="card"><h2>${hesc(title)}</h2><p class="sub">${hesc(sub)}</p>${cfgs.map((c) => `<div class="hrow"><span class="hl">${hesc(c.model.replace("deepseek-", ""))} · ${c.arm === "tanpa" ? "tanpa L2" : "dengan L2"}</span><span class="cells">${results.filter((r) => r.kind === kind && r.model === c.model && r.arm === c.arm).map((r) => `<i title="${hesc(r.sample)} · run ${r.run} · ${r.outcome}" style="background:${colors[r.outcome] ?? "var(--mute)"}"></i>`).join("")}</span></div>`).join("")}</section>`;
const trs = agg.map((a) => `<tr><td>${hesc(a.model.replace("deepseek-", ""))}</td><td>${a.arm === "tanpa" ? "tanpa L2" : "dengan L2"}</td><td>${a.realFlag}/${a.real.length}</td><td>${a.synFlag}/${a.syn.length}</td><td><b>${a.fp}/${a.legit.length}</b></td><td>${a.timeouts}/${a.n}</td><td>${a.bad + a.err}</td><td>${sec(a.med)}</td></tr>`).join("");
put(
    "conclusions.html",
    `<!doctype html>
<html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Layer 2 v2 Compare</title>
<style>
:root{--bg:#f6f5f2;--card:#fff;--fg:#1d1c1a;--mute:#9a968f;--line:#e3e0d9;--c-a:#3b5ccc;--c-b:#e08a1e;--ok:#2f9e5f;--bad:#d1453b;--warn:#d9b100}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#151514;--card:#1f1e1c;--fg:#ecebe7;--mute:#77736c;--line:#33312d;--c-a:#7d97f0;--c-b:#f0a94a;--ok:#4cc386;--bad:#ef6c62;--warn:#e8c43a}}
:root[data-theme="dark"]{--bg:#151514;--card:#1f1e1c;--fg:#ecebe7;--mute:#77736c;--line:#33312d;--c-a:#7d97f0;--c-b:#f0a94a;--ok:#4cc386;--bad:#ef6c62;--warn:#e8c43a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,system-ui,sans-serif}
main{max-width:860px;margin:0 auto;padding:24px 16px 64px}h1{font-size:24px;margin:0 0 4px}h2{font-size:16px;margin:0 0 2px}
.meta{color:var(--mute);font-size:13px;margin-bottom:20px}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:0 0 16px}
.sub{color:var(--mute);font-size:13px;margin:0 0 10px}svg{width:100%;height:auto;display:block}.gl{font-weight:600;font-size:13px;fill:var(--fg)}.al{font-size:12px;fill:var(--mute)}.vl{font-size:12px;fill:var(--fg)}
.legend span{display:inline-flex;align-items:center;gap:6px;margin-right:14px;font-size:13px}.legend i{width:12px;height:12px;border-radius:3px;display:inline-block}
ul{margin:0;padding-left:18px}li{margin:6px 0}table{width:100%;border-collapse:collapse;font-size:13px;display:block;overflow-x:auto}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
.hrow{display:flex;gap:10px;align-items:center;margin:4px 0}.hl{width:190px;flex:none;font-size:12px;color:var(--mute)}.cells{display:flex;flex-wrap:wrap;gap:2px}.cells i{width:11px;height:11px;border-radius:2px;display:inline-block}
@media (max-width:560px){.hrow{flex-direction:column;align-items:flex-start}.hl{width:auto}}
</style></head><body><main>
<h1>Layer 2 v2 → layer 4</h1>
<p class="meta">Testing ${NN} · ${now.getDate()} ${MON[now.getMonth()]} ${now.getFullYear()} · thinking off · ${RUNS} putaran × ${samples.length} sampel (${samples.filter((s) => s.kind === "scam-real").length} scam nyata, ${samples.filter((s) => s.kind === "scam-syn").length} sintetis, ${samples.filter((s) => s.kind === "legit-trap").length} halaman sah) · batas ${LIMIT_MS / 1000} s${aborted ? ` · <b>DIHENTIKAN: ${hesc(aborted)}</b>` : ""}</p>
<div class="card legend"><span><i style="background:var(--c-a)"></i>tanpa L2 (produksi)</span><span><i style="background:var(--c-b)"></i>dengan L2 v2</span></div>
<section class="card"><h2>Kesimpulan</h2><ul>${concl.map((c) => `<li>${hesc(c).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")}</li>`).join("")}</ul></section>
${bars("Scam nyata yang ditandai", "Makin tinggi makin baik (2 sampel × putaran).", (a) => pc(a.realFlag, a.real.length), (v) => v.toFixed(0), "%")}
${bars("Scam sintetis yang ditandai", "Makin tinggi makin baik. URL sintetis buatan.", (a) => pc(a.synFlag, a.syn.length), (v) => v.toFixed(0), "%")}
${bars("False positive pada halaman sah", "Makin rendah makin baik. Halaman sah yang tampak mencurigakan (traps).", (a) => pc(a.fp, a.legit.length), (v) => v.toFixed(0), "%")}
${bars("Timeout (batas 6 s)", "Makin rendah makin baik.", (a) => pc(a.timeouts, a.n), (v) => v.toFixed(0), "%")}
${heat("legit-trap", "Peta halaman sah", "Hijau = benar (tidak ditandai), merah = false positive, abu = timeout.", FPC)}
${heat("scam-real", "Peta scam nyata", "Hijau = ditandai (benar), merah = lolos, abu = timeout.", OC)}
<section class="card"><h2>Tabel ringkas</h2><table><thead><tr><th>Model</th><th>Arm</th><th>scam nyata</th><th>scam sintetis</th><th>false positive</th><th>timeout</th><th>error/skema</th><th>selesai (median)</th></tr></thead><tbody>${trs}</tbody></table></section>
<p class="meta">Kesimpulan dibuat otomatis dari <code>results.json</code>. Prototipe L2 v2 belum dikalibrasi; n kecil; selisih satu dua run bukan bukti.</p>
</main></body></html>`
);

for (const f of written) {
    if (readFileSync(f, "utf8").includes(config.apiKey)) {
        rmSync(f);
        throw new Error(`API key ditemukan di ${f}; file dihapus.`);
    }
}
console.log(`selesai. file: ${written.map((f) => f.slice(OUT.length + 1)).join(", ")}`);
console.log(`OUT=${OUT}`);
