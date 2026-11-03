// ai_usage (05b K4): one Workers Analytics Engine point per /analyze that reached the analysis, so the cost of layer 4
// can be followed over time. Counts and our own labels only: no IP, domain, URL, title, page text, prompt, answer or key,
// and no `indexes` (SECURITY A1, A4; wrangler.toml "no request logs"). Without the AI_USAGE binding nothing is written.
import { PROMPT_VERSION } from "../prompts/reality-check.js";

/** blobs[1] when no case set is in use (case library off, missing or broken; layer4/cases.js). */
export const NO_CASES = "none";
const MAX_TOKENS = 1e7;

/** Token counts from an OpenAI-compatible `usage` object; anything that is not a plain count is 0. */
export function tokenUsage(usage) {
    const count = (n) => (typeof n === "number" && Number.isFinite(n) && n >= 0 ? Math.min(Math.floor(n), MAX_TOKENS) : 0);
    return { in: count(usage?.prompt_tokens), out: count(usage?.completion_tokens) };
}

/**
 * What one request reports. `layer4` is filled by the reality check (outcome, tokens, ms) when there is one; `rdapFailed`
 * is set when a domain-age lookup ran and gave no age. Mutable on purpose: the checker is shared by concurrent
 * requests, so per-request numbers cannot be read back from its counters.
 */
export function createUsageReport({ hasLayer4, casesVersion = null }) {
    return { layer4: { outcome: hasLayer4 ? null : "off", tokensIn: 0, tokensOut: 0, ms: 0 }, rdapFailed: 0, casesVersion: casesVersion ?? NO_CASES };
}

/** The RDAP client with one change: a lookup that gives no age (failure, timeout, unknown TLD) sets `report.rdapFailed`. */
export function watchRdap(rdap, report) {
    if (!rdap) return rdap;
    return {
        lookupAgeDays: async (host) => {
            const days = await rdap.lookupAgeDays(host).catch(() => null);
            if (days === null) report.rdapFailed = 1;
            return days;
        },
    };
}

/** The layer 4 checker with the request's report (and the active case set, if any) passed along. */
export function watchLlm(llm, report, cases = null) {
    if (!llm) return llm;
    return { check: (snapshot, ctx) => llm.check(snapshot, { ...ctx, report: report.layer4, cases }) };
}

/**
 * Writes the point. Never throws and never waits: a missing binding, a quota or any binding error leaves the answer as it is.
 * blobs: prompt version, cases version, layer 4 outcome (an OUTCOMES name from layer4/reality.js, or "off").
 * doubles: tokens in, tokens out, layer 4 ms, RDAP failed (0/1).
 */
export function writeUsage(dataset, report) {
    if (typeof dataset?.writeDataPoint !== "function") return;
    const l4 = report.layer4;
    try {
        dataset.writeDataPoint({
            blobs: [PROMPT_VERSION, report.casesVersion, l4.outcome ?? "http_error"], // null: the checker threw before it counted an outcome
            doubles: [l4.tokensIn, l4.tokensOut, l4.ms, report.rdapFailed],
        });
    } catch {
        // usage is best effort
    }
}
