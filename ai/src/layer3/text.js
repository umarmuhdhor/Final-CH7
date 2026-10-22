// Word splitting for field names and labels. No regular expressions: a single linear pass,
// so a hostile 100,000-character label cannot cause backtracking (SECURITY A3).

const SEPARATOR = "|";

function kindOf(code) {
    if (code >= 48 && code <= 57) return "digit";
    if (code >= 65 && code <= 90) return "upper";
    if (code >= 97 && code <= 122) return "lower";
    if (code < 0xc0) return "other"; // includes NBSP and Latin-1 punctuation
    if ((code >= 0x2000 && code <= 0x206f) || (code >= 0x3000 && code <= 0x303f) || (code >= 0xff00 && code <= 0xff0f)) return "other"; // general, CJK and full-width punctuation
    if (code > 127) return "lower"; // other scripts: treat as letters
    return "other";
}

// Cyrillic letters that look like Latin ones (a page can use them to dodge keyword matching).
const LOOKALIKE = { а: "a", е: "e", о: "o", р: "p", с: "c", і: "i", у: "y", х: "x", к: "k", т: "t", м: "m", н: "h", в: "b" };

/**
 * Makes look-alike spellings plain: NFKC (full-width letters, NBSP, ellipsis), drops invisible characters
 * (soft hyphen, zero-width, BOM, combining marks) and maps Cyrillic look-alikes. One linear pass.
 * @param {string} text
 */
export function fold(text) {
    let out = "";
    for (const ch of text.normalize("NFKC")) {
        const code = ch.codePointAt(0);
        if (code === 0xad || (code >= 0x200b && code <= 0x200f) || (code >= 0x2060 && code <= 0x2064) || code === 0xfeff || (code >= 0x300 && code <= 0x36f)) continue;
        out += LOOKALIKE[ch.toLowerCase()] ?? ch;
    }
    return out;
}

/**
 * Splits on anything that is not a letter or digit, on camelCase (userPin -> user pin),
 * and between letters and digits (pin6 -> pin 6). PIN stays one word.
 * @param {string} text
 * @returns {string[]} lowercase words
 */
export function words(text) {
    text = fold(text);
    const out = [];
    let start = -1;
    let prev = "other";
    const flush = (end) => {
        if (start >= 0) out.push(text.slice(start, end).toLowerCase());
        start = -1;
    };
    for (let i = 0; i < text.length; i++) {
        const kind = kindOf(text.charCodeAt(i));
        if (kind === "other") {
            flush(i);
        } else if (start < 0) {
            start = i;
        } else if (
            (prev === "lower" && kind === "upper") ||
            ((prev === "lower" || prev === "upper") && kind === "digit") ||
            (prev === "digit" && (kind === "lower" || kind === "upper")) ||
            (prev === "upper" && kind === "upper" && kindOf(text.charCodeAt(i + 1) || 0) === "lower")
        ) {
            flush(i);
            start = i;
        }
        prev = kind;
    }
    flush(text.length);
    return out;
}

/**
 * Words and two-word phrases of several strings, for O(1) lookups.
 * Phrases never span two strings (a separator word sits between them).
 * @param {(string|null|undefined)[]} parts
 * @returns {Set<string>} e.g. {"nomor", "kartu", "nomor kartu"}
 */
export function vocabulary(parts) {
    const set = new Set();
    for (const part of parts) {
        if (!part) continue;
        const w = words(part);
        for (let i = 0; i < w.length; i++) {
            set.add(w[i]);
            if (i + 1 < w.length) set.add(`${w[i]} ${w[i + 1]}`);
        }
        set.add(SEPARATOR);
    }
    return set;
}

/** True when any entry (a word or "two words") is in the vocabulary. */
export function hasAny(vocab, entries) {
    for (const e of entries) if (vocab.has(e)) return true;
    return false;
}
