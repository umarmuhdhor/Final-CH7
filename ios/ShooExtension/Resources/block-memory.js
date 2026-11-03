// Owner: lead. Block memory on the phone (EX-06, #231). ES module, used by background.js.
// A site blocked once opens straight to the block screen next time: no /analyze (so no LLM call), no
// POST /scans (so no second push to the guardian). Only a `safe` verdict for its domain clears it.
// Kept in storage.local only; nothing here leaves the phone.

export const TTL_MS = 14 * 24 * 60 * 60 * 1000; // the backend keeps a scan 14 days; after that the page is scanned again
export const MAX_ENTRIES = 500; // oldest dropped first
export const STORAGE_KEY = "blockMemory.v1";
const MAX_REASONS = 3; // what blocked.html shows (block.js payloadFor)
const MAX_PATH = 300;

// Platforms where anyone can publish a page (from ai/src/layer3/official.js USER_CONTENT and
// ai/src/blocklist/allowlist.js SHARED_HOSTS). Keying them by registrable domain would let one scam on
// sites.google.com block all of google.com. A subdomain of one (alice.medium.com, x.sharepoint.com) is
// keyed by its full host; the host itself (docs.google.com, s3.amazonaws.com) by host + path, since the
// page's owner is in the path there.
const SHARED = [
    "docs.google.com", "sites.google.com", "drive.google.com", "script.google.com", "forms.office.com", "forms.microsoft.com",
    "forms.cloud.microsoft", "sites.live.com", "sway.office.com", "onedrive.live.com", "storage.googleapis.com", "s3.amazonaws.com",
    "express.adobe.com", "acrobat.adobe.com", "spark.adobe.com", "paper.dropbox.com", "gist.github.com", "medium.com",
    "wordpress.com", "blogspot.com", "blogger.com", "wixsite.com", "wix.com", "weebly.com", "squarespace.com", "webflow.io",
    "github.io", "githubusercontent.com", "gitlab.io", "vercel.app", "netlify.app", "pages.dev", "workers.dev", "web.app",
    "firebaseapp.com", "herokuapp.com", "glitch.me", "repl.co", "onrender.com", "fly.dev", "000webhostapp.com", "infinityfreeapp.com",
    "forms.gle", "bit.ly", "tinyurl.com", "t.co", "goo.gl", "ngrok.io", "ngrok-free.app", "trycloudflare.com", "azurewebsites.net",
    "amazonaws.com", "cloudfront.net", "sharepoint.com", "googleapis.com", "googleusercontent.com", "linktr.ee", "t.me", "wa.me",
    "tumblr.com", "mediafire.com", "mega.nz", "canva.site", "godaddysites.com", "rebrand.ly", "is.gd", "cutt.ly", "windows.net",
    "notion.site", "carrd.co", "typedream.app", "framer.app", "webwave.me", "mystrikingly.com", "yolasite.com", "jimdofree.com",
];

/**
 * What a blocked page is remembered by: the registrable domain, except on a shared platform (see SHARED).
 * @param {string} url
 * @param {(hostname: string) => string} registrableDomain
 * @returns {string|null} null for anything that is not an http(s) page
 */
export function memoryKey(url, registrableDomain) {
    let parsed;
    try {
        parsed = new URL(url);
    } catch {
        return null;
    }
    if (!/^https?:$/.test(parsed.protocol)) return null;
    const host = parsed.hostname.toLowerCase().replace(/\.+$/, "").replace(/^www\./, "");
    if (!host) return null;
    if (SHARED.includes(host)) {
        const path = parsed.pathname.replace(/\/+$/, "").slice(0, MAX_PATH);
        return `${host}${path || "/"}`;
    }
    if (SHARED.some((shared) => host.endsWith(`.${shared}`))) return host;
    return registrableDomain(host) || host;
}

/** Only what blocked.html shows, so a stored entry can't grow or carry page data beyond the reasons. */
function cleanSignals(signals) {
    if (!Array.isArray(signals)) return [];
    return [...signals]
        .filter((s) => s && typeof s.id === "string" && Number.isInteger(s.weight))
        .sort((a, b) => b.weight - a.weight)
        .slice(0, MAX_REASONS)
        .map(({ id, layer, weight, label, labelSimple }) => ({ id, layer, weight, label, labelSimple }));
}

/**
 * @param {object} deps
 * @param {{ get(key): Promise<object>, set(items): Promise<void> }} deps.storage  browser.storage.local
 * @param {(hostname: string) => string} deps.registrableDomain
 */
export function createBlockMemory({ storage, registrableDomain, now = () => Date.now() }) {
    let queue = Promise.resolve(); // read-modify-write one at a time: two tabs can block at once

    async function load() {
        try {
            const stored = (await storage.get(STORAGE_KEY))?.[STORAGE_KEY];
            return stored && typeof stored === "object" && !Array.isArray(stored) ? stored : {};
        } catch {
            return {};
        }
    }

    /** Runs `change(entries)` on a fresh copy and saves it if it returns true. Never rejects. */
    function update(change) {
        const run = queue.then(async () => {
            const entries = await load();
            if (!change(entries)) return;
            const keys = Object.keys(entries);
            if (keys.length > MAX_ENTRIES) {
                keys.sort((a, b) => (entries[a].at ?? 0) - (entries[b].at ?? 0));
                for (const key of keys.slice(0, keys.length - MAX_ENTRIES)) delete entries[key];
            }
            await storage.set({ [STORAGE_KEY]: entries });
        });
        queue = run.catch((error) => console.warn("[Shoo] block memory", error));
        return queue;
    }

    const expired = (entry) => !entry || !Number.isFinite(entry.at) || now() - entry.at >= TTL_MS;

    /** @returns {Promise<{domain, score, signals, recordId}|null>} the remembered block, or null */
    async function recall(url) {
        const key = memoryKey(url, registrableDomain);
        if (!key) return null;
        await queue;
        const entry = (await load())[key];
        if (!entry) return null;
        if (expired(entry)) {
            await update((entries) => delete entries[key]);
            return null;
        }
        return { domain: entry.domain, score: entry.score, signals: entry.signals ?? [], recordId: entry.recordId ?? null };
    }

    /** Remembers a page the moment it is blocked. */
    function remember(url, { domain, score, signals }) {
        const key = memoryKey(url, registrableDomain);
        if (!key || typeof domain !== "string" || !Number.isInteger(score)) return Promise.resolve();
        return update((entries) => {
            entries[key] = { domain, score: Math.min(100, Math.max(0, score)), signals: cleanSignals(signals), recordId: null, at: now() };
            return true;
        });
    }

    /** The backend's scan id, once POST /scans answers, so "Review in Shoo" opens the right Detail later. */
    function setRecord(url, recordId) {
        const key = memoryKey(url, registrableDomain);
        if (!key || typeof recordId !== "string" || !recordId) return Promise.resolve();
        return update((entries) => {
            if (!entries[key]) return false;
            entries[key].recordId = recordId;
            return true;
        });
    }

    /** A `safe` verdict for this registrable domain: every page remembered under it opens again. */
    function forgetDomain(domain) {
        if (typeof domain !== "string" || !domain) return Promise.resolve();
        return update((entries) => {
            let changed = false;
            for (const [key, entry] of Object.entries(entries)) {
                if (entry?.domain === domain) {
                    delete entries[key];
                    changed = true;
                }
            }
            return changed;
        });
    }

    return { recall, remember, setRecord, forgetDomain };
}
