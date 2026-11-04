// Gabungkan log server, observed.json (dibaca dari screenshot), dan hasil 31 Okt menjadi <versi>/data.json dan <versi>/HASIL.md.
// Bagian yang ditulis tangan: <versi>/pengaturan.md dan <versi>/analisis.md.
//   node ai/test-layer-live/scripts/report.mjs [v1]
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const version = process.argv[2] || "v1";
const dir = join(here, "..", version);
const repo = join(here, "..", "..", "..");
const readJson = (file) => JSON.parse(readFileSync(file, "utf8"));
const readOptional = (file) => (existsSync(file) ? readFileSync(file, "utf8").trim() : "");

const ctx = { console };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(readFileSync(join(repo, "ios", "ShooExtension", "Resources", "pipeline.js"), "utf8"), ctx);
const { mergeSignals, scoreFrom } = ctx.ShooPipeline;

const links = readJson(join(dir, "links.json"));
const observed = readJson(join(dir, "observed.json"));
const calls = readFileSync(join(dir, ".raw", "calls.jsonl"), "utf8").trim().split("\n").map((line) => JSON.parse(line));
const qa = join(repo, "plan", "alief", "qa", "img", "figma-parity");
const oldRows = new Map(readJson(join(qa, "live-l2", "live-results.json")).rows.map((r) => [r.id, r]));
const oldL1 = new Set(readJson(join(qa, "layer2-dataset-results.json")).results.filter((r) => JSON.stringify(r).includes("db_match")).map((r) => r.id));

const mask = (host) => host.replace(/\./g, "[.]");
const ms = (n) => (n === null || n === undefined ? "-" : Math.round(n).toLocaleString("id-ID"));
const SHOWN = { blokir: "Blokir", "peringatan-kuat": "Peringatan kuat", peringatan: "Peringatan", "tanpa-tanda": "Tanpa tanda", kosong: "Halaman kosong", "diadang-safari": "Diadang Safari" };
const NOT_OPENED = new Set(["kosong", "diadang-safari"]);

function oldResult(id) {
    const row = oldRows.get(id);
    if (!row) return "-";
    const live = String(row.live).replace(/\*\*/g, "");
    const percent = live.match(/(\d+)\s*%/)?.[1];
    let text;
    if (/^blank/i.test(live)) text = "Kosong";
    else if (/Deceptive Website/.test(live)) text = "Diadang Safari";
    else if (/Blocked/.test(live)) text = `Blokir ${percent}`;
    else text = percent ?? "-";
    return oldL1.has(id) ? `${text} ᴸ¹` : text;
}

const rows = links.map((link) => {
    // Tab lama bisa memeriksa ulang saat link berikutnya sudah ditandai: panggilan dari host link lain bukan milik link ini.
    const otherHosts = new Set(links.filter((l) => l.host !== link.host).map((l) => l.host));
    const own = calls.filter((c) => c.id === link.id && !otherHosts.has(c.host));
    const signals = mergeSignals(...own.map((c) => [...c.localSignals, ...c.signals]));
    const byLayer = (layer) => signals.filter((s) => s.layer === layer);
    const llmCalls = own.flatMap((c) => c.llm.map((l) => ({ ...l, analyzeMs: c.analyzeMs })));
    const decisive = llmCalls.at(-1) ?? null;
    const slowest = own.reduce((best, c) => (best === null || c.analyzeMs > best ? c.analyzeMs : best), null);
    return {
        id: link.id,
        label: link.label,
        host: link.host,
        url: link.url,
        note: link.note,
        resolves: link.resolves,
        observed: observed[link.id] ?? null,
        calls: own.length,
        errors: own.filter((c) => c.status !== 200).length,
        l2: byLayer(2),
        l3: byLayer(3),
        l4: byLayer(4),
        total: own.length ? scoreFrom(signals) : null,
        llm: llmCalls,
        llmMs: decisive?.ms ?? null,
        analyzeMs: decisive?.analyzeMs ?? slowest,
        rdapMs: own.reduce((sum, c) => sum + c.rdapMs, 0),
        old: oldResult(link.id),
        ownCalls: own,
    };
});

const sum = (signals) => signals.reduce((total, s) => total + s.weight, 0);
function l4Cell(r) {
    if (r.l4.length) return `+${sum(r.l4)} flag`;
    if (!r.llm.length) return "-";
    return r.llm.some((l) => l.verdict) ? "tidak flag" : "gagal";
}
const shownCell = (r) => {
    if (!r.observed) return "-";
    const percent = r.observed.percent === null || r.observed.percent === undefined ? "" : ` ${r.observed.percent}%`;
    return `${SHOWN[r.observed.status] ?? r.observed.status}${percent}`;
};
const differs = (r) => r.observed && !NOT_OPENED.has(r.observed.status) && r.observed.percent !== null && r.observed.percent !== undefined && r.total !== null && r.observed.percent !== r.total;

function tableRow(r) {
    const link = `${r.id} [${r.url}](${r.url})`;
    const must = r.label === "scam" ? "≥ 80" : "< 30";
    if (!r.resolves) return `| ${link} | ${must} | - | - | - | - | site gone | - | - | ${r.old} | - |`;
    const shot = `<a href="ss/${r.id}.jpg"><img src="ss/${r.id}.jpg" width="56"></a>`;
    const num = (signals) => (r.calls ? sum(signals) : "-");
    return `| ${link} | ${must} | ${num(r.l2)} | ${num(r.l3)} | ${l4Cell(r)} | ${r.total ?? "-"}${differs(r) ? " beda" : ""} | ${shownCell(r)} | ${ms(r.llmMs)} | ${ms(r.analyzeMs)} | ${r.old} | ${shot} |`;
}
const HEAD = "| Link | Harus | L2 | L3 | L4 | Total | Tampil di HP | LLM ms | /analyze ms | 31 Okt | SS |\n|---|---|---:|---:|---|---:|---|---:|---:|---|---|";
const table = (label) => [HEAD, ...rows.filter((r) => r.label === label).map(tableRow)].join("\n");

const list = (signals) => signals.map((s) => `${s.id} ${s.weight}`).join(", ") || "-";
function detail(r) {
    if (!r.resolves) return null;
    const verdicts = r.llm.map((l) => (l.verdict ? `asks ${l.verdict.asks.join("+") || "-"}, reasonable ${l.verdict.reasonable}, confidence ${l.verdict.confidence}` : `tanpa jawaban sah (${l.status})`));
    const tokens = r.llm.reduce((total, l) => total + (l.usage?.total_tokens ?? 0), 0);
    return [
        `<details><summary>${r.id}</summary>`,
        "",
        `- **L2:** ${list(r.l2)}`,
        `- **L3:** ${list(r.l3)}`,
        `- **L4:** ${r.l4.length ? `${list(r.l4)}; ` : ""}${verdicts.join(" / ") || "tidak ditanya"}`,
        `- **Waktu:** RDAP ${ms(r.rdapMs)} ms, LLM ${r.llm.map((l) => ms(l.ms)).join(" + ") || "-"} ms, /analyze ${ms(r.analyzeMs)} ms`,
        `- **Panggilan:** /analyze ${r.calls}, LLM ${r.llm.length}${tokens ? `, ${tokens.toLocaleString("id-ID")} token` : ""}`,
        ...(r.observed?.note ? [`- **Catatan:** ${r.observed.note}`] : []),
        "",
        "</details>",
    ].join("\n");
}

const opened = (label) => rows.filter((r) => r.label === label && r.resolves && r.observed && !NOT_OPENED.has(r.observed.status));
const percent = (r) => r.observed.percent ?? 0;
const scamOpened = opened("scam");
const legitOpened = opened("legit");
const blocked = scamOpened.filter((r) => r.observed.status === "blokir" || percent(r) >= 80);
const over50 = scamOpened.filter((r) => percent(r) >= 50);
const flagged = legitOpened.filter((r) => percent(r) >= 30 || r.observed.status === "blokir");
const errors = rows.reduce((total, r) => total + r.errors, 0);
const pct = (a, b) => (b ? Math.round((a / b) * 100) : 0);
const pass = (ok) => (ok ? "lulus" : "**gagal**");

function stats(values) {
    const v = values.filter((n) => Number.isFinite(n)).sort((a, b) => a - b);
    if (!v.length) return "-";
    const at = (p) => v[Math.min(v.length - 1, Math.ceil(p * v.length) - 1)];
    return `${ms(at(0.5))} / ${ms(at(0.95))} / ${ms(v.at(-1))} (${v.length} panggilan)`;
}
const allLlm = rows.flatMap((r) => r.llm);
const allCalls = rows.flatMap((r) => r.ownCalls);
const tokens = (key) => allLlm.reduce((total, l) => total + (l.usage?.[key] ?? 0), 0);
const notOpened = (label) => rows.filter((r) => r.label === label && r.resolves && r.observed && NOT_OPENED.has(r.observed.status)).map((r) => r.id);
const gone = rows.filter((r) => !r.resolves).map((r) => r.id);

const summary = {
    scamOpened: scamOpened.length, scamBlocked: blocked.length, scamOver50: over50.length,
    legitOpened: legitOpened.length, legitFlagged: flagged.length, serverErrors: errors, llmCalls: allLlm.length,
    llmMissingUsage: allLlm.filter((l) => !l.usage).length, gone, notOpenedScam: notOpened("scam"), notOpenedLegit: notOpened("legit"),
    differs: rows.filter(differs).map((r) => r.id),
};

const hasil = `# Hasil v1: tes live L2-L4 di simulator iPhone

${readOptional(join(dir, "pengaturan.md"))}

## Batas lulus

Hanya dari halaman yang terbuka. Situs mati: ${gone.length} (${gone.join(", ") || "-"}). Tidak terbuka atau diadang: scam ${notOpened("scam").join(", ") || "-"}; legit ${notOpened("legit").join(", ") || "-"}.

| Cek | Target | Hasil | |
|---|---|---|---|
| Scam diblokir (≥ 80) | minimal 70% | ${blocked.length} dari ${scamOpened.length} = ${pct(blocked.length, scamOpened.length)}% | ${pass(pct(blocked.length, scamOpened.length) >= 70)} |
| Scam skor ≥ 50 | minimal 90% | ${over50.length} dari ${scamOpened.length} = ${pct(over50.length, scamOpened.length)}% | ${pass(pct(over50.length, scamOpened.length) >= 90)} |
| Legit kena tanda (≥ 30) | 0 | ${flagged.length} dari ${legitOpened.length} | ${pass(flagged.length === 0)} |
| Error server | 0 | ${errors} | ${pass(errors === 0)} |

## Scam (${rows.filter((r) => r.label === "scam").length})

${table("scam")}

## Legit (${rows.filter((r) => r.label === "legit").length})

${table("legit")}

Cara baca: **Link** adalah URL persis yang dibuka saat tes dan bisa diklik. Baris scam masih bisa aktif, jadi jangan dibuka di perangkat pribadi. **L4** \`-\` tidak ditanya, \`tidak flag\`, \`+N flag\`, atau \`gagal\`. **Total** dihitung dari log dengan \`pipeline.js\`. \`beda\` berarti tidak sama dengan persen di layar. **LLM ms** dan **/analyze ms** dari panggilan LLM terakhir pada halaman itu, atau dari \`/analyze\` paling lama kalau LLM tidak dipanggil. **ᴸ¹** berarti tes 31 Okt mengenai link itu lewat daftar L1, jadi tidak sebanding langsung.

## Waktu

Median / p95 / maksimum, dalam milidetik.

| Yang diukur | Hasil |
|---|---|
| LLM | ${stats(allLlm.map((l) => l.ms))} |
| /analyze, panggilan dengan LLM | ${stats(allCalls.filter((c) => c.llm.length).map((c) => c.analyzeMs))} |
| /analyze, semua | ${stats(allCalls.map((c) => c.analyzeMs))} |
| RDAP, panggilan yang benar-benar lookup | ${stats(allCalls.filter((c) => c.rdapMs > 0).map((c) => c.rdapMs))} |

Panggilan LLM: ${allLlm.length}. Token: ${tokens("total_tokens").toLocaleString("id-ID")} (masuk ${tokens("prompt_tokens").toLocaleString("id-ID")}, keluar ${tokens("completion_tokens").toLocaleString("id-ID")}).

## Detail per link

${rows.map(detail).filter(Boolean).join("\n\n")}

${readOptional(join(dir, "analisis.md"))}
`;

writeFileSync(join(dir, "HASIL.md"), hasil);
writeFileSync(join(dir, "data.json"), JSON.stringify({ summary, rows: rows.map(({ ownCalls, ...r }) => r) }, null, 2) + "\n");
console.log(JSON.stringify(summary, null, 2));
