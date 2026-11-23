// Courier scams (jnex.cc, 23 Nov 2026): a fake tracking page says the delivery failed because the address is incomplete,
// then asks for a redelivery fee by card. Couriers (JNE, J&T, Pos Indonesia, ...) never ask for card data on a site they do
// not own, so a card ask next to a courier lure weighs enough to block on its own.
// No new signal id (no contract change): the lure is `urgent_language` with courier wording, the card ask keeps `asks_card` /
// `asks_cvv` with a higher weight and courier wording, like buildBrandFormSignal does for `brand_logo_offsite`.
// Official hosts never get here (the callers skip them). Plain string search only (match.js), no regex on page text.
import { buildIndex, findPhrase, evidenceOf } from "./match.js";
import { CONTENT_WEIGHTS } from "./signals.js";

/** A card or CVV ask on a courier-lure page: enough to block without RDAP or the model (extension blocks at 80). */
export const COURIER_CARD_WEIGHT = 80;

/**
 * Courier names, lowercase. Kept here until brands.json (lead-owned, detector/) gets a courier category (#682); then this list
 * should come from there. Only matched in the title and image alts (the page claiming to BE the courier), never in body
 * text: shop checkouts name couriers as shipping options ("Pengiriman: JNE REG").
 */
export const COURIER_NAMES = [
    "jne", "jne express", "j&t", "j&t express", "jnt", "pos indonesia", "posindonesia", "sicepat", "anteraja", "ninja xpress",
    "ninja express", "id express", "lion parcel", "tiki", "wahana", "sap express", "shopee express", "spx express", "dhl", "fedex",
];

/**
 * What these pages say. Specific on purpose: a failed delivery, a held parcel, an incomplete address, a redelivery fee.
 * Ordinary shop and courier wording ("lengkapi alamat pengiriman", "cek resi", "ongkir", "gagal dikirim" as in a chat
 * message) is NOT here.
 */
export const COURIER_LURE_PHRASES = [
    "pengiriman gagal", "paket gagal dikirim", "paket gagal diantar", "paket tidak dapat dikirim", "paket tidak dapat diantar",
    "paket tertahan", "paket anda tertahan", "paket anda ditahan", "paket kamu tertahan",
    "alamat tidak lengkap", "alamat tujuan tidak lengkap", "alamat penerima tidak lengkap",
    "biaya pengiriman ulang", "biaya pengantaran ulang", "pengiriman ulang", "pengantaran ulang",
    // Not bare "delivery failed" / "failed delivery": e-mail RFCs and mail-server pages say that (rfc-editor.org in the lab).
    "package delivery failed", "parcel delivery failed", "delivery attempt failed", "failed delivery attempt",
    "package on hold", "parcel on hold", "your package is on hold",
    "incomplete address", "address is incomplete", "redelivery", "reschedule delivery", "unable to deliver your package",
    "could not deliver your package",
];

/** Two or more different couriers among the alts is a shipping-options strip on a shop, not a courier's own page. */
const SHIPPING_STRIP_COURIERS = 2;

/** First lure phrase in `source` (earliest on the page), with the exact page text as evidence. */
function findLure(source) {
    if (!source) return null;
    const index = buildIndex(source);
    let best = null;
    for (const phrase of COURIER_LURE_PHRASES) {
        const hit = findPhrase(index, phrase);
        if (hit && (!best || hit.start < best.hit.start)) best = { phrase, hit };
    }
    return best && { phrase: best.phrase, evidence: evidenceOf(index, best.hit) };
}

/** @param {{ text: string, title: string }} snapshot sanitised @returns {{ phrase: string, evidence: string } | null} */
export function findCourierLure(snapshot) {
    return findLure(snapshot.text) ?? findLure(snapshot.title);
}

const namesIn = (source) => {
    if (!source) return [];
    const index = buildIndex(source);
    return COURIER_NAMES.filter((name) => findPhrase(index, name));
};

/** The page presents itself as a courier: a lure phrase, a courier name in the title, or one courier's logo alt. */
export function looksLikeCourier(snapshot) {
    if (findCourierLure(snapshot)) return true;
    if (namesIn(snapshot.title).length) return true;
    const inAlts = new Set();
    for (const alt of snapshot.imageAlts) for (const name of namesIn(alt)) inAlts.add(name.split(" ")[0].replace("posindonesia", "pos"));
    return inAlts.size > 0 && inAlts.size < SHIPPING_STRIP_COURIERS;
}

/**
 * `urgent_language` for a courier lure. Always the full weight: unlike shop words ("terakhir hari ini"), a failed-delivery
 * claim on a site the courier does not own has one purpose, even before the form that follows it (jnex.cc page 1 has none).
 * @param {string} phrase our own phrase from the list (never page text) @param {string} evidence exact page text
 */
export function buildCourierLureSignal(phrase, evidence) {
    return {
        id: "urgent_language",
        layer: 3,
        weight: CONTENT_WEIGHTS.urgent_language,
        label: { en: `Fake failed-delivery message: "${phrase}"`, id: `Pesan palsu paket gagal kirim: "${phrase}"` },
        labelSimple: { en: "Says your package is stuck so you pay or fill in your details", id: "Bilang paketmu tertahan supaya kamu bayar atau isi data" },
        evidence,
    };
}

const CARD_TEXT = {
    asks_card: {
        label: { en: "Courier page asks for a card number. Couriers never ask for card details", id: "Halaman kurir meminta nomor kartu. Kurir tidak pernah meminta data kartu" },
        labelSimple: { en: "Delivery companies never ask for your bank card", id: "Jasa kirim paket tidak pernah meminta kartu bank kamu" },
    },
    asks_cvv: {
        label: { en: "Courier page asks for the card security code (CVV). Couriers never ask for card details", id: "Halaman kurir meminta kode keamanan kartu (CVV). Kurir tidak pernah meminta data kartu" },
        labelSimple: { en: "Delivery companies never ask for your bank card", id: "Jasa kirim paket tidak pernah meminta kartu bank kamu" },
    },
};

/**
 * Lifts `asks_card` / `asks_cvv` on a courier page to COURIER_CARD_WEIGHT with courier wording. Same ids, same evidence
 * (field name). Anything else, and every signal on a page that does not look like a courier, is returned unchanged.
 * @param {object[]} formSignals layer 3 form signals (forms.js), never for an official host
 */
export function liftCourierCardAsks(formSignals, snapshot) {
    if (!formSignals.some((s) => CARD_TEXT[s.id]) || !looksLikeCourier(snapshot)) return formSignals;
    return formSignals.map((s) =>
        CARD_TEXT[s.id] ? { ...s, weight: COURIER_CARD_WEIGHT, label: { ...CARD_TEXT[s.id].label }, labelSimple: { ...CARD_TEXT[s.id].labelSimple } } : s,
    );
}
