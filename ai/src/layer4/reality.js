// Layer 4: "is the data this page asks for reasonable for this kind of page?" (M4).
// - Only a small summary leaves the server: host, title (<= 120 chars), field labels (<= 12), brand names (<= 3, from
//   brands.json, D-imelda-42), ids of rules that fired and layer 2 reason codes (our codes only, from the client's
//   `suspicious_link`). No page text, no URL path or query, no typed values (SECURITY A1, A4).
// - Page words go into the user message as JSON data; the system prompt is a fixed string.
// - The answer must match schema.js, else it is ignored. Layer 4 can only ADD a signal (D-imelda-06).
// - Any failure, timeout or cap -> no signal; layer 3 already answered.
import { SYSTEM_PROMPT, PROMPT_VERSION, LINK_TEXT } from "../../prompts/reality-check.js";
import { hostOf } from "../layer3/official.js";
import { IGNORED_TYPES } from "../layer3/forms.js";
import { buildIndex, findPhrase, evidenceOf } from "../layer3/match.js";
import { detectBrands } from "../layer3/content.js";
import { fold } from "../layer3/text.js";
import { registrableDomain } from "../rdap/domain.js";
import { createRateLimiter } from "../ratelimit.js";
import { createProvider } from "./provider.js";
import { parseVerdict } from "./schema.js";

export const WEIGHT = 30; // plan/imelda/ref/R1: starting proposal, tuned in phase 07
export const MIN_CONFIDENCE = 0.6;
export const GATE_MIN_SCORE = 15; // D-imelda-05 (in force)
export const CLIENT_CALLS_PER_HOUR = 20; // per IP; /analyze itself gets its limit in phase 08
/** How each check ended. Counts only: no page data (SECURITY A1). */
export const OUTCOMES = Object.freeze(["gated", "capped", "timeout", "http_error", "bad_schema", "reasonable", "flagged"]);
const MAX_FIELDS = 12;
const MAX_LABEL = 60;
const MAX_TITLE = 120;
const MAX_LINK_CHECKS = 12;

/** Control chars out, emails and digit runs of 4+ masked (a title may carry a name or an order number), then cut. */
const clean = (s, max) =>
    String(s ?? "")
        .replace(/[\u0000-\u001f\u007f]/g, " ")
        .replace(/\S+@\S+/g, "[email]")
        .replace(/\d[\d .-]{2,}\d/g, "[number]")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, max);

/**
 * Gate (D-imelda-05): not an official site, a form with at least one field, rule score >= 15.
 * `score` is OUR rules' score only: numbers sent by the client must not decide who costs money.
 */
export function passesGate(snapshot, { official, score }) {
    if (official) return false;
    if (!snapshot.forms.some((f) => f.fields.length > 0)) return false;
    return score >= GATE_MIN_SCORE;
}

/**
 * Reason codes from the client's layer 2 `suspicious_link` (its evidence is "code,code,..."). Untrusted: only codes the
 * prompt has a legend for survive, so nothing from the client but our own words reaches the model.
 */
function linkChecks(localSignals) {
    if (!Array.isArray(localSignals)) return [];
    const codes = new Set();
    for (const s of localSignals.slice(0, 30)) {
        if (!s || typeof s !== "object" || s.id !== "suspicious_link" || s.layer !== 2 || typeof s.evidence !== "string") continue;
        for (const code of s.evidence.slice(0, 500).split(",")) {
            const c = code.trim();
            if (Object.hasOwn(LINK_TEXT, c)) codes.add(c);
        }
    }
    return [...codes].slice(0, MAX_LINK_CHECKS);
}

/** What the model sees. Exported for tests. */
export function buildInput(snapshot, ruleIds, localSignals = []) {
    const fields = [];
    for (const form of snapshot.forms) {
        for (const f of form.fields) {
            if (fields.length >= MAX_FIELDS) break;
            const type = clean(f.type, 20).toLowerCase() || "text";
            if (IGNORED_TYPES.has(type)) continue; // hidden values and buttons ask nothing and would eat the 12 slots
            const label = clean(f.label || f.placeholder || f.name || f.id, MAX_LABEL);
            fields.push({ type, label });
        }
    }
    // site is null for IPs, intranet names and junk. brands: names from brands.json (our wording), at most 3, [] when none (D-imelda-42)
    return {
        site: registrableDomain(hostOf(snapshot.url)),
        title: clean(snapshot.title, MAX_TITLE),
        fields,
        brands: detectBrands(snapshot),
        rules: ruleIds.slice(0, 20),
        link_checks: linkChecks(localSignals),
    };
}

const MASKED = /\[(?:number|email)\]/;

/**
 * The model copies a phrase from the cleaned title it saw. It is kept only when it is in the title (what the model saw)
 * AND in the page text (the extension highlights text under <body>, never <title>). Matching is folded and
 * space-collapsed like the layer 3 phrases; a masked run ([number], [email]) splits the phrase and the longest
 * remaining piece is used. The evidence returned is the exact slice of `snapshot.text`.
 */
function evidenceFrom(candidate, snapshot) {
    if (typeof candidate !== "string" || candidate.length > 120) return undefined;
    const pieces = candidate.split(MASKED).map((p) => fold(p).toLowerCase().replace(/\s+/g, " ").trim());
    const needle = pieces.reduce((a, b) => (b.length > a.length ? b : a), "");
    if (needle.length < 8) return undefined;
    if (!findPhrase(buildIndex(snapshot.title), needle)) return undefined;
    const text = buildIndex(snapshot.text);
    const hit = findPhrase(text, needle);
    return hit ? evidenceOf(text, hit) : undefined;
}

function buildSignal(evidence) {
    return {
        id: "unreasonable_request",
        layer: 4,
        weight: WEIGHT,
        label: { en: "The data requested does not fit this kind of page", id: "Data yang diminta tidak wajar untuk jenis halaman ini" },
        labelSimple: { en: "A real page of this kind would not ask for this", id: "Halaman asli seperti ini tidak akan meminta ini" },
        ...(evidence ? { evidence } : {}),
    };
}

/**
 * @param {{ config: object, fetch: typeof fetch, now?: () => number, clientCallsPerHour?: number }} deps
 *   clientCallsPerHour: per-IP limit on LLM calls. `Infinity` turns it off (local eval: every request comes from one
 *   "unknown" client); the daily cap stays the breaker.
 * @returns {{ meta: object, stats(): object, check(snapshot: object, ctx: { official: boolean, score: number, ruleIds: string[], deadlineMs?: number }): Promise<object | null> }}
 */
export function createRealityCheck({ config, fetch, now = Date.now, clientCallsPerHour = CLIENT_CALLS_PER_HOUR }) {
    const ask = createProvider({ config, fetch });
    const perClient = Number.isFinite(clientCallsPerHour) ? createRateLimiter({ limit: clientCallsPerHour, windowMs: 60 * 60 * 1000, now }) : () => ({ ok: true });
    const outcomes = Object.fromEntries(OUTCOMES.map((k) => [k, 0]));
    const end = (outcome, result = null) => {
        outcomes[outcome] += 1;
        return result;
    };
    let day = "";
    let used = 0;

    function withinCap() {
        const today = new Date(now()).toISOString().slice(0, 10);
        if (today !== day) {
            day = today;
            used = 0;
        }
        if (used >= config.dailyCap) return false;
        used += 1;
        return true;
    }

    return {
        meta: { promptVersion: PROMPT_VERSION, model: config.model }, // record both with every eval run (SECURITY A13)
        /** Outcome counters since this checker was built (one Worker isolate). A wrong model or key shows up as http_error / bad_schema, not as "always reasonable". */
        stats: () => ({ promptVersion: PROMPT_VERSION, model: config.model, outcomes: { ...outcomes } }),
        async check(snapshot, { official, score, ruleIds, localSignals = [], client = "unknown", deadlineMs = config.timeoutMs }) {
            if (!passesGate(snapshot, { official, score })) return end("gated");
            const input = buildInput(snapshot, ruleIds, localSignals);
            if (!input.site) return end("gated"); // not a public domain: nothing sensible to judge, nothing to send
            const budget = Math.min(config.timeoutMs, deadlineMs);
            if (budget <= 0 || !perClient(client).ok || !withinCap()) return end("capped");
            const messages = [
                { role: "system", content: SYSTEM_PROMPT },
                { role: "user", content: `DATA_START\n${JSON.stringify(input)}\nDATA_END` },
            ];
            const controller = new AbortController();
            let timer;
            const timeout = new Promise((resolve) => {
                timer = setTimeout(() => {
                    controller.abort();
                    resolve({ ok: false, reason: "timeout" });
                }, budget);
            });
            try {
                const answer = await Promise.race([ask(messages, controller.signal), timeout]);
                if (!answer.ok) return end(controller.signal.aborted ? "timeout" : answer.reason);
                const verdict = parseVerdict(answer.content);
                if (!verdict) return end("bad_schema");
                if (verdict.reasonable || verdict.confidence < MIN_CONFIDENCE || verdict.asks.length === 0) return end("reasonable");
                return end("flagged", buildSignal(evidenceFrom(verdict.evidence, snapshot)));
            } catch {
                return end("http_error");
            } finally {
                clearTimeout(timer);
            }
        },
    };
}
