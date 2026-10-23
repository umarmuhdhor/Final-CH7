// Eval helpers (M2). Read-only use of other folders: detector/ (to run M1) and the extension's domain helper (so
// snapshot.domain is computed exactly like the real extension does it). Nothing here writes outside ai/eval/.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";
import vm from "node:vm";
import { build } from "../../detector/scripts/build.mjs";
import { PSL_RULES } from "../../ios/ShooExtension/Resources/psl.js";
import { parseRules, registrableDomain } from "../../ios/ShooExtension/Resources/domain.js";

export const THRESHOLDS = { warning: 30, secondWarning: 50, blocked: 80 }; // contracts/README.md, owned by the lead
export const TARGETS = { scamAtLeast50: 0.9, scamAtLeast80: 0.7, legitAtLeast30: 0 }; // docs/mandates/imelda.md
export const MIN_PER_CLASS = 50;

const rules = parseRules(PSL_RULES);

// ---------- samples ----------
export function domainOf(url) {
    return registrableDomain(new URL(url).hostname, rules);
}

/** @returns {string[]} problems; empty = valid */
export function validateSample(s) {
    const bad = [];
    if (!s || typeof s !== "object") return ["not an object"];
    if (typeof s.id !== "string" || !/^[a-z0-9][a-z0-9._-]*$/.test(s.id)) bad.push("id must be a lowercase slug");
    if (!["scam", "legit"].includes(s.label)) bad.push('label must be "scam" or "legit"');
    if (typeof s.source !== "string" || !s.source) bad.push("source is required (where the page came from)");
    const snap = s.snapshot;
    if (!snap || typeof snap !== "object") return [...bad, "snapshot is required"];
    try {
        new URL(snap.url);
    } catch {
        bad.push("snapshot.url must be a full URL");
    }
    if (snap.text !== undefined && (typeof snap.text !== "string" || snap.text.length > 20000)) bad.push("snapshot.text: string, max 20000 chars");
    if (snap.forms !== undefined && !Array.isArray(snap.forms)) bad.push("snapshot.forms must be an array");
    if (snap.imageAlts !== undefined && (!Array.isArray(snap.imageAlts) || snap.imageAlts.length > 50)) bad.push("snapshot.imageAlts: array, max 50");
    for (const f of (snap.forms || []).flatMap((x) => x.fields || [])) {
        if ("value" in f) bad.push("form fields must not carry values");
    }
    if (s.label === "scam" && s.synthetic !== true && s.redacted !== true) bad.push("real scam samples must set redacted: true after a manual check");
    return bad;
}

/** Fills the fields the extension would have set, so a URL-only sample is enough for layers 1-2. */
export function normalizeSnapshot(snap) {
    return {
        domain: domainOf(snap.url),
        title: "",
        lang: null,
        text: "",
        forms: [],
        imageAlts: [],
        capturedAt: new Date(0).toISOString(),
        ...snap,
    };
}

function* walk(dir) {
    for (const name of readdirSync(dir).sort()) {
        const p = join(dir, name);
        if (statSync(p).isDirectory()) yield* walk(p);
        else if (extname(name) === ".json" && name !== "HOLDOUT.json") yield p; // HOLDOUT.json is the split seed, not a sample
    }
}

/** A file holds one sample or an array of samples. @returns {{samples: object[], errors: string[]}} */
export function loadSamples(dir) {
    const samples = [];
    const errors = [];
    const seen = new Set();
    for (const file of walk(dir)) {
        let parsed;
        try {
            parsed = JSON.parse(readFileSync(file, "utf8"));
        } catch (e) {
            errors.push(`${file}: invalid JSON (${e.message})`);
            continue;
        }
        for (const s of Array.isArray(parsed) ? parsed : [parsed]) {
            const problems = validateSample(s);
            if (problems.length) errors.push(`${file} [${s?.id ?? "?"}]: ${problems.join("; ")}`);
            else if (seen.has(s.id)) errors.push(`${file} [${s.id}]: duplicate id`);
            else {
                seen.add(s.id);
                samples.push(s);
            }
        }
    }
    return { samples, errors };
}

// ---------- detector (M1) ----------
export function loadDetector() {
    const ctx = { URL };
    vm.createContext(ctx);
    vm.runInContext(build(), ctx); // the same single script the extension gets
    // the detector lives in another vm context: copy results so they are plain objects here
    return { analyzeLocal: async (snapshot) => JSON.parse(JSON.stringify(await ctx.ShooDetector.analyzeLocal(snapshot))) };
}

/** POST /analyze (M3). Never throws, like the extension after 8 s, but says whether the call worked:
 *  @returns {Promise<{signals: object[], ok: boolean}>} ok is false for a network error, HTTP error, bad body or any malformed signal. */
export async function analyzeRemote(baseUrl, snapshot, localSignals) {
    try {
        const res = await fetch(new URL("/analyze", baseUrl), {
            method: "POST",
            headers: { "Content-Type": "application/json", Authorization: "Bearer eval" },
            body: JSON.stringify({ snapshot, localSignals }),
            signal: AbortSignal.timeout(8000),
        });
        if (!res.ok) return { signals: [], ok: false };
        const body = await res.json();
        if (!Array.isArray(body.signals)) return { signals: [], ok: false };
        const wellFormed = (x) => x && typeof x.id === "string" && Number.isInteger(x.layer) && Number.isFinite(x.weight);
        const signals = body.signals.filter(wellFormed);
        return { signals, ok: signals.length === body.signals.length };
    } catch {
        return { signals: [], ok: false };
    }
}

// ---------- scoring (same rules as the extension: contracts/detector-interface.md) ----------
const onlyLayers = (signals, layers) => (Array.isArray(signals) ? signals : []).filter((s) => layers.includes(s.layer));

export function scoreOf(signals) {
    if (signals.some((s) => s.id === "db_match")) return 100;
    return Math.min(100, signals.reduce((sum, s) => sum + s.weight, 0));
}

export function statusOf(score) {
    if (score >= THRESHOLDS.blocked) return "blocked";
    if (score >= THRESHOLDS.secondWarning) return "warning 2";
    if (score >= THRESHOLDS.warning) return "warning 1";
    return "normal";
}

/** Runs one sample through the layers that are available. @returns result row */
export async function evaluate(sample, { detector, analyzeUrl = null }) {
    const snapshot = normalizeSnapshot(sample.snapshot);
    const t0 = performance.now();
    const local = onlyLayers(await detector.analyzeLocal(snapshot), [1, 2]);
    const localMs = performance.now() - t0;
    let remote = [];
    let remoteMs = null;
    let remoteOk = null;
    if (analyzeUrl) {
        const t1 = performance.now();
        const r = await analyzeRemote(analyzeUrl, snapshot, local);
        remote = onlyLayers(r.signals, [3, 4]);
        remoteOk = r.ok;
        remoteMs = performance.now() - t1;
    }
    const signals = [...local, ...remote];
    const localScore = scoreOf(local);
    const score = scoreOf(signals);
    return { id: sample.id, label: sample.label, tags: sample.tags || [], synthetic: !!sample.synthetic, localScore, score, status: statusOf(score), signals, localMs, remoteMs, remoteOk };
}

// ---------- metrics ----------
const rate = (n, d) => (d ? n / d : null);

export function summarize(rows, { remote = false } = {}) {
    const scam = rows.filter((r) => r.label === "scam");
    const legit = rows.filter((r) => r.label === "legit");
    const count = (list, min) => list.filter((r) => r.score >= min).length;
    const level = (signal) => Number((/level (\d)/.exec(signal.evidence || "") || [])[1] || 0);

    const falsePositives = legit.filter((r) => r.score >= THRESHOLDS.warning);
    const misses = scam.filter((r) => r.score < THRESHOLDS.secondWarning);

    const byLevel = {};
    for (const r of falsePositives) for (const s of r.signals) byLevel[`level ${level(s)} ${s.id}`] = (byLevel[`level ${level(s)} ${s.id}`] || 0) + 1;

    const ms = rows.map((r) => r.localMs).sort((a, b) => a - b);
    const remoteMs = rows.map((r) => r.remoteMs).filter(Number.isFinite).sort((a, b) => a - b);
    const enough = scam.length >= MIN_PER_CLASS && legit.length >= MIN_PER_CLASS;
    const checksOf = (sc, lg) => ({
        scamAtLeast50: { value: rate(count(sc, 50), sc.length), target: TARGETS.scamAtLeast50 },
        scamAtLeast80: { value: rate(count(sc, 80), sc.length), target: TARGETS.scamAtLeast80 },
        legitAtLeast30: { value: lg.length ? count(lg, 30) : null, target: TARGETS.legitAtLeast30 },
    });
    const metOf = (c) => c.scamAtLeast50.value >= c.scamAtLeast50.target && c.scamAtLeast80.value >= c.scamAtLeast80.target && c.legitAtLeast30.value <= c.legitAtLeast30.target;
    // A claim about the mandate targets may only rest on real pages (R2 §4): synthetic ones are written by us.
    const realScam = scam.filter((r) => !r.synthetic);
    const realLegit = legit.filter((r) => !r.synthetic);
    const realEnough = realScam.length >= MIN_PER_CLASS && realLegit.length >= MIN_PER_CLASS;
    const checksAll = checksOf(scam, legit);
    const checks = checksOf(realScam, realLegit);
    const remoteFailures = rows.filter((r) => r.remoteOk === false).length; // /analyze failed for this page: its layer 3-4 result is missing

    const tally = (list) => ({
        scam: { n: list.filter((r) => r.label === "scam").length, atLeast50: count(list.filter((r) => r.label === "scam"), 50), atLeast80: count(list.filter((r) => r.label === "scam"), 80) },
        legit: { n: list.filter((r) => r.label === "legit").length, atLeast30: count(list.filter((r) => r.label === "legit"), 30) },
    });
    const tags = [...new Set(rows.flatMap((r) => r.tags || []))].filter((t) => t !== "holdout").sort();
    const byTag = Object.fromEntries(tags.map((t) => [t, tally(rows.filter((r) => (r.tags || []).includes(t)))]));
    const isHoldout = (r) => (r.tags || []).includes("holdout");

    return {
        byTag,
        bySplit: { holdout: tally(rows.filter(isHoldout)), tuning: tally(rows.filter((r) => !isHoldout(r))) },
        real: tally(rows.filter((r) => !r.synthetic)),
        synthetic: tally(rows.filter((r) => r.synthetic)),
        mode: remote ? "layers 1-4" : "layers 1-2 only",
        counts: { scam: scam.length, legit: legit.length },
        enough,
        realEnough,
        remoteFailures,
        scam: { atLeast30: count(scam, 30), atLeast50: count(scam, 50), atLeast80: count(scam, 80) },
        legit: { atLeast30: count(legit, 30), atLeast50: count(legit, 50), atLeast80: count(legit, 80) },
        checks, // real samples only
        checksAll, // every sample, synthetic included: for information, not for claims
        targetsMet: realEnough && remote && remoteFailures === 0 ? metOf(checks) : null, // needs real layer 3-4 results for every page and 50+ real per class
        falsePositives: falsePositives.map((r) => r.id),
        misses: misses.map((r) => r.id),
        falsePositiveSignals: byLevel,
        timing: { analyzeLocalAvgMs: ms.length ? ms.reduce((a, b) => a + b, 0) / ms.length : null, analyzeLocalMaxMs: ms.at(-1) ?? null, analyzeRemoteP95Ms: remoteMs.length ? remoteMs[Math.ceil(remoteMs.length * 0.95) - 1] : null },
    };
}

/** Run once before a --analyze-url eval: analyzeRemote swallows errors by design, so an unreachable service would otherwise look like "layers 1-4" with empty layer 3-4. */
export async function probeAnalyze(baseUrl) {
    const snapshot = { url: "https://probe.invalid/", domain: "probe.invalid", title: "", lang: null, text: "", forms: [], imageAlts: [], capturedAt: new Date(0).toISOString() };
    try {
        const res = await fetch(new URL("/analyze", baseUrl), {
            method: "POST",
            headers: { "Content-Type": "application/json", Authorization: "Bearer eval" },
            body: JSON.stringify({ snapshot, localSignals: [] }),
            signal: AbortSignal.timeout(5000),
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const body = await res.json();
        if (!Array.isArray(body.signals)) throw new Error("response has no signals array");
    } catch (e) {
        throw new Error(`/analyze at ${baseUrl} is not usable (${e.message}); refusing to report layers 3-4 numbers`);
    }
}

/**
 * Layer 4 outcome counters from the local dev server (GET /_dev/layer4). null when the server has no such route
 * (a deployed Worker) or layer 4 is off. Counters are cumulative per server process: diff a before/after pair.
 */
export async function layer4Stats(baseUrl) {
    try {
        const res = await fetch(new URL("/_dev/layer4", baseUrl), { signal: AbortSignal.timeout(5000) });
        if (!res.ok) return null;
        const body = await res.json();
        return body && typeof body.outcomes === "object" ? body : null;
    } catch {
        return null;
    }
}

/** after - before, per outcome. `before` may be null (counters started at zero). */
export function layer4Delta(before, after) {
    if (!after) return null;
    const outcomes = {};
    for (const [k, v] of Object.entries(after.outcomes)) outcomes[k] = v - (before?.outcomes?.[k] ?? 0);
    return { promptVersion: after.promptVersion, model: after.model, outcomes };
}

/** --strict: only a run that really judged the targets and met them passes; "nothing was judged" is not a pass. */
export function strictExitCode(summary) {
    return summary.targetsMet === true ? 0 : summary.targetsMet === false ? 1 : 2;
}

/** The holdout is looked at once, at the end of phase 07: rows tagged holdout stay out of per-sample output unless asked for. */
export function visibleRows(rows, { showHoldout = false } = {}) {
    return showHoldout ? rows : rows.filter((r) => !(r.tags || []).includes("holdout"));
}

/** What `--json` prints: the same holdout hiding as the table, for the rows and for the id lists in the summary. */
export function jsonReport(rows, summary, { showHoldout = false } = {}) {
    const shown = visibleRows(rows, { showHoldout });
    const ids = new Set(shown.map((r) => r.id));
    const keep = (list) => list.filter((id) => ids.has(id));
    return {
        summary: { ...summary, falsePositives: keep(summary.falsePositives), misses: keep(summary.misses), holdoutRowsHidden: rows.length - shown.length },
        rows: shown,
    };
}
