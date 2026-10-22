// Official domains (detector/data/brands.json, shared with layer 2). Sensitive fields on an official
// site are normal, so layer 3 stays silent there.
import brands from "../../../detector/data/brands.json" with { type: "json" };

const OFFICIAL = new Set(brands.brands.flatMap((b) => b.domains.map((d) => d.toLowerCase())));

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
const USER_CONTENT = ["docs.google.com", "sites.google.com", "drive.google.com", "script.google.com", "forms.office.com", "forms.microsoft.com", "sites.live.com", "storage.googleapis.com", "firebaseapp.com", "web.app"];

/** True for an official domain or any of its subdomains (bca.co.id, ibank.bca.co.id; not notbca.co.id). */
export function isOfficialHost(host) {
    if (!host || host.length > 253) return false;
    for (const shared of USER_CONTENT) if (host === shared || host.endsWith(`.${shared}`)) return false;
    const labels = host.split(".");
    for (let i = 0; i < labels.length - 1; i++) {
        if (OFFICIAL.has(labels.slice(i).join("."))) return true;
    }
    return false;
}
