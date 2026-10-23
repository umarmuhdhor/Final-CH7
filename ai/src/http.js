// Small HTTP helpers: JSON error format from contracts/api.md and a size-capped body reader.

export class HttpError extends Error {
    constructor(status, code, message) {
        super(message);
        this.status = status;
        this.code = code;
    }
}

/** `{ "error": { "code", "message" } }` (contracts/api.md). Messages are fixed text: never echo input. */
export function errorResponse(status, code, message, headers = {}) {
    return new Response(JSON.stringify({ error: { code, message } }), {
        status,
        headers: { "content-type": "application/json", ...headers },
    });
}

/**
 * Reads the request body as text but gives up as soon as it passes `maxBytes`,
 * so an oversized or endless body is never held in memory or parsed.
 * @param {Request} request
 * @param {number} maxBytes
 * @returns {Promise<string>}
 */
export async function readTextLimited(request, maxBytes) {
    const tooLarge = () => new HttpError(413, "too_large", "Request body is too large.");
    const declared = Number(request.headers.get("content-length"));
    if (Number.isFinite(declared) && declared > maxBytes) throw tooLarge();
    if (!request.body) return "";

    const reader = request.body.getReader();
    const chunks = [];
    let total = 0;
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.byteLength;
        if (total > maxBytes) {
            await reader.cancel().catch(() => {});
            throw tooLarge();
        }
        chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
    }
    return new TextDecoder().decode(bytes);
}
