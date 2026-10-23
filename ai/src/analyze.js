// Orchestrates layer 3: form signals + content signals (sync rules) and new_domain (RDAP, parallel).
// Layer 4 (LLM reality check) runs after the rules, behind a cost gate, and can only add a signal. Nothing is stored or logged.
import { sanitizeSnapshot } from "./validate.js";
import { formSignals } from "./layer3/forms.js";
import { contentSignals } from "./layer3/content.js";
import { buildNewDomainSignal } from "./layer3/signals.js";
import { hostOf, isOfficialHost } from "./layer3/official.js";

/**
 * D-imelda-38: answer within 6.5 s of the request arriving. The extension gives up after 8 s, so 1.5 s is left for the
 * network (connect, upload, download). Layer 4 gets what is left of this, never more than its own cap (layer4/config.js).
 */
export const SERVER_DEADLINE_MS = 6500;

/** Strongest first, ties by id (same order as the form signals had on their own). */
const strongestFirst = (signals) => signals.sort((a, b) => b.weight - a.weight || (a.id < b.id ? -1 : 1));

function rules(snapshot, official, impersonation = false) {
    const forms = formSignals(snapshot, { official });
    // Words weigh full when something sensitive is asked, or when the domain itself already looks like impersonation.
    return strongestFirst([...forms, ...contentSignals(snapshot, { official, asksData: forms.length > 0 || impersonation })]);
}

/** True when the extension's own layer 1-2 signals already add up to >= 10 (D-imelda-31). Untrusted numbers: they only change how much WORDS weigh. */
function looksLikeImpersonation(localSignals) {
    if (!Array.isArray(localSignals)) return false;
    let sum = 0;
    for (const s of localSignals.slice(0, 30)) {
        if (s && typeof s === "object" && (s.layer === 1 || s.layer === 2) && Number.isFinite(s.weight) && s.weight > 0) sum += Math.min(s.weight, 100);
    }
    return sum >= 10;
}

/**
 * Rules only: pure and synchronous, no network. This is the part that must stay under 100 ms CPU.
 * @param {object} rawSnapshot PageSnapshot (contracts/detector-interface.md); sanitised here
 * @returns {object[]} Signal[] (layer 3)
 */
export function analyzeSnapshot(rawSnapshot) {
    const snapshot = sanitizeSnapshot(rawSnapshot);
    return rules(snapshot, isOfficialHost(hostOf(snapshot.url)));
}

/**
 * Rules + domain age. The RDAP lookup starts first and runs while the rules run; it has its own
 * deadline and returns null on any failure, so the rules' answer never depends on it.
 * @param {object} rawSnapshot
 * @param {{ rdap?: { lookupAgeDays(host: string): Promise<number|null> } | null, llm?: { check: Function } | null, client?: string, localSignals?: unknown, deadline?: number, now?: () => number }} [deps]
 *   deadline: time (ms, same clock as `now`) by which the answer must be ready; layer 4 is cut there. Default: none.
 */
export async function analyze(rawSnapshot, { rdap = null, llm = null, client = "unknown", localSignals = [], deadline = Infinity, now = Date.now } = {}) {
    const snapshot = sanitizeSnapshot(rawSnapshot);
    const host = hostOf(snapshot.url);
    const official = isOfficialHost(host);
    const age = rdap && !official ? rdap.lookupAgeDays(host).catch(() => null) : Promise.resolve(null);
    const signals = rules(snapshot, official, looksLikeImpersonation(localSignals));
    // Layer 4 starts right after the rules and runs while RDAP (1.5 s) is still answering. Its budget is what is left of
    // the deadline, capped by the checker (<= 6 s).
    // Our rules' weights only, never the client's numbers. But localSignals can lift the WORD weights (impersonation
    // above), so a client can move this gate score by up to +20 (D-imelda-27). Low risk: the client controls the snapshot anyway.
    const score = signals.reduce((sum, s) => sum + s.weight, 0);
    const reality = llm ? llm.check(snapshot, { official, score, ruleIds: signals.map((s) => s.id), client, deadlineMs: deadline - now() }).catch(() => null) : Promise.resolve(null);
    const [days, layer4] = await Promise.all([age, reality]);
    if (layer4) signals.push(layer4);
    const domainSignal = days === null ? null : buildNewDomainSignal(days);
    if (domainSignal) signals.push(domainSignal);
    return strongestFirst(signals);
}
