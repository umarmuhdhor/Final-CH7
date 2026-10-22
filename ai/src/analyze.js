// Orchestrates layer 3: form signals + content signals (sync rules) and new_domain (RDAP, parallel).
// Layer 4 (LLM reality check) runs after the rules, behind a cost gate, and can only add a signal. Nothing is stored or logged.
import { sanitizeSnapshot } from "./validate.js";
import { formSignals } from "./layer3/forms.js";
import { contentSignals } from "./layer3/content.js";
import { buildNewDomainSignal } from "./layer3/signals.js";
import { hostOf, isOfficialHost } from "./layer3/official.js";

/** Strongest first, ties by id (same order as the form signals had on their own). */
const strongestFirst = (signals) => signals.sort((a, b) => b.weight - a.weight || (a.id < b.id ? -1 : 1));

function rules(snapshot, official) {
    const forms = formSignals(snapshot, { official });
    return strongestFirst([...forms, ...contentSignals(snapshot, { official, asksData: forms.length > 0 })]);
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
 * @param {{ rdap?: { lookupAgeDays(host: string): Promise<number|null> } | null, llm?: { check: Function } | null, client?: string }} [deps]
 */
export async function analyze(rawSnapshot, { rdap = null, llm = null, client = "unknown" } = {}) {
    const snapshot = sanitizeSnapshot(rawSnapshot);
    const host = hostOf(snapshot.url);
    const official = isOfficialHost(host);
    const age = rdap && !official ? rdap.lookupAgeDays(host).catch(() => null) : Promise.resolve(null);
    const signals = rules(snapshot, official);
    // Layer 4 starts right after the rules and runs while RDAP is still answering. Its budget is separate (<= 4 s).
    const score = signals.reduce((sum, s) => sum + s.weight, 0); // our rules only, never client-supplied numbers
    const reality = llm ? llm.check(snapshot, { official, score, ruleIds: signals.map((s) => s.id), client }).catch(() => null) : Promise.resolve(null);
    const [days, layer4] = await Promise.all([age, reality]);
    if (layer4) signals.push(layer4);
    const domainSignal = days === null ? null : buildNewDomainSignal(days);
    if (domainSignal) signals.push(domainSignal);
    return strongestFirst(signals);
}
