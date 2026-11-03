// Every signal id Shoo itself emits: layers 1-2 (detector/src/detector.js `signal("…")`), layer 3 (src/layer3) and
// layer 4 (src/layer4/reality.js). Ids reach the admin dashboard through scans, i.e. from clients, so anything that
// leaves it for a public report or the model input is checked against this list (05b X3/X4). A test fails when a new
// id is emitted but missing here (test/learning.test.mjs).
export const KNOWN_SIGNAL_IDS = Object.freeze(
    new Set([
        "db_match",
        "lookalike_domain",
        "brand_plus_keyword",
        "cheap_tld",
        "suspicious_link",
        "asks_pin",
        "asks_otp",
        "asks_password",
        "asks_card",
        "asks_cvv",
        "asks_ktp",
        "asks_selfie_ktp",
        "urgent_language",
        "brand_logo_offsite",
        "new_domain",
        "unreasonable_request",
    ]),
);

export const isKnownSignal = (id) => typeof id === "string" && KNOWN_SIGNAL_IDS.has(id);
