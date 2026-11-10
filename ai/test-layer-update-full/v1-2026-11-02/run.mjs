#!/usr/bin/env node
// Tes perbandingan arsitektur Layer 1-4: Lama (3459f58) lawan Baru (A, branch ini) lawan Baru + umur (C), 75 link asli.
// Plan: PLAN.md. Hasil: HASIL.md. Mentah: .hasil/full.json (di-gitignore, isi payload dengan domain asli).
//
// Tiap link: L2 (detector.js lewat vm, L1 mati) -> RDAP live 1 dtk (sekali, dipakai tiga versi) -> analyze() kode lama dan
// kode baru berdampingan, satu LLM bersama (request yang isinya sama dikirim sekali, K6) -> opsi C (prompt v5 di skrip)
// hanya untuk link yang new_domain-nya menyala dan lolos gate baru (K7) -> skor dan tingkat dari pipeline.js lewat vm.
// Tidak ada permintaan ke situs scam. Ke RDAP hanya nama domain. Isi ai/.env tidak pernah dicetak atau disimpan.
//
// Pakai:  node run.mjs --dry               LLM tiruan, semua 75 link, cek gate, body lama = baru, isi payload (RDAP live)
//         node run.mjs --only 01           LLM sungguhan, satu link, ke .hasil/only-01.json
//         node run.mjs                     jalankan penuh, satu per satu, ke .hasil/full.json (--resume: lanjut yang belum)
//         node run.mjs --report            tulis HASIL.md dari .hasil/full.json
import { execFileSync, execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import vm from "node:vm";
import { analyze as newAnalyze } from "../../src/analyze.js";
import { sanitizeSnapshot } from "../../src/validate.js";
import { hostOf, isOfficialHost } from "../../src/layer3/official.js";
import { buildNewDomainSignal } from "../../src/layer3/signals.js";
import { registrableDomain } from "../../src/rdap/domain.js";
import { createRdapClient } from "../../src/rdap/rdap.js";
import { createMemoryCache } from "../../src/rdap/cache.js";
import { createRealityCheck as newCheck, buildInput, MIN_CONFIDENCE } from "../../src/layer4/reality.js";
import { parseVerdict } from "../../src/layer4/schema.js";
import { readConfig } from "../../src/layer4/config.js";
import { SYSTEM_PROMPT, PROMPT_VERSION, LINK_TEXT } from "../../prompts/reality-check.js";

const here = dirname(fileURLToPath(import.meta.url));
const aiDir = join(here, "..", "..");
const repoDir = join(aiDir, "..");
const outDir = join(here, ".hasil");
const oldDir = join(outDir, "old");
const detectorFile = join(repoDir, "ios", "ShooExtension", "Resources", "detector.js");
const pipelineFile = join(repoDir, "ios", "ShooExtension", "Resources", "pipeline.js");
const OLD_COMMIT = "3459f58";
const NEW_COMMIT = "2c51aee";
const BRANCH = "feat/AI-M4-thinking-off-asks-otp-boxes";

const LLM_TIMEOUT_MS = 6500; // K5
const RDAP_TIMEOUT_MS = 1000; // K4
const STOP_AFTER_HTTP_ERRORS = 10;
const SLOW_A = 5500;
const SLOW_B = 6000;
const LEVELS = ["normal", "warning 1", "warning 2", "blokir"];

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

// ---- prasyarat ---------------------------------------------------------------
function preflight() {
    if (Number(process.versions.node.split(".")[0]) < 22) throw new Error(`Node >= 22 diperlukan, ini ${process.version}`);
    const branch = git("branch", "--show-current");
    if (branch !== BRANCH) throw new Error(`branch ${branch}, seharusnya ${BRANCH}`);
    for (const c of [NEW_COMMIT, OLD_COMMIT]) git("cat-file", "-t", c);
    git("merge-base", "--is-ancestor", NEW_COMMIT, "HEAD"); // melempar kalau bukan leluhur
    if (!existsSync(detectorFile) || !existsSync(pipelineFile)) throw new Error("detector.js atau pipeline.js tidak ada");
    if (!existsSync(join(oldDir, "ai", "src", "analyze.js"))) {
        log(`memuat kode lama ${OLD_COMMIT} ke .hasil/old`);
        execSync(`mkdir -p "${oldDir}" && git archive ${OLD_COMMIT} ai/src ai/prompts detector/data | tar -x -C "${oldDir}"`, { cwd: repoDir, shell: "/bin/sh" });
    }
}

// ---- data: 26 scam + 49 legit asli -------------------------------------------
async function loadSamples() {
    const snapDir = join(aiDir, "test-layer3", "snapshots");
    const readJson = async (p) => JSON.parse(await readFile(p, "utf8"));
    const real = (list) => list.filter((x) => x.synthetic !== true);
    const files = (await readdir(snapDir)).filter((f) => f.endsWith(".json")).sort();
    const snaps = [];
    for (const f of files) {
        const r = await readJson(join(snapDir, f));
        snaps.push({ id: r.id, kind: r.id.startsWith("L") ? "legit" : "scam", snapshot: r.snapshot, age28: r.rdapAgeDays ?? null, source: "test-layer3" });
    }
    const evalDir = join(aiDir, "eval", "data");
    const mk = (list, kind, source) => real(list).map((x) => ({ id: x.id, kind, snapshot: x.snapshot, age28: null, source }));
    const scamSeed = mk(await readJson(join(evalDir, "scam", "seed.json")), "scam", "eval/scam/seed");
    const legitReal = mk(await readJson(join(evalDir, "legit", "real.json")), "legit", "eval/legit/real");
    const legitSeed = mk(await readJson(join(evalDir, "legit", "seed.json")), "legit", "eval/legit/seed");
    const n = (a, kind) => a.filter((x) => x.kind === kind).length;
    const counts = { snapScam: n(snaps, "scam"), snapLegit: n(snaps, "legit"), scamSeed: scamSeed.length, legitReal: legitReal.length, legitSeed: legitSeed.length };
    const scam = [...snaps.filter((x) => x.kind === "scam"), ...scamSeed];
    const legit = [...snaps.filter((x) => x.kind === "legit"), ...legitReal, ...legitSeed];
    if (snaps.length !== 35 || scam.length !== 26 || legit.length !== 49 || new Set([...scam, ...legit].map((x) => x.id)).size !== 75) {
        throw new Error(`jumlah sampel salah, bukan 26 scam + 49 legit: ${JSON.stringify(counts)}`);
    }
    return { recs: [...scam, ...legit], counts };
}

// ---- L2 dan pipeline.js lewat vm (L1 mati: ShooLists tidak ada) ----------------
async function loadScript(file, globalName) {
    const ctx = { URL, console };
    ctx.globalThis = ctx;
    vm.createContext(ctx);
    vm.runInContext(await readFile(file, "utf8"), ctx);
    if (!ctx[globalName]) throw new Error(`${globalName} tidak terpasang oleh ${file}`);
    return ctx[globalName];
}

// ---- RDAP live (K4) ----------------------------------------------------------
async function makeRdap() {
    // Bootstrap IANA ikut batas 1 dtk di produksi; di sana ia sudah hangat di memori isolate. Dihangatkan sekali di sini
    // dengan satu domain contoh supaya link pertama tidak kalah hanya karena unduhan bootstrap.
    for (let i = 0; i < 3; i++) {
        const client = createRdapClient({ fetch, cache: createMemoryCache(), timeoutMs: 5000 });
        if ((await client.lookupAgeDays("example.com", { cache: createMemoryCache() })) !== null) {
            const live = createRdapClient({ fetch, cache: createMemoryCache(), timeoutMs: RDAP_TIMEOUT_MS });
            // client baru butuh bootstrap lagi, jadi hangatkan juga yang berbatas 1 dtk (bootstrap sudah ada di cache HTTP/DNS)
            for (let j = 0; j < 3; j++) if ((await live.lookupAgeDays("example.com", { cache: createMemoryCache() })) !== null) return live;
        }
    }
    throw new Error("RDAP tidak bisa dijangkau (bootstrap IANA gagal); cek jaringan");
}

async function liveAge(rdap, host, official) {
    if (official) return { age: null, status: "dilewati (situs resmi)", ms: 0 };
    if (!registrableDomain(host)) return { age: null, status: "dilewati (bukan domain publik)", ms: 0 };
    const t0 = performance.now();
    const age = await rdap.lookupAgeDays(host, { cache: createMemoryCache() }).catch(() => null);
    const ms = Math.round(performance.now() - t0);
    if (age !== null) return { age, status: "berhasil", ms };
    return { age: null, status: ms >= RDAP_TIMEOUT_MS - 50 ? "timeout" : "gagal", ms };
}

// ---- prompt v5, hanya di skrip (opsi C) ---------------------------------------
const LINK_CHECKS_LINE = /^- link_checks: codes of our checks on the page address:.*$/m;
const SITE_AGE_LINE = `- site_age: how old the site's domain is, for example "3 days old"; only present when the domain is under 90 days old`;
const HELP_FROM = "rules and link_checks help you understand";
const HELP_TO = "rules, link_checks and site_age help you understand";

/** Berhenti (throw) kalau salah satu penggantian tidak menemukan teks asalnya, tepat satu kali. */
function toV5(bodyText, ageDays) {
    const body = JSON.parse(bodyText);
    const [sys, usr] = body.messages;
    if (sys?.role !== "system" || usr?.role !== "user") throw new Error("prompt v5: susunan messages tidak dikenal");
    if ((sys.content.match(new RegExp(LINK_CHECKS_LINE.source, "gm")) ?? []).length !== 1) throw new Error("prompt v5: baris link_checks tidak ditemukan tepat satu kali");
    sys.content = sys.content.replace(LINK_CHECKS_LINE, (line) => `${line}\n${SITE_AGE_LINE}`);
    if (sys.content.split(HELP_FROM).length !== 2) throw new Error(`prompt v5: teks "${HELP_FROM}" tidak ditemukan tepat satu kali`);
    sys.content = sys.content.replace(HELP_FROM, () => HELP_TO);
    const m = /^DATA_START\n([\s\S]*)\nDATA_END$/.exec(usr.content);
    if (!m) throw new Error("prompt v5: user message tanpa DATA_START/DATA_END");
    const data = JSON.parse(m[1]);
    data.site_age = `${ageDays} days old`;
    usr.content = `DATA_START\n${JSON.stringify(data)}\nDATA_END`;
    return JSON.stringify(body);
}

const v5Template = () => JSON.stringify({ messages: [{ role: "system", content: SYSTEM_PROMPT }, { role: "user", content: "DATA_START\n{}\nDATA_END" }] });
const SYSTEM_V5 = () => JSON.parse(toV5(v5Template(), 3)).messages[0].content;

// ---- cek isi payload (SECURITY A1, A4) ----------------------------------------
const norm = (s) => String(s ?? "").normalize("NFKD").toLowerCase().replace(/\s+/g, " ").trim();
const ALLOWED_KEYS = ["site", "title", "fields", "brands", "rules", "link_checks"];

/** Daftar pelanggaran (kosong = bersih) untuk satu body sebelum dikirim. `tag` 'C' = boleh punya site_age. */
function payloadViolations(bodyText, ctx, tag) {
    const bad = [];
    const body = JSON.parse(bodyText);
    const [sys, usr] = body.messages ?? [];
    if (sys?.content !== (tag === "C" ? SYSTEM_V5() : SYSTEM_PROMPT)) bad.push("system message bukan teks prompt yang dikira");
    const m = /^DATA_START\n([\s\S]*)\nDATA_END$/.exec(usr?.content ?? "");
    if (!m) return [...bad, "user message tanpa DATA_START/DATA_END"];
    const input = JSON.parse(m[1]);
    const allowed = tag === "C" ? [...ALLOWED_KEYS, "site_age"] : ALLOWED_KEYS;
    for (const k of Object.keys(input)) if (!allowed.includes(k)) bad.push(`kunci tak dikenal: ${k}`);
    for (const k of ALLOWED_KEYS) if (!(k in input)) bad.push(`kunci hilang: ${k}`);
    if (tag === "C" && input.site_age !== `${ctx.age} days old`) bad.push(`site_age ${JSON.stringify(input.site_age)} bukan umur live`);
    if (tag !== "C" && /site_age|days? old|new_domain/.test(m[1])) bad.push("umur domain ikut terkirim");
    if (typeof input.site === "string" && !/^[a-z0-9.-]+$/.test(input.site)) bad.push("site bukan nama domain polos");
    if (!Array.isArray(input.fields) || input.fields.length > 12 || input.fields.some((f) => Object.keys(f).sort().join() !== "label,type")) bad.push("fields bukan {type,label} (maks 12)");
    if (!Array.isArray(input.rules) || input.rules.some((r) => !/^[a-z0-9_]+$/.test(r) || r === "new_domain" || r === "unreasonable_request")) bad.push("rules berisi id yang tak boleh");
    if (!Array.isArray(input.link_checks) || input.link_checks.some((c) => !Object.hasOwn(LINK_TEXT, c))) bad.push("link_checks di luar legenda");
    if (!Array.isArray(input.brands) || input.brands.length > 3 || input.brands.some((b) => typeof b !== "string")) bad.push("brands salah bentuk");
    if (typeof input.title !== "string" || input.title.length > 120) bad.push("title lebih dari 120 karakter");
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

// ---- LLM bersama per link (K6) -------------------------------------------------
const abortError = () => new DOMException("aborted", "AbortError");
const abortable = (promise, signal) =>
    new Promise((resolve, reject) => {
        if (signal?.aborted) return reject(abortError());
        const onAbort = () => reject(abortError());
        signal?.addEventListener("abort", onAbort, { once: true });
        promise.then(resolve, reject).finally(() => signal?.removeEventListener("abort", onAbort));
    });

const approxTokens = (s) => Math.ceil(String(s).length / 4);

class LinkLlm {
    constructor({ mock, timeoutMs, check }) {
        this.mock = mock;
        this.timeoutMs = timeoutMs;
        this.check = check;
        this.entries = new Map(); // isi body -> permintaan asli
        this.bodies = {}; // tag -> [body]
        this.fatal = null;
    }

    /** fetch untuk satu createRealityCheck. `rewrite` mengubah body sebelum dikirim (opsi C). */
    fetchFor(tag, rewrite) {
        return async (url, init) => {
            let body = String(init.body);
            if (rewrite) {
                try {
                    body = rewrite(body);
                } catch (e) {
                    this.fatal = String(e.message);
                    throw e;
                }
            }
            (this.bodies[tag] ??= []).push(body);
            let entry = this.entries.get(body);
            if (!entry) {
                entry = this.start(url, body, init, tag);
                this.entries.set(body, entry);
            }
            entry.tags.add(tag);
            const r = await abortable(entry.done, init.signal);
            if (r.kind === "timeout") return abortable(new Promise(() => {}), init.signal); // tunggu timer pemanggil sendiri
            if (r.kind !== "response") throw new TypeError("fetch failed");
            const empty = [204, 205, 304].includes(r.status);
            return new Response(empty ? null : r.text, { status: r.status, headers: { "content-type": r.contentType } });
        };
    }

    start(url, body, init, tag) {
        const entry = { tags: new Set(), ms: null, status: null, finish: null, raw: null, rawBody: null, usage: null, body };
        const t0 = performance.now();
        entry.done = (async () => {
            const bad = this.check(body, tag);
            if (bad.length) {
                this.fatal = `payload tidak boleh dikirim (${tag}): ${bad.join("; ")}`;
                entry.ms = 0;
                return { kind: "blocked" };
            }
            if (this.mock) {
                const m = this.mock(body);
                Object.assign(entry, { ms: 0, status: 200, finish: "stop", raw: m.content, usage: m.usage });
                return { kind: "response", status: 200, text: JSON.stringify({ choices: [{ message: { content: m.content }, finish_reason: "stop" }], usage: m.usage }), contentType: "application/json" };
            }
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), this.timeoutMs);
            try {
                const res = await fetch(url, { ...init, body, signal: controller.signal });
                const text = await res.text();
                entry.ms = Math.round(performance.now() - t0);
                entry.status = res.status;
                try {
                    const j = JSON.parse(text);
                    entry.usage = j.usage ?? null;
                    entry.finish = j.choices?.[0]?.finish_reason ?? null;
                    entry.raw = j.choices?.[0]?.message?.content ?? null;
                } catch {
                    entry.rawBody = text.slice(0, 300); // bukan JSON: sedikit untuk diagnosis (isi respons provider, bukan kunci)
                }
                return { kind: "response", status: res.status, text, contentType: res.headers.get("content-type") ?? "application/json" };
            } catch {
                entry.ms = Math.round(performance.now() - t0);
                return controller.signal.aborted ? { kind: "timeout" } : { kind: "neterror" };
            } finally {
                clearTimeout(timer);
            }
        })();
        return entry;
    }
}

const DRY_ANSWER = { content: JSON.stringify({ page_type: "bank", asks: ["password"], reasonable: false, confidence: 0.9, evidence: null }), usage: { prompt_tokens: 100, completion_tokens: 20, total_tokens: 120 } };

// ---- skor dan tingkat dari pipeline.js -----------------------------------------
let P; // ShooPipeline
const levelOf = (score) => {
    const s = P.statusFor(score);
    if (s === "blocked") return 3;
    return s === "warning" ? (score >= P.THRESHOLD.secondWarning ? 2 : 1) : 0;
};
const slim = (s) => ({ id: s.id, layer: s.layer, weight: s.weight, ...(s.evidence ? { evidence: s.evidence } : {}) });
const outcomeOf = (llm) => Object.entries(llm.stats().outcomes).find(([, n]) => n > 0)?.[0] ?? null;

/** local = sinyal L2; remote = keluaran analyze() (L3, plus L4 kalau ada). */
function versionRecord(local, remote, llm) {
    const outcome = outcomeOf(llm);
    const l4 = remote.find((s) => s.layer === 4) ?? null;
    const merge = (r) => P.mergeSignals(P.validSignals(local, [1, 2]), P.validSignals(r, [3, 4]));
    const total = P.scoreFrom(merge(remote));
    const scoreNoL4 = P.scoreFrom(merge(remote.filter((s) => s.layer !== 4)));
    return {
        total,
        level: levelOf(total),
        scoreNoL4,
        levelNoL4: levelOf(scoreNoL4),
        asked: outcome !== null && outcome !== "gated" && outcome !== "capped",
        outcome,
        flagged: Boolean(l4),
        l4: l4 ? { weight: l4.weight, evidence: l4.evidence ?? null } : null,
        l3: remote.filter((s) => s.layer === 3).map(slim),
    };
}

/** Jumlah bobot L1-L2 seperti analyze.js menghitungnya untuk gate. */
function localScore(local) {
    let n = 0;
    for (const s of local.slice(0, 30)) if (s && (s.layer === 1 || s.layer === 2) && Number.isFinite(s.weight) && s.weight > 0) n += Math.min(s.weight, 100);
    return n;
}

// ---- satu link -----------------------------------------------------------------
async function runLink(rec, env) {
    const snap = sanitizeSnapshot(rec.snapshot);
    const host = hostOf(snap.url);
    const official = isOfficialHost(host);
    const hasForm = snap.forms.some((f) => f.fields.length > 0);
    const local = (await env.detector.analyzeLocal(rec.snapshot)) ?? [];
    const rdap = await liveAge(env.rdap, host, official);
    const stub = { lookupAgeDays: async () => rdap.age };

    const hub = new LinkLlm({
        mock: env.dry ? () => DRY_ANSWER : null,
        timeoutMs: LLM_TIMEOUT_MS,
        check: (body, tag) => payloadViolations(body, { url: snap.url, forms: snap.forms, text: snap.text, age: rdap.age }, tag),
    });
    const mkCheck = (mod, tag, rewrite) => mod.createRealityCheck({ config: env.cfg, fetch: hub.fetchFor(tag, rewrite), clientCallsPerHour: Infinity });
    const llmOld = mkCheck(env.old, "old");
    const llmNew = mkCheck(env.neu, "new");
    const [oldSigs, newSigs] = await Promise.all([
        env.old.analyze(rec.snapshot, { rdap: stub, llm: llmOld, localSignals: local }),
        newAnalyze(rec.snapshot, { rdap: stub, llm: llmNew, localSignals: local }),
    ]);
    const vOld = versionRecord(local, oldSigs, llmOld);
    const vNew = versionRecord(local, newSigs, llmNew);

    // gate yang diharapkan, dihitung terpisah dari sinyal yang keluar
    const l3New = newSigs.filter((s) => s.layer === 3);
    const total13 = localScore(local) + sum(l3New.map((s) => s.weight));
    const ruleScore = sum(l3New.filter((s) => s.id !== "new_domain").map((s) => s.weight));
    const siteNull = !buildInput(snap, [], local).site;
    const gates = {
        total13,
        ruleScore,
        siteNull,
        oldExpected: !official && !siteNull && hasForm && ruleScore >= 15,
        newExpected: !official && !siteNull && total13 >= 30 && total13 < 80,
    };

    // opsi C: new_domain menyala dan A bertanya (K7)
    let vC = null;
    let cSkip = null;
    if (!newSigs.some((s) => s.id === "new_domain")) cSkip = "new_domain tidak menyala";
    else if (!vNew.asked) cSkip = `tidak lolos gate baru (${vNew.outcome})`;
    else {
        const llmC = mkCheck(env.neu, "C", (b) => toV5(b, rdap.age));
        const cSigs = await newAnalyze(rec.snapshot, { rdap: stub, llm: llmC, localSignals: local });
        vC = versionRecord(local, cSigs, llmC);
    }

    // permintaan asli
    const outcomes = { old: vOld.outcome, new: vNew.outcome, C: vC?.outcome ?? null };
    const requests = [...hub.entries.values()].map((e) => {
        const tags = ["old", "new", "C"].filter((t) => e.tags.has(t));
        const parsedBody = JSON.parse(e.body);
        const m = /^DATA_START\n([\s\S]*)\nDATA_END$/.exec(parsedBody.messages[1].content);
        const ap = approxTokens(parsedBody.messages.map((x) => x.content).join(""));
        const ac = approxTokens(e.raw ?? "");
        const approx = { prompt: ap, completion: ac, total: ap + ac };
        const usage = e.usage && Number.isFinite(e.usage.prompt_tokens) ? { prompt: e.usage.prompt_tokens, completion: e.usage.completion_tokens, total: e.usage.total_tokens, estimated: false } : { ...approx, estimated: true };
        return {
            tags,
            input: m ? JSON.parse(m[1]) : null,
            ms: e.ms,
            status: e.status,
            finish: e.finish,
            raw: e.raw,
            ...(e.rawBody ? { rawBody: e.rawBody } : {}),
            usage,
            approx,
            verdict: e.raw ? parseVerdict(e.raw) : null,
            outcome: outcomes[tags[0]],
            outcomes: Object.fromEntries(tags.map((t) => [t, outcomes[t]])),
        };
    });

    const problems = [];
    if (hub.fatal) problems.push(hub.fatal);
    if (hub.bodies.old?.length && hub.bodies.new?.length && JSON.stringify(hub.bodies.old) !== JSON.stringify(hub.bodies.new)) problems.push("body LLM lama dan baru tidak sama");
    if (vOld.asked !== gates.oldExpected && vOld.outcome !== "capped") problems.push(`gate lama: diharapkan ${gates.oldExpected ? "bertanya" : "gated"}, hasil ${vOld.outcome}`);
    if (vNew.asked !== gates.newExpected && vNew.outcome !== "capped") problems.push(`gate baru: diharapkan ${gates.newExpected ? "bertanya" : "gated"}, hasil ${vNew.outcome}`);
    if (JSON.stringify(vOld.l3) !== JSON.stringify(vNew.l3)) problems.push("sinyal L3 lama dan baru beda");

    return {
        id: rec.id,
        kind: rec.kind,
        source: rec.source,
        url: snap.url,
        host,
        title: snap.title,
        official,
        hasForm,
        age28: rec.age28,
        rdap,
        l2: { signals: local.map(slim), score: localScore(local) },
        l3: { signals: vNew.l3, score: sum(vNew.l3.map((s) => s.weight)), ruleScore },
        gates,
        old: vOld,
        new: vNew,
        c: vC,
        cSkip,
        requests,
        problems,
    };
}

// ---- jalankan ------------------------------------------------------------------
async function measure() {
    const only = arg("--only");
    const dry = flag("--dry");
    const resume = flag("--resume");
    preflight();
    P = await loadScript(pipelineFile, "ShooPipeline");
    const detector = await loadScript(detectorFile, "ShooDetector");
    const { recs: all, counts } = await loadSamples();
    const old = {
        analyze: (await import(pathToFileURL(join(oldDir, "ai", "src", "analyze.js")))).analyze,
        createRealityCheck: (await import(pathToFileURL(join(oldDir, "ai", "src", "layer4", "reality.js")))).createRealityCheck,
    };
    const oldPrompt = await import(pathToFileURL(join(oldDir, "ai", "prompts", "reality-check.js")));
    if (oldPrompt.SYSTEM_PROMPT !== SYSTEM_PROMPT) throw new Error("teks prompt lama dan baru beda: body LLM tidak mungkin sama");
    SYSTEM_V5(); // penggantian prompt v5 harus menemukan teks asalnya, kalau tidak throw di sini

    let recs = all;
    if (only) {
        recs = all.filter((r) => r.id === only);
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
        const base = readConfig(process.env); // hanya untuk pemeriksaan keamanan (https, host publik); batas waktu diganti di bawah
        if (!base) throw new Error("ai/.env belum lengkap (LLM_API_KEY, LLM_MODEL, LLM_BASE_URL) atau tidak aman");
        cfg = { ...base, timeoutMs: LLM_TIMEOUT_MS, dailyCap: 1e6 };
    }

    const rdap = await makeRdap();
    const env = { dry, cfg, detector, rdap, old, neu: { createRealityCheck: newCheck } };

    await mkdir(outDir, { recursive: true });
    const outFile = join(outDir, dry ? "dry.json" : only ? `only-${only}.json` : "full.json");
    let out = {
        meta: {
            model: cfg.model,
            host: new URL(cfg.baseUrl).hostname,
            promptVersion: PROMPT_VERSION,
            thinking: "off (chat_template_kwargs {thinking:false}, sudah di provider.js lama dan baru)",
            temperature: 0,
            maxTokens: 200,
            llmTimeoutMs: LLM_TIMEOUT_MS,
            rdapTimeoutMs: RDAP_TIMEOUT_MS,
            minConfidence: MIN_CONFIDENCE,
            node: process.version,
            commit: git("rev-parse", "--short", "HEAD"),
            oldCommit: OLD_COMMIT,
            uncommitted: git("status", "--short", "ai/src", "ai/prompts").split("\n").filter(Boolean),
            detectorVersion: detector.version ?? null,
            counts,
            systemPrompt: SYSTEM_PROMPT,
            systemPromptV5: SYSTEM_V5(),
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
        const s = await runLink(rec, env);
        out.samples.push(s);
        const reqText = s.requests.map((r) => `${r.tags.join("+")} ${r.outcome} ${r.ms} ms`).join("; ") || "tanpa LLM";
        log(`${s.id} ${s.kind} L2 ${s.l2.score} L3 ${s.l3.score} umur ${s.rdap.age ?? "-"} | lama ${s.old.total}/${LEVELS[s.old.level]} baru ${s.new.total}/${LEVELS[s.new.level]}${s.c ? ` C ${s.c.total}/${LEVELS[s.c.level]}` : ""} | ${reqText}${s.problems.length ? ` | MASALAH: ${s.problems.join("; ")}` : ""}`);
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
        for (const r of s.requests) {
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

/** Ringkasan --dry: jumlah, gate tiap versi, body lama = baru, payload bersih. */
function dryChecks(out, full) {
    const S = out.samples;
    const n = (f) => S.filter(f).length;
    const lines = [];
    lines.push(`\n=== RINGKASAN --dry ${full ? "(75 link)" : `(${S.length} link)`} ===`);
    lines.push(`sampel: ${n((s) => s.kind === "scam")} scam + ${n((s) => s.kind === "legit")} legit; sumber ${JSON.stringify(out.meta.counts)}`);
    lines.push(`gate lama  : bertanya ${n((s) => s.old.asked)}, gated ${n((s) => !s.old.asked)}; sesuai rumus: ${n((s) => s.old.asked === s.gates.oldExpected)} / ${S.length}`);
    lines.push(`gate baru  : bertanya ${n((s) => s.new.asked)}, gated ${n((s) => !s.new.asked)}; sesuai rumus: ${n((s) => s.new.asked === s.gates.newExpected)} / ${S.length}`);
    lines.push(`bertanya   : keduanya ${n((s) => s.old.asked && s.new.asked)}, hanya lama ${n((s) => s.old.asked && !s.new.asked)}, hanya baru ${n((s) => !s.old.asked && s.new.asked)}, tidak ${n((s) => !s.old.asked && !s.new.asked)}`);
    lines.push(`opsi C     : diuji ${n((s) => s.c)}; dilewati: ${[...new Set(S.filter((s) => !s.c).map((s) => s.cSkip))].map((r) => `${r} ${n((s) => !s.c && s.cSkip === r)}`).join(", ")}`);
    lines.push(`permintaan LLM asli (tiruan): ${sum(S.map((s) => s.requests.length))}; link yang keduanya bertanya: ${n((s) => s.old.asked && s.new.asked)}, body lama = baru di ${n((s) => s.old.asked && s.new.asked && !s.problems.some((p) => p.includes("body")))}`);
    lines.push(`RDAP live  : berhasil ${n((s) => s.rdap.status === "berhasil")}, gagal ${n((s) => s.rdap.status === "gagal")}, timeout ${n((s) => s.rdap.status === "timeout")}, dilewati ${n((s) => s.rdap.status.startsWith("dilewati"))}`);
    lines.push(`new_domain menyala di ${n((s) => s.l3.signals.some((x) => x.id === "new_domain"))} link`);
    lines.push(`pelanggaran payload / masalah lain: ${S.flatMap((s) => s.problems.map((p) => `${s.id}: ${p}`)).join(" | ") || "tidak ada"}`);
    console.log(lines.join("\n"));
}

// ---- laporan -------------------------------------------------------------------
const maskHost = (h) => h.replace(/\./g, "[.]");
function masker(s) {
    const hosts = [...new Set([s.host, s.host.replace(/^www\./, ""), registrableDomain(s.host)].filter(Boolean))].sort((a, b) => b.length - a.length);
    return (text) => hosts.reduce((t, h) => t.split(h).join(maskHost(h)), String(text));
}
const cell = (x) => String(x).replace(/\|/g, "\\|").replace(/\n/g, " ");
const fmtMs = (x) => (x == null ? "-" : Math.round(x).toString());
const ver = (v) => (v ? `${v.total} ${LEVELS[v.level]}${v.flagged ? ` (flag +${v.l4.weight})` : ""}` : "-");
const sigText = (signals) => (signals.length ? signals.map((s) => `${s.id}:${s.weight}`).join(", ") : "-");
const l2Text = (signals) => (signals.length ? signals.map((s) => `${s.id}:${s.weight}${s.id === "suspicious_link" && s.evidence ? ` [${s.evidence}]` : ""}`).join(", ") : "-");
const askedBy = (s) => (s.old.asked && s.new.asked ? "keduanya" : s.old.asked ? "lama" : s.new.asked ? "baru" : "-");
const mainReq = (s) => s.requests.find((r) => r.tags.includes("old") || r.tags.includes("new")) ?? null;
const cReq = (s) => s.requests.find((r) => r.tags.includes("C")) ?? null;
const ansText = (r) => (r ? (r.verdict ? `${r.verdict.pageType}; ${r.verdict.asks.join("+") || "[]"}; ${r.verdict.reasonable}; ${r.verdict.confidence}` : `(${r.outcome})`) : "-");

/** Sebab beda Lama -> A. Satu dari daftar di PLAN.md. */
function cause(s) {
    const o = s.old;
    const n = s.new;
    if (o.level === n.level) return "-";
    if (o.asked && !n.asked) return s.gates.total13 >= 80 ? "gate baru: total >= 80, LLM dilewati" : s.gates.total13 < 30 ? "gate baru: total < 30, LLM dilewati" : `tidak diketahui (baru: ${n.outcome})`;
    if (!o.asked && n.asked) return !s.hasForm ? "gate baru: tanpa form" : s.gates.ruleScore < 15 ? "gate baru: skor aturan < 15" : "tidak diketahui (gate lama)";
    if (o.asked && n.asked) {
        if (o.flagged && !n.flagged) return "confidence 0,6-0,7";
        if (o.flagged && n.flagged) return "bobot flag";
    }
    return "tidak diketahui";
}

async function report() {
    const d = JSON.parse(await readFile(join(outDir, "full.json"), "utf8"));
    P = await loadScript(pipelineFile, "ShooPipeline");
    const S = d.samples;
    const scam = S.filter((s) => s.kind === "scam");
    const legit = S.filter((s) => s.kind === "legit");
    const lines = [];
    const p = (x = "") => lines.push(x);
    const reqs = S.flatMap((s) => s.requests.map((r) => ({ ...r, id: s.id, hasForm: s.hasForm, s })));
    const ms = reqs.filter((r) => r.ms != null).map((r) => r.ms);
    const outcomeN = (o) => reqs.filter((r) => r.outcome === o).length;
    const tokTotal = sum(reqs.map((r) => r.usage.total));
    const tokIn = sum(reqs.map((r) => r.usage.prompt));
    const tokOut = sum(reqs.map((r) => r.usage.completion));
    const tilde = reqs.some((r) => r.usage.estimated) ? "~" : "";
    const noForm = reqs.filter((r) => !r.hasForm);
    const diffs = S.filter((s) => s.old.level !== s.new.level);
    const up = (s) => s.new.level > s.old.level;
    const diffC = S.filter((s) => s.c && s.c.level !== s.new.level);
    const inKind = (list, f) => list.filter(f).length;
    const finalC = (s) => s.c ?? s.new; // C untuk link yang diuji, selain itu sama dengan A
    const isC = (r) => r.tags.includes("C");

    p("<!-- AUTO:START -->");
    p(`_Dibuat oleh \`run.mjs --report\` dari \`.hasil/full.json\` pada ${new Date().toISOString()}. Jangan edit di dalam blok ini; bagian "Analisis" di bawah blok ini aman._`);
    p("");
    p("# Hasil tes perbandingan arsitektur Layer 1-4 (Lama, Baru, Baru + umur)");
    p("");
    p(`- Model \`${d.meta.model}\` di \`${d.meta.host}\`, prompt \`${d.meta.promptVersion}\`, thinking off, temperature ${d.meta.temperature}, max_tokens ${d.meta.maxTokens}. Opsi C: prompt v5 hanya di skrip.`);
    p(`- Kode baru: commit \`${d.meta.commit}\` (\`${NEW_COMMIT}\` ada di riwayat); kode lama: \`${d.meta.oldCommit}\`. Belum di-commit di \`ai/src\`/\`ai/prompts\`: ${d.meta.uncommitted.map((l) => `\`${l.trim()}\``).join(", ") || "tidak ada"}. Node ${d.meta.node}. detector.js versi ${d.meta.detectorVersion ?? "?"}, L1 mati.`);
    p(`- Mulai ${d.meta.startedAt}, selesai ${d.meta.finishedAt ?? "BELUM SELESAI"}.${d.meta.stoppedEarly ? ` **Berhenti dini: ${d.meta.stoppedEarly}.**` : ""} Tanggal data: ${d.meta.startedAt.slice(0, 10)}.`);
    p(`- ${S.length} link (${scam.length} scam + ${legit.length} legit), satu per satu, tiap link satu kali ke LLM (Lama dan Baru berbagi jawaban). Batas LLM ${d.meta.llmTimeoutMs / 1000} dtk, RDAP live ${d.meta.rdapTimeoutMs / 1000} dtk. Domain disamarkan.`);
    p('- Tingkat: normal 0-29, warning 1 30-49, warning 2 50-79, blokir 80+. "Beda" = tingkat beda; angka beda dengan tingkat sama dicatat terpisah.');
    p(`- Token dibaca dari \`usage\` respons provider${reqs.some((r) => r.usage.estimated) ? "; permintaan tanpa respons diganti perkiraan karakter ÷ 4 dan ditandai ~" : ""}.`);
    p("");

    p("## Ringkasan");
    p("");
    p("### Link yang beda, Lama lawan A");
    p("");
    p("| ukuran | scam | legit |");
    p("|---|---|---|");
    p(`| Link beda tingkat | ${inKind(scam, (s) => diffs.includes(s))} / ${scam.length} | ${inKind(legit, (s) => diffs.includes(s))} / ${legit.length} |`);
    p(`| Naik | ${inKind(scam, (s) => diffs.includes(s) && up(s))} | ${inKind(legit, (s) => diffs.includes(s) && up(s))} |`);
    p(`| Turun | ${inKind(scam, (s) => diffs.includes(s) && !up(s))} | ${inKind(legit, (s) => diffs.includes(s) && !up(s))} |`);
    p(`| Tingkat sama, angka beda | ${inKind(scam, (s) => s.old.level === s.new.level && s.old.total !== s.new.total)} | ${inKind(legit, (s) => s.old.level === s.new.level && s.old.total !== s.new.total)} |`);
    p(`| Beda tingkat, A lawan C (hanya link yang diuji) | ${inKind(scam, (s) => diffC.includes(s))} | ${inKind(legit, (s) => diffC.includes(s))} |`);
    p("");
    p("### Jumlah link per tingkat");
    p("");
    p("| jenis | versi | normal | warning 1 | warning 2 | blokir |");
    p("|---|---|--:|--:|--:|--:|");
    for (const [name, list] of [["scam", scam], ["legit", legit]]) {
        for (const [vn, f] of [["Lama", (s) => s.old], ["A", (s) => s.new], ["C (A untuk yang tidak diuji)", finalC]]) {
            p(`| ${name} | ${vn} | ${[0, 1, 2, 3].map((l) => inKind(list, (s) => f(s).level === l)).join(" | ")} |`);
        }
    }
    p("");
    p("### Legit yang kena flag dan blokir");
    p("");
    p("| versi | kena flag LLM | diblokir (skor >= 80) |");
    p("|---|---|---|");
    for (const [vn, f] of [["Lama", (s) => s.old], ["A", (s) => s.new], ["C (A untuk yang tidak diuji)", finalC]]) {
        const fl = legit.filter((s) => f(s).flagged);
        const bl = legit.filter((s) => f(s).level === 3);
        p(`| ${vn} | ${fl.length} / ${legit.length}${fl.length ? ` (${fl.map((s) => s.id).join(", ")})` : ""} | ${bl.length} / ${legit.length}${bl.length ? ` (${bl.map((s) => s.id).join(", ")})` : ""} |`);
    }
    p("");
    p("### Panggilan LLM");
    p("");
    p("| ukuran | semua | scam | legit |");
    p("|---|--:|--:|--:|");
    const askRow = (label, f) => p(`| ${label} | ${inKind(S, f)} | ${inKind(scam, f)} | ${inKind(legit, f)} |`);
    askRow("Hanya lama bertanya", (s) => s.old.asked && !s.new.asked);
    askRow("Hanya baru bertanya", (s) => !s.old.asked && s.new.asked);
    askRow("Keduanya bertanya", (s) => s.old.asked && s.new.asked);
    askRow("Tidak ada yang bertanya", (s) => !s.old.asked && !s.new.asked);
    askRow("Lama bertanya, halaman tanpa form", (s) => s.old.asked && !s.hasForm);
    askRow("Baru bertanya, halaman tanpa form", (s) => s.new.asked && !s.hasForm);
    const reqCount = (list, f) => list.flatMap((s) => s.requests).filter(f).length;
    p(`| Permintaan LLM asli (Lama + Baru berbagi) | ${reqCount(S, (r) => !isC(r))} | ${reqCount(scam, (r) => !isC(r))} | ${reqCount(legit, (r) => !isC(r))} |`);
    p(`| Permintaan C (prompt v5) | ${reqCount(S, isC)} | ${reqCount(scam, isC)} | ${reqCount(legit, isC)} |`);
    p("");
    p("### Opsi C (prompt v5, `site_age`)");
    p("");
    const cTested = S.filter((s) => s.c);
    const extra = cTested.filter((s) => s.c.flagged && !s.new.flagged);
    const lost = cTested.filter((s) => !s.c.flagged && s.new.flagged);
    const flagN = (list, f) => list.filter((s) => f(s).flagged).length;
    p("| ukuran | hasil |");
    p("|---|---|");
    p(`| Link diuji (new_domain menyala dan lolos gate baru) | ${cTested.length} (scam ${cTested.filter((s) => s.kind === "scam").length}, legit ${cTested.filter((s) => s.kind === "legit").length}) |`);
    p(`| Flag tambahan di C | ${extra.length}${extra.length ? `: ${extra.map((s) => `${s.id} (${s.kind})`).join(", ")}` : ""} |`);
    p(`| Flag yang hilang di C | ${lost.length}${lost.length ? `: ${lost.map((s) => `${s.id} (${s.kind})`).join(", ")}` : ""} |`);
    p(`| Legit kena flag, A lawan C | ${flagN(legit, (s) => s.new)} lawan ${flagN(legit, finalC)} |`);
    p(`| Scam kena flag, A lawan C | ${flagN(scam, (s) => s.new)} lawan ${flagN(scam, finalC)} |`);
    const cOk = flagN(scam, finalC) > flagN(scam, (s) => s.new) && flagN(legit, finalC) <= flagN(legit, (s) => s.new);
    p(`| Syarat C (scam kena flag bertambah, legit kena flag tidak bertambah dibanding A) | ${cOk ? "**terpenuhi**" : "tidak terpenuhi"}; keputusan akhir di Imelda |`);
    p("");
    p("### Waktu, token, RDAP, gagal");
    p("");
    p("| ukuran | hasil |");
    p("|---|---|");
    p(`| Waktu LLM (ms), semua permintaan asli | median ${fmtMs(ms.length ? median(ms) : null)}, p95 ${fmtMs(ms.length ? pctl(ms, 95) : null)}, maks ${fmtMs(ms.length ? Math.max(...ms) : null)} (${ms.length} permintaan) |`);
    p(`| Permintaan > ${SLOW_A / 1000} dtk / > ${SLOW_B / 1000} dtk | ${ms.filter((x) => x > SLOW_A).length} / ${ms.filter((x) => x > SLOW_B).length} |`);
    p(`| Timeout ${d.meta.llmTimeoutMs / 1000} dtk | ${outcomeN("timeout")} |`);
    p(`| Token total | ${tilde}${tokTotal} (rata-rata ${tilde}${reqs.length ? Math.round(tokTotal / reqs.length) : 0} per permintaan; input ${tilde}${tokIn}, output ${tilde}${tokOut}) |`);
    p(`| Token, halaman tanpa form | ${tilde}${sum(noForm.map((r) => r.usage.total))} dalam ${noForm.length} permintaan |`);
    const rd = (st) => S.filter((s) => s.rdap.status === st);
    p(`| RDAP live | berhasil ${rd("berhasil").length}, gagal ${rd("gagal").length}, timeout ${rd("timeout").length}, dilewati ${S.filter((s) => s.rdap.status.startsWith("dilewati")).length} |`);
    const lostND = S.filter((s) => s.age28 != null && buildNewDomainSignal(s.age28) && !buildNewDomainSignal(s.rdap.age ?? 99999));
    p(`| Link kehilangan \`new_domain\` dibanding umur 28 Okt | ${lostND.length}${lostND.length ? `: ${lostND.map((s) => `${s.id} (28 Okt ${s.age28} hari, sekarang ${s.rdap.age ?? s.rdap.status})`).join(", ")}` : ""} |`);
    p(`| Gagal | bad_schema ${outcomeN("bad_schema")}, http_error ${outcomeN("http_error")}, timeout ${outcomeN("timeout")} |`);
    p("");

    p("## Batas lulus");
    p("");
    p("Ditetapkan di PLAN.md sebelum mengukur. Scam hanya dilaporkan.");
    p("");
    p("| ukuran | batas | hasil | lulus |");
    p("|---|---|---|:-:|");
    const legitBlockedA = legit.filter((s) => s.new.level === 3);
    const legitUp = legit.filter(up);
    p(`| Legit diblokir di A | 0 / ${legit.length} | ${legitBlockedA.length} / ${legit.length}${legitBlockedA.length ? ` (${legitBlockedA.map((s) => s.id).join(", ")})` : ""} | ${legitBlockedA.length === 0 ? "lulus" : "**gagal**"} |`);
    p(`| Legit yang tingkatnya naik dari Lama ke A | 0 | ${legitUp.length}${legitUp.length ? ` (${legitUp.map((s) => `${s.id}: ${LEVELS[s.old.level]} → ${LEVELS[s.new.level]}`).join(", ")})` : ""} | ${legitUp.length === 0 ? "lulus" : "**gagal**"} |`);
    p(`| \`bad_schema\` | dilaporkan | ${outcomeN("bad_schema")} | - |`);
    p(`| Timeout ${d.meta.llmTimeoutMs / 1000} dtk | dilaporkan | ${outcomeN("timeout")} | - |`);
    p("");
    p(`Scam: Lama ${flagN(scam, (s) => s.old)} kena flag, A ${flagN(scam, (s) => s.new)}; diblokir Lama ${inKind(scam, (s) => s.old.level === 3)} / ${scam.length}, A ${inKind(scam, (s) => s.new.level === 3)} / ${scam.length}.`);
    p("");

    const slow = reqs.filter((r) => r.ms > SLOW_A);
    p("## Waktu: permintaan > 5,5 dtk");
    p("");
    p("Sisa waktu produksi sekarang ±5,5 dtk kalau RDAP dingin. Kolom terakhir = tingkat A kalau LLM timeout (tanpa sinyal Layer 4).");
    p("");
    if (!slow.length) p("Tidak ada.");
    else {
        p("| id | domain | untuk | ms | hasil | tingkat A sekarang | tingkat A kalau LLM timeout |");
        p("|---|---|---|--:|---|---|---|");
        for (const r of slow) p(`| ${r.id} | \`${maskHost(r.s.host)}\` | ${r.tags.join("+")} | ${r.ms} | ${r.outcome} | ${ver(r.s.new)} | ${r.s.new.scoreNoL4} ${LEVELS[r.s.new.levelNoL4]} |`);
    }
    p("");

    const head = ["id", "domain", "jenis", "L2", "L3", "umur live", "umur 28 Okt", "form", "Lama", "A", "C", "bertanya", "jawaban LLM (`page_type`; asks; reasonable; confidence)", "ms", "sebab beda"];
    const header = `| ${head.join(" | ")} |\n|${head.map(() => "---").join("|")}|`;
    const row = (s) => {
        const r = mainReq(s);
        const c = cReq(s);
        const ans = `${ansText(r)}${c ? ` / C: ${ansText(c)}` : ""}`;
        const msText = r || c ? `${r ? fmtMs(r.ms) : "-"}${c ? ` / C ${fmtMs(c.ms)}` : ""}` : "-";
        const cDiff = s.c && s.c.level !== s.new.level ? "C: jawaban LLM berubah dengan site_age" : "";
        const causeText = [cause(s) === "-" ? "" : cause(s), cDiff].filter(Boolean).join("; ") || "-";
        return `| ${[
            s.id,
            `\`${maskHost(s.host)}\``,
            s.kind,
            s.l2.score,
            `${s.l3.score}${s.l3.signals.length ? ` (${sigText(s.l3.signals)})` : ""}`,
            s.rdap.age ?? s.rdap.status,
            s.age28 ?? "-",
            s.hasForm ? "ya" : "tidak",
            ver(s.old),
            ver(s.new),
            ver(s.c),
            askedBy(s),
            ans,
            msText,
            causeText,
        ]
            .map(cell)
            .join(" | ")} |`;
    };
    const beda = S.filter((s) => s.old.level !== s.new.level || (s.c && s.c.level !== s.new.level));
    p("## Link yang beda (Lama lawan A, atau A lawan C)");
    p("");
    if (!beda.length) p("Tidak ada.");
    else {
        p(header);
        for (const s of beda) p(row(s));
    }
    p("");
    p("## Semua link");
    p("");
    p(`### Scam (${scam.length})`);
    p("");
    p(header);
    for (const s of scam) p(row(s));
    p("");
    p(`### Legit (${legit.length})`);
    p("");
    p(header);
    for (const s of legit) p(row(s));
    p("");

    p("## Detail per link");
    p("");
    p("JSON = isi `user message` persis yang dikirim (antara `DATA_START` dan `DATA_END`), domain disamarkan. System message ada di akhir.");
    p("");
    for (const s of S) {
        const m = masker(s);
        p(`### ${s.id} hxxps://${maskHost(s.host)} (${s.kind})`);
        p("");
        p(`- L2: ${l2Text(s.l2.signals)} (skor ${s.l2.score}); L3: ${sigText(s.l3.signals)} (skor ${s.l3.score}); form: ${s.hasForm ? "ya" : "tidak"}; situs resmi: ${s.official ? "ya" : "tidak"}`);
        p(`- RDAP live: ${s.rdap.status}${s.rdap.age != null ? `, ${s.rdap.age} hari` : ""}, ${s.rdap.ms} ms; umur 28 Okt: ${s.age28 ?? "-"}`);
        p(`- Lama: ${ver(s.old)}, ${s.old.asked ? `bertanya (${s.old.outcome})` : "gated"}; A: ${ver(s.new)}, ${s.new.asked ? `bertanya (${s.new.outcome})` : "gated"}${s.c ? `; C: ${ver(s.c)} (${s.c.outcome})` : `; C: tidak diuji (${s.cSkip})`}`);
        for (const r of s.requests) {
            p("");
            p(`Permintaan untuk ${r.tags.join("+")}: ${r.outcome}, ${r.ms} ms, status ${r.status}, finish ${r.finish ?? "?"}, token ${r.usage.estimated ? "~" : ""}${r.usage.prompt}/${r.usage.completion}/${r.usage.total}`);
            p("");
            p("```json");
            p(m(JSON.stringify(r.input, null, 2)));
            p("```");
            p("");
            p("Jawaban mentah:");
            p("");
            p("```json");
            p(m(r.raw ?? r.rawBody ?? "(kosong)"));
            p("```");
        }
        p("");
    }
    p("### System message v4 (Lama, A)");
    p("");
    p("```");
    p(d.meta.systemPrompt);
    p("```");
    p("");
    p("### System message v5 (C, hanya di skrip)");
    p("");
    p("```");
    p(d.meta.systemPromptV5);
    p("```");
    p("<!-- AUTO:END -->");

    const file = join(here, "HASIL.md");
    const old = await readFile(file, "utf8").catch(() => "");
    const i = old.indexOf("<!-- AUTO:END -->");
    const manual = i >= 0 ? old.slice(i + "<!-- AUTO:END -->".length) : "\n\n## Analisis\n\nBelum diisi.\n";
    await writeFile(file, lines.join("\n") + manual);
    console.log(`ok: ${file} (${S.length} link, ${reqs.length} permintaan LLM)`);
}

try {
    if (flag("--report")) await report();
    else await measure();
} catch (e) {
    log(`GAGAL: ${e.message}`);
    process.exitCode = 1;
}
