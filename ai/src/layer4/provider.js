// Generic chat-completions client (OpenAI-compatible request shape, which most providers offer).
// Model, base URL and key come from config. It returns { ok: true, content } or { ok: false, reason }; it never throws
// and never forwards anything the provider said about an error (SECURITY A10). A parsed answer also carries the
// provider's token counts as `usage` ({ in, out }, 0 when the provider sends none) for the ai_usage point (05b K4).
import { tokenUsage } from "../usage.js";

const MAX_RESPONSE_BYTES = 64 * 1024;
const HTTP_ERROR = Object.freeze({ ok: false, reason: "http_error" });
const BAD_SCHEMA = Object.freeze({ ok: false, reason: "bad_schema" });
const TIMEOUT = Object.freeze({ ok: false, reason: "timeout" });

/**
 * @param {{ config: object, fetch: typeof fetch }} deps
 * @returns {(messages: object[], signal: AbortSignal, opts?: { maxTokens?: number }) => Promise<{ ok: true, content: string, usage: { in: number, out: number } } | { ok: false, reason: "http_error" | "bad_schema" | "timeout", usage?: { in: number, out: number } }>}
 */
export function createProvider({ config, fetch }) {
    return async (messages, signal, opts = {}) => {
        try {
            const res = await fetch(`${config.baseUrl}/chat/completions`, {
                method: "POST",
                headers: { "content-type": "application/json", authorization: `Bearer ${config.apiKey}` },
                body: JSON.stringify({
                    model: config.model,
                    messages,
                    temperature: 0, // A13: repeatable answers
                    max_tokens: opts.maxTokens ?? 200, // layer 4 answers are one short verdict; POST /review asks for 2000
                    response_format: { type: "json_object" },
                    chat_template_kwargs: { thinking: false }, // no hidden reasoning pass: measured 1.2 s median (test-layer4)
                }),
                signal,
                // The key must not follow a redirect to another host. "manual" (not "error": Workers reject it and every call
                // failed in production) hands back the 3xx, which `!res.ok` below turns into http_error. Same as rdap.js.
                redirect: "manual",
            });
            if (!res.ok) return HTTP_ERROR;
            const declared = Number(res.headers.get("content-length"));
            if (Number.isFinite(declared) && declared > MAX_RESPONSE_BYTES) return BAD_SCHEMA;
            const raw = await res.text();
            if (raw.length > MAX_RESPONSE_BYTES) return BAD_SCHEMA;
            let body;
            try {
                body = JSON.parse(raw);
            } catch {
                return BAD_SCHEMA;
            }
            const content = body?.choices?.[0]?.message?.content;
            const usage = tokenUsage(body?.usage); // a reply without content was still billed
            return typeof content === "string" ? { ok: true, content, usage } : { ...BAD_SCHEMA, usage };
        } catch {
            return signal?.aborted ? TIMEOUT : HTTP_ERROR; // network failure, redirect refused, or our abort
        }
    };
}
