// Request validation and snapshot sanitising. Everything from the page is untrusted:
// keep only the keys layer 3 needs, cap every size, never keep values the user typed.
import { LIMITS } from "./limits.js";

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const str = (v, max) => (typeof v === "string" ? v.slice(0, max) : null);

/**
 * Checks the body shape of POST /analyze. Returns a fixed message on failure (never echoes input).
 * @param {unknown} body
 * @returns {{ error: string } | { snapshot: object, localSignals: unknown[] }}
 */
export function validateRequest(body) {
    if (!isObject(body)) return { error: "Body must be a JSON object with a snapshot." };
    const { snapshot, localSignals } = body;
    if (!isObject(snapshot)) return { error: "snapshot must be an object." };
    if (typeof snapshot.url !== "string" || snapshot.url.length === 0 || snapshot.url.length > LIMITS.MAX_URL_CHARS) return { error: "snapshot.url must be a URL string." };
    let parsed;
    try {
        parsed = new URL(snapshot.url);
    } catch {
        return { error: "snapshot.url must be a URL string." };
    }
    if (parsed.hostname.length > 253) return { error: "snapshot.url must be a URL string." };
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return { error: "snapshot.url must be http or https." };
    if (localSignals !== undefined && !Array.isArray(localSignals)) return { error: "localSignals must be an array." };
    return { snapshot, localSignals: localSignals ?? [] };
}

/**
 * Keeps only what layer 3 reads, with every size capped (LIMITS). Safe to run twice.
 * Drops unknown keys, so a stray `value` on a field never travels further.
 * @param {any} snapshot
 */
export function sanitizeSnapshot(snapshot) {
    const rawForms = Array.isArray(snapshot.forms) ? snapshot.forms : [];
    const forms = [];
    let fieldBudget = LIMITS.MAX_FIELDS_TOTAL;
    for (const form of rawForms) {
        if (forms.length >= LIMITS.MAX_FORMS) break;
        if (!isObject(form) || !Array.isArray(form.fields)) continue;
        const fields = [];
        for (const f of form.fields) {
            if (fields.length >= LIMITS.MAX_FIELDS_PER_FORM || fieldBudget <= 0) break;
            if (!isObject(f)) continue;
            fieldBudget--;
            fields.push({
                type: str(f.type, 40) ?? "text",
                name: str(f.name, LIMITS.MAX_FIELD_TEXT),
                id: str(f.id, LIMITS.MAX_FIELD_TEXT),
                label: str(f.label, LIMITS.MAX_FIELD_TEXT),
                placeholder: str(f.placeholder, LIMITS.MAX_FIELD_TEXT),
                autocomplete: str(f.autocomplete, LIMITS.MAX_FIELD_TEXT),
            });
        }
        forms.push({ action: str(form.action, LIMITS.MAX_URL_CHARS), fields });
    }
    const imageAlts = (Array.isArray(snapshot.imageAlts) ? snapshot.imageAlts : [])
        .filter((a) => typeof a === "string")
        .slice(0, LIMITS.MAX_IMAGE_ALTS)
        .map((a) => a.slice(0, LIMITS.MAX_ALT_CHARS));
    return {
        url: str(snapshot.url, LIMITS.MAX_URL_CHARS) ?? "",
        title: str(snapshot.title, LIMITS.MAX_TITLE_CHARS) ?? "",
        lang: str(snapshot.lang, 35),
        text: str(snapshot.text, LIMITS.MAX_TEXT_CHARS) ?? "",
        forms,
        imageAlts,
    };
}
