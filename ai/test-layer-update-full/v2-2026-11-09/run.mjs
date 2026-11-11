#!/usr/bin/env node
// Tes v2 Layer 4: detail L2 ke LLM (B), penjelasan `reason` (B), aturan peniruan (C), lawan kontrol A (prompt v4 produksi).
// Plan: PLAN.md (keputusan K1-K12 dan batas lulus ditetapkan di sana, bukan di skrip ini). Hasil: HASIL.md. Mentah: .hasil/ (di-gitignore).
//
// Tiap link: L2 (detector.js lewat vm, L1 mati) -> RDAP live 1 dtk (sekali per domain, .hasil/rdap.json, dipakai tiga versi)
// -> L3 (analyzeWithDomain produksi, tanpa LLM) -> tiga permintaan LLM satu per satu (urutan A/B/C dirotasi per link)
// -> aturan flag -> skor dan tingkat dari pipeline.js lewat vm.
// Tidak ada permintaan ke situs scam. Ke RDAP hanya nama domain (kecuali trap brand: tidak dihubungi sama sekali).
// Isi ai/.env tidak pernah dicetak atau disimpan; yang dicatat cuma nama model dan host.
//
// Pakai:  node run.mjs --dry               LLM tiruan, semua 63 link, cek gate, body A = produksi, payload, penggantian prompt
//         node run.mjs --only <id>         LLM sungguhan, satu link, ke .hasil/only-<id>.json
//         node run.mjs                     jalankan penuh, satu per satu, ke .hasil/full.json (--resume: lanjut yang belum)
//         node run.mjs --report            tulis HASIL.md dari .hasil/full.json
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { analyzeWithDomain } from "../../src/analyze.js";
import { sanitizeSnapshot } from "../../src/validate.js";
import { hostOf, isOfficialHost } from "../../src/layer3/official.js";
import { registrableDomain } from "../../src/rdap/domain.js";
import { createRdapClient } from "../../src/rdap/rdap.js";
import { createMemoryCache } from "../../src/rdap/cache.js";
import { createRealityCheck, buildInput, passesGate, MIN_CONFIDENCE, WEIGHT, GATE_BLOCK_SCORE } from "../../src/layer4/reality.js";
import { createProvider } from "../../src/layer4/provider.js";
import { parseVerdict } from "../../src/layer4/schema.js";
import { readConfig, MAX_TIMEOUT_MS } from "../../src/layer4/config.js";
import { SYSTEM_PROMPT, PROMPT_VERSION, LINK_TEXT } from "../../prompts/reality-check.js";
import brandsJson from "../../../detector/data/brands.json" with { type: "json" };

const here = dirname(fileURLToPath(import.meta.url));
const aiDir = join(here, "..", "..");
const repoDir = join(aiDir, "..");
const outDir = join(here, ".hasil");
const rdapFile = join(outDir, "rdap.json");
const detectorFile = join(repoDir, "ios", "ShooExtension", "Resources", "detector.js");
const pipelineFile = join(repoDir, "ios", "ShooExtension", "Resources", "pipeline.js");

const LLM_TIMEOUT_MS = 8000; // K5
const RDAP_TIMEOUT_MS = 1000; // K6
const CUT_MS = MAX_TIMEOUT_MS; // K5: lebih dari ini = akan terpotong di produksi
const STOP_AFTER_HTTP_ERRORS = 10;
const TOKENS = { A: 200, B: 300, C: 300 };
const VERSIONS = ["A", "B", "C"];
const PROMPT_NAMES = { A: PROMPT_VERSION, B: "reality-check.v5-l2-reason", C: "reality-check.v5c-impersonate" };
const LEVELS = ["normal", "warning 1", "warning 2", "blokir"];
const EXPECTED = { scam: 26, legit: 19, trap: 10, trapbrand: 8 };
const KIND_NAMES = { scam: "Scam asli", legit: "Legit asli non-resmi", trap: "Trap (sintetis)", trapbrand: "Trap brand (sintetis)" };
const KINDS = Object.keys(EXPECTED);

const arg = (name) => {
    const i = process.argv.indexOf(name);
    return i > -1 ? process.argv[i + 1] : undefined;
};
const flag = (name) => process.argv.includes(name);
const log = (s) => process.stderr.write(`${s}\n`);

// ---- statistik ---------------------------------------------------------------
const sorted = (xs) => [...xs].sort((a, b) => a - b);
const sum = (xs) => xs.reduce((a, b) => a + b, 0);
const median = (xs) => {
    const s = sorted(xs);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const pctl = (xs, p) => sorted(xs)[Math.max(0, Math.ceil((p / 100) * xs.length) - 1)]; // nearest-rank
const git = (...a) => execFileSync("git", a, { cwd: repoDir, encoding: "utf8" }).trim();
const gitOk = (...a) => {
    try {
        execFileSync("git", a, { cwd: repoDir, stdio: "ignore" });
        return true;
    } catch {
        return false;
    }
};

// ---- prasyarat (PLAN.md "Prasyarat") ---------------------------------------------
function preflight() {
    if (Number(process.versions.node.split(".")[0]) < 22) throw new Error(`Node >= 22 diperlukan, ini ${process.version}`);
    if (!existsSync(detectorFile) || !existsSync(pipelineFile)) throw new Error("detector.js atau pipeline.js tidak ada");
    const clean = gitOk("diff", "--quiet", "HEAD", "--", "ai/src", "ai/prompts", "detector", "ios/ShooExtension/Resources");
    if (!clean) throw new Error("ada perubahan belum di-commit di ai/src, ai/prompts, detector, atau ios/ShooExtension/Resources; hentikan dan laporkan");
    return { codeClean: clean, diffMain: git("diff", "--stat", "origin/main", "--", "ai/src", "ai/prompts", "detector") };
}

// ---- data: 26 scam, 19 legit asli non-resmi, 10 trap, 8 trap brand -----------------
async function loadSamples() {
    const readJson = async (p) => JSON.parse(await readFile(p, "utf8"));
    const snapDir = join(aiDir, "test-layer3", "snapshots");
    const files = (await readdir(snapDir)).filter((f) => f.endsWith(".json")).sort();
    const snaps = [];
    for (const f of files) {
        const r = await readJson(join(snapDir, f));
        snaps.push({ id: r.id, kind: r.id.startsWith("L") ? "legit" : "scam", snapshot: r.snapshot, source: "test-layer3" });
    }
    const evalDir = join(aiDir, "eval", "data");
    const real = (list) => list.filter((x) => x.synthetic !== true);
    const mk = (list, kind, source) => list.map((x) => ({ id: x.id, kind, snapshot: x.snapshot, source }));
    const scamSeed = mk(real(await readJson(join(evalDir, "scam", "seed.json"))), "scam", "eval/scam/seed");
    const legitReal = mk(real(await readJson(join(evalDir, "legit", "real.json"))), "legit", "eval/legit/real");
    const legitSeed = mk(real(await readJson(join(evalDir, "legit", "seed.json"))), "legit", "eval/legit/seed");
    const traps = mk(await readJson(join(evalDir, "legit", "traps.json")), "trap", "eval/legit/traps");
    const trapBrand = mk(await readJson(join(here, "trap-brand.json")), "trapbrand", "v2/trap-brand");

    const scam = [...snaps.filter((x) => x.kind === "scam"), ...scamSeed];
    const legitAll = [...snaps.filter((x) => x.kind === "legit"), ...legitReal, ...legitSeed];
    const legit = legitAll.filter((x) => !isOfficialHost(hostOf(x.snapshot.url)));
    const counts = { snapshots: snaps.length, scam: scam.length, legitAsli: legitAll.length, legitNonResmi: legit.length, trap: traps.length, trapbrand: trapBrand.length };
    const recs = [...scam, ...legit, ...traps, ...trapBrand];
    const want = EXPECTED;
    if (snaps.length !== 35 || scam.length !== want.scam || legit.length !== want.legit || traps.length !== want.trap || trapBrand.length !== want.trapbrand || new Set(recs.map((r) => r.id)).size !== recs.length) {
        throw new Error(`jumlah sampel salah, bukan 26 + 19 + 10 + 8 dengan id unik: ${JSON.stringify(counts)}`);
    }
    return { recs, counts };
}

// ---- L2 dan pipeline.js lewat vm (L1 mati: ShooLists tidak ada) ----------------------
async function loadScript(file, globalName) {
    const ctx = { URL, console };
    ctx.globalThis = ctx;
    vm.createContext(ctx);
    vm.runInContext(await readFile(file, "utf8"), ctx);
    if (!ctx[globalName]) throw new Error(`${globalName} tidak terpasang oleh ${file}`);
    return ctx[globalName];
}

// ---- RDAP live, sekali per domain (K6) ----------------------------------------------
async function loadRdapCache() {
    try {
        return JSON.parse(await readFile(rdapFile, "utf8"));
    } catch {
        return {};
    }
}

async function makeRdap() {
    // Bootstrap IANA ikut batas 1 dtk; di produksi ia sudah hangat di memori isolate. Dihangatkan sekali di sini.
    for (let i = 0; i < 3; i++) {
        const client = createRdapClient({ fetch, cache: createMemoryCache(), timeoutMs: 5000 });
        if ((await client.lookup("example.com", { cache: createMemoryCache() })).ageDays !== null) {
            const live = createRdapClient({ fetch, cache: createMemoryCache(), timeoutMs: RDAP_TIMEOUT_MS });
            for (let j = 0; j < 3; j++) if ((await live.lookup("example.com", { cache: createMemoryCache() })).ageDays !== null) return live;
        }
    }
    throw new Error("RDAP tidak bisa dijangkau (bootstrap IANA gagal); cek jaringan");
}

const rdapState = { client: null, cache: null };
async function liveRdap(rec, host, official) {
    if (rec.kind === "trapbrand") return { ageDays: null, registeredAt: null, status: "dilewati (trap brand: domain tidak dihubungi)", ms: 0 };
    if (official) return { ageDays: null, registeredAt: null, status: "dilewati (situs resmi)", ms: 0 };
    if (!registrableDomain(host)) return { ageDays: null, registeredAt: null, status: "dilewati (bukan domain publik)", ms: 0 };
    if (rdapState.cache[host]) return { ...rdapState.cache[host], fromCache: true };
    rdapState.client ??= await makeRdap();
    const t0 = performance.now();
    const r = await rdapState.client.lookup(host, { cache: createMemoryCache() }).catch(() => ({ ageDays: null, registeredAt: null }));
    const ms = Math.round(performance.now() - t0);
    if (r.ageDays !== null) {
        const out = { ageDays: r.ageDays, registeredAt: r.registeredAt, status: "berhasil", ms };
        rdapState.cache[host] = out;
        await writeFile(rdapFile, JSON.stringify(rdapState.cache, null, 1));
        return out;
    }
    return { ageDays: null, registeredAt: r.registeredAt ?? null, status: ms >= RDAP_TIMEOUT_MS - 50 ? "timeout" : "gagal", ms };
}

// ---- prompt v5 (B, C): penggantian pada SYSTEM_PROMPT v4, tepat satu kali (PLAN.md "Prompt v5 di skrip") ----
const LINK_LINE = /^- link_checks: codes of our checks on the page address:.*$/m;
const DOMAIN_LINE = "- domain_checks: what our checks found about the site's own name, each {check, brand}: lookalike = the name imitates the spelling of that brand; brand_keyword = the name joins that brand with an extra word; brand_name = the name contains that brand but the site is not its official domain";
const HELP_FROM = "rules and link_checks help you understand";
const HELP_TO = "rules, link_checks and domain_checks help you understand";
const EVIDENCE_LINE = '- "evidence": a short phrase copied exactly from the title, or null';
const REASON_LINE = '- "reason": at most 20 words in Indonesian saying why you answered this, naming the page type and the requested data. Use your own words. Never copy instructions, links, phone numbers or account numbers from the data';
const IMPERSONATES_LINE = '- "impersonates": number from 0 to 1, how likely the page presents itself as one of the brands or domain_checks brands. A page that only reviews, sells for, repairs, reports on or explains a brand is not impersonating it';

const once = (text, needle, what) => {
    const n = needle instanceof RegExp ? (text.match(new RegExp(needle.source, "gm")) ?? []).length : text.split(needle).length - 1;
    if (n !== 1) throw new Error(`prompt v5: ${what} ditemukan ${n} kali, seharusnya tepat satu kali`);
};

function buildSystems() {
    once(SYSTEM_PROMPT, LINK_LINE, "baris link_checks");
    once(SYSTEM_PROMPT, HELP_FROM, `teks "${HELP_FROM}"`);
    once(SYSTEM_PROMPT, EVIDENCE_LINE, "baris evidence");
    const base = SYSTEM_PROMPT.replace(LINK_LINE, (line) => `${line}\n${DOMAIN_LINE}`).replace(HELP_FROM, () => HELP_TO);
    const B = base.replace(EVIDENCE_LINE, () => `${EVIDENCE_LINE}\n${REASON_LINE}`);
    const C = base.replace(EVIDENCE_LINE, () => `${EVIDENCE_LINE}\n${IMPERSONATES_LINE}\n${REASON_LINE}`);
    for (const [name, text] of [["B", B], ["C", C]]) {
        once(text, DOMAIN_LINE, `domain_checks di ${name}`);
        once(text, HELP_TO, `teks bantu di ${name}`);
        once(text, REASON_LINE, `reason di ${name}`);
    }
    once(C, IMPERSONATES_LINE, "impersonates di C");
    if (B.includes("impersonates")) throw new Error("prompt B tidak boleh menyebut impersonates");
    return { A: SYSTEM_PROMPT, B, C };
}

// ---- domain_checks (PLAN.md "Isi domain_checks") ----------------------------------------
const BRAND_NAME_BY_ID = new Map(brandsJson.brands.map((b) => [b.id, b.name]));
const BRAND_NAMES = new Set(BRAND_NAME_BY_ID.values());
const DOMAIN_CHECKS = new Set(["lookalike", "brand_keyword", "brand_name"]);

function domainChecks(local) {
    const out = [];
    const seen = new Set();
    for (const s of local) {
        if (s.layer !== 2 || typeof s.evidence !== "string") continue;
        const [idPart, levelPart] = s.evidence.split(" · ");
        const brand = BRAND_NAME_BY_ID.get((idPart ?? "").trim());
        if (!brand) continue; // id tak dikenal dibuang
        let check = null;
        if (s.id === "lookalike_domain" && levelPart === "level 3") check = "lookalike";
        else if (s.id === "brand_plus_keyword" && levelPart === "level 2") check = "brand_keyword";
        else if (s.id === "lookalike_domain" && levelPart === "level 1") check = "brand_name";
        if (!check || seen.has(`${check}|${brand}`)) continue;
        seen.add(`${check}|${brand}`);
        out.push({ check, brand });
    }
    return out.slice(0, 3);
}

// ---- cek isi payload (SECURITY A1, A4, K11) ------------------------------------------------
const norm = (s) => String(s ?? "").normalize("NFKD").toLowerCase().replace(/\s+/g, " ").trim();
const BASE_KEYS = ["site", "title", "fields", "brands", "rules", "link_checks"];

/** Daftar pelanggaran (kosong = bersih) untuk satu body sebelum dikirim. */
function payloadViolations(bodyText, ctx, tag, systems) {
    const bad = [];
    const body = JSON.parse(bodyText);
    const [sys, usr] = body.messages ?? [];
    if (sys?.content !== systems[tag]) bad.push("system message bukan teks prompt yang dikira");
    if (body.max_tokens !== TOKENS[tag]) bad.push(`max_tokens ${body.max_tokens}, seharusnya ${TOKENS[tag]}`);
    const m = /^DATA_START\n([\s\S]*)\nDATA_END$/.exec(usr?.content ?? "");
    if (!m) return [...bad, "user message tanpa DATA_START/DATA_END"];
    const input = JSON.parse(m[1]);
    const allowed = tag === "A" ? BASE_KEYS : [...BASE_KEYS, "domain_checks"];
    for (const k of Object.keys(input)) if (!allowed.includes(k)) bad.push(`kunci tak dikenal: ${k}`);
    for (const k of allowed) if (!(k in input)) bad.push(`kunci hilang: ${k}`);
    if (/site_age|days? old|new_domain|evidence/.test(m[1])) bad.push("umur domain atau evidence ikut terkirim");
    if (typeof input.site === "string" && !/^[a-z0-9.-]+$/.test(input.site)) bad.push("site bukan nama domain polos");
    if (!Array.isArray(input.fields) || input.fields.length > 12 || input.fields.some((f) => Object.keys(f).sort().join() !== "label,type")) bad.push("fields bukan {type,label} (maks 12)");
    if (!Array.isArray(input.rules) || input.rules.some((r) => !/^[a-z0-9_]+$/.test(r) || r === "new_domain" || r === "unreasonable_request")) bad.push("rules berisi id yang tak boleh");
    if (!Array.isArray(input.link_checks) || input.link_checks.some((c) => !Object.hasOwn(LINK_TEXT, c))) bad.push("link_checks di luar legenda");
    if (!Array.isArray(input.brands) || input.brands.length > 3 || input.brands.some((b) => !BRAND_NAMES.has(b))) bad.push("brands salah bentuk atau bukan dari brands.json");
    if (typeof input.title !== "string" || input.title.length > 120) bad.push("title lebih dari 120 karakter");
    if (tag !== "A") {
        const dc = input.domain_checks;
        if (!Array.isArray(dc) || dc.length > 3) bad.push("domain_checks bukan array maks 3");
        else {
            const keys = dc.map((d) => `${d?.check}|${d?.brand}`);
            if (new Set(keys).size !== keys.length) bad.push("domain_checks berisi duplikat");
            for (const d of dc) {
                if (Object.keys(d ?? {}).sort().join() !== "brand,check" || !DOMAIN_CHECKS.has(d.check) || !BRAND_NAMES.has(d.brand)) bad.push(`domain_checks salah bentuk: ${JSON.stringify(d)}`);
            }
            if (JSON.stringify(dc) !== JSON.stringify(ctx.domainChecks)) bad.push("domain_checks tidak sama dengan yang dihitung dari L2");
        }
    }
    // path, query, hash, action form, nilai ketikan: tidak boleh muncul di payload
    const raw = m[1];
    let u = null;
    try {
        u = new URL(ctx.url);
    } catch {
        /* url rusak: tidak ada yang bisa dicek */
    }
    if (u) {
        if (u.pathname.length > 1 && raw.includes(u.pathname)) bad.push("path URL ikut terkirim");
        if (u.search.length > 1 && raw.includes(u.search)) bad.push("query URL ikut terkirim");
        if (u.hash.length > 1 && raw.includes(u.hash)) bad.push("hash URL ikut terkirim");
    }
    for (const form of ctx.forms) {
        if (typeof form.action === "string" && form.action.length >= 6 && raw.includes(form.action)) bad.push("action form ikut terkirim");
        for (const f of form.fields) if (typeof f.value === "string" && f.value.length >= 3 && raw.includes(f.value)) bad.push("nilai ketikan ikut terkirim");
    }
    // teks halaman: potongan 30 karakter dari text tidak boleh ada di payload selain title dan label field (yang memang dari halaman)
    const rest = norm(JSON.stringify({ ...input, title: "", fields: input.fields?.map((f) => ({ type: f.type })) }));
    const text = norm(ctx.text);
    for (let i = 0; i + 30 <= text.length; i += 15) {
        if (rest.includes(text.slice(i, i + 30))) {
            bad.push("potongan teks halaman ikut terkirim");
            break;
        }
    }
    return bad;
}

// ---- panggilan LLM -------------------------------------------------------------------------
const approxTokens = (s) => Math.ceil(String(s).length / 4);

function unfence(content) {
    const t = String(content).trim();
    const open = /^```(?:json)?[ \t]*\r?\n/i;
    const close = /\r?\n?```$/;
    return open.test(t) && close.test(t) ? t.replace(open, "").replace(close, "") : t;
}

/** Tiruan respons provider untuk --dry dan untuk pemeriksaan body produksi. Key `reason` / `impersonates` hanya kalau promptnya memintanya. */
function mockResponse(bodyText) {
    const body = JSON.parse(bodyText);
    const m = /^DATA_START\n([\s\S]*)\nDATA_END$/.exec(body.messages[1].content);
    const input = JSON.parse(m[1]);
    const askSensitive = input.fields.some((f) => /pass|pin|otp|kata sandi/i.test(`${f.type} ${f.label}`));
    const system = body.messages[0].content;
    const answer = { page_type: askSensitive ? "bank" : "other", asks: askSensitive ? ["password"] : [], reasonable: !askSensitive, confidence: askSensitive ? 0.9 : 0.6, evidence: null };
    if (system.includes('"reason"')) answer.reason = askSensitive ? "Halaman bank meminta kata sandi, tidak wajar." : "Halaman biasa tanpa permintaan data sensitif.";
    if (system.includes('"impersonates"')) answer.impersonates = input.domain_checks?.length && input.brands.length ? 0.8 : 0.1;
    const content = JSON.stringify(answer);
    const prompt = approxTokens(body.messages.map((x) => x.content).join(""));
    const completion = approxTokens(content);
    return { id: "mock", model: "dry-model", choices: [{ index: 0, message: { role: "assistant", content }, finish_reason: "stop" }], usage: { prompt_tokens: prompt, completion_tokens: completion, total_tokens: prompt + completion } };
}

/** fetch yang menyimpan respons provider utuh. `mock`: jawab sendiri tanpa jaringan. */
function recordingFetch(store, mock) {
    return async (url, init) => {
        store.requestBody = String(init.body);
        if (mock) {
            store.status = 200;
            store.text = JSON.stringify(mock(store.requestBody));
            return new Response(store.text, { status: 200, headers: { "content-type": "application/json" } });
        }
        const res = await fetch(url, init); // melempar kalau diabort atau jaringan gagal
        const text = await res.text();
        store.status = res.status;
        store.text = text;
        const empty = [204, 205, 304].includes(res.status);
        return new Response(empty ? null : text, { status: res.status, headers: { "content-type": res.headers.get("content-type") ?? "application/json" } });
    };
}

const slim = (s) => ({ id: s.id, layer: s.layer, weight: s.weight, ...(s.evidence ? { evidence: s.evidence } : {}) });

/** Body persis seperti yang dibuat provider.js produksi, dipakai untuk pemeriksaan payload sebelum kirim. */
const bodyOf = (cfg, messages, tag) =>
    JSON.stringify({ model: cfg.model, messages, temperature: 0, max_tokens: TOKENS[tag], response_format: { type: "json_object" }, chat_template_kwargs: { thinking: false } });

/** Satu panggilan: provider produksi, parseVerdict produksi, lalu aturan flag. */
async function askVersion(tag, ctx, env) {
    const input = buildInput(ctx.snapshot, ctx.ruleIds, ctx.local);
    if (tag !== "A") input.domain_checks = ctx.domainChecks;
    const messages = [
        { role: "system", content: env.systems[tag] },
        { role: "user", content: `DATA_START\n${JSON.stringify(input)}\nDATA_END` },
    ];
    const rec = { tag, prompt: PROMPT_NAMES[tag], maxTokens: TOKENS[tag], asked: true, input, outcome: null, ms: null, status: null, finish: null, usage: null, usageEstimated: false, response: null, rawBody: null, verdict: null, reason: null, impersonates: null, flagged: false, flagVia: null };

    const bad = payloadViolations(bodyOf(env.cfg, messages, tag), { url: ctx.snapshot.url, forms: ctx.snapshot.forms, text: ctx.snapshot.text, domainChecks: ctx.domainChecks }, tag, env.systems);
    if (bad.length) {
        rec.outcome = "diblokir";
        rec.problems = bad.map((b) => `payload ${tag} tidak boleh dikirim: ${b}`);
        return rec;
    }

    const store = {};
    const ask = createProvider({ config: env.cfg, fetch: recordingFetch(store, env.dry ? mockResponse : null) });
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);
    const t0 = performance.now();
    let answer;
    try {
        answer = await ask(messages, controller.signal, { maxTokens: TOKENS[tag] });
    } finally {
        clearTimeout(timer);
    }
    rec.ms = Math.round(performance.now() - t0);
    rec.status = store.status ?? null;
    if (store.text != null) {
        try {
            const j = JSON.parse(store.text);
            rec.response = j; // respons provider utuh: content, finish_reason, usage lengkap, id, model, dan field lain
            rec.finish = j.choices?.[0]?.finish_reason ?? null;
            rec.usage = j.usage ?? null;
        } catch {
            rec.rawBody = store.text.slice(0, 300);
        }
    }
    if (!rec.usage || !Number.isFinite(rec.usage.prompt_tokens)) {
        const p = approxTokens(messages.map((x) => x.content).join(""));
        const c = approxTokens(answer.content ?? "");
        rec.usage = { prompt_tokens: p, completion_tokens: c, total_tokens: p + c };
        rec.usageEstimated = true;
    }
    if (!answer.ok) {
        rec.outcome = answer.reason;
        return rec;
    }
    const verdict = parseVerdict(answer.content);
    if (!verdict) {
        rec.outcome = "bad_schema";
        return rec;
    }
    rec.verdict = verdict;
    let extra = {};
    try {
        extra = JSON.parse(unfence(answer.content));
    } catch {
        /* parseVerdict sudah menerimanya, jadi ini tidak terjadi */
    }
    rec.reason = typeof extra.reason === "string" ? extra.reason : null;
    rec.impersonates = typeof extra.impersonates === "number" && extra.impersonates >= 0 && extra.impersonates <= 1 ? extra.impersonates : null;
    const prodRule = !verdict.reasonable && verdict.confidence >= MIN_CONFIDENCE && verdict.asks.length > 0;
    const brandsOverlap = ctx.domainChecks.some((d) => input.brands.includes(d.brand));
    const impRule = tag === "C" && rec.impersonates !== null && rec.impersonates >= 0.7 && brandsOverlap;
    rec.flagged = prodRule || impRule;
    rec.flagVia = prodRule ? "produksi" : impRule ? "peniruan" : null;
    rec.outcome = rec.flagged ? "flagged" : "reasonable";
    return rec;
}

// ---- skor dan tingkat dari pipeline.js ---------------------------------------------------------
let P; // ShooPipeline
const levelOf = (score) => {
    const s = P.statusFor(score);
    if (s === "blocked") return 3;
    return s === "warning" ? (score >= P.THRESHOLD.secondWarning ? 2 : 1) : 0;
};

/** Tanda Layer 4 seperti buildSignal produksi (reality.js, tidak diekspor): +30, atau sisa jalan ke 80. */
const l4Signal = (score) => ({
    id: "unreasonable_request",
    layer: 4,
    weight: Math.max(WEIGHT, Math.ceil(GATE_BLOCK_SCORE - score)),
    label: { en: "The data requested does not fit this kind of page", id: "Data yang diminta tidak wajar untuk jenis halaman ini" },
    labelSimple: { en: "A real page of this kind would not ask for this", id: "Halaman asli seperti ini tidak akan meminta ini" },
});

function localScore(local) {
    let n = 0;
    for (const s of local.slice(0, 30)) if (s && (s.layer === 1 || s.layer === 2) && Number.isFinite(s.weight) && s.weight > 0) n += Math.min(s.weight, 100);
    return n;
}

function views(local, l3, total13, flagged) {
    const merge = (extra) => P.mergeSignals(P.validSignals(local, [1, 2]), P.validSignals([...l3, ...extra], [3, 4]));
    const base = P.scoreFrom(merge([]));
    const forcedTotal = flagged ? P.scoreFrom(merge([l4Signal(total13)])) : base;
    return { base, baseLevel: levelOf(base), flagWeight: flagged ? l4Signal(total13).weight : null, forcedTotal, forcedLevel: levelOf(forcedTotal) };
}

// ---- satu link --------------------------------------------------------------------------------------
async function runLink(rec, index, env) {
    const snapshot = sanitizeSnapshot(rec.snapshot);
    const host = hostOf(snapshot.url);
    const official = isOfficialHost(host);
    const hasForm = snapshot.forms.some((f) => f.fields.length > 0);
    const local = (await env.detector.analyzeLocal(rec.snapshot)) ?? [];
    const rdap = await liveRdap(rec, host, official);
    const stub = { lookup: async () => ({ registeredAt: rdap.registeredAt ?? null, ageDays: rdap.ageDays }) };
    const { signals: l3All } = await analyzeWithDomain(rec.snapshot, { rdap: stub, llm: null, localSignals: local });
    const l3 = l3All.filter((s) => s.layer === 3);
    const ruleIds = l3.filter((s) => s.id !== "new_domain").map((s) => s.id); // seperti analyze.js: sebelum new_domain
    const total13 = localScore(local) + sum(l3.map((s) => s.weight));
    const brandsFound = buildInput(snapshot, ruleIds, local).brands;
    const siteNull = !buildInput(snapshot, [], local).site;
    const gateOk = passesGate({ official, score: total13 }) && !siteNull;
    const dChecks = domainChecks(local);
    const askable = !official && !siteNull; // K7: semua link non-resmi ditanya, termasuk yang tidak lolos gate
    const ctx = { snapshot, ruleIds, local, domainChecks: dChecks };
    const problems = [];

    // trap brand: tiap baris harus menyalakan sinyal brand L2 dan detectBrands harus menemukan brand yang sama
    if (rec.kind === "trapbrand") {
        const l2brand = local.filter((s) => s.id === "lookalike_domain" || s.id === "brand_plus_keyword");
        const l2Names = l2brand.map((s) => BRAND_NAME_BY_ID.get(String(s.evidence).split(" · ")[0].trim())).filter(Boolean);
        if (!l2brand.length) problems.push("trap brand tidak menyalakan sinyal brand L2: ganti contohnya");
        else if (!l2Names.some((n) => brandsFound.includes(n))) problems.push(`trap brand: brand L2 (${l2Names.join(",")}) tidak sama dengan detectBrands (${brandsFound.join(",") || "kosong"})`);
        if (hasForm) problems.push("trap brand harus tanpa form");
    }

    // body A harus sama byte-per-byte dengan body dari createRealityCheck().check() produksi (jaringan tidak dipakai)
    let bodyAEqualsProduction = null;
    if (gateOk) {
        const store = {};
        const prod = createRealityCheck({ config: env.cfg, fetch: recordingFetch(store, mockResponse), clientCallsPerHour: Infinity });
        await prod.check(snapshot, { official, score: total13, ruleIds, localSignals: local, client: "v2", deadlineMs: LLM_TIMEOUT_MS });
        const messages = [
            { role: "system", content: env.systems.A },
            { role: "user", content: `DATA_START\n${JSON.stringify(buildInput(snapshot, ruleIds, local))}\nDATA_END` },
        ];
        bodyAEqualsProduction = store.requestBody === bodyOf(env.cfg, messages, "A");
        if (!bodyAEqualsProduction) problems.push("body versi A tidak sama dengan body production");
    }

    // tiga versi, satu per satu, urutan dirotasi per link (K4)
    const order = [0, 1, 2].map((i) => VERSIONS[(i + index) % 3]);
    const v = {};
    for (const tag of order) {
        if (!askable) {
            v[tag] = { tag, prompt: PROMPT_NAMES[tag], asked: false, outcome: "gated", flagged: false, flagVia: null };
            continue;
        }
        v[tag] = await askVersion(tag, ctx, env);
        if (v[tag].problems) {
            problems.push(...v[tag].problems);
            break;
        }
    }
    for (const tag of VERSIONS) {
        const r = v[tag];
        if (!r) continue;
        r.view = views(local, l3, total13, r.flagged);
        r.prodFlagged = r.flagged && gateOk;
        r.prodTotal = r.prodFlagged ? r.view.forcedTotal : r.view.base;
        r.prodLevel = levelOf(r.prodTotal);
    }

    return {
        id: rec.id,
        kind: rec.kind,
        source: rec.source,
        index,
        order,
        url: snapshot.url,
        host,
        title: snapshot.title,
        official,
        hasForm,
        rdap,
        l2: { signals: local.map(slim), score: localScore(local) },
        l3: { signals: l3.map(slim), score: sum(l3.map((s) => s.weight)) },
        total13,
        gateOk,
        siteNull,
        brands: brandsFound,
        domainChecks: dChecks,
        bodyAEqualsProduction,
        v,
        problems,
    };
}

// ---- jalankan -----------------------------------------------------------------------------------------
async function measure() {
    const only = arg("--only");
    const dry = flag("--dry");
    const resume = flag("--resume");
    const pre = preflight();
    P = await loadScript(pipelineFile, "ShooPipeline");
    const detector = await loadScript(detectorFile, "ShooDetector");
    const systems = buildSystems(); // berhenti kalau ada penggantian yang tidak menemukan teks asalnya
    const { recs: all, counts } = await loadSamples();
    let recs = all.map((r, index) => ({ ...r, index }));
    if (only) {
        recs = recs.filter((r) => r.id === only);
        if (!recs.length) throw new Error(`link ${only} tidak ada`);
    }

    let cfg;
    if (dry) cfg = { baseUrl: "https://llm.invalid/v1", apiKey: "dry-run", model: "dry-model", timeoutMs: LLM_TIMEOUT_MS, dailyCap: 1e6 };
    else {
        try {
            process.loadEnvFile(join(aiDir, ".env"));
        } catch (e) {
            if (e?.code !== "ENOENT") throw e;
        }
        const base = readConfig(process.env); // untuk pemeriksaan keamanan (https, host publik); batas waktu kita sendiri
        if (!base) throw new Error("ai/.env belum lengkap (LLM_API_KEY, LLM_MODEL, LLM_BASE_URL) atau tidak aman");
        cfg = { ...base, timeoutMs: LLM_TIMEOUT_MS, dailyCap: 1e6 };
    }

    await mkdir(outDir, { recursive: true });
    rdapState.cache = await loadRdapCache();
    const env = { dry, cfg, detector, systems };
    const outFile = join(outDir, dry ? "dry.json" : only ? `only-${only}.json` : "full.json");
    let out = {
        meta: {
            model: cfg.model,
            host: new URL(cfg.baseUrl).hostname,
            prompts: PROMPT_NAMES,
            thinking: "off (chat_template_kwargs {thinking:false}, dari provider.js produksi)",
            temperature: 0,
            maxTokens: TOKENS,
            llmTimeoutMs: LLM_TIMEOUT_MS,
            cutMs: CUT_MS,
            rdapTimeoutMs: RDAP_TIMEOUT_MS,
            minConfidence: MIN_CONFIDENCE,
            node: process.version,
            commit: git("rev-parse", "--short", "HEAD"),
            branch: git("branch", "--show-current"),
            codeClean: pre.codeClean,
            diffMain: pre.diffMain,
            detectorVersion: detector.version ?? null,
            counts,
            systems,
            startedAt: new Date().toISOString(),
            finishedAt: null,
            stoppedEarly: null,
            dry,
        },
        samples: [],
    };
    if (resume && !dry && !only && existsSync(outFile)) {
        out = JSON.parse(await readFile(outFile, "utf8"));
        out.meta.resumedAt = [...(out.meta.resumedAt ?? []), new Date().toISOString()];
        out.meta.stoppedEarly = null;
        out.meta.finishedAt = null;
        log(`lanjut: ${out.samples.length} link sudah ada`);
    }
    const done = new Set(out.samples.map((s) => s.id));
    const save = () => writeFile(outFile, JSON.stringify(out));

    let httpErrorsInRow = 0;
    let failed = 0;
    for (const rec of recs) {
        if (done.has(rec.id)) continue;
        const s = await runLink(rec, rec.index, env);
        out.samples.push(s);
        const cells = VERSIONS.map((t) => {
            const r = s.v[t];
            return `${t} ${r.asked ? `${r.outcome}${r.flagged ? "*" : ""} ${r.ms}ms ${LEVELS[r.prodLevel]}` : "gated"}`;
        });
        log(`${s.id} ${s.kind} L2 ${s.l2.score} L3 ${s.l3.score} total ${s.total13} gate ${s.gateOk ? "ya" : "tidak"} umur ${s.rdap.ageDays ?? "-"} | ${cells.join(" | ")}${s.problems.length ? ` | MASALAH: ${s.problems.join("; ")}` : ""}`);
        if (s.problems.length) {
            failed++;
            if (!dry) {
                out.meta.stoppedEarly = `masalah di ${s.id}: ${s.problems.join("; ")}`;
                await save();
                log(`BERHENTI: ${out.meta.stoppedEarly}`);
                process.exitCode = 2;
                return;
            }
        }
        for (const t of s.order) {
            const r = s.v[t];
            if (!r?.asked) continue;
            httpErrorsInRow = r.outcome === "http_error" ? httpErrorsInRow + 1 : 0;
            if (httpErrorsInRow >= STOP_AFTER_HTTP_ERRORS) {
                out.meta.stoppedEarly = `${STOP_AFTER_HTTP_ERRORS} http_error berturut-turut, berhenti setelah ${s.id}`;
                await save();
                log(`BERHENTI: ${out.meta.stoppedEarly}`);
                process.exitCode = 2;
                return;
            }
        }
        await save();
    }
    out.meta.finishedAt = new Date().toISOString();
    await save();
    if (dry) dryChecks(out, recs.length === all.length);
    log(`selesai, ${outFile}`);
    if (failed) process.exitCode = 1;
}

/** Ringkasan --dry: jumlah sampel, trap brand, body A = produksi, penggantian prompt, payload bersih. */
function dryChecks(out, full) {
    const S = out.samples;
    const n = (f) => S.filter(f).length;
    const lines = [`\n=== RINGKASAN --dry ${full ? "(63 link)" : `(${S.length} link)`} ===`];
    lines.push(`sampel: ${KINDS.map((k) => `${k} ${n((s) => s.kind === k)}`).join(", ")}; sumber ${JSON.stringify(out.meta.counts)}`);
    const tb = S.filter((s) => s.kind === "trapbrand");
    lines.push(`trap brand: ${tb.filter((s) => s.l2.signals.some((x) => x.id === "lookalike_domain" || x.id === "brand_plus_keyword") && s.brands.length).length} / ${tb.length} menyalakan sinyal brand L2 dan ditemukan detectBrands; tanpa form ${tb.filter((s) => !s.hasForm).length} / ${tb.length}; L1-L3 ${tb.map((s) => `${s.id}:${s.total13}`).join(" ")}`);
    lines.push(`penggantian prompt: A sama dengan SYSTEM_PROMPT = ${out.meta.systems.A === SYSTEM_PROMPT}, B ${out.meta.systems.B.length - SYSTEM_PROMPT.length} karakter lebih panjang, C ${out.meta.systems.C.length - SYSTEM_PROMPT.length}; tiap penggantian ditemukan tepat satu kali (kalau tidak, skrip berhenti sebelum link pertama)`);
    const gated = S.filter((s) => s.gateOk);
    lines.push(`gate produksi: lolos ${gated.length}, tidak ${S.length - gated.length}; resmi ${n((s) => s.official)}, site null ${n((s) => s.siteNull)}; ditanya paksa ${n((s) => !s.official && !s.siteNull)}`);
    lines.push(`body A = production: ${n((s) => s.bodyAEqualsProduction === true)} / ${gated.length} link yang lolos gate (berbeda: ${n((s) => s.bodyAEqualsProduction === false)})`);
    lines.push(`domain_checks tidak kosong di ${n((s) => s.domainChecks.length)} link: ${S.filter((s) => s.domainChecks.length).map((s) => `${s.id}[${s.domainChecks.map((d) => `${d.check}:${d.brand}`).join("+")}]`).join(" ")}`);
    lines.push(`RDAP live: berhasil ${n((s) => s.rdap.status === "berhasil")}, gagal ${n((s) => s.rdap.status === "gagal")}, timeout ${n((s) => s.rdap.status === "timeout")}, dilewati ${n((s) => s.rdap.status.startsWith("dilewati"))}; dari cache ${n((s) => s.rdap.fromCache)}`);
    lines.push(`new_domain menyala di ${n((s) => s.l3.signals.some((x) => x.id === "new_domain"))} link`);
    lines.push(`pelanggaran payload dan masalah lain: ${S.flatMap((s) => s.problems.map((p) => `${s.id}: ${p}`)).join(" | ") || "tidak ada"}`);
    console.log(lines.join("\n"));
}

// ---- laporan ----------------------------------------------------------------------------------------------
const maskHost = (h) => h.replace(/\./g, "[.]");
function masker(s) {
    const hosts = [...new Set([s.host, s.host.replace(/^www\./, ""), registrableDomain(s.host)].filter(Boolean))].sort((a, b) => b.length - a.length);
    return (text) => hosts.reduce((t, h) => t.split(h).join(maskHost(h)), String(text));
}
const hostPath = (s) => {
    let path = "";
    try {
        const u = new URL(s.url);
        path = u.pathname === "/" ? "" : u.pathname; // tanpa query dan fragment (K10)
    } catch {
        /* url rusak */
    }
    return `${maskHost(s.host)}${path}`;
};
const cell = (x) => String(x).replace(/\|/g, "\\|").replace(/\n/g, " ");
const fmtMs = (x) => (x == null ? "-" : Math.round(x).toString());
const sigText = (signals) => (signals.length ? signals.map((s) => `${s.id}:${s.weight}`).join(", ") : "-");
const l2Text = (signals) => (signals.length ? signals.map((s) => `${s.id}:${s.weight}${s.evidence ? ` [${s.evidence}]` : ""}`).join(", ") : "-");
const words = (t) => String(t).trim().split(/\s+/).filter(Boolean).length;
const LEAK = /https?:\/\/|www\.|\b[\w-]+\.(?:com|id|net|org|co|xyz|info|link)\b|\+?\d[\d\s().-]{5,}\d|\d{4,}/i;

function answerText(r) {
    if (!r.asked) return "tidak ditanya";
    if (!r.verdict) return `(${r.outcome})`;
    const v = r.verdict;
    return `${v.pageType}; asks ${v.asks.join("+") || "[]"}; reasonable ${v.reasonable}; conf ${v.confidence}${r.impersonates != null ? `; imp ${r.impersonates}` : ""}`;
}

async function report() {
    const d = JSON.parse(await readFile(join(outDir, "full.json"), "utf8"));
    P = await loadScript(pipelineFile, "ShooPipeline");
    const S = d.samples;
    const by = (k) => S.filter((s) => s.kind === k);
    const lines = [];
    const p = (x = "") => lines.push(x);
    const calls = (list, t) => list.map((s) => s.v[t]).filter((r) => r.asked && r.outcome !== "diblokir");
    const ms = (list, t) => calls(list, t).map((r) => r.ms).filter((x) => x != null);
    const flaggedF = (list, t) => list.filter((s) => s.v[t].flagged); // tampilan paksa
    const flaggedP = (list, t) => list.filter((s) => s.v[t].prodFlagged); // tampilan produksi
    const ids = (list) => (list.length ? ` (${list.map((s) => s.id).join(", ")})` : "");
    const cnt = (list, f) => list.filter(f).length;
    const outcomeN = (list, t, o) => cnt(calls(list, t), (r) => r.outcome === o);
    const tok = (list, t, key) => sum(calls(list, t).map((r) => r.usage?.[key] ?? 0));
    const anyEst = S.some((s) => VERSIONS.some((t) => s.v[t].usageEstimated));
    const tilde = anyEst ? "~" : "";

    p("<!-- AUTO:START -->");
    p(`_Dibuat oleh \`run.mjs --report\` dari \`.hasil/full.json\` pada ${new Date().toISOString()}. Jangan edit di dalam blok ini; bagian "Analisis" di bawah blok ini aman._`);
    p("");
    p("# Hasil tes v2 Layer 4 (A kontrol, B detail L2 + reason, C + aturan peniruan)");
    p("");
    p(`- Model \`${d.meta.model}\` di \`${d.meta.host}\`, thinking off, temperature ${d.meta.temperature}, \`max_tokens\` A ${d.meta.maxTokens.A} / B ${d.meta.maxTokens.B} / C ${d.meta.maxTokens.C}.`);
    p(`- Prompt: A \`${d.meta.prompts.A}\` (produksi), B \`${d.meta.prompts.B}\`, C \`${d.meta.prompts.C}\` (B dan C hanya di skrip).`);
    p(`- Commit \`${d.meta.commit}\` di branch \`${d.meta.branch}\`. Kode bersih di \`ai/src\`, \`ai/prompts\`, \`detector\`, \`ios/ShooExtension/Resources\`: ${d.meta.codeClean ? "ya" : "TIDAK"}. Beda dengan \`origin/main\` di \`ai/src\`, \`ai/prompts\`, \`detector\`: ${d.meta.diffMain ? `\`${d.meta.diffMain.split("\n").pop().trim()}\`` : "tidak ada"}. Node ${d.meta.node}. detector.js versi ${d.meta.detectorVersion ?? "?"}, L1 mati.`);
    p(`- Mulai ${d.meta.startedAt}, selesai ${d.meta.finishedAt ?? "BELUM SELESAI"}.${d.meta.stoppedEarly ? ` **Berhenti dini: ${d.meta.stoppedEarly}.**` : ""} Tanggal data: ${d.meta.startedAt.slice(0, 10)}.`);
    p(`- ${S.length} link (${KINDS.map((k) => `${KIND_NAMES[k]} ${by(k).length}`).join(", ")}), satu putaran, tiap versi satu kali per link, satu per satu, urutan A/B/C dirotasi. Batas LLM ${d.meta.llmTimeoutMs / 1000} dtk; panggilan lebih dari ${d.meta.cutMs / 1000} dtk dihitung "akan terpotong di produksi". RDAP live ${d.meta.rdapTimeoutMs / 1000} dtk, satu lookup per domain. Domain disamarkan, ditulis host + path.`);
    p('- Tingkat: normal 0-29, warning 1 30-49, warning 2 50-79, blokir 80+. **Produksi** = gate berlaku (total L1-L3 30-79). **Paksa** = LLM ditanya di semua link non-resmi, hasilnya dihitung walau di luar gate.');
    p(`- Token dibaca dari \`usage\` respons provider${anyEst ? "; permintaan tanpa respons diganti perkiraan karakter ÷ 4 dan ditandai ~" : ""}.`);
    p("");

    p("## Ringkasan");
    p("");
    p("### Kena flag, tampilan produksi (dan jumlah per tingkat)");
    p("");
    p("| jenis | versi | kena flag | normal | warning 1 | warning 2 | blokir |");
    p("|---|---|--:|--:|--:|--:|--:|");
    for (const k of KINDS) {
        for (const t of VERSIONS) {
            const list = by(k);
            p(`| ${KIND_NAMES[k]} | ${t} | ${flaggedP(list, t).length} / ${list.length} | ${[0, 1, 2, 3].map((l) => cnt(list, (s) => s.v[t].prodLevel === l)).join(" | ")} |`);
        }
    }
    p("");
    p("### Kena flag, tampilan paksa");
    p("");
    p("| jenis | versi | kena flag | link |");
    p("|---|---|--:|---|");
    for (const k of KINDS) {
        for (const t of VERSIONS) {
            const f = flaggedF(by(k), t);
            p(`| ${KIND_NAMES[k]} | ${t} | ${f.length} / ${by(k).length} | ${f.map((s) => s.id).join(", ") || "-"} |`);
        }
    }
    p("");
    p("### Link yang berubah dibanding A");
    p("");
    p("| jenis | versi | tingkat produksi naik | tingkat produksi turun | flag paksa bertambah | flag paksa hilang |");
    p("|---|---|---|---|---|---|");
    for (const k of KINDS) {
        for (const t of ["B", "C"]) {
            const list = by(k);
            const f = (arr) => (arr.length ? arr.map((s) => s.id).join(", ") : "-");
            p(`| ${KIND_NAMES[k]} | ${t} | ${f(list.filter((s) => s.v[t].prodLevel > s.v.A.prodLevel))} | ${f(list.filter((s) => s.v[t].prodLevel < s.v.A.prodLevel))} | ${f(list.filter((s) => s.v[t].flagged && !s.v.A.flagged))} | ${f(list.filter((s) => !s.v[t].flagged && s.v.A.flagged))} |`);
        }
    }
    p("");
    p("### Waktu LLM (ms), semua panggilan");
    p("");
    p(`| versi | panggilan | median | p95 | maks | > 5,5 dtk | > ${d.meta.cutMs / 1000} dtk | > ${d.meta.llmTimeoutMs / 1000} dtk (timeout) |`);
    p("|---|--:|--:|--:|--:|--:|--:|--:|");
    for (const t of VERSIONS) {
        const m = ms(S, t);
        p(`| ${t} | ${m.length} | ${fmtMs(m.length ? median(m) : null)} | ${fmtMs(m.length ? pctl(m, 95) : null)} | ${fmtMs(m.length ? Math.max(...m) : null)} | ${cnt(m, (x) => x > 5500)} | ${cnt(m, (x) => x > d.meta.cutMs)} | ${outcomeN(S, t, "timeout")} |`);
    }
    p("");
    p("### Token");
    p("");
    p("| versi | total | rata-rata input | rata-rata output | selisih total terhadap A |");
    p("|---|--:|--:|--:|--:|");
    const totA = tok(S, "A", "total_tokens");
    for (const t of VERSIONS) {
        const n = calls(S, t).length || 1;
        const tot = tok(S, t, "total_tokens");
        p(`| ${t} | ${tilde}${tot} | ${tilde}${Math.round(tok(S, t, "prompt_tokens") / n)} | ${tilde}${Math.round(tok(S, t, "completion_tokens") / n)} | ${t === "A" ? "-" : `${tot - totA >= 0 ? "+" : ""}${tot - totA} (${totA ? Math.round(((tot - totA) / totA) * 100) : 0}%)`} |`);
    }
    p("");
    p("### Gagal");
    p("");
    p("| versi | `bad_schema` | `finish: length` | `http_error` | timeout | payload diblokir |");
    p("|---|--:|--:|--:|--:|--:|");
    for (const t of VERSIONS) {
        const all = S.map((s) => s.v[t]).filter((r) => r.asked);
        p(`| ${t} | ${cnt(all, (r) => r.outcome === "bad_schema")} | ${cnt(all, (r) => r.finish === "length")} | ${cnt(all, (r) => r.outcome === "http_error")} | ${cnt(all, (r) => r.outcome === "timeout")} | ${cnt(all, (r) => r.outcome === "diblokir")} |`);
    }
    p("");
    p("### `reason`");
    p("");
    p("| versi | jawaban | `reason` terisi | > 20 kata | berisi link / telepon / deret angka | jawaban kena flag | flag dengan `reason` terisi dan ≤ 20 kata |");
    p("|---|--:|--:|--:|--:|--:|--:|");
    for (const t of ["B", "C"]) {
        const ans = calls(S, t).filter((r) => r.verdict);
        const filled = ans.filter((r) => r.reason && r.reason.trim());
        const fl = ans.filter((r) => r.flagged);
        p(`| ${t} | ${ans.length} | ${filled.length} | ${cnt(filled, (r) => words(r.reason) > 20)} | ${cnt(filled, (r) => LEAK.test(r.reason))} | ${fl.length} | ${cnt(fl, (r) => r.reason && r.reason.trim() && words(r.reason) <= 20)} |`);
    }
    p("");
    const rdapN = (st) => cnt(S, (s) => s.rdap.status === st);
    p(`RDAP live: berhasil ${rdapN("berhasil")}, gagal ${rdapN("gagal")}, timeout ${rdapN("timeout")}, dilewati ${cnt(S, (s) => s.rdap.status.startsWith("dilewati"))}. \`new_domain\` menyala di ${cnt(S, (s) => s.l3.signals.some((x) => x.id === "new_domain"))} link. Gate produksi lolos di ${cnt(S, (s) => s.gateOk)} link; ditanya paksa di ${cnt(S, (s) => s.v.A.asked)} link.`);
    p("");

    // ---- batas lulus ----
    p("## Batas lulus");
    p("");
    p("Ditetapkan di PLAN.md sebelum mengukur. Kalau A sendiri gagal di batas waktu, kolom batas waktu ditulis \"provider\".");
    p("");
    const legit = by("legit");
    const trap = by("trap");
    const tbr = by("trapbrand");
    const scam = by("scam");
    const pa = (t) => {
        const m = ms(S, t);
        return { p95: m.length ? pctl(m, 95) : null, slow: cnt(m, (x) => x > d.meta.cutMs) };
    };
    const aTimeFail = !(pa("A").p95 < 6000) || pa("A").slow > 1;
    const verdictRow = (label, limit, scope, f) => {
        const res = scope.map((t) => ({ t, ...f(t) }));
        p(`| ${label} | ${limit} | ${res.map((r) => `${r.t}: ${r.text}`).join("; ")} | ${res.map((r) => `${r.t}: ${r.ok == null ? "-" : r.ok ? "lulus" : r.provider ? "provider" : "**gagal**"}`).join("; ")} |`);
    };
    p("| ukuran | batas | hasil | lulus |");
    p("|---|---|---|---|");
    verdictRow("Legit asli kena flag, paksa", "0 / 19", ["B", "C"], (t) => ({ text: `${flaggedF(legit, t).length} / ${legit.length}${ids(flaggedF(legit, t))}`, ok: flaggedF(legit, t).length === 0 }));
    verdictRow("Trap kena flag, paksa", "tidak lebih banyak dari A", ["B", "C"], (t) => ({ text: `${flaggedF(trap, t).length} (A ${flaggedF(trap, "A").length})${ids(flaggedF(trap, t))}`, ok: flaggedF(trap, t).length <= flaggedF(trap, "A").length }));
    verdictRow("Trap brand kena flag, paksa", "0 / 8", ["C"], (t) => ({ text: `${flaggedF(tbr, t).length} / ${tbr.length}${ids(flaggedF(tbr, t))}`, ok: flaggedF(tbr, t).length === 0 }));
    verdictRow("Scam kena flag, produksi", "tidak kurang dari A", ["B", "C"], (t) => ({ text: `${flaggedP(scam, t).length} (A ${flaggedP(scam, "A").length})`, ok: flaggedP(scam, t).length >= flaggedP(scam, "A").length }));
    verdictRow("`bad_schema` + `finish: length`", "0", ["B", "C"], (t) => {
        const n = outcomeN(S, t, "bad_schema") + cnt(calls(S, t), (r) => r.finish === "length");
        return { text: String(n), ok: n === 0 };
    });
    verdictRow("p95 waktu LLM", "< 6.000 ms", ["B", "C"], (t) => ({ text: `${fmtMs(pa(t).p95)} ms (A ${fmtMs(pa("A").p95)})`, ok: pa(t).p95 < 6000, provider: aTimeFail }));
    verdictRow("Panggilan > 6 dtk", "maks 1 dari 63", ["B", "C"], (t) => ({ text: `${pa(t).slow} (A ${pa("A").slow})`, ok: pa(t).slow <= 1, provider: aTimeFail }));
    verdictRow("`reason` terisi dan ≤ 20 kata pada jawaban kena flag", "≥ 95%", ["B", "C"], (t) => {
        const fl = calls(S, t).filter((r) => r.flagged);
        const good = cnt(fl, (r) => r.reason && r.reason.trim() && words(r.reason) <= 20);
        return { text: fl.length ? `${good} / ${fl.length} (${Math.round((good / fl.length) * 100)}%)` : "tidak ada jawaban flag", ok: fl.length ? good / fl.length >= 0.95 : null };
    });
    verdictRow("`reason` berisi link / telepon / deret angka", "0", ["B", "C"], (t) => {
        const n = cnt(calls(S, t).filter((r) => r.reason), (r) => LEAK.test(r.reason));
        return { text: String(n), ok: n === 0 };
    });
    const lp = S.find((s) => s.id === "lphone-login");
    verdictRow("`lphone-login` kena flag", "ya", ["C"], () => ({ text: lp ? `produksi ${lp.v.C.prodFlagged ? "ya" : "tidak"}, paksa ${lp.v.C.flagged ? "ya" : "tidak"}${lp.v.C.flagVia ? ` (lewat aturan ${lp.v.C.flagVia})` : ""}` : "link tidak ada di data", ok: lp ? lp.v.C.prodFlagged : null }));
    p("");

    const head = ["id", "host + path", "jenis", "L2 (sinyal dan evidence)", "L3", "umur", "form", "L1-L3", "gate", "A", "B", "C"];
    const header = `| ${head.join(" | ")} |\n|${head.map(() => "---").join("|")}|`;
    const vcell = (r) => {
        if (!r.asked) return "tidak ditanya";
        const lv = `${r.prodTotal} ${LEVELS[r.prodLevel]}${r.flagged ? ` (flag${r.flagVia ? ` ${r.flagVia}` : ""}${r.prodFlagged ? "" : ", di luar gate"})` : ""}`;
        return `${lv}; ${answerText(r)}${r.reason ? `; alasan: ${r.reason}` : ""}; ${fmtMs(r.ms)} ms`;
    };
    const row = (s) => {
        const m = masker(s);
        return `| ${[s.id, `\`${hostPath(s)}\``, s.kind, m(l2Text(s.l2.signals)), `${s.l3.score}${s.l3.signals.length ? ` (${sigText(s.l3.signals)})` : ""}`, s.rdap.ageDays ?? s.rdap.status, s.hasForm ? "ya" : "tidak", s.total13, s.gateOk ? "ya" : "tidak", ...VERSIONS.map((t) => m(vcell(s.v[t])))].map(cell).join(" | ")} |`;
    };
    p("## Semua link");
    p("");
    for (const k of KINDS) {
        p(`### ${KIND_NAMES[k]} (${by(k).length})`);
        p("");
        p(header);
        for (const s of by(k)) p(row(s));
        p("");
    }

    p("## Detail per link");
    p("");
    p("Input = isi `user message` persis yang dikirim (antara `DATA_START` dan `DATA_END`), domain disamarkan. Respons provider utuh disimpan apa adanya (field `choices`, `usage`, dan lainnya). Contoh template K9 hanya kandidat teks untuk user, bukan keluaran LLM.");
    p("");
    for (const s of S) {
        const m = masker(s);
        p(`### ${s.id} hxxps://${hostPath(s)} (${s.kind})`);
        p("");
        p(`- L2: ${m(l2Text(s.l2.signals))} (skor ${s.l2.score}); L3: ${sigText(s.l3.signals)} (skor ${s.l3.score}); L1-L3: ${s.total13}; form: ${s.hasForm ? "ya" : "tidak"}; situs resmi: ${s.official ? "ya" : "tidak"}; lolos gate: ${s.gateOk ? "ya" : "tidak"}`);
        p(`- RDAP live: ${s.rdap.status}${s.rdap.ageDays != null ? `, ${s.rdap.ageDays} hari` : ""}, ${s.rdap.ms} ms${s.rdap.fromCache ? " (dari .hasil/rdap.json)" : ""}`);
        p(`- \`domain_checks\`: ${s.domainChecks.length ? m(JSON.stringify(s.domainChecks)) : "[]"}; \`brands\`: ${JSON.stringify(s.brands)}; urutan panggilan: ${s.order.join(" → ")}`);
        for (const t of VERSIONS) {
            const r = s.v[t];
            p("");
            if (!r.asked) {
                p(`**${t}**: tidak ditanya (${s.official ? "situs resmi" : "bukan domain publik"}).`);
                continue;
            }
            p(`**${t}** (\`${r.prompt}\`, \`max_tokens\` ${r.maxTokens}): ${r.outcome}${r.flagged ? ` (flag ${r.flagVia})` : ""}, ${fmtMs(r.ms)} ms, status ${r.status ?? "?"}, finish ${r.finish ?? "?"}, token ${r.usageEstimated ? "~" : ""}${r.usage?.prompt_tokens}/${r.usage?.completion_tokens}/${r.usage?.total_tokens}, tingkat produksi ${LEVELS[r.prodLevel]} (${r.prodTotal}), tingkat paksa ${LEVELS[r.view.forcedLevel]} (${r.view.forcedTotal})`);
            if (r.verdict?.asks.length) p(`- Contoh template K9: _Halaman ${r.verdict.pageType} ini meminta ${r.verdict.asks.join(", ")}_`);
            p("");
            p("Input:");
            p("");
            p("```json");
            p(m(JSON.stringify(r.input, null, 2)));
            p("```");
            p("");
            p("Respons provider utuh:");
            p("");
            p("```json");
            p(m(r.response ? JSON.stringify(r.response, null, 2) : (r.rawBody ?? "(tidak ada respons)")));
            p("```");
        }
        p("");
    }
    p("### System message A (v4 produksi)");
    p("");
    p("```");
    p(d.meta.systems.A);
    p("```");
    p("");
    p("### System message B (v5-l2-reason, hanya di skrip)");
    p("");
    p("```");
    p(d.meta.systems.B);
    p("```");
    p("");
    p("### System message C (v5c-impersonate, hanya di skrip)");
    p("");
    p("```");
    p(d.meta.systems.C);
    p("```");
    p("<!-- AUTO:END -->");

    const file = join(here, "HASIL.md");
    const old = await readFile(file, "utf8").catch(() => "");
    const i = old.indexOf("<!-- AUTO:END -->");
    const manual = i >= 0 ? old.slice(i + "<!-- AUTO:END -->".length) : "\n\n## Analisis\n\nBelum diisi.\n";
    await writeFile(file, lines.join("\n") + manual);
    console.log(`ok: ${file} (${S.length} link, ${sum(S.map((s) => VERSIONS.filter((t) => s.v[t].asked).length))} panggilan LLM)`);
}

try {
    if (flag("--report")) await report();
    else await measure();
} catch (e) {
    log(`GAGAL: ${e.message}`);
    process.exitCode = 1;
}
