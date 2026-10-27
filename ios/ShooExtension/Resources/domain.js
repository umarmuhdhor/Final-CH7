// Owner: lead. Registrable domain via the Public Suffix List (EX-02). ES module, used by background.js.
// "a.b.co.id" → "b.co.id", "scam.vercel.app" → "scam.vercel.app" (private suffix), "www.bca.co.id" → "bca.co.id".
// Verdicts apply per registrable domain (PRD §5), so getting this wrong blocks or unblocks a whole platform.

/** @param {string} text  one rule per line (see psl.js) */
export function parseRules(text) {
    const exact = new Set();
    const wildcard = new Set(); // "*.ck" stored as "ck"
    const exception = new Set(); // "!www.ck" stored as "www.ck"
    for (const line of text.split("\n")) {
        const rule = line.trim();
        if (!rule) continue;
        if (rule.startsWith("!")) exception.add(rule.slice(1));
        else if (rule.startsWith("*.")) wildcard.add(rule.slice(2));
        else exact.add(rule);
    }
    return { exact, wildcard, exception };
}

const IPV4 = /^\d{1,3}(\.\d{1,3}){3}$/;

/**
 * @param {string} hostname  location.hostname (already punycode, may have trailing dot)
 * @param {{exact: Set<string>, wildcard: Set<string>, exception: Set<string>}} rules
 * @returns {string} lowercase registrable domain; the hostname itself for IPs, single labels and bare suffixes
 */
export function registrableDomain(hostname, rules) {
    const host = String(hostname || "").toLowerCase().replace(/\.+$/, "");
    if (!host || IPV4.test(host) || host.includes(":")) return host;

    const labels = host.split(".");
    if (labels.length < 2) return host;

    // Longest matching rule wins; an exception beats a wildcard of the same length.
    let suffixLength = 1; // default rule "*"
    for (let i = 0; i < labels.length; i++) {
        const candidate = labels.slice(i).join(".");
        if (rules.exception.has(candidate)) {
            suffixLength = labels.length - i - 1;
            break;
        }
        const parent = labels.slice(i + 1).join(".");
        if (rules.exact.has(candidate) || (parent && rules.wildcard.has(parent))) {
            suffixLength = labels.length - i;
            break;
        }
    }

    if (suffixLength >= labels.length) return host;
    return labels.slice(-(suffixLength + 1)).join(".");
}

/** Fallback when the list can't be loaded: strips "www." only. */
export function naiveDomain(hostname) {
    return String(hostname || "").toLowerCase().replace(/\.+$/, "").replace(/^www\./, "");
}

/**
 * `https://host/path` only, for URLs that leave the phone (/analyze): a reset token, session id or OAuth
 * code in the query or fragment, or credentials before the host, must never be sent. The full URL stays
 * on the device (layer 2 reads it).
 */
export function shareableUrl(url) {
    try {
        const parsed = new URL(url);
        return parsed.origin + parsed.pathname;
    } catch {
        return String(url).split(/[?#]/)[0];
    }
}
