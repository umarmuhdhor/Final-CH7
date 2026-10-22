// Layer 4: "is the data this page asks for reasonable for this kind of page?" (M4).
// - Only a small summary leaves the server: host, title (<= 120 chars), field labels (<= 12) and ids of rules that fired.
//   No page text, no URL path or query, no typed values (SECURITY A1, A4).
// - Page words go into the user message as JSON data; the system prompt is a fixed string.
// - The answer must match schema.js, else it is ignored. Layer 4 can only ADD a signal (D-imelda-06).
// - Any failure, timeout or cap -> no signal; layer 3 already answered.
import { SYSTEM_PROMPT } from "../../prompts/reality-check.js";
import { hostOf } from "../layer3/official.js";
import { registrableDomain } from "../rdap/domain.js";
import { PROMPT_VERSION } from "../../prompts/reality-check.js";
import { createRateLimiter } from "../ratelimit.js";
import { createProvider } from "./provider.js";
import { parseVerdict } from "./schema.js";

export const WEIGHT = 30; // plan/imelda/ref/R1: starting proposal, tuned in phase 07
export const MIN_CONFIDENCE = 0.6;
export const GATE_MIN_SCORE = 15; // D-imelda-05 (proposal, not yet approved)
export const CLIENT_CALLS_PER_HOUR = 20; // per IP; /analyze itself gets its limit in phase 08
const MAX_FIELDS = 12;
const MAX_LABEL = 60;
const MAX_TITLE = 120;

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

/** What the model sees. Exported for tests. */
export function buildInput(snapshot, ruleIds) {
    const fields = [];
    for (const form of snapshot.forms) {
        for (const f of form.fields) {
            if (fields.length >= MAX_FIELDS) break;
            const label = clean(f.label || f.placeholder || f.name || f.id, MAX_LABEL);
            if (label || f.type) fields.push({ type: clean(f.type, 20) || "text", label });
        }
    }
    // site is null for IPs, intranet names and junk
    return { site: registrableDomain(hostOf(snapshot.url)), title: clean(snapshot.title, MAX_TITLE), fields, rules: ruleIds.slice(0, 20) };
}

function evidenceFrom(candidate, snapshot) {
    if (typeof candidate !== "string") return undefined;
    const needle = candidate.trim();
    if (needle.length < 8 || needle.length > 120) return undefined;
    // Only the title: the model never saw the text, and `text` is client-supplied.
    for (const haystack of [snapshot.title]) {
        const low = haystack.toLowerCase();
        if (low.length !== haystack.length) continue; // case folding changed the length: offsets would not match
        const i = low.indexOf(needle.toLowerCase());
        if (i >= 0) return haystack.slice(i, i + needle.length);
    }
    return undefined;
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
 * @param {{ config: object, fetch: typeof fetch, now?: () => number }} deps
 * @returns {{ check(snapshot: object, ctx: { official: boolean, score: number, ruleIds: string[], deadlineMs?: number }): Promise<object | null> }}
 */
export function createRealityCheck({ config, fetch, now = Date.now }) {
    const ask = createProvider({ config, fetch });
    const perClient = createRateLimiter({ limit: CLIENT_CALLS_PER_HOUR, windowMs: 60 * 60 * 1000, now });
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
        async check(snapshot, { official, score, ruleIds, client = "unknown", deadlineMs = config.timeoutMs }) {
            if (!passesGate(snapshot, { official, score })) return null;
            const input = buildInput(snapshot, ruleIds);
            if (!input.site) return null; // not a public domain: nothing sensible to judge, nothing to send
            const budget = Math.min(config.timeoutMs, deadlineMs);
            if (budget <= 0 || !perClient(client).ok || !withinCap()) return null;
            const messages = [
                { role: "system", content: SYSTEM_PROMPT },
                { role: "user", content: `DATA_START\n${JSON.stringify(input)}\nDATA_END` },
            ];
            const controller = new AbortController();
            let timer;
            const timeout = new Promise((resolve) => {
                timer = setTimeout(() => {
                    controller.abort();
                    resolve(null);
                }, budget);
            });
            try {
                const content = await Promise.race([ask(messages, controller.signal), timeout]);
                const verdict = parseVerdict(content);
                if (!verdict || verdict.reasonable || verdict.confidence < MIN_CONFIDENCE || verdict.asks.length === 0) return null;
                return buildSignal(evidenceFrom(verdict.evidence, snapshot));
            } catch {
                return null;
            } finally {
                clearTimeout(timer);
            }
        },
    };
}
