// Layer 3 form signals: weights and bilingual wording.
// Weights are the starting proposal from plan/imelda/ref/R1 (not tested on real traffic yet; tuned in phase 07).

export const WEIGHTS = Object.freeze({
    asks_pin: 35,
    asks_otp: 25,
    asks_password: 15,
    asks_card: 20,
    asks_cvv: 25,
    asks_ktp: 25,
    asks_selfie_ktp: 35,
});

// label = Guardian wording. labelSimple = Protected (parent) wording: short, no technical words.
const TEXT = {
    asks_pin: {
        label: { en: "Form asks for a PIN or passcode", id: "Form meminta PIN atau kode sandi" },
        labelSimple: { en: "Asks for your secret PIN", id: "Meminta PIN rahasia kamu" },
    },
    asks_otp: {
        label: { en: "Form asks for a one-time code (OTP)", id: "Form meminta kode sekali pakai (OTP)" },
        labelSimple: { en: "Asks for the code sent to your phone", id: "Meminta kode yang dikirim ke HP kamu" },
    },
    asks_password: {
        label: { en: "Form asks for a password on an unofficial site", id: "Form meminta kata sandi di situs tidak resmi" },
        labelSimple: { en: "Asks for your password on a site that is not official", id: "Meminta kata sandi kamu di situs yang tidak resmi" },
    },
    asks_card: {
        label: { en: "Form asks for a card number", id: "Form meminta nomor kartu" },
        labelSimple: { en: "Asks for your bank card number", id: "Meminta nomor kartu bank kamu" },
    },
    asks_cvv: {
        label: { en: "Form asks for the card security code (CVV)", id: "Form meminta kode keamanan kartu (CVV)" },
        labelSimple: { en: "Asks for the 3 digits on the back of your card", id: "Meminta 3 angka di belakang kartu kamu" },
    },
    asks_ktp: {
        label: { en: "Form asks for a KTP number", id: "Form meminta nomor KTP" },
        labelSimple: { en: "Asks for your ID card number", id: "Meminta nomor KTP kamu" },
    },
    asks_selfie_ktp: {
        label: { en: "Form asks for a selfie with KTP", id: "Form meminta selfie dengan KTP" },
        labelSimple: { en: "Asks for a photo of you holding your ID card", id: "Meminta foto kamu sambil memegang KTP" },
    },
};

/**
 * @param {keyof typeof WEIGHTS} id
 * @param {string | null} evidence field name/id, never a typed value
 */
export function buildSignal(id, evidence) {
    const signal = { id, layer: 3, weight: WEIGHTS[id], label: { ...TEXT[id].label }, labelSimple: { ...TEXT[id].labelSimple } };
    if (evidence) signal.evidence = evidence;
    return signal;
}

// ---- phase 03: content and domain-age signals --------------------------------
// Starting weights from plan/imelda/ref/R1 and D-imelda-15/16/17; tuned in phase 07. (new_domain: see newDomainWeight)
export const CONTENT_WEIGHTS = Object.freeze({ urgent_language: 15, brand_logo_offsite: 25 });
// Words are cheap: shops, news and blogs say "terakhir hari ini" and show bank logos. Without a form that asks for
// something sensitive nothing can be stolen on the page, so the words weigh about half (phase 07, D-imelda-31).
export const QUIET_CONTENT_WEIGHTS = Object.freeze({ urgent_language: 8, brand_logo_offsite: 12 });

/** @param {string} phrase our own phrase from the list (never page text) @param {string} evidence exact page text */
export function buildUrgentSignal(phrase, evidence, { quiet = false } = {}) {
    return {
        id: "urgent_language",
        layer: 3,
        weight: (quiet ? QUIET_CONTENT_WEIGHTS : CONTENT_WEIGHTS).urgent_language,
        label: { en: `Urgent language: "${phrase}"`, id: `Kalimat mendesak: "${phrase}"` },
        labelSimple: { en: "Rushes you to act fast", id: "Memaksa kamu cepat-cepat bertindak" },
        evidence,
    };
}

/** @param {string} brandName display name from brands.json @param {string} evidence exact page text */
export function buildBrandLogoSignal(brandName, evidence, { quiet = false } = {}) {
    return {
        id: "brand_logo_offsite",
        layer: 3,
        weight: (quiet ? QUIET_CONTENT_WEIGHTS : CONTENT_WEIGHTS).brand_logo_offsite,
        label: { en: `${brandName} logo on an unofficial site`, id: `Logo ${brandName} di situs tidak resmi` },
        labelSimple: { en: `Pretends to be ${brandName}`, id: `Berpura-pura menjadi ${brandName}` },
        evidence,
    };
}

/**
 * Same id as the logo signal (no new id, no contract change), raised when the FORM is a copy of a brand's sign-in form
 * (fingerprints.js). Always the full weight: a copied form is not "words", it is the page claiming to be the brand while
 * it collects the login. No `evidence`: a field name is not text on the page, so there is nothing for the extension to
 * highlight (evidence is optional, D-imelda decision on A7).
 * @param {string} brandName display name from brands.json
 */
export function buildBrandFormSignal(brandName) {
    return {
        id: "brand_logo_offsite",
        layer: 3,
        weight: CONTENT_WEIGHTS.brand_logo_offsite,
        label: { en: `${brandName} sign-in form copied on an unofficial site`, id: `Form login ${brandName} ditiru di situs tidak resmi` },
        labelSimple: { en: `Pretends to be ${brandName}`, id: `Berpura-pura menjadi ${brandName}` },
    };
}

/** Weight by domain age (D-imelda-15). null = old enough, no signal. */
export function newDomainWeight(days) {
    if (days < 7) return 30;
    if (days <= 30) return 20;
    if (days <= 90) return 10;
    return null;
}

/** @param {number} days whole days since registration */
export function buildNewDomainSignal(days) {
    const weight = newDomainWeight(days);
    if (weight === null) return null;
    return {
        id: "new_domain",
        layer: 3,
        weight,
        label: { en: `Domain age ${days} ${days === 1 ? "day" : "days"}`, id: `Umur domain ${days} hari` },
        labelSimple: { en: days === 1 ? "This site was made 1 day ago" : `This site was made ${days} days ago`, id: `Situs ini baru dibuat ${days} hari lalu` },
        // no `evidence`: the extension highlights it on the page, and an age is not page text (contracts/fixtures)
    };
}
