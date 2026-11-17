// Owner: lead. Registrable domain via the Public Suffix List (EX-02). ES module, used by background.js.
// "a.b.co.id" → "b.co.id", "scam.vercel.app" → "scam.vercel.app" (private suffix), "www.bca.co.id" → "bca.co.id".
// Verdicts apply per registrable domain (PRD §5), so getting this wrong blocks or unblocks a whole platform.
// `pageDomain` is the `domain` the extension sends: this, except the full host on host_path platforms (#495).

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

// #495: platforms where anyone publishes a page under a path of the host (or of a host under it). Mirrors the
// backend's `admin.domain_lists` rows with `hosting = 'host_path'` (backend/db/scripts/domain-lists-seed.sql),
// the rows `public.verdict_shared` reads. One page there says nothing about the rest of the registrable domain
// (a Google Form is not google.com), so `domain` is the full host. Platforms where anyone gets a subdomain
// (vercel.app, github.io) need nothing here: the PSL already splits their tenants.
export const HOST_PATH_HOSTS = [
    "1drv.ms", "acrobat.adobe.com", "cloud.microsoft", "docs.google.com", "drive.google.com", "express.adobe.com",
    "firebasestorage.googleapis.com", "forms.cloud.microsoft", "forms.microsoft.com", "forms.office.com", "gist.github.com",
    "onedrive.live.com", "paper.dropbox.com", "script.google.com", "sites.google.com", "sites.live.com", "spark.adobe.com",
    "storage.googleapis.com", "sway.office.com",
];

/** Lowercase, trailing dots gone (#450), an IPv6 literal in brackets (as `URL.hostname` gives it). */
export function normalHost(hostname) {
    const host = String(hostname || "").trim().toLowerCase().replace(/\.+$/, "");
    return host.includes(":") && !host.startsWith("[") ? `[${host}]` : host;
}

/** True for a host_path platform host or a host under one (sway.cloud.microsoft); `host` already normal. */
export function isHostPathHost(host) {
    return HOST_PATH_HOSTS.some((shared) => host === shared || host.endsWith(`.${shared}`));
}

/**
 * The `domain` the extension sends (POST /scans, GET /verdicts, contracts/api.md "`domain`") and
 * files block memory under (#487, #495):
 * - a host_path platform (sites.google.com, docs.google.com, sway.cloud.microsoft) → the full host, no `www.`;
 * - otherwise the registrable domain, which is the full host when there is none: an IP (`[2001:db8::1]`),
 *   a single label (`router`), a public suffix or `www.<public suffix>` (`www.co.id`, `www.com`).
 * Layer-1 list matching keeps using the registrable domain (lists.js), never this.
 * @param {string} hostname
 * @param {(hostname: string) => string} registrable  registrableDomain with the PSL rules, or naiveDomain
 */
export function pageDomain(hostname, registrable) {
    const host = normalHost(hostname);
    if (!host) return host;
    const bare = host.replace(/^www\./, "");
    if (isHostPathHost(bare)) return bare;
    return registrable(host) || host;
}

/**
 * @param {string} hostname  location.hostname (already punycode, may have trailing dot)
 * @param {{exact: Set<string>, wildcard: Set<string>, exception: Set<string>}} rules
 * @returns {string} lowercase registrable domain; the hostname itself for IPs, single labels and bare suffixes
 */
export function registrableDomain(hostname, rules) {
    const host = normalHost(hostname);
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

/** Fallback when the list can't be loaded: strips "www." only, and never down to one label (www.com stays). */
export function naiveDomain(hostname) {
    const host = normalHost(hostname);
    const bare = host.replace(/^www\./, "");
    return bare.includes(".") ? bare : host;
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
