// Orchestrates layer 3: form signals + content signals (sync rules) and new_domain (RDAP, parallel).
// Layer 4 (LLM reality check) runs after the rules, behind a cost gate, and can only add a signal. Nothing is stored or logged.
import { sanitizeSnapshot } from "./validate.js";
import { formSignals } from "./layer3/forms.js";
import { contentSignals } from "./layer3/content.js";
import { buildNewDomainSignal } from "./layer3/signals.js";
import { hostOf, isOfficialHost } from "./layer3/official.js";

/**
 * D-imelda-39: answer within 6.5 s of the request arriving. The extension gives up after 8 s, so 1.5 s is left for the
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

/** Sum of the extension's own layer 1-2 weights (untrusted numbers; layer 3/4 sent by a client are ignored, we compute those). */
function localScore(localSignals) {
    if (!Array.isArray(localSignals)) return 0;
    let sum = 0;
    for (const s of localSignals.slice(0, 30)) {
        if (s && typeof s === "object" && (s.layer === 1 || s.layer === 2) && Number.isFinite(s.weight) && s.weight > 0) sum += Math.min(s.weight, 100);
    }
    return sum;
}

/** True when layer 1-2 already add up to >= 10 (D-imelda-31): it only changes how much WORDS weigh. */
const looksLikeImpersonation = (localSignals) => localScore(localSignals) >= 10;

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
    // D-imelda-46: the LLM only settles the middle. It waits for the domain age (<= 1 s), because new_domain is part of the
    // layer 1-3 total that decides: total < 30 nothing is shown, total >= 80 the extension blocks, only 30..79 is asked.
    // The total counts the client's layer 1-2 weights (untrusted, so a client can open or close the gate for its own page;
    // each call is still capped per IP and per day). Layer 4's budget is what is left of the deadline, capped by the checker (<= 6 s).
    const days = await age;
    const domainSignal = days === null ? null : buildNewDomainSignal(days);
    if (domainSignal) signals.push(domainSignal);
    const score = localScore(localSignals) + signals.reduce((sum, s) => sum + s.weight, 0);
    const layer4 = llm ? await llm.check(snapshot, { official, score, ruleIds: signals.map((s) => s.id), localSignals, client, deadlineMs: deadline - now() }).catch(() => null) : null;
    if (layer4) signals.push(layer4);
    return strongestFirst(signals);
}
