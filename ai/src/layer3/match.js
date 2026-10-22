// Phrase search that returns offsets into the ORIGINAL page text (SECURITY A5).
// Matching runs on a folded copy (fold(): NFKC, invisible characters dropped, Cyrillic look-alikes mapped, lowercase,
// spaces collapsed). Every folded unit remembers which original span it came from, so the evidence we report is
// always `original.slice(start, end)`, a real substring of the page, never a rewritten one.
// No regular expressions: one linear pass to build the index, indexOf to search.
import { fold } from "./text.js";

const NEWLINES = new Set(["\n", "\r", "\v", "\f", "\u0085", " ", " "]);
/** Evidence longer than this (e.g. a phrase stretched by thousands of zero-width characters) is refused. */
const MAX_EVIDENCE_CHARS = 200;

/**
 * @param {string} text
 * @returns {{ text: string, folded: string, from: number[], to: number[] }}
 */
export function buildIndex(text) {
    let folded = "";
    const from = [];
    const to = [];
    let i = 0;
    for (const ch of text) {
        const start = i;
        i += ch.length;
        let f = NEWLINES.has(ch) ? "\n" : fold(ch).toLowerCase();
        if (f === "") continue; // invisible character: no folded unit, but it stays inside any span around it
        if (f === "\t") f = " ";
        if (f === " " && folded.endsWith(" ")) {
            to[to.length - 1] = i; // collapse a run of spaces into one, and let its span cover the whole run
            continue;
        }
        for (const unit of f) {
            for (let k = 0; k < unit.length; k++) {
                folded += unit[k];
                from.push(start);
                to.push(i);
            }
        }
    }
    return { text, folded, from, to };
}

const LETTER = /^\p{L}$/u; // one character at a time: linear, no backtracking

function isWordChar(ch) {
    const c = ch.charCodeAt(0);
    if (c >= 48 && c <= 57) return true;
    return ch.toLowerCase() !== ch.toUpperCase() || (c > 127 && LETTER.test(ch)); // second test: caseless scripts (Arabic, CJK, Thai)
}

function boundaryAt(folded, i) {
    return i < 0 || i >= folded.length || !isWordChar(folded[i]);
}

/**
 * First whole-word occurrence of `phrase` at or after folded offset `fromFolded` (lowercase, single spaces, no line breaks).
 * @param {ReturnType<typeof buildIndex>} index
 * @param {string} phrase
 * @param {number} [fromFolded]
 * @returns {{ start: number, end: number, foldedStart: number, foldedEnd: number } | null} start/end index the original text
 */
export function findPhrase(index, phrase, fromFolded = 0) {
    const { folded, from, to } = index;
    let pos = fromFolded;
    for (;;) {
        const at = folded.indexOf(phrase, pos);
        if (at < 0) return null;
        const end = at + phrase.length;
        if (boundaryAt(folded, at - 1) && boundaryAt(folded, end)) {
            const start = from[at];
            const stop = to[end - 1];
            // a phrase stretched by invisible characters is skipped, but later clean occurrences still count
            if (stop - start <= MAX_EVIDENCE_CHARS && start < stop) return { start, end: stop, foldedStart: at, foldedEnd: end };
        }
        pos = at + 1;
    }
}

/** Exact piece of the original text for a hit from findPhrase. */
export const evidenceOf = (index, hit) => index.text.slice(hit.start, hit.end);
