// Caps that keep one request cheap no matter what a hostile page sends (SECURITY A3).
// Starting values; revisit in phase 08 with real traffic.
export const LIMITS = Object.freeze({
    /** Bodies above this are refused with 413 before they are parsed. */
    MAX_BODY_BYTES: 200 * 1024,
    /** contracts/detector-interface.md: visible text, max 20,000 chars. */
    MAX_TEXT_CHARS: 20_000,
    /** contracts/detector-interface.md: imageAlts, max 50. */
    MAX_IMAGE_ALTS: 50,
    MAX_ALT_CHARS: 300,
    MAX_URL_CHARS: 2048,
    MAX_TITLE_CHARS: 500,
    MAX_FORMS: 20,
    MAX_FIELDS_PER_FORM: 60,
    /** Across all forms of one snapshot. */
    MAX_FIELDS_TOTAL: 300,
    /** Per string of a field: name, id, label, placeholder, autocomplete, accept. */
    MAX_FIELD_TEXT: 120,
    /** `capture` is a keyword ("user", "environment"). */
    MAX_CAPTURE_CHARS: 20,
});
