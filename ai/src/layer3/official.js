// Official domains (detector/data/brands.json, shared with layer 2). Sensitive fields on an official
// site are normal, so layer 3 stays silent there.
import brands from "../../../detector/data/brands.json" with { type: "json" };

import { POPULAR, SHARED_HOSTS } from "../blocklist/allowlist.js";
import { registrableDomain } from "../rdap/domain.js";

const OFFICIAL = new Set(brands.brands.flatMap((b) => b.domains.map((d) => d.toLowerCase())));

// Link shorteners in POPULAR: they forward anywhere, so they are never "the site the user is on".
const SHORTENERS = new Set(["tokopedia.link"]);
/**
 * Popular sites that layer 3 treats like brands (phase 07, D-imelda-30). Narrower than POPULAR, whose job is
 * "never publish on the blocklist": a public suffix there (go.id) is not one site, so it never earns silence.
 */
export const LAYER3_QUIET = new Set([...POPULAR].filter((d) => registrableDomain(d) === d && !SHORTENERS.has(d)));

/** Host of a URL string, lowercase; "" when it cannot be parsed. */
export function hostOf(url) {
    try {
        return new URL(url).hostname.toLowerCase().replace(/\.$/, "");
    } catch {
        return "";
    }
}

// Hosts under an official domain where ANYONE can publish a page (forms, sites, file hosting).
// A scam form on docs.google.com must not get the official-site exemption.
const USER_CONTENT = [
    "docs.google.com", "sites.google.com", "drive.google.com", "script.google.com", "forms.office.com", "forms.microsoft.com", "sites.live.com",
    "storage.googleapis.com", "firebaseapp.com", "web.app", "sway.office.com", "onedrive.live.com", "forms.cloud.microsoft", "sharepoint.com", "1drv.ms",
    // user-made pages on popular domains (review #60): common phishing lures
    "express.adobe.com", "acrobat.adobe.com", "spark.adobe.com", "paper.dropbox.com", "gist.github.com",
];
// Every subdomain except www is a user's own blog / page (alice.medium.com).
const USER_SUBDOMAINS = ["medium.com"];

/** True for an official or popular domain or any of its subdomains (bca.co.id, ibank.bca.co.id; not notbca.co.id). */
export function isOfficialHost(host) {
    if (!host || host.length > 253) return false;
    for (const shared of USER_CONTENT) if (host === shared || host.endsWith(`.${shared}`)) return false;
    for (const apex of USER_SUBDOMAINS) if (host.endsWith(`.${apex}`) && host !== `www.${apex}`) return false;
    // Platforms where anyone can publish a page (S3, CDNs, site builders) never earn the official exemption, even when popular.
    for (const shared of SHARED_HOSTS) if (host === shared || host.endsWith(`.${shared}`)) return false;
    const labels = host.split(".");
    for (let i = 0; i < labels.length - 1; i++) {
        const tail = labels.slice(i).join(".");
        if (OFFICIAL.has(tail) || LAYER3_QUIET.has(tail)) return true; // popular sites: same silence as brands (phase 07, D-imelda-30)
    }
    return false;
}
