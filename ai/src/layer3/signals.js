// Layer 3 form signals: weights and bilingual wording.
// Weights are the starting proposal from plan/imelda/ref/R1 (not tested on real traffic yet; tuned in phase 07).

export const WEIGHTS = Object.freeze({
    asks_pin: 35,
    asks_otp: 30,
    asks_password: 15,
    asks_card: 30,
    asks_cvv: 30,
    asks_ktp: 30,
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

/** @param {string} phrase our own phrase from the list (never page text) @param {string} evidence exact page text */
export function buildUrgentSignal(phrase, evidence) {
    return {
        id: "urgent_language",
        layer: 3,
        weight: CONTENT_WEIGHTS.urgent_language,
        label: { en: `Urgent language: "${phrase}"`, id: `Kalimat mendesak: "${phrase}"` },
        labelSimple: { en: "Rushes you to act fast", id: "Memaksa kamu cepat-cepat bertindak" },
        evidence,
    };
}

/** @param {string} brandName display name from brands.json @param {string} evidence exact page text */
export function buildBrandLogoSignal(brandName, evidence) {
    return {
        id: "brand_logo_offsite",
        layer: 3,
        weight: CONTENT_WEIGHTS.brand_logo_offsite,
        label: { en: `${brandName} logo on an unofficial site`, id: `Logo ${brandName} di situs tidak resmi` },
        labelSimple: { en: `Pretends to be ${brandName}`, id: `Berpura-pura menjadi ${brandName}` },
        evidence,
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
