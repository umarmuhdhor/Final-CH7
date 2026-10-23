// Layer 3, form part: which sensitive data does a form ask for?
// Pure keyword rules over field name / id / label / placeholder / autocomplete. No model, no network.
// Words are matched whole ("pin" does not fire inside "shipping" or "pinjaman").
import { vocabulary, hasAny } from "./text.js";
import { buildSignal } from "./signals.js";

/** Field types that cannot ask for anything: buttons, hidden values, tick boxes. */
const IGNORED_TYPES = new Set(["hidden", "submit", "button", "reset", "image", "checkbox", "radio"]);

// Entries are single words or "two words". Indonesian + English.
const RULES = {
    ktp: ["ktp", "nik", "induk kependudukan", "national id", "id card", "identity card", "kartu identitas"],
    cvv: ["cvv", "cvc", "cc csc", "card verification"],
    // Too common on their own (captcha: "kode keamanan"), so they need card context.
    cvvNeedsCard: ["kode keamanan", "security code"],
    card: ["nomor kartu", "no kartu", "card number", "cc number", "cardnumber", "ccnumber", "credit card", "debit card", "kartu kredit", "kartu debit"],
    otp: ["otp", "kode verifikasi", "verification code", "sms code"],
    // "one-time donation" is not a code: needs a code-like word next to it.
    otpNeedsCode: ["one time"],
    pin: ["pin", "mpin", "m pin", "passcode", "pass code", "kode sandi", "kode akses"],
};
const SELFIE = ["selfie", "swafoto"];
const SELFIE_DOC = RULES.ktp;
const CARD_CONTEXT = ["kartu", "card", "cc", "kredit", "credit", "debit"];
const CODE_WORDS = ["code", "kode", "password", "pin", "passcode", "token"];
/** A card number field that is really something else (family card, member card, holder name...). */
const NOT_A_CARD = ["keluarga", "member", "anggota", "loyalty", "gift", "nama", "name", "holder", "id", "employee", "student", "staff", "pemilik", "expiry", "expiration", "exp", "berlaku"];
/** "ID card" of a school, company or club is not a national ID. */
const NOT_A_KTP_ID = ["student", "employee", "staff", "mahasiswa", "pegawai", "karyawan", "siswa", "member", "anggota"];
/** PIN in the sense of a map pin. */
const NOT_A_PIN = ["location", "lokasi", "map", "peta"];
/** A selfie field that is a profile photo, not an ID check. */
const PROFILE_PHOTO = ["profile", "profil", "avatar"];
const POSTAL = ["postal", "zip", "postcode", "kodepos", "kode pos"];

/**
 * @param {{ type: string, name: string|null, id: string|null, label: string|null, placeholder: string|null, autocomplete: string|null }} f
 * @returns {{ kind: string|null, selfie: boolean }} kind before pairing a lone selfie with a KTP field in the same form.
 * Order of the checks is the priority: a field answers with the first kind that fits, never two.
 *
 * Each attribute (name, id, label, ...) is read on its own. An "exclusion" word only cancels a keyword found in the
 * SAME attribute, so a page cannot switch a signal off by stuffing a harmless word into another attribute.
 */
function classify(f) {
    const type = f.type.toLowerCase();
    if (IGNORED_TYPES.has(type)) return { kind: null, selfie: false };
    const parts = [f.name, f.id, f.label, f.placeholder, f.autocomplete].filter(Boolean).map((p) => vocabulary([p]));
    const some = (test) => parts.some(test);
    const match = (entries, excluded = []) => some((v) => hasAny(v, entries) && !hasAny(v, excluded));
    const anywhere = (entries) => some((v) => hasAny(v, entries));

    const selfie = match(SELFIE, PROFILE_PHOTO);
    const ktp = match(RULES.ktp, NOT_A_KTP_ID);
    let kind = null;
    if (selfie && ktp) kind = "asks_selfie_ktp";
    else if (ktp && !anywhere(SELFIE)) kind = "asks_ktp";
    else if (match(RULES.cvv) || (match(RULES.cvvNeedsCard) && anywhere(CARD_CONTEXT))) kind = "asks_cvv";
    else if (match(RULES.card, NOT_A_CARD)) kind = "asks_card";
    else if (match(RULES.otp) || some((v) => hasAny(v, RULES.otpNeedsCode) && hasAny(v, CODE_WORDS))) kind = "asks_otp";
    else if (match(RULES.pin, NOT_A_PIN) && !(anywhere(["pin code"]) && anywhere(POSTAL))) kind = "asks_pin";
    else if (type === "password") kind = "asks_password";
    return { kind, selfie };
}

const evidenceOf = (f) => (f.name ? f.name : f.id ? f.id : null);

/**
 * @param {{ forms: { fields: any[] }[] }} snapshot already sanitised (validate.js)
 * @param {{ official: boolean }} ctx official = the page is on an official domain: stay silent
 * @returns {object[]} signals, one per kind, strongest first
 */
export function formSignals(snapshot, { official }) {
    if (official) return [];
    const found = new Map(); // id -> evidence of the first field that raised it
    const raise = (id, field) => {
        if (!found.has(id)) found.set(id, evidenceOf(field));
    };
    for (const form of snapshot.forms) {
        const results = form.fields.map((f) => ({ f, ...classify(f) }));
        const formAsksKtp = results.some((r) => r.kind === "asks_ktp");
        for (const { f, kind, selfie } of results) {
            // A selfie field next to a KTP field in the same form is a selfie-with-KTP request.
            const final = kind === null && selfie && formAsksKtp ? "asks_selfie_ktp" : kind;
            if (final) raise(final, f);
        }
    }
    // A card form always asks number + expiry + CVV: that is ONE request for card data, not two (review #60).
    // Otherwise every small shop with its own card checkout scores 50 (struck-out fields). CVV alone still counts.
    if (found.has("asks_card")) found.delete("asks_cvv");
    return [...found.entries()]
        .map(([id, evidence]) => buildSignal(id, evidence))
        .sort((a, b) => b.weight - a.weight || (a.id < b.id ? -1 : 1));
}
