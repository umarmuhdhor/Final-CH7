// One place for the personal-data patterns, shared by snapshot.mjs (masking) and check-redaction.mjs (verifying).
// Order matters for masking: e-mail, phone numbers, then long digit runs, so "+62 812 ..." is not eaten as a number.

/** Makes look-alike characters plain: fullwidth forms (NFKC), Arabic-Indic digits, zero-width and soft-hyphen characters. */
export function fold(text) {
    return String(text ?? "")
        .normalize("NFKC")
        .replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660))
        .replace(/[۰-۹]/g, (c) => String(c.charCodeAt(0) - 0x6f0))
        .replace(/[​-‍⁠﻿­]/g, "");
}

export const MASKS = [
    ["email", "[email]", /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi],
    ["email (spelled out)", "[email]", /[A-Z0-9._%+-]+\s*[[(]\s*at\s*[\])]\s*[A-Z0-9-]+(?:\s*[[(]?\s*(?:dot|\.)\s*[\])]?\s*[A-Z0-9-]+)+/gi],
    ["phone", "[phone]", /(?<![\d+])\+?(?:62|0)[\s.-]?8[\d\s.-]{7,13}\d(?!\d)/g],
    ["landline", "[phone]", /(?<!\d)\(?0[1-9]\d{1,2}\)?[ .-]?\d{6,8}(?!\d)/g],
    ["long number", "[number]", /(?<!\d)(?:\d[ .-]?){12,18}\d(?!\d)/g], // card, NIK, account numbers (13-19 digits)
];

export const SECRETS = [
    ["secret (sk-)", /\bsk-[A-Za-z0-9_-]{16,}/],
    ["secret (AKIA)", /\bAKIA[0-9A-Z]{16}\b/],
    ["secret (JWT)", /\beyJ[\w-]+\.eyJ[\w-]+\.[\w-]+/],
    ["secret (token)", /\b(?:ghp|gho|xox[abp]|AIza)[\w-]{16,}/],
];
