// Orchestrates layer 3: form signals + content signals (sync rules) and new_domain (RDAP, parallel).
// LLM (phase 06) plugs in here later. Nothing is stored or logged.
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
 * @param {{ rdap?: { lookupAgeDays(host: string): Promise<number|null> } | null }} [deps]
 */
export async function analyze(rawSnapshot, { rdap = null } = {}) {
    const snapshot = sanitizeSnapshot(rawSnapshot);
    const host = hostOf(snapshot.url);
    const official = isOfficialHost(host);
    const age = rdap && !official ? rdap.lookupAgeDays(host).catch(() => null) : Promise.resolve(null);
    const signals = rules(snapshot, official);
    const days = await age;
    const domainSignal = days === null ? null : buildNewDomainSignal(days);
    if (domainSignal) signals.push(domainSignal);
    return strongestFirst(signals);
}
