// Layer 3 content signals: urgent_language and brand_logo_offsite (phase 03; brand_logo_offsite also from a copied sign-in form, fingerprints.js).
// Text is matched against fixed phrase lists with plain string search (no regex, no backtracking).
// Evidence is an exact piece of the page; labels only ever contain OUR wording (phrase list / brand name).
import brands from "../../../detector/data/brands.json" with { type: "json" };
import { buildIndex, findPhrase, evidenceOf } from "./match.js";
import { hasAny, vocabulary } from "./text.js";
import { buildUrgentSignal, buildBrandLogoSignal, buildBrandFormSignal } from "./signals.js";
import { FIELD_FINGERPRINTS } from "./fingerprints.js";

// Always urgent: an account threat or a countdown that scams use. Bilingual (ID + EN).
const URGENT_PHRASES = [
    "diblokir dalam 24 jam", "ditutup dalam 24 jam", "dibekukan dalam 24 jam",
    "akun anda akan ditutup", "akun anda akan diblokir", "akun anda akan dibekukan", "rekening anda akan diblokir",
    "klaim sekarang", "segera verifikasi", "verifikasi sekarang juga", "terakhir hari ini",
    "your account will be suspended", "your account will be closed", "your account will be blocked",
    "verify immediately", "immediate action required", "urgent action required", "final warning",
];
// Ordinary shop wording too ("ships within 24 hours", "act now, sale ends"): only urgent when a threat word sits nearby.
const URGENT_NEEDS_THREAT = ["dalam 24 jam", "within 24 hours", "act now", "act immediately", "bertindak sekarang"];
const THREAT_WORDS = [
    "blokir", "diblokir", "dibekukan", "ditutup", "dihapus", "hangus", "verifikasi", "konfirmasi", "keamanan", "peringatan",
    "block", "blocked", "suspend", "suspended", "closed", "frozen", "terminated", "deleted", "verify", "verification", "security", "alert", "urgent", "warning",
];
const THREAT_WINDOW = 80;

/** Text around a hit, cut on spaces so a half word ("unblocked" -> "blocked") never counts. */
function threatWindow(folded, hit) {
    let from = Math.max(0, hit.foldedStart - THREAT_WINDOW);
    let to = Math.min(folded.length, hit.foldedEnd + THREAT_WINDOW);
    if (from > 0) from = folded.indexOf(" ", from) + 1 || hit.foldedStart;
    if (to < folded.length) to = folded.lastIndexOf(" ", to) > hit.foldedEnd ? folded.lastIndexOf(" ", to) : hit.foldedEnd;
    return folded.slice(from, to);
}

function findUrgent(source) {
    if (!source) return null;
    const index = buildIndex(source);
    let best = null;
    const consider = (phrase, hit) => {
        if (hit && (!best || hit.start < best.hit.start)) best = { phrase, hit };
    };
    for (const phrase of URGENT_PHRASES) consider(phrase, findPhrase(index, phrase));
    for (const phrase of URGENT_NEEDS_THREAT) {
        // every occurrence is checked: a benign first one must not hide a later one next to a threat word
        for (let hit = findPhrase(index, phrase); hit; hit = findPhrase(index, phrase, hit.foldedStart + 1)) {
            if (hasAny(vocabulary([threatWindow(index.folded, hit)]), THREAT_WORDS)) {
                consider(phrase, hit);
                break;
            }
        }
    }
    return best && { phrase: best.phrase, evidence: evidenceOf(index, best.hit) };
}

// ---- brand_logo_offsite -----------------------------------------------------
// "icon" is left out on purpose: shops show "Facebook icon" / "Instagram icon" share buttons everywhere.
const LOGO_WORDS = ["logo"];
// Brands whose logo appears on ordinary sites as "sign in with" / share / follow buttons. Only their titles count.
const ALT_EXEMPT = new Set(["meta", "google", "apple", "microsoft"]);
// A title that names a brand is only a claim to BE that brand when it also invites an action (blogs say "Cara cek saldo BCA" or "Cara membuat akun BCA").
const TITLE_ACTION_WORDS = ["login", "signin", "masuk", "verifikasi", "verify", "verification", "secure", "otp", "pin"];
/** Three or more different brands among the alts looks like a payment-method strip, not an imitation. */
const PAYMENT_STRIP_BRANDS = 3;
/** Most brand names layer 4 gets (detectBrands). */
const MAX_LLM_BRANDS = 3;

const BRANDS = brands.brands.map((b) => {
    const common = new Set(b.commonNames || []);
    const all = [...new Set([b.name.toLowerCase(), ...b.names])];
    return { id: b.id, name: b.name, altTerms: ALT_EXEMPT.has(b.id) ? [] : all, titleTerms: all.filter((t) => !common.has(t)) };
});

function matchBrand(source, termsOf) {
    const index = buildIndex(source);
    for (const brand of BRANDS) {
        for (const term of brand[termsOf]) {
            const hit = findPhrase(index, term);
            if (hit) return { brand: brand.name, evidence: evidenceOf(index, hit) };
        }
    }
    return null;
}

function findBrandLogo(snapshot) {
    const alts = snapshot.imageAlts;
    const seen = new Set();
    let first = null;
    for (const alt of alts) {
        const hit = matchBrand(alt, "altTerms");
        if (!hit) continue;
        seen.add(hit.brand);
        if (!first && hasAny(vocabulary([alt]), LOGO_WORDS)) first = hit;
    }
    if (first && seen.size < PAYMENT_STRIP_BRANDS) return first;
    if (snapshot.title && hasAny(vocabulary([snapshot.title]), TITLE_ACTION_WORDS)) return matchBrand(snapshot.title, "titleTerms");
    return null;
}

const brandNameOf = (brandId) => brands.brands.find((b) => b.id === brandId)?.name ?? null;

/**
 * A form copied from a brand's own sign-in page (fingerprints.js). Whole `name` / `id` values only, case-insensitive,
 * and at least `minHits` DIFFERENT values, so one generic name never fires it. Not for official hosts: the caller skips them.
 * @returns {{ brand: string } | null}
 */
function findBrandForm(snapshot) {
    for (const fp of FIELD_FINGERPRINTS) {
        const hits = new Set();
        for (const form of snapshot.forms) {
            for (const f of form.fields) {
                const name = f.name?.trim().toLowerCase();
                const id = f.id?.trim().toLowerCase();
                if (name && fp.names.includes(name)) hits.add(`name:${name}`);
                if (id && fp.ids.includes(id)) hits.add(`id:${id}`);
            }
        }
        const brand = hits.size >= fp.minHits ? brandNameOf(fp.brandId) : null;
        if (brand) return { brand };
    }
    return null;
}

/**
 * Brand names the page shows, for layer 4 (the LLM). Our own wording from brands.json, never page text (D-imelda-42).
 * Sources: a copied sign-in form, the title, and image alts. Alts of brands that ordinary sites show as "sign in with"
 * buttons (ALT_EXEMPT) do not count on their own, and 3+ different brands in the alts look like a payment strip: skipped.
 * @param {{ title: string, imageAlts: string[], forms: { fields: any[] }[] }} snapshot sanitised
 * @returns {string[]} at most MAX_LLM_BRANDS names, no duplicates
 */
export function detectBrands(snapshot) {
    const found = [];
    const add = (name) => {
        if (name && !found.includes(name)) found.push(name);
    };
    add(findBrandForm(snapshot)?.brand);
    if (snapshot.title) add(matchBrand(snapshot.title, "titleTerms")?.brand);
    const fromAlts = new Set();
    for (const alt of snapshot.imageAlts) {
        const hit = matchBrand(alt, "altTerms");
        if (hit) fromAlts.add(hit.brand);
    }
    if (fromAlts.size < PAYMENT_STRIP_BRANDS) for (const name of fromAlts) add(name);
    return found.slice(0, MAX_LLM_BRANDS);
}

/**
 * @param {{ text: string, title: string, imageAlts: string[], forms: { fields: any[] }[] }} snapshot sanitised
 * @param {{ official: boolean, asksData?: boolean }} ctx asksData: a form signal (asks_*) fired; without it the words weigh less
 * @returns {object[]} 0-2 signals
 */
export function contentSignals(snapshot, { official, asksData = true }) {
    const quiet = !asksData;
    const out = [];
    const urgent = findUrgent(snapshot.text) ?? findUrgent(snapshot.title);
    if (urgent) out.push(buildUrgentSignal(urgent.phrase, urgent.evidence, { quiet }));
    if (!official) {
        // One brand_logo_offsite at most. A copied sign-in form is the stronger claim, so it wins over a logo/title hit.
        const form = findBrandForm(snapshot);
        if (form) {
            out.push(buildBrandFormSignal(form.brand));
        } else {
            const logo = findBrandLogo(snapshot);
            if (logo) out.push(buildBrandLogoSignal(logo.brand, logo.evidence, { quiet }));
        }
    }
    return out;
}
