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
