#!/usr/bin/env node
// Runner for ai/testing/PLAN-llm-test.md. Tests layers 1-4 on ONE link and writes the whole testing folder:
//   ai/testing/<DD-mon-YYYY>/<NN>-testing-<HH.MM>/{link.md, llm-response.md, report.md, captured-sample.json, raw/*.json}
//
//   node ai/testing/tools/run-llm-plan.mjs "<url>" [--runs 10] [--diag 3] [--stream 3] [--models a,b] [--reasoning default|off]
//                                          [--snapshot file.json] [--no-llm] [--note "text"] [--out-root dir]
//
// Safety: the page is fetched ONCE by ai/eval/tools/capture.mjs (static GET, no JavaScript, no cookies, public hosts only).
// It is never opened in a browser. Links are written defanged (hxxps://example[.]com). The API key is read from ai/.env,
// never printed, and every output file is scanned for it before the script ends.
// The name must NOT end in "-test.mjs": `node --test` would run it (and call the LLM) by itself.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { cpus } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import vm from "node:vm";

const R = fileURLToPath(new URL("../../../", import.meta.url)); // Final-CH7/
const imp = (p) => import(pathToFileURL(join(R, p)).href);

// ---- args ----------------------------------------------------------------------------------------------------------
const args = { _: [] };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--no-llm") args.noLlm = true;
    else if (argv[i].startsWith("--")) args[argv[i].slice(2)] = argv[++i];
    else args._.push(argv[i]);
}
const RUNS = Number(args.runs ?? 10);
const DIAG = Number(args.diag ?? 3);
const STREAM = Number(args.stream ?? 3);
const MODELS = (args.models ?? "").split(",").map((s) => s.trim()).filter(Boolean);
const REASONING_OFF = args.reasoning === "off";
const reasoningExtra = REASONING_OFF ? { reasoning: { enabled: false } } : {};
const NOTE = args.note ?? "";

// ---- helpers -------------------------------------------------------------------------------------------------------
const pad = (n) => String(n).padStart(2, "0");
const MON = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const MON_ID = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
const defang = (u) => String(u).replace(/^https?/i, (m) => (m.toLowerCase() === "https" ? "hxxps" : "hxxp")).replace(/\./g, "[.]");
const num = (x, d = 1) => (x === null || x === undefined || Number.isNaN(x) ? "-" : Number(x).toFixed(d).replace(".", ","));
const sec = (ms) => num(ms / 1000, 2) + " s";
const median = (a) => {
    if (!a.length) return null;
    const s = [...a].sort((x, y) => x - y);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
const stats = (a) => ({ n: a.length, min: a.length ? Math.min(...a) : null, med: median(a), max: a.length ? Math.max(...a) : null, avg: mean(a) });
const statLine = (s, f = (x) => sec(x)) => (s.n ? `${f(s.min)} / ${f(s.med)} / ${f(s.max)} / ${f(s.avg)}` : "-");
const git = (...a) => {
    try {
        return execFileSync("git", ["-C", R, ...a], { encoding: "utf8" }).trim();
    } catch {
        return "?";
    }
};
const esc = (s) => String(s ?? "").replace(/\|/g, "\\|").replace(/\n/g, " ");
const j = (o) => "```json\n" + JSON.stringify(o, null, 2) + "\n```\n";

// ---- output folder ---------------------------------------------------------------------------------------------------
const now = new Date();
const outRoot = args["out-root"] ?? join(R, "ai/testing");
const dateName = `${pad(now.getDate())}-${MON[now.getMonth()]}-${now.getFullYear()}`;
const dateDir = join(outRoot, dateName);
const taken = existsSync(dateDir) ? readdirSync(dateDir).map((n) => /^(\d+)-testing-/.exec(n)).filter(Boolean).map((m) => Number(m[1])) : [];
const NN = pad(Math.max(0, ...taken) + 1);
const TIME = `${pad(now.getHours())}.${pad(now.getMinutes())}`;
const folderName = `${NN}-testing-${TIME}`;
const OUT = join(dateDir, folderName);
mkdirSync(join(OUT, "raw"), { recursive: true });
const written = [];
const put = (rel, text) => {
    writeFileSync(join(OUT, rel), text);
    written.push(join(OUT, rel));
};
console.log(`folder: ${OUT}`);

// ---- 1. the link: capture (or reuse a snapshot) ---------------------------------------------------------------------
const url = args._[0];
let sample;
if (args.snapshot) {
    sample = JSON.parse(readFileSync(args.snapshot, "utf8"));
} else {
    if (!url) throw new Error('Kasih link: node ai/testing/tools/run-llm-plan.mjs "<url>"');
    const slug = (new URL(url).hostname.replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "").toLowerCase() + "-probe").slice(0, 60);
    try {
        execFileSync(process.execPath, [join(R, "ai/eval/tools/capture.mjs"), url, "--label", "scam", "--id", slug, "--source", "llm test plan (PLAN-llm-test.md)", "--out", OUT], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    } catch (e) {
        throw new Error(`Gagal mengambil halaman (mungkin sudah mati, bukan HTML, atau host non-publik): ${String(e.stderr || e.message).trim().split("\n").pop()}`);
    }
    sample = JSON.parse(readFileSync(join(OUT, `${slug}.json`), "utf8"));
    rmSync(join(OUT, `${slug}.json`));
}
const snapshot = sample.snapshot;
const linkUrl = url ?? snapshot.url;
put("captured-sample.json", JSON.stringify(sample, null, 2));

// ---- 2. layers 1-4 inputs --------------------------------------------------------------------------------------------
const ctx = { URL, console };
vm.createContext(ctx);
vm.runInContext(readFileSync(join(R, "ios/ShooExtension/Resources/detector.js"), "utf8"), ctx);
const { analyze, analyzeSnapshot } = await imp("ai/src/analyze.js");
const { buildInput, passesGate, createRealityCheck } = await imp("ai/src/layer4/reality.js");
const { sanitizeSnapshot } = await imp("ai/src/validate.js");
const { readConfig } = await imp("ai/src/layer4/config.js");
const { parseVerdict } = await imp("ai/src/layer4/schema.js");
const { SYSTEM_PROMPT, PROMPT_VERSION } = await imp("ai/prompts/reality-check.js");

let t = performance.now();
const local = await ctx.ShooDetector.analyzeLocal(snapshot);
const l12ms = performance.now() - t;
for (let i = 0; i < 200; i++) analyzeSnapshot(snapshot);
t = performance.now();
for (let i = 0; i < 2000; i++) analyzeSnapshot(snapshot);
const l3us = ((performance.now() - t) / 2000) * 1000;
const l3 = analyzeSnapshot(snapshot);
const l3score = l3.reduce((a, s) => a + s.weight, 0);
const clean = sanitizeSnapshot(snapshot);
const gate = passesGate(clean, { official: false, score: l3score });
const input = buildInput(clean, l3.map((s) => s.id));
const userMessage = `DATA_START\n${JSON.stringify(input)}\nDATA_END`;

// ---- link.md ---------------------------------------------------------------------------------------------------------
const fields = snapshot.forms.flatMap((f) => f.fields);
put(
    "link.md",
    `# Link yang diuji (testing ${NN}, ${now.getDate()} ${MON_ID[now.getMonth()]} ${now.getFullYear()}, ${TIME})

> **Jangan dibuka di browser.** Ini halaman phishing/scam. Halaman hanya diambil sekali lewat \`ai/eval/tools/capture.mjs\` (GET statis, tanpa JavaScript, tanpa cookie, host publik saja). Link ditulis *defanged*; untuk mengembalikannya ganti \`hxxp\` → \`http\` dan \`[.]\` → \`.\`.

| Item | Nilai |
|---|---|
| Link (defanged) | \`${defang(linkUrl)}\` |
| Domain | \`${snapshot.domain}\` |
| Waktu pengambilan | ${snapshot.capturedAt} |
| Cara ambil | ${args.snapshot ? `memakai snapshot yang sudah ada (\`${args.snapshot.split("/").slice(-2).join("/")}\`)` : "\`capture.mjs\` (GET statis, UA iPhone Safari)"} |
| Ukuran HTML | ${sample.meta?.bytes ?? "-"} byte |
| Catatan penguji | ${NOTE || "-"} |
| Status redaksi | \`redacted: ${sample.redacted}\`. Email dimasking \`[email]\` oleh capture; **belum dicek manual** untuk data pribadi |

## Yang diambil dari halaman (snapshot, sama dengan yang dikirim extension)

| Field | Isi |
|---|---|
| \`title\` | ${esc(snapshot.title)} |
| \`lang\` | ${snapshot.lang ?? "-"} |
| \`text\` | ${snapshot.text.length} karakter: \`${esc(snapshot.text.slice(0, 160))}${snapshot.text.length > 160 ? "…" : ""}\` |
| \`forms\` | ${snapshot.forms.length} form, ${fields.length} field |
| \`imageAlts\` | ${snapshot.imageAlts.length ? snapshot.imageAlts.map((a) => `\`${esc(a)}\``).join(", ") : "-"} |

Field form:

| type | name | id | label | placeholder | autocomplete |
|---|---|---|---|---|---|
${fields.map((f) => `| ${esc(f.type)} | ${esc(f.name)} | ${esc(f.id)} | ${esc(f.label)} | ${esc(f.placeholder)} | ${esc(f.autocomplete)} |`).join("\n") || "| - | - | - | - | - | - |"}

## Hasil layer 1 sampai 3 (tanpa LLM)

| Layer | Hasil | Waktu |
|---|---|---|
| 1–2 (detector di extension, disimulasikan; blocklist layer 1 tidak ikut) | ${local.length ? local.map((s) => `\`${s.id}:${s.weight}\``).join(", ") : "0 sinyal"} | ${num(l12ms, 2)} ms |
| 3 (aturan form + isi; RDAP dimatikan) | ${l3.length ? l3.map((s) => `\`${s.id}:${s.weight}\`${s.evidence ? ` (evidence \`${esc(s.evidence)}\`)` : ""}`).join(", ") : "0 sinyal"} | ${num(l3us, 1)} µs/panggilan |
| Skor layer 3 | **${l3score}** (peringatan ≥ 30, tinggi ≥ 50, blokir ≥ 80) | |
| Lolos gerbang LLM (bukan resmi, form ≥ 1 field, skor ≥ 15) | **${gate ? "ya" : "tidak"}** | |

## Yang dikirim ke LLM (setelah disanitasi, sebelum dikirim)

${j(input)}
`
);

// ---- 3. LLM ----------------------------------------------------------------------------------------------------------
try {
    process.loadEnvFile(join(R, "ai/.env"));
} catch (e) {
    if (e?.code !== "ENOENT") throw e;
}
const config = readConfig(process.env);
const llm = { codePath: [], diag: [], stream: [], models: [] };
const providerHost = config ? new URL(config.baseUrl).host : "-";
let skipReason = null;
if (args.noLlm) skipReason = "dijalankan dengan --no-llm";
else if (!config) skipReason = "layer 4 mati: LLM_API_KEY / LLM_MODEL / LLM_BASE_URL belum lengkap di ai/.env";
else if (!gate) skipReason = "halaman tidak lolos gerbang LLM (skor layer 3 < 15 atau situs resmi), jadi produksi tidak akan memanggil LLM";

const buildBody = (extra = {}, model = config?.model) => ({ model, messages: [{ role: "system", content: SYSTEM_PROMPT }, { role: "user", content: userMessage }], temperature: 0, max_tokens: 200, response_format: { type: "json_object" }, ...extra });
const endpoint = config ? `${config.baseUrl}/chat/completions` : "";
const headers = config ? { "content-type": "application/json", authorization: `Bearer ${config.apiKey}` } : {};

if (!skipReason) {
    console.log(`LLM: ${config.model} @ ${providerHost}, ${RUNS} run kode asli + ${DIAG} diagnosa + ${STREAM} stream${MODELS.length ? " + model: " + MODELS.join(",") : ""}${REASONING_OFF ? " (reasoning off)" : ""}`);
    // (a) the real code path (createRealityCheck, hard 6 s limit) ---------------------------------------------------------
    for (let i = 1; i <= RUNS; i++) {
        let httpMs = null;
        let status = null;
        let raw = null;
        const spy = async (u, init) => {
            const body = REASONING_OFF ? JSON.stringify({ ...JSON.parse(init.body), ...reasoningExtra }) : init.body;
            const t0 = performance.now();
            const res = await fetch(u, { ...init, body });
            status = res.status;
            raw = await res.clone().text();
            httpMs = performance.now() - t0;
            return res;
        };
        const check = createRealityCheck({ config, fetch: spy });
        const t0 = performance.now();
        const signals = await analyze(snapshot, { rdap: null, llm: check, localSignals: local, client: `plan-${i}`, deadline: Date.now() + 6500 });
        const total = performance.now() - t0;
        let parsed = null;
        try {
            parsed = JSON.parse(raw);
        } catch {}
        const outcome = Object.entries(check.stats().outcomes).find(([, v]) => v > 0)?.[0] ?? "?";
        llm.codePath.push({ run: i, totalMs: total, httpMs, status, outcome, finish: parsed?.choices?.[0]?.finish_reason ?? null, usage: parsed?.usage ?? null, content: parsed?.choices?.[0]?.message?.content ?? null, signals: signals.map((s) => `${s.id}:${s.weight}`), score: signals.reduce((a, s) => a + s.weight, 0), raw: parsed ?? (raw ? raw.slice(0, 500) : null) });
        console.log(`  kode asli #${i}: ${Math.round(total)} ms ${outcome}`);
    }
    // (b) plain non-stream, no 6 s limit (to see how long the provider really needs) -------------------------------------
    const plain = async (name, extra = {}, model = config.model) => {
        const t0 = performance.now();
        try {
            const res = await fetch(endpoint, { method: "POST", headers, body: JSON.stringify(buildBody(extra, model)), signal: AbortSignal.timeout(90000) });
            const headersMs = performance.now() - t0;
            const text = await res.text();
            const totalMs = performance.now() - t0;
            let b = null;
            try {
                b = JSON.parse(text);
            } catch {}
            const m = b?.choices?.[0];
            return { name, model, extra, http: res.status, headersMs, totalMs, finish: m?.finish_reason ?? null, usage: b?.usage ?? null, content: m?.message?.content ?? null, schemaOk: Boolean(parseVerdict(m?.message?.content)), error: b?.error?.message ?? null, raw: b ?? text.slice(0, 500) };
        } catch (e) {
            return { name, model, extra, error: `${e.name}: ${e.message}`, totalMs: performance.now() - t0 };
        }
    };
    for (let i = 1; i <= DIAG; i++) {
        llm.diag.push(await plain(`diagnosa#${i}`, reasoningExtra));
        console.log(`  diagnosa #${i}: ${Math.round(llm.diag.at(-1).totalMs)} ms`);
    }
    // (c) streaming: where the time goes (reasoning phase vs answer) ----------------------------------------------------
    for (let i = 1; i <= STREAM; i++) {
        const t0 = performance.now();
        const ev = { first: null, rStart: null, rEnd: null, cStart: null, last: null };
        let rChunks = 0;
        let cChunks = 0;
        let text = "";
        let usage = null;
        try {
            const res = await fetch(endpoint, { method: "POST", headers, body: JSON.stringify({ ...buildBody(reasoningExtra), stream: true, stream_options: { include_usage: true } }), signal: AbortSignal.timeout(90000) });
            const dec = new TextDecoder();
            let buf = "";
            for await (const part of res.body) {
                buf += dec.decode(part, { stream: true });
                let k;
                while ((k = buf.indexOf("\n")) >= 0) {
                    const line = buf.slice(0, k).trim();
                    buf = buf.slice(k + 1);
                    if (!line.startsWith("data:")) continue;
                    const d = line.slice(5).trim();
                    if (d === "[DONE]") continue;
                    let o;
                    try {
                        o = JSON.parse(d);
                    } catch {
                        continue;
                    }
                    const at = performance.now() - t0;
                    ev.first ??= at;
                    ev.last = at;
                    if (o.usage) usage = o.usage;
                    const dl = o.choices?.[0]?.delta ?? {};
                    if (dl.reasoning_content ?? dl.reasoning) {
                        rChunks++;
                        ev.rStart ??= at;
                        ev.rEnd = at;
                    }
                    if (dl.content) {
                        cChunks++;
                        ev.cStart ??= at;
                        text += dl.content;
                    }
                }
            }
            llm.stream.push({ name: `stream#${i}`, http: res.status, ...ev, rChunks, cChunks, content: text, usage });
        } catch (e) {
            llm.stream.push({ name: `stream#${i}`, error: `${e.name}: ${e.message}`, ...ev, rChunks, cChunks, content: text });
        }
        console.log(`  stream #${i}: ${Math.round(llm.stream.at(-1).last ?? 0)} ms`);
    }
    // (d) optional other models --------------------------------------------------------------------------------------------
    for (const model of MODELS) {
        for (let i = 1; i <= 2; i++) {
            llm.models.push(await plain(`${model}#${i}`, reasoningExtra, model));
            console.log(`  ${model} #${i}: ${Math.round(llm.models.at(-1).totalMs)} ms`);
        }
    }
    put("raw/code-path.json", JSON.stringify(llm.codePath, null, 2));
    put("raw/diagnosa.json", JSON.stringify(llm.diag, null, 2));
    put("raw/stream.json", JSON.stringify(llm.stream, null, 2));
    if (llm.models.length) put("raw/models.json", JSON.stringify(llm.models, null, 2));
}

// ---- llm-response.md (same sections as ai/testing/26-oct-2026/04-testing-10.30/llm-response.md, plus the code-path table) ----
const reasoningOf = (u) => u?.completion_tokens_details?.reasoning_tokens ?? u?.reasoning_tokens ?? null;
const cp = llm.codePath;
const cpDone = cp.filter((r) => !["timeout", "http_error", "capped"].includes(r.outcome));
const body = !skipReason ? buildBody(reasoningExtra) : { model: config?.model ?? "(belum diatur)", messages: [], temperature: 0, max_tokens: 200, response_format: { type: "json_object" } };
let md = `# Request dan respons mentah LLM${providerHost !== "-" ? ` (${providerHost})` : ""}

> Testing ${NN} · ${now.getDate()} ${MON_ID[now.getMonth()]} ${now.getFullYear()}, ${TIME} · link: \`${defang(linkUrl)}\` · prompt \`${PROMPT_VERSION}\` · API key tidak ikut tersimpan
`;
if (skipReason) {
    md += `\n**Tidak ada panggilan LLM di testing ini:** ${skipReason}.\n\nRequest yang akan dikirim ada di bagian 1; sistem prompt di bagian 6. Data masuk LLM: lihat \`link.md\`.\n`;
}
md += `
Isi file ini: request yang dikirim, hasil lewat kode asli (batas 6 detik), respons mentah lengkap (termasuk teks "berpikir" model di \`reasoning_content\` bila ada), garis waktu streaming${MODELS.length ? ", dan hasil beberapa model" : ""}. Data mentah semua panggilan ada di folder \`raw/\`.

## 1. Request (sama untuk semua panggilan, kecuali yang disebut)

\`\`\`http
POST ${endpoint || "<LLM_BASE_URL>/chat/completions"}
content-type: application/json
authorization: Bearer <key disensor>
\`\`\`

Body${REASONING_OFF ? " (di panggilan ini `reasoning: {enabled: false}` ditambahkan, berbeda dari kode produksi)" : ""}:

${j({ ...body, messages: [{ role: "system", content: `(system prompt ${PROMPT_VERSION}, lihat bagian 6)` }, { role: "user", content: userMessage }] })}`;
if (!skipReason) {
    md += `\n## 2. Lewat kode asli (\`createRealityCheck\`, batas ${config.timeoutMs / 1000} s), ${cp.length} run\n\n| Run | Waktu | Hasil layer 4 | finish | Token prompt / completion / reasoning | Sinyal akhir | Skor |\n|---|---|---|---|---|---|---|\n`;
    for (const r of cp) md += `| ${r.run} | ${sec(r.totalMs)} | ${r.outcome} | ${r.finish ?? "-"} | ${r.usage ? `${r.usage.prompt_tokens} / ${r.usage.completion_tokens} / ${reasoningOf(r.usage) ?? "-"}` : "-"} | ${r.signals.join(", ")} | ${r.score} |\n`;
    md += `\nJawaban yang masuk (run yang selesai):\n\n`;
    for (const r of cpDone) md += `- run ${r.run}: \`${esc(String(r.content ?? "").replace(/\s+/g, " "))}\`\n`;
    if (!cpDone.length) md += "- (tidak ada run yang selesai)\n";

    md += `\n## 3. Panggilan non-stream tanpa batas 6 detik (diagnosa), ${llm.diag.length} panggilan\n\n| Panggilan | Header tiba | Selesai | finish | Token completion | Token reasoning | Jawaban |\n|---|---|---|---|---|---|---|\n`;
    for (const r of llm.diag) md += `| ${r.name} | ${r.headersMs ? sec(r.headersMs) : "-"} | ${sec(r.totalMs)} | ${r.finish ?? r.error ?? "-"} | ${r.usage?.completion_tokens ?? "-"} | ${reasoningOf(r.usage) ?? "-"} | ${r.schemaOk ? "JSON valid" : "**tidak valid / kosong**"} |\n`;
    const best = [...llm.diag].filter((r) => r.raw && typeof r.raw === "object").sort((a, b) => a.totalMs - b.totalMs)[0] ?? cp.find((r) => r.raw && typeof r.raw === "object");
    md += `\n## 4. Respons mentah lengkap: ${best ? `\`${best.name ?? "kode asli #" + best.run}\` (${sec(best.totalMs)})` : "-"}\n\nPerhatikan \`reasoning_content\` (kalau ada): itu teks "berpikir" model sebelum menulis jawaban. \`content\` adalah jawaban sebenarnya.\n\n${best ? j(best.raw) : "(tidak ada respons)\n"}`;

    md += `\n## 5. Streaming: di mana waktu habis\n\nPermintaan yang sama dengan \`stream: true\`, waktu sejak request keluar.\n\n| Run | Byte pertama | Reasoning mulai | Reasoning selesai | Jawaban mulai | Selesai | Porsi reasoning | Potongan reasoning / jawaban |\n|---|---|---|---|---|---|---|---|\n`;
    for (const r of llm.stream) md += `| ${r.name} | ${r.first != null ? sec(r.first) : "-"} | ${r.rStart != null ? sec(r.rStart) : "-"} | ${r.rEnd != null ? sec(r.rEnd) : "-"} | ${r.cStart != null ? sec(r.cStart) : "-"} | ${r.last != null ? sec(r.last) : r.error ?? "-"} | ${r.rEnd && r.last ? Math.round((r.rEnd / r.last) * 100) + "%" : "-"} | ${r.rChunks} / ${r.cChunks} |\n`;
    if (llm.stream[0]?.content) md += `\nJawaban JSON dari ${llm.stream[0].name}: \`${esc(llm.stream[0].content.replace(/\s+/g, " "))}\`\n`;
    if (llm.models.length) {
        md += `\n## 5b. Hasil model lain di ${providerHost} (2 panggilan per model, non-stream)\n\n| Model | Panggilan | Waktu | Token reasoning | Skema valid | Penilaian |\n|---|---|---|---|---|---|\n`;
        for (const r of llm.models) {
            const v = parseVerdict(r.content);
            md += `| ${r.model} | ${r.name.split("#")[1]} | ${sec(r.totalMs)} | ${reasoningOf(r.usage) ?? "-"} | ${v ? "ya" : "tidak"} | ${v ? `${v.reasonable ? "wajar" : "TIDAK WAJAR"} ${v.confidence}` : (r.error ?? "-")} |\n`;
        }
    }
}
md += `\n## 6. System prompt yang dikirim (\`${PROMPT_VERSION}\`)\n\n\`\`\`text\n${SYSTEM_PROMPT}\n\`\`\`\n`;
put("llm-response.md", md);

// ---- report.md (numbers filled in; the analysis is for Claude to write after reading the data) ---------------------------
const cpMs = stats(cpDone.map((r) => r.totalMs));
const dgMs = stats(llm.diag.filter((r) => !r.error).map((r) => r.totalMs));
const outcomes = {};
for (const r of cp) outcomes[r.outcome] = (outcomes[r.outcome] ?? 0) + 1;
const scores = cp.map((r) => r.score);
const rShare = llm.stream.filter((r) => r.rEnd && r.last).map((r) => (r.rEnd / r.last) * 100);
put(
    "report.md",
    `# Testing ${NN}: layer 1–4 pada satu link

> Tanggal: ${now.getDate()} ${MON_ID[now.getMonth()]} ${now.getFullYear()}, ${TIME} · folder \`${dateName}/${folderName}\` · branch \`${git("branch", "--show-current")}\` @ \`${git("rev-parse", "--short", "HEAD")}\`${git("status", "--short", "--", "ai/src", "ai/prompts") ? " (+ perubahan belum di-commit di `ai/src` / `ai/prompts`)" : ""}
> Penguji: Imelda (dijalankan bersama Claude lewat \`PLAN-llm-test.md\`, runner \`tools/run-llm-plan.mjs\`)
> Link yang diuji dan isi snapshot: lihat \`link.md\` · request/respons mentah: \`llm-response.md\` · data mentah: \`raw/\`
> Bagian "Analisis" di bawah ditulis setelah data dibaca; angka di tabel dihasilkan otomatis oleh runner.

## 1. Setelan

| Item | Nilai |
|---|---|
| Link (defanged) | \`${defang(linkUrl)}\` |
| Penyedia / model | ${skipReason ? "(LLM tidak dipanggil)" : `\`${providerHost}\` / \`${config.model}\``} |
| Prompt | \`${PROMPT_VERSION}\` |
| Reasoning | ${REASONING_OFF ? "**dimatikan** (`reasoning: {enabled: false}` ditambahkan oleh runner; BERBEDA dari kode produksi)" : "bawaan (tidak ada parameter `reasoning` yang dikirim, sama seperti kode produksi)"} |
| \`temperature\` / \`max_tokens\` / \`response_format\` | 0 / 200 / \`json_object\` |
| Batas waktu layer 4 | ${config ? config.timeoutMs : "-"} ms (\`MAX_TIMEOUT_MS\`); server \`/analyze\` 6.500 ms; extension 8.000 ms |
| \`LLM_DAILY_CAP\` | ${config ? config.dailyCap : "-"} |
| Jumlah panggilan | ${skipReason ? "0" : `${RUNS} lewat kode asli, ${DIAG} diagnosa non-stream, ${STREAM} stream${MODELS.length ? `, ${MODELS.length * 2} model lain` : ""}`} |
| RDAP | dimatikan (domain scam tidak dikirim ke registry) |
| Mesin | ${cpus()[0]?.model ?? "?"}, Node ${process.version}, ${process.platform}/${process.arch} |
| Catatan | ${NOTE || "-"} |
${skipReason ? `\n**LLM tidak dipanggil:** ${skipReason}.\n` : ""}
## 2. Waktu per layer

| Layer | Waktu |
|---|---|
| 1–2 (detector, disimulasikan) | ${num(l12ms, 2)} ms |
| 3 (aturan, rata-rata 2.000 panggilan) | ${num(l3us, 1)} µs |
| 4 (LLM), run yang selesai lewat kode asli: min / median / maks / rata-rata | ${skipReason ? "-" : `${statLine(cpMs)} (n = ${cpMs.n} dari ${cp.length})`} |
| 4 (LLM), non-stream tanpa batas 6 s: min / median / maks / rata-rata | ${skipReason ? "-" : `${statLine(dgMs)} (n = ${dgMs.n})`} |
| 4 (LLM), streaming: porsi waktu di fase reasoning | ${rShare.length ? `${num(Math.min(...rShare), 0)}–${num(Math.max(...rShare), 0)}%` : "-"} |

## 3. Hasil

| Pertanyaan | Hasil |
|---|---|
| Sinyal layer 1–2 | ${local.length ? local.map((s) => s.id).join(", ") : "tidak ada"} |
| Sinyal layer 3 | ${l3.length ? l3.map((s) => `${s.id} (${s.weight})`).join(", ") : "tidak ada"} |
| Skor layer 3 | ${l3score} |
| Lolos gerbang LLM | ${gate ? "ya" : "tidak"} |
${skipReason ? "" : `| Hasil ${cp.length} run layer 4 | ${Object.entries(outcomes).map(([k, v]) => `${k}: ${v}`).join(", ")} |
| Timeout (batas ${config.timeoutMs / 1000} s) | ${outcomes.timeout ?? 0} dari ${cp.length} (${num(((outcomes.timeout ?? 0) / cp.length) * 100, 0)}%) |
| Skor akhir (min / maks) | ${Math.min(...scores)} / ${Math.max(...scores)} (ambang peringatan 30) |
| Skor ≥ 30 | ${scores.filter((s) => s >= 30).length} dari ${cp.length} run |`}

## 4. Analisis (diisi Claude setelah membaca data)

_Belum diisi._ Isi: temuan utama (apa yang terdeteksi, apa yang lolos dan kenapa), kenapa waktunya sebesar itu, apa yang tidak konsisten antar-run, perbandingan dengan testing sebelumnya di tanggal yang sama, rekomendasi.

## 5. Batasan

- Satu link, satu mesin, satu jam. Kecepatan penyedia LLM berubah menurut beban.
- Pengambilan halaman statis (tanpa JavaScript): \`text\` bisa lebih pendek daripada yang dibaca extension di Safari.
- Layer 1 (blocklist 190.000 domain) dan RDAP (\`new_domain\`) tidak ikut, jadi skor produksi bisa berbeda.
- Dijalankan dari Mac, bukan dari Cloudflare Worker.
- Status redaksi sampel: \`redacted: ${sample.redacted}\`; jangan masukkan ke eval set sebelum diperiksa manual.
`
);

// ---- key leak check ----------------------------------------------------------------------------------------------------
if (config?.apiKey) {
    for (const f of written) {
        if (readFileSync(f, "utf8").includes(config.apiKey)) {
            rmSync(f);
            throw new Error(`API key ditemukan di ${f}; file dihapus. Periksa sebelum melanjutkan.`);
        }
    }
}
console.log(`selesai. file: ${written.map((f) => f.slice(OUT.length + 1)).join(", ")}`);
console.log(`OUT=${OUT}`);
