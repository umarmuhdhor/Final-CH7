// HTML -> PageSnapshot (contracts/detector-interface.md) + redaction of personal data. Pure functions, no network.
// A small tolerant scanner, not a browser: it reads the static HTML only, so content that a script adds later is NOT seen
// (e.g. a login form inside an iframe shows up in meta.iframes instead of snapshot.forms).

const MAX_TEXT = 20000; // PageSnapshot.text limit
const MAX_ALTS = 50; // PageSnapshot.imageAlts limit
const SKIP_INPUT_TYPES = new Set(["hidden", "submit", "button", "image", "reset"]);

/** Masks things that identify a person. Order matters: phone numbers first, so "+62 812 ..." is not eaten as a long number. */
export function redact(text) {
    return String(text ?? "")
        .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[email]")
        .replace(/(?<![\d+])\+?(?:62|0)[\s.-]?8[\d\s.-]{7,13}\d(?!\d)/g, "[phone]")
        .replace(/(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)/g, "[number]"); // card, NIK, account numbers (13-19 digits)
}

/** Keeps scheme, host and path; query values and fragment can carry names, ids or tokens. */
export function redactUrl(url) {
    try {
        const u = new URL(url);
        const keys = [...u.searchParams.keys()];
        const query = keys.length ? "?" + keys.map((k) => `${encodeURIComponent(k)}=REDACTED`).join("&") : "";
        return `${u.origin}${u.pathname}${query}`;
    } catch {
        return redact(url);
    }
}

function decode(s) {
    return s
        .replace(/&nbsp;|&#160;/g, " ")
        .replace(/&quot;/g, '"')
        .replace(/&#0?39;|&apos;/g, "'")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&amp;/g, "&");
}

function attrs(tag) {
    const out = {};
    const re = /([a-zA-Z_:][-\w:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
    const body = tag.replace(/^<\s*[a-zA-Z0-9-]+/, "").replace(/\/?>$/, "");
    for (const m of body.matchAll(re)) out[m[1].toLowerCase()] = decode(m[2] ?? m[3] ?? m[4] ?? "");
    return out;
}

function clean(text) {
    return decode(text.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
}

/**
 * @param {string} html
 * @param {{url: string, domain?: string, capturedAt?: string}} page
 * @returns {{ snapshot: object, meta: { iframes: string[], bytes: number } }}
 */
export function parseHtml(html, { url, domain, capturedAt = new Date().toISOString() }) {
    const src = String(html ?? "").replace(/<!--[\s\S]*?-->/g, "");

    const title = clean((src.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1] || "");
    const lang = (src.match(/<html[^>]*\slang\s*=\s*["']?([\w-]+)/i) || [])[1] || null;

    const labelFor = {};
    for (const m of src.matchAll(/<label\b([^>]*)>([\s\S]*?)<\/label>/gi)) {
        const id = attrs(`<label ${m[1]}>`).for;
        if (id) labelFor[id] = clean(m[2]);
    }

    const toField = (tag, kind) => {
        const a = attrs(tag);
        const type = kind === "input" ? (a.type || "text").toLowerCase() : kind;
        if (SKIP_INPUT_TYPES.has(type)) return null;
        return {
            type,
            name: a.name || null,
            id: a.id || null,
            label: (a.id && labelFor[a.id]) || a["aria-label"] || null,
            placeholder: a.placeholder || null,
            autocomplete: a.autocomplete || null, // field VALUES are never read
        };
    };
    const fieldsIn = (chunk) =>
        [...chunk.matchAll(/<(input|select|textarea)\b[^>]*>/gi)].map((m) => toField(m[0], m[1].toLowerCase())).filter(Boolean);

    const forms = [];
    let outside = src;
    for (const m of src.matchAll(/<form\b([^>]*)>([\s\S]*?)<\/form>/gi)) {
        forms.push({ action: attrs(`<form ${m[1]}>`).action || null, fields: fieldsIn(m[2]) });
        outside = outside.replace(m[0], " ");
    }
    const loose = fieldsIn(outside); // single-page apps often have inputs without a <form>
    if (loose.length) forms.push({ action: null, fields: loose });

    const imageAlts = [...src.matchAll(/<img\b[^>]*>/gi)]
        .map((m) => attrs(m[0]).alt)
        .filter(Boolean)
        .slice(0, MAX_ALTS)
        .map(redact);

    const iframes = [...src.matchAll(/<iframe\b[^>]*>/gi)].map((m) => attrs(m[0]).src).filter(Boolean);

    const body = src
        .replace(/<(script|style|noscript|template|svg)\b[\s\S]*?<\/\1>/gi, " ")
        .replace(/<head\b[\s\S]*?<\/head>/i, " ");
    const text = redact(clean(body)).slice(0, MAX_TEXT);

    return {
        snapshot: {
            url: redactUrl(url),
            ...(domain ? { domain } : {}),
            title: redact(title),
            lang,
            text,
            forms,
            imageAlts,
            capturedAt,
        },
        meta: { iframes, bytes: Buffer.byteLength(src) },
    };
}
