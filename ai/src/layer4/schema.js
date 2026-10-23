// The model's answer is accepted only if it matches this exact shape. Anything else is ignored, never an error.
import { PAGE_TYPES, ASK_KINDS } from "../../prompts/reality-check.js";

const PAGE = new Set(PAGE_TYPES);
const ASKS = new Set(ASK_KINDS);
const OPEN_FENCE = /^```(?:json)?[ \t]*\r?\n/i;
const CLOSE_FENCE = /\r?\n?```$/;

/** Some models ignore response_format and wrap the object in one ```json ... ``` fence. Strip exactly that, nothing more. */
function unfence(content) {
    const t = content.trim();
    if (!OPEN_FENCE.test(t) || !CLOSE_FENCE.test(t)) return t;
    return t.replace(OPEN_FENCE, "").replace(CLOSE_FENCE, "");
}

/**
 * @param {string} content the model's message text
 * @returns {{ pageType: string, asks: string[], reasonable: boolean, confidence: number, evidence: string | null } | null}
 */
export function parseVerdict(content) {
    if (typeof content !== "string" || content.length === 0 || content.length > 4000) return null;
    let v;
    try {
        v = JSON.parse(unfence(content));
    } catch {
        return null;
    }
    if (v === null || typeof v !== "object" || Array.isArray(v)) return null;
    if (!PAGE.has(v.page_type)) return null;
    if (!Array.isArray(v.asks) || v.asks.length > ASK_KINDS.length || !v.asks.every((a) => ASKS.has(a))) return null;
    if (typeof v.reasonable !== "boolean") return null;
    if (typeof v.confidence !== "number" || !(v.confidence >= 0 && v.confidence <= 1)) return null;
    if (v.evidence !== null && v.evidence !== undefined && typeof v.evidence !== "string") return null;
    return { pageType: v.page_type, asks: [...new Set(v.asks)], reasonable: v.reasonable, confidence: v.confidence, evidence: v.evidence ?? null };
}
