// Orchestrates layer 3. Today: form signals only. Text signals (phase 03) and LLM (phase 06) plug in here.
import { sanitizeSnapshot } from "./validate.js";
import { formSignals } from "./layer3/forms.js";
import { hostOf, isOfficialHost } from "./layer3/official.js";

/**
 * Pure and synchronous: no storage, no network, no logging.
 * @param {object} rawSnapshot PageSnapshot (contracts/detector-interface.md); sanitised here
 * @returns {object[]} Signal[] (layer 3)
 */
export function analyzeSnapshot(rawSnapshot) {
    const snapshot = sanitizeSnapshot(rawSnapshot);
    const official = isOfficialHost(hostOf(snapshot.url));
    return formSignals(snapshot, { official });
}
