// Field "fingerprints" of well-known login forms (layer 3, brand_logo_offsite).
// A phishing kit copies a company's sign-in page together with its HTML, so the form keeps the company's own
// field names and ids. A page that is NOT on that company's domain and has these names is a copy.
// Matching is exact on the whole `name` / `id` value (lowercase), never a substring, and needs `minHits` DIFFERENT
// values: one generic name ("passwd") must never be enough on its own.
//
// Only fingerprints that are known to belong to one company belong here. Add one only after checking the real page.

/** @type {ReadonlyArray<{ brandId: string, names: string[], ids: string[], minHits: number }>} */
export const FIELD_FINGERPRINTS = Object.freeze([
    // Microsoft account / Entra sign-in (login.live.com, login.microsoftonline.com): email field name="loginfmt" id="i0116",
    // password field id="i0118". "passwd" is the password field's name there too, but it is a common name, so it is not listed.
    { brandId: "microsoft", names: ["loginfmt"], ids: ["i0116", "i0118"], minHits: 2 },
]);
