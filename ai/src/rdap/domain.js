// Registrable domain of a host, validated hard because it is the ONLY thing that leaves the server (SECURITY A2/Q2).
// Linear character checks, no regular expressions.
import brands from "../../../detector/data/brands.json" with { type: "json" };

const TWO_LABEL_SUFFIXES = new Set(brands.suffixes);
// Second-level labels used under country TLDs (com.br, co.za, ...). Approximation of the public suffix list.
const GENERIC_SECOND_LEVEL = new Set(["com", "co", "net", "org", "gov", "edu", "ac", "or", "go", "ne", "sch", "web", "biz", "mil", "gob", "nom", "ltd", "plc"]);
// Names that never exist on the public internet, or that point at private networks.
const RESERVED_TLDS = new Set(["local", "localhost", "internal", "onion", "test", "invalid", "lan", "home", "corp", "arpa", "localdomain", "intranet", "private", "alt"]);

function validLabel(label) {
    if (label.length < 1 || label.length > 63) return false;
    if (label[0] === "-" || label[label.length - 1] === "-") return false;
    for (let i = 0; i < label.length; i++) {
        const c = label.charCodeAt(i);
        if (!((c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 45)) return false;
    }
    return true;
}

function validTld(tld) {
    if (tld.startsWith("xn--")) return tld.length > 4 && validLabel(tld);
    if (tld.length < 2 || tld.length > 24) return false;
    for (let i = 0; i < tld.length; i++) {
        const c = tld.charCodeAt(i);
        if (c < 97 || c > 122) return false; // letters only: rejects 127.0.0.1, 0x7f.1, 1.2.3.4
    }
    return true;
}

/**
 * True for a syntactically valid public DNS name with at least two labels.
 * @param {string} host
 */
export function isPublicHostname(host) {
    if (typeof host !== "string" || host.length === 0 || host.length > 253) return false;
    const labels = host.split(".");
    if (labels.length < 2) return false;
    for (const l of labels) if (!validLabel(l)) return false;
    const tld = labels[labels.length - 1];
    return validTld(tld) && !RESERVED_TLDS.has(tld);
}

/**
 * @param {string} host hostname as parsed from a URL
 * @returns {string | null} e.g. "login.bca-aman.co.id" -> "bca-aman.co.id"; null for anything that is not a public domain
 */
export function registrableDomain(host) {
    if (typeof host !== "string") return null;
    let h = host.toLowerCase();
    if (h.endsWith(".")) h = h.slice(0, -1);
    if (!isPublicHostname(h)) return null;
    const labels = h.split(".");
    const tld = labels[labels.length - 1];
    const sld = labels[labels.length - 2];
    let keep = 2;
    if (TWO_LABEL_SUFFIXES.has(`${sld}.${tld}`) || (tld.length === 2 && GENERIC_SECOND_LEVEL.has(sld))) keep = 3;
    if (labels.length < keep) return null;
    return labels.slice(-keep).join(".");
}
