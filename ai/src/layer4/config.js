// Layer 4 settings come from environment variables only (Worker secrets / ai/.env). Missing or unsafe -> layer 4 is off.
export const MAX_TIMEOUT_MS = 4000; // plan/imelda/ref/R1 §3: LLM budget
const DEFAULT_DAILY_CAP = 5000;

/**
 * @param {Record<string, string | undefined>} env
 * @returns {{ apiKey: string, model: string, baseUrl: string, timeoutMs: number, dailyCap: number } | null}
 */
export function readConfig(env) {
    const apiKey = env?.LLM_API_KEY;
    const model = env?.LLM_MODEL;
    const base = env?.LLM_BASE_URL;
    if (!apiKey || !model || !base) return null;
    if (!base.startsWith("https://")) return null; // the key must never travel over plain HTTP
    const timeout = Number(env.LLM_TIMEOUT_MS);
    const cap = Number(env.LLM_DAILY_CAP);
    return {
        apiKey,
        model,
        baseUrl: base.replace(/\/+$/, ""),
        timeoutMs: Number.isFinite(timeout) && timeout > 0 ? Math.min(timeout, MAX_TIMEOUT_MS) : MAX_TIMEOUT_MS,
        dailyCap: Number.isInteger(cap) && cap >= 0 ? cap : DEFAULT_DAILY_CAP,
    };
}
