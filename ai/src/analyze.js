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
    return strongestFirst([...formSignals(snapshot, { official }), ...contentSignals(snapshot, { official })]);
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
 * @param {{ rdap?: { lookupAgeDays(host: string): Promise<number|null> } | null, llm?: { check: Function } | null, localSignals?: object[] }} [deps]
 */
export async function analyze(rawSnapshot, { rdap = null, llm = null, localSignals = [] } = {}) {
    const snapshot = sanitizeSnapshot(rawSnapshot);
    const host = hostOf(snapshot.url);
    const official = isOfficialHost(host);
    const age = rdap && !official ? rdap.lookupAgeDays(host).catch(() => null) : Promise.resolve(null);
    const signals = rules(snapshot, official);
    // Layer 4 starts right after the rules and runs while RDAP is still answering. Its budget is separate (<= 4 s).
    const score = provisionalScore(signals, localSignals);
    const reality = llm ? llm.check(snapshot, { official, score, ruleIds: signals.map((s) => s.id) }).catch(() => null) : Promise.resolve(null);
    const [days, layer4] = await Promise.all([age, reality]);
    if (layer4) signals.push(layer4);
    const domainSignal = days === null ? null : buildNewDomainSignal(days);
    if (domainSignal) signals.push(domainSignal);
    return strongestFirst(signals);
}

/** Layers 1-3 so far: our rules plus whatever the extension already found (untrusted numbers, so each is capped). */
function provisionalScore(ruleSignals, localSignals) {
    let sum = 0;
    for (const s of ruleSignals) sum += s.weight;
    for (const s of Array.isArray(localSignals) ? localSignals.slice(0, 30) : []) {
        const w = s && typeof s === "object" ? s.weight : 0;
        if (Number.isFinite(w) && w > 0) sum += Math.min(w, 100);
    }
    return Math.min(100, sum);
}
