// Owner: lead. Finishes the page replica drafted by replica.js (EX-07, contracts/api.md "Page replica").
// ES module, used by background.js: only the background can fetch cross-origin stylesheets and images.
// Stylesheets are inlined, small images become data: URIs, everything else that would load is removed,
// then the document is gzipped and base64'd for POST /scans.

// contracts/api.md: ≤ 400 KB as base64, ≤ 3 MB decompressed, else the backend drops the replica.
const MAX_BASE64 = 400 * 1024;
const MAX_HTML_BYTES = 3 * 1024 * 1024;
const MAX_IMAGE_BYTES = 40 * 1024;
const MAX_IMAGES_BYTES = 300 * 1024;
const MAX_IMAGES = 60;
const MAX_SHEET_CHARS = 600 * 1024; // one fetched stylesheet
const MAX_CSS_CHARS = 1_500_000; // all of them
const MAX_IMPORT_DEPTH = 2;
const FETCH_TIMEOUT_MS = 3000;
const PARALLEL = 6;

const CSS_URL = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)'"\s]*))\s*\)/gi;
const CSS_IMPORT = /@import\s+(?:url\(\s*)?["']?([^"')\s;]+)["']?\s*\)?([^;]*);/gi;
const FONT = /\.(woff2?|ttf|otf|eot)(\?|#|$)/i;
// Grey box for an image that couldn't be inlined: keeps the layout, shows something was there.
const PLACEHOLDER = "data:image/svg+xml;base64," + btoa('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><rect width="1" height="1" fill="#e5e5ea"/></svg>');

function absolute(url, base) {
    try {
        return new URL(url, base).href;
    } catch {
        return null;
    }
}

/**
 * One stylesheet ready to inline: @imports fetched (or dropped), url()s made into image tokens or none,
 * fonts dropped (the replica uses system fonts), `</style` defused.
 * @param {(url: string) => string} imageToken  registers an image, returns its token
 */
export async function processCss(text, base, { fetchText, imageToken, depth = 0 }) {
    const imports = [];
    text = text.replace(CSS_IMPORT, (whole, href, media) => {
        imports.push({ href: absolute(href, base), media: media.trim() });
        return "";
    });
    let inlined = "";
    for (const { href, media } of imports) {
        if (!href || depth >= MAX_IMPORT_DEPTH || !/^https?:/i.test(href)) continue;
        const css = await fetchText(href).catch(() => null);
        if (css == null) continue;
        const done = await processCss(css.slice(0, MAX_SHEET_CHARS), href, { fetchText, imageToken, depth: depth + 1 });
        inlined += media ? `@media ${media} {\n${done}\n}\n` : `${done}\n`;
    }
    const body = text.replace(CSS_URL, (whole, dq, sq, bare) => {
        const raw = dq ?? sq ?? bare ?? "";
        if (!raw || raw.startsWith("#")) return whole;
        if (/^data:/i.test(raw)) return /^data:(image|font)\//i.test(raw) ? `url(${raw.replace(/[\s"'()]/g, "")})` : "none";
        const url = absolute(raw, base);
        if (!url || !/^https?:/i.test(url) || FONT.test(url)) return "none";
        return `url(${imageToken(url)})`;
    });
    return (inlined + body).replace(/<\/(style)/gi, "<\\/$1");
}

/** Runs `work` over `items` with at most PARALLEL at once. */
async function eachLimited(items, work) {
    let next = 0;
    const lane = async () => {
        while (next < items.length) {
            const i = next++;
            await work(items[i], i);
        }
    };
    await Promise.all(Array.from({ length: Math.min(PARALLEL, items.length) }, lane));
}

/**
 * The finished document (not yet compressed).
 * @param draft  replica.js capture(): { html, sheets, resources, nonce }
 * @param io     { fetchText(url) → string, fetchImage(url, maxBytes) → data: URI | null }
 * @param {{ images?: boolean, css?: boolean }} keep  false drops that part (to fit the size limits)
 */
export async function assemble(draft, io, keep = { images: true, css: true }) {
    const { nonce } = draft;
    const images = [...draft.resources];
    const ids = new Map(images.map((url, i) => [url, i]));
    const imageToken = (url) => {
        if (!ids.has(url)) {
            ids.set(url, images.length);
            images.push(url);
        }
        return `${nonce}-i-${ids.get(url)}`;
    };

    const css = [];
    let cssChars = 0;
    for (const sheet of draft.sheets) {
        let text = "";
        if (keep.css && cssChars < MAX_CSS_CHARS) {
            const raw = sheet.text ?? (sheet.href ? await io.fetchText(sheet.href).catch(() => null) : null);
            if (raw != null) text = await processCss(raw.slice(0, MAX_SHEET_CHARS), sheet.base, { fetchText: io.fetchText, imageToken });
        }
        cssChars += text.length;
        css.push(cssChars <= MAX_CSS_CHARS ? text : "");
    }

    const inlined = new Array(images.length).fill(null);
    if (keep.images) {
        let budget = MAX_IMAGES_BYTES;
        await eachLimited(images.slice(0, MAX_IMAGES), async (url, i) => {
            if (budget <= 0) return;
            const data = await io.fetchImage(url, Math.min(MAX_IMAGE_BYTES, budget)).catch(() => null);
            if (!data || data.length * 0.75 > budget) return; // base64 → bytes
            budget -= data.length * 0.75;
            inlined[i] = data;
        });
    }

    // Stylesheets first: their text holds image tokens of its own.
    return draft.html
        .replace(new RegExp(`${nonce}-s-(\\d+)`, "g"), (whole, n) => css[Number(n)] ?? "")
        .replace(new RegExp(`${nonce}-i-(\\d+)`, "g"), (whole, n) => inlined[Number(n)] ?? PLACEHOLDER);
}

/** gzip → base64, or null when this runtime can't compress. */
export async function gzipBase64(text) {
    if (typeof CompressionStream === "undefined") return null;
    const stream = new Blob([text]).stream().pipeThrough(new CompressionStream("gzip"));
    const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(binary);
}

/**
 * pageReplicaBase64 for POST /scans, or null. Too big → again without images, then without stylesheets
 * (the page's text and structure are the evidence that matters most), then no replica.
 */
export async function buildReplica(draft, io, { compress = gzipBase64 } = {}) {
    if (!draft?.html || !draft.nonce) return null;
    io = remembered(io); // each try below reuses what the first one fetched
    for (const keep of [{ images: true, css: true }, { images: false, css: true }, { images: false, css: false }]) {
        const html = await assemble(draft, io, keep);
        if (new TextEncoder().encode(html).length > MAX_HTML_BYTES) continue;
        const packed = await compress(html);
        if (packed == null) return null;
        if (packed.length <= MAX_BASE64) return packed;
    }
    return null;
}

/** io whose answers are kept per URL, failures too. */
function remembered(io) {
    const texts = new Map();
    const images = new Map();
    const once = (map, key, load) => {
        if (!map.has(key)) map.set(key, load());
        return map.get(key);
    };
    return {
        fetchText: (url) => once(texts, url, () => io.fetchText(url)),
        fetchImage: (url, maxBytes) => once(images, `${maxBytes} ${url}`, () => io.fetchImage(url, maxBytes)),
    };
}

/** Real fetchers for background.js: no cookies, cached copies first (the page just loaded them). */
export function webIO(fetchImpl = fetch) {
    const get = async (url) => {
        const response = await fetchImpl(url, { credentials: "omit", cache: "force-cache", signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response;
    };
    return {
        async fetchText(url) {
            const response = await get(url);
            const type = response.headers.get("Content-Type") || "";
            if (type && !/text\/css|text\/plain/i.test(type)) throw new Error("not css");
            return (await response.text()).slice(0, MAX_SHEET_CHARS);
        },
        async fetchImage(url, maxBytes) {
            const response = await get(url);
            const type = (response.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
            if (!type.startsWith("image/")) return null;
            const length = Number(response.headers.get("Content-Length"));
            if (length > maxBytes) return null;
            const bytes = new Uint8Array(await response.arrayBuffer());
            if (bytes.length > maxBytes) return null;
            let binary = "";
            for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
            return `data:${type};base64,${btoa(binary)}`;
        },
    };
}
